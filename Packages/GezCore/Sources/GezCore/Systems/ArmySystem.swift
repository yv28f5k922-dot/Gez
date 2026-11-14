import Foundation

/// Tuning constants for Phase 6: national manpower, levies, mercenaries,
/// movement speed, province supply limits, attrition, and vassal revolts.
public enum ArmyModel {
    /// Share of owned population that forms the base national manpower pool.
    public static let baseManpowerPopShare = 0.012
    /// Months to refill an empty national manpower pool from 0 to max.
    public static let manpowerRecoveryMonths = 120.0
    /// Share of a province's peasant and noble pops that can be mustered as levies.
    public static let baseLevyPopShare = 0.03
    /// Extra levy share from tribal-culture pops.
    public static let tribalLevyBonusShare = 0.02
    /// Minimum men required in a province to muster a levy.
    public static let minLevyMen = 200
    /// Mercenary recruitment cost multiplier over a professional regiment's base cost.
    public static let mercenaryCostMultiplier = 1.75
    /// Mercenary monthly upkeep multiplier over a professional regiment's upkeep.
    public static let mercenaryUpkeepMultiplier = 1.60
    /// Levy monthly field-ration upkeep multiplier over base upkeep.
    public static let levyUpkeepMultiplier = 0.60
    /// Global upkeep scale so 1453 standing armies leave realms with a peacetime budget surplus.
    public static let upkeepScale = 0.55
    /// Normal foot march speed in km per day on open plains.
    public static let baseMarchKmPerDay = 30.0
    /// Extra travel time multiplier when crossing a major river border.
    public static let riverCrossingMultiplier = 1.35
    /// Travel time reduction per level of Paved Roads (`road`).
    public static let roadSpeedBonusPerLevel = 0.08
    /// Opinion threshold below which a great vassal may rise in open revolt.
    public static let revoltOpinionBelow = -60
    /// Monthly chance a deeply disloyal vassal raises banners in revolt.
    public static let monthlyRevoltChance = 0.05
}

/// Reasons why recruiting or raising troops in a province is refused.
public enum ArmyRefusal: Error, Equatable, Sendable {
    case notOwner
    case unitLocked
    case notEnoughManpower
    case cannotAfford
    case mercenaryCapReached
    case leviesAlreadyRaised
    case vassalRefusing
    case tooFewPeople

    public var reason: String {
        switch self {
        case .notOwner:            return "Not your province"
        case .unitLocked:          return "Unit type not available to your realm"
        case .notEnoughManpower:   return "Not enough national manpower"
        case .cannotAfford:        return "Not enough ducats"
        case .mercenaryCapReached: return "Mercenary limit reached"
        case .leviesAlreadyRaised: return "Province levies are already raised"
        case .vassalRefusing:      return "Disloyal vassal refuses to muster levies"
        case .tooFewPeople:        return "Too few people to muster a levy"
        }
    }
}

/// Phase 6 simulation system: manpower, recruitment, levies, mercenaries,
/// daily province-to-province movement, supply & attrition, great vassal
/// revolts, and military AI.
public enum ArmySystem {

    // MARK: - Settle & Manpower

    /// Recomputes `maxManpower` for every country and clamps `manpower`.
    public static func settle(_ world: inout World, seedPool: Bool = false) {
        let C = world.countries.count
        if world.military.manpower.count != C {
            world.military.resize(countries: C)
        }
        for c in world.countries.ids {
            let maxMP = calculateMaxManpower(world, c)
            world.military.maxManpower[c.index] = maxMP
            if seedPool {
                world.military.manpower[c.index] = (maxMP * 0.75).rounded()
            } else {
                world.military.manpower[c.index] = min(world.military.manpower[c.index], maxMP)
            }
        }
    }

    /// Marshal council bonus to max manpower and recovery (+1.5% per point above 5).
    public static func marshalBonus(_ world: World, _ country: CountryID) -> Double {
        guard let m = world.countries.council[country.index][CouncilSeat.marshal.rawValue],
              world.people.characters.isAlive(m) else { return 0 }
        let skill = world.people.characters.skill(m, .martial)
        return Double(skill - 5) * 0.015
    }

    public static func calculateMaxManpower(_ world: World, _ country: CountryID) -> Double {
        let owned = world.provinces(ownedBy: country)
        guard !owned.isEmpty else { return 0 }
        var popSum = 0.0
        var barracksMen = 0.0
        let T = world.economy.buildings.typeCount
        for pid in owned {
            // Provinces held by a tax-refusing vassal do not contribute to crown manpower.
            if let h = world.provinces.holder[pid.index], world.people.refusing.contains(h) {
                continue
            }
            popSum += world.provinces.population[pid.index]
            for t in 0..<T {
                if case .manpower(let x) = world.economy.buildingTypes[t].effect {
                    let lvl = world.economy.buildings.level(pid, BuildingTypeID(t))
                    if lvl > 0 {
                        barracksMen += Double(lvl) * x * 1_000.0
                    }
                }
            }
        }
        let base = popSum * ArmyModel.baseManpowerPopShare + barracksMen
        let factor = max(0.25, 1.0 + world.government.modifier(country, .manpower) + marshalBonus(world, country))
        return max(500.0, (base * factor).rounded())
    }

    public static func monthlyManpowerGain(_ world: World, _ country: CountryID) -> Double {
        let maxMP = world.military.maxManpower[country.index]
        guard world.military.manpower[country.index] < maxMP else { return 0 }
        return (maxMP / ArmyModel.manpowerRecoveryMonths).rounded()
    }

    // MARK: - Unit Unlocks & Recruitment Costs

    /// True if `country` satisfies the unlock rules for `unitId`.
    public static func canRecruit(_ world: World, _ country: CountryID, _ unitId: UnitTypeID) -> Bool {
        let u = world.military.unit(unitId)
        if u.requires.isEmpty { return true }
        let tag = world.countries.tag[country.index]
        let gov = world.countries.government[country.index]
        let cap = world.countries.capital[country.index]
        let capRegion = cap.map { world.regionName(of: $0) }
        let capCulture = cap.map { world.cultures.key[world.provinces.majorityCulture[$0.index].index] }
        let rulerCulture = world.countries.ruler[country.index].map {
            world.cultures.key[world.people.characters.culture[$0.index].index]
        }
        let estateKeys: Set<String> = Set(
            world.government.estates[country.index].map { world.government.rules.estates[$0.index].key }
        )

        for clause in u.requires {
            switch clause {
            case .estate(let keys):
                if keys.contains(where: { estateKeys.contains($0) }) { return true }
            case .government(let govs):
                if govs.contains(gov) { return true }
            case .culture(let cultures):
                if let rc = rulerCulture, cultures.contains(rc) { return true }
                if let cc = capCulture, cultures.contains(cc) { return true }
            case .region(let regions):
                if let cr = capRegion, regions.contains(cr) { return true }
            case .tags(let tags):
                if tags.contains(tag) { return true }
            }
        }
        return false
    }

    /// All unit types unlocked for `country`.
    public static func availableUnits(_ world: World, for country: CountryID) -> [UnitType] {
        world.military.unitTypes.filter { canRecruit(world, country, $0.id) }
    }

    /// Ducat cost to recruit a professional regiment of `unitId` in `province`
    /// (base cost + local market price of required military goods, scaled by inflation).
    public static func recruitmentCost(_ world: World, _ country: CountryID, _ province: ProvinceID, _ unitId: UnitTypeID) -> Double {
        let u = world.military.unit(unitId)
        var total = u.cost
        if let m = world.market(of: province) {
            for (g, amount) in u.goods {
                total += amount * world.economy.markets.price(m, g)
            }
        }
        total *= (1.0 + world.countries.inflation[country.index])
        return total.rounded()
    }

    /// Ducat cost to hire a mercenary regiment of `unitId`.
    public static func mercenaryCost(_ world: World, _ country: CountryID, _ unitId: UnitTypeID) -> Double {
        let u = world.military.unit(unitId)
        return (u.cost * ArmyModel.mercenaryCostMultiplier * (1.0 + world.countries.inflation[country.index])).rounded()
    }

    /// Maximum mercenary men `country` can keep under contract at once.
    public static func mercenaryLimit(_ world: World, _ country: CountryID) -> Int {
        max(3_000, Int((world.military.maxManpower[country.index] * 0.5).rounded()))
    }

    // MARK: - Recruiting Professionals & Mercenaries

    public static func recruitRefusal(
        _ world: World,
        _ country: CountryID,
        in province: ProvinceID,
        unit unitId: UnitTypeID,
        checkMoney: Bool = true
    ) -> ArmyRefusal? {
        if world.provinces.owner[province.index] != country { return .notOwner }
        if !canRecruit(world, country, unitId) { return .unitLocked }
        let u = world.military.unit(unitId)
        if world.military.manpower[country.index] < Double(u.maxMen) { return .notEnoughManpower }
        if checkMoney && world.countries.treasury[country.index] < recruitmentCost(world, country, province, unitId) {
            return .cannotAfford
        }
        return nil
    }

    /// Recruits a standing professional regiment in `province`, deducting
    /// manpower and ducats and adding the unit's weapons/horses/gunpowder/etc.
    /// to the local market's `pendingDemand`.
    @discardableResult
    public static func recruitProfessional(
        _ world: inout World,
        _ country: CountryID,
        in province: ProvinceID,
        unit unitId: UnitTypeID,
        intoArmy targetArmy: ArmyID? = nil
    ) -> Result<ArmyID, ArmyRefusal> {
        if let ref = recruitRefusal(world, country, in: province, unit: unitId) {
            return .failure(ref)
        }
        let u = world.military.unit(unitId)
        let cost = recruitmentCost(world, country, province, unitId)
        world.countries.treasury[country.index] -= cost
        world.military.manpower[country.index] = max(0, world.military.manpower[country.index] - Double(u.maxMen))

        if let m = world.market(of: province) {
            for (g, amount) in u.goods {
                world.economy.markets.pendingDemand[world.economy.markets.slot(m, g)] += amount
            }
        }

        let reg = Regiment(type: unitId, origin: .professional, men: u.maxMen, morale: u.morale)
        let armyId = attachRegiment(&world, country: country, province: province, regiment: reg, preferredArmy: targetArmy)
        return .success(armyId)
    }

    /// Hires a mercenary regiment in `province` for pure gold (no national
    /// manpower or local pop cost).
    @discardableResult
    public static func hireMercenary(
        _ world: inout World,
        _ country: CountryID,
        in province: ProvinceID,
        unit unitId: UnitTypeID,
        intoArmy targetArmy: ArmyID? = nil
    ) -> Result<ArmyID, ArmyRefusal> {
        if world.provinces.owner[province.index] != country { return .failure(.notOwner) }
        if !canRecruit(world, country, unitId) { return .failure(.unitLocked) }
        let u = world.military.unit(unitId)
        let currentMercs = world.military.totalMen(of: country, origin: .mercenary)
        if currentMercs + u.maxMen > mercenaryLimit(world, country) {
            return .failure(.mercenaryCapReached)
        }
        let cost = mercenaryCost(world, country, unitId)
        if world.countries.treasury[country.index] < cost {
            return .failure(.cannotAfford)
        }
        world.countries.treasury[country.index] -= cost
        let reg = Regiment(type: unitId, origin: .mercenary, men: u.maxMen, morale: u.morale)
        let armyId = attachRegiment(&world, country: country, province: province, regiment: reg, preferredArmy: targetArmy)
        return .success(armyId)
    }

    private static func attachRegiment(
        _ world: inout World,
        country: CountryID,
        province: ProvinceID,
        regiment: Regiment,
        preferredArmy: ArmyID?
    ) -> ArmyID {
        if let aid = preferredArmy {
            let i = Int(aid.rawValue)
            if i >= 0 && i < world.military.armies.count && world.military.armies.alive[i]
                && world.military.armies.owner[i] == country
                && !world.military.armies.isRebel[i]
                && world.military.armies.province[i] == province {
                world.military.armies.regiments[i].append(regiment)
                return aid
            }
        }
        if let existing = world.military.armies(in: province).first(where: {
            let idx = Int($0.rawValue)
            return world.military.armies.owner[idx] == country && !world.military.armies.isRebel[idx]
        }) {
            world.military.armies.regiments[Int(existing.rawValue)].append(regiment)
            return existing
        }
        let pName = world.provinces.name[province.index]
        return world.military.armies.append(
            name: "Army of \(pName)",
            owner: country,
            province: province,
            commander: nil,
            regiments: [regiment]
        )
    }

    // MARK: - Levies (Tied to Province Pops)

    /// True if any raised `.levy` regiment on the map comes from `province`.
    public static func hasRaisedLevies(_ world: World, in province: ProvinceID) -> Bool {
        for i in 0..<world.military.armies.count where world.military.armies.alive[i] {
            if world.military.armies.regiments[i].contains(where: { $0.origin == .levy && $0.homeProvince == province }) {
                return true
            }
        }
        return false
    }

    /// Number of men `province` can muster as levies right now from its
    /// peasant, noble, and tribal pops.
    public static func availableLevyMen(_ world: World, in province: ProvinceID) -> Int {
        guard let owner = world.provinces.owner[province.index] else { return 0 }
        if hasRaisedLevies(world, in: province) { return 0 }
        if let holder = world.provinces.holder[province.index], world.people.refusing.contains(holder) {
            return 0
        }
        return rawLevyMen(world, in: province, for: owner)
    }

    private static func rawLevyMen(_ world: World, in province: ProvinceID, for country: CountryID) -> Int {
        let tribalSet = world.government.rules.tribalCultures
        var raw = 0.0
        for i in world.pops.range(for: province) {
            let cls = world.pops.socialClass[i]
            guard cls == .peasants || cls == .nobles else { continue }
            var rate = ArmyModel.baseLevyPopShare
            if tribalSet.contains(world.pops.culture[i]) {
                rate += ArmyModel.tribalLevyBonusShare
            }
            raw += world.pops.size[i] * rate
        }
        let factor = max(0.25, 1.0 + world.government.modifier(country, .levySize))
        return Int((raw * factor).rounded())
    }

    /// Raises levies from `province`, removing the mustered men from the
    /// province's `.peasants` and `.nobles` pops so farm/mine output drops
    /// while they are away.
    @discardableResult
    public static func raiseLevies(
        _ world: inout World,
        _ country: CountryID,
        in province: ProvinceID,
        intoArmy targetArmy: ArmyID? = nil
    ) -> Result<ArmyID, ArmyRefusal> {
        if world.provinces.owner[province.index] != country { return .failure(.notOwner) }
        if hasRaisedLevies(world, in: province) { return .failure(.leviesAlreadyRaised) }
        if let holder = world.provinces.holder[province.index], world.people.refusing.contains(holder) {
            return .failure(.vassalRefusing)
        }
        let men = rawLevyMen(world, in: province, for: country)
        if men < ArmyModel.minLevyMen { return .failure(.tooFewPeople) }

        deductMenFromPops(&world, in: province, men: men)
        let regs = buildLevyRegiments(world, country: country, province: province, totalMen: men)
        var aid: ArmyID? = targetArmy
        for reg in regs {
            aid = attachRegiment(&world, country: country, province: province, regiment: reg, preferredArmy: aid)
        }
        return .success(aid!)
    }

    /// Raises levies across all eligible provinces of `country` and gathers
    /// them in their respective provinces (or capital if adjacent).
    @discardableResult
    public static func raiseAllLevies(_ world: inout World, _ country: CountryID) -> Int {
        var totalRaised = 0
        for pid in world.provinces(ownedBy: country) {
            let men = availableLevyMen(world, in: pid)
            guard men >= ArmyModel.minLevyMen else { continue }
            if case .success = raiseLevies(&world, country, in: pid) {
                totalRaised += men
            }
        }
        return totalRaised
    }

    /// Disbands all `.levy` regiments belonging to `country`, returning
    /// surviving soldiers to their home provinces' pops.
    public static func disbandLevies(_ world: inout World, of country: CountryID) {
        for aid in world.military.armies(of: country) {
            let i = Int(aid.rawValue)
            var kept: [Regiment] = []
            for reg in world.military.armies.regiments[i] {
                if reg.origin == .levy {
                    returnLevyToPops(&world, regiment: reg)
                } else {
                    kept.append(reg)
                }
            }
            if kept.isEmpty {
                world.military.armies.remove(aid)
            } else {
                world.military.armies.regiments[i] = kept
            }
        }
    }

    /// Disbands an entire army: levy survivors return to their home province
    /// pops, and half of professional survivors return to national manpower.
    public static func disband(_ world: inout World, army id: ArmyID) {
        let i = Int(id.rawValue)
        guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { return }
        let owner = world.military.armies.owner[i]
        let maxMP = world.military.maxManpower[owner.index]
        for reg in world.military.armies.regiments[i] {
            switch reg.origin {
            case .levy:
                returnLevyToPops(&world, regiment: reg)
            case .professional:
                let returned = (Double(reg.men) * 0.5).rounded()
                world.military.manpower[owner.index] = min(maxMP, world.military.manpower[owner.index] + returned)
            case .mercenary:
                break
            }
        }
        world.military.armies.remove(id)
    }

    private static func deductMenFromPops(_ world: inout World, in province: ProvinceID, men: Int) {
        let range = world.pops.range(for: province)
        var eligibleTotal = 0.0
        for i in range {
            let cls = world.pops.socialClass[i]
            if cls == .peasants || cls == .nobles {
                eligibleTotal += world.pops.size[i]
            }
        }
        guard eligibleTotal > 0 else { return }
        let take = min(eligibleTotal * 0.5, Double(men))
        for i in range {
            let cls = world.pops.socialClass[i]
            if cls == .peasants || cls == .nobles {
                let share = world.pops.size[i] / eligibleTotal
                world.pops.size[i] = max(1, world.pops.size[i] - take * share)
            }
        }
        recalculateProvincePopulation(&world, province)
    }

    private static func returnLevyToPops(_ world: inout World, regiment: Regiment) {
        guard regiment.men > 0, let home = regiment.homeProvince else { return }
        let range = world.pops.range(for: home)
        var peasantTotal = 0.0
        for i in range where world.pops.socialClass[i] == .peasants {
            peasantTotal += world.pops.size[i]
        }
        if peasantTotal > 0 {
            for i in range where world.pops.socialClass[i] == .peasants {
                let share = world.pops.size[i] / peasantTotal
                world.pops.size[i] += Double(regiment.men) * share
            }
        } else if let first = range.first {
            world.pops.size[first] += Double(regiment.men)
        }
        recalculateProvincePopulation(&world, home)
    }

    private static func recalculateProvincePopulation(_ world: inout World, _ province: ProvinceID) {
        var sum = 0.0
        for i in world.pops.range(for: province) {
            sum += world.pops.size[i]
        }
        world.provinces.population[province.index] = sum.rounded()
    }

    private static func buildLevyRegiments(
        _ world: World,
        country: CountryID,
        province: ProvinceID,
        totalMen: Int
    ) -> [Regiment] {
        let inf = world.military.unit("infantry")!
        let arc = world.military.unit("archers")!
        let cav = world.military.unit("cavalry")!
        let ha = world.military.unit("horse_archers")
        let isHorde = world.countries.government[country.index] == .steppeHorde
            || world.government.rules.tribalCultures.contains(world.provinces.majorityCulture[province.index])

        var remaining = totalMen
        var regs: [Regiment] = []
        while remaining > 0 {
            let chunk = min(1_000, remaining)
            remaining -= chunk
            let u: UnitType
            if isHorde, let ha, canRecruit(world, country, ha.id), regs.count % 2 == 0 {
                u = ha
            } else if regs.count % 4 == 1 && chunk >= 500 {
                u = arc
            } else if regs.count % 5 == 2 && chunk >= 600 {
                u = cav
            } else {
                u = inf
            }
            regs.append(Regiment(
                type: u.id,
                origin: .levy,
                men: chunk,
                morale: u.morale * 0.9,
                homeProvince: province
            ))
        }
        return regs
    }

    // MARK: - Commanders & Army Organization

    /// Characters in `country`'s court who can command an army (sorted by Martial skill descending).
    public static func commanderCandidates(_ world: World, _ country: CountryID, date: GameDate) -> [CharacterID] {
        let ch = world.people.characters
        let ruler = world.countries.ruler[country.index]
        let rebelLeaders: Set<CharacterID> = Set(
            world.military.rebelArmies(of: country).compactMap { world.military.armies.rebelLeader[Int($0.rawValue)] }
        )
        return ch.ids.filter { cid in
            guard ch.court[cid.index] == country, ch.isAlive(cid), !rebelLeaders.contains(cid) else { return false }
            guard ch.age(cid, on: date) >= CharacterSystem.adultAge else { return false }
            if ch.female[cid.index] && cid != ruler { return false }
            return true
        }.sorted { a, b in
            let ma = ch.skill(a, .martial), mb = ch.skill(b, .martial)
            return ma != mb ? ma > mb : a.index < b.index
        }
    }

    /// Assigns `commander` to `army` (unassigning them from any other army first).
    public static func assignCommander(_ world: inout World, army: ArmyID, commander: CharacterID?) {
        let i = Int(army.rawValue)
        guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { return }
        if let cmd = commander {
            for j in 0..<world.military.armies.count where world.military.armies.alive[j] {
                if world.military.armies.commander[j] == cmd {
                    world.military.armies.commander[j] = nil
                }
            }
        }
        world.military.armies.commander[i] = commander
    }

    /// Merges all other friendly non-rebel armies standing in the same province into `army`.
    @discardableResult
    public static func mergeArmiesInProvince(_ world: inout World, into army: ArmyID) -> Int {
        let i = Int(army.rawValue)
        guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { return 0 }
        let owner = world.military.armies.owner[i]
        let prov = world.military.armies.province[i]
        var mergedCount = 0
        for other in world.military.armies(in: prov) where other != army {
            let j = Int(other.rawValue)
            guard world.military.armies.owner[j] == owner,
                  world.military.armies.isRebel[j] == world.military.armies.isRebel[i] else { continue }
            world.military.armies.regiments[i].append(contentsOf: world.military.armies.regiments[j])
            if world.military.armies.commander[i] == nil {
                world.military.armies.commander[i] = world.military.armies.commander[j]
            }
            world.military.armies.remove(other)
            mergedCount += 1
        }
        return mergedCount
    }

    /// Splits half the regiments of `army` into a new army in the same province.
    public static func splitArmy(_ world: inout World, army: ArmyID) -> ArmyID? {
        let i = Int(army.rawValue)
        guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { return nil }
        let regs = world.military.armies.regiments[i]
        guard regs.count >= 2 else { return nil }
        let mid = regs.count / 2
        let firstHalf = Array(regs[0..<mid])
        let secondHalf = Array(regs[mid..<regs.count])
        world.military.armies.regiments[i] = firstHalf
        let prov = world.military.armies.province[i]
        let owner = world.military.armies.owner[i]
        return world.military.armies.append(
            name: "Detachment of \(world.provinces.name[prov.index])",
            owner: owner,
            province: prov,
            commander: nil,
            regiments: secondHalf
        )
    }

    // MARK: - Movement & Pathfinding

    /// Pace of `army` (determined by its slowest regiment, e.g. 0.70 with bombards, 1.40 all-cavalry).
    public static func armySpeed(_ world: World, _ army: ArmyID) -> Double {
        let i = Int(army.rawValue)
        guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { return 1.0 }
        let regs = world.military.armies.regiments[i]
        guard !regs.isEmpty else { return 1.0 }
        var slowest = Double.greatestFiniteMagnitude
        for r in regs {
            let s = world.military.unit(r.type).speed
            if s < slowest { slowest = s }
        }
        return max(0.4, slowest)
    }

    /// Days required for `army` (or a generic foot army if nil) to march between
    /// adjacent provinces `a` and `b`.
    public static func stepDays(_ world: World, from a: ProvinceID, to b: ProvinceID, army: ArmyID? = nil) -> Double {
        let locA = world.provinces.location[a.index]
        let locB = world.provinces.location[b.index]
        let distKm = max(25.0, min(350.0, MarketModel.km(locA, locB)))
        let terrainMult = MarketModel.terrainCost(world.provinces.terrain[b.index])
        let riverMult = world.isRiverBorder(a, b) ? ArmyModel.riverCrossingMultiplier : 1.0

        var roadLevel = 0.0
        if let roadType = world.economy.buildingType(key: "road") {
            let la = Double(world.economy.buildings.level(a, roadType))
            let lb = Double(world.economy.buildings.level(b, roadType))
            roadLevel = (la + lb) * 0.5
        }
        let roadMult = max(0.55, 1.0 - ArmyModel.roadSpeedBonusPerLevel * roadLevel)

        var speedMult = 1.0
        if let aid = army {
            speedMult = armySpeed(world, aid)
            let i = Int(aid.rawValue)
            if i >= 0 && i < world.military.armies.count,
               let cmd = world.military.armies.commander[i],
               world.people.characters.isAlive(cmd) {
                let martial = world.people.characters.skill(cmd, .martial)
                speedMult *= (1.0 + Double(martial) * 0.015)
            }
        }

        let rawDays = (distKm / ArmyModel.baseMarchKmPerDay) * terrainMult * riverMult * roadMult / speedMult
        return max(1.0, (rawDays * 10.0).rounded() / 10.0)
    }

    /// Labels each province with the id of the land mass it belongs to
    /// (provinces connected through `neighbors`). Two provinces with different
    /// labels cannot be reached from each other by marching, so callers can
    /// skip the full-map `findPath` search that would fail anyway.
    public static func landComponents(_ world: World) -> [Int] {
        let P = world.provinces.count
        var label = Array(repeating: -1, count: P)
        var next = 0
        for start in 0..<P where label[start] == -1 {
            label[start] = next
            var stack = [start]
            while let u = stack.popLast() {
                for nb in world.provinces.neighbors[u] where label[nb.index] == -1 {
                    label[nb.index] = next
                    stack.append(nb.index)
                }
            }
            next += 1
        }
        return label
    }

    /// Finds the fastest path of adjacent provinces from `start` to `goal`.
    /// Returns the sequence of hops after `start` (ending with `goal`), or
    /// empty if `start == goal` or unreachable.
    public static func findPath(
        _ world: World,
        from start: ProvinceID,
        to goal: ProvinceID,
        army: ArmyID? = nil
    ) -> [ProvinceID] {
        guard start != goal else { return [] }
        let P = world.provinces.count
        var dist = Array(repeating: Double.infinity, count: P)
        var prev = Array(repeating: -1, count: P)
        var visited = Array(repeating: false, count: P)
        dist[start.index] = 0

        // Simple binary heap by (cost, provinceIndex).
        var heap: [(Double, Int)] = [(0.0, start.index)]

        func push(_ item: (Double, Int)) {
            heap.append(item)
            var idx = heap.count - 1
            while idx > 0 {
                let parent = (idx - 1) / 2
                if heap[idx].0 < heap[parent].0 {
                    heap.swapAt(idx, parent)
                    idx = parent
                } else {
                    break
                }
            }
        }

        func pop() -> (Double, Int)? {
            guard !heap.isEmpty else { return nil }
            if heap.count == 1 { return heap.removeLast() }
            let top = heap[0]
            heap[0] = heap.removeLast()
            var idx = 0
            let n = heap.count
            while true {
                let l = 2 * idx + 1, r = 2 * idx + 2
                var smallest = idx
                if l < n && heap[l].0 < heap[smallest].0 { smallest = l }
                if r < n && heap[r].0 < heap[smallest].0 { smallest = r }
                if smallest != idx {
                    heap.swapAt(idx, smallest)
                    idx = smallest
                } else {
                    break
                }
            }
            return top
        }

        let armyOwner: CountryID? = army.flatMap { aid in
            let idx = Int(aid.rawValue)
            guard idx >= 0, idx < world.military.armies.count,
                  world.military.armies.alive[idx],
                  !world.military.armies.isRebel[idx],
                  !world.military.armies.isRetreating[idx] else { return nil }
            return world.military.armies.owner[idx]
        }

        while let (d, u) = pop() {
            if visited[u] { continue }
            visited[u] = true
            if u == goal.index { break }
            let uPid = ProvinceID(u)
            for nb in world.provinces.neighbors[u] {
                let v = nb.index
                if visited[v] { continue }
                if let mover = armyOwner,
                   !SiegeSystem.canStep(world, for: mover, from: uPid, to: nb, pathStart: start) {
                    continue
                }
                let nd = d + stepDays(world, from: uPid, to: nb, army: army)
                if nd < dist[v] {
                    dist[v] = nd
                    prev[v] = u
                    push((nd, v))
                }
            }
        }

        guard prev[goal.index] != -1 else { return [] }
        var path: [ProvinceID] = []
        var cur = goal.index
        while cur != start.index && cur != -1 {
            path.append(ProvinceID(cur))
            cur = prev[cur]
        }
        path.reverse()
        return path
    }

    /// Orders `army` to march to `destination` along the fastest province path.
    @discardableResult
    public static func orderMove(_ world: inout World, army: ArmyID, to destination: ProvinceID) -> Bool {
        let i = Int(army.rawValue)
        guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { return false }
        let start = world.military.armies.province[i]
        if start == destination {
            world.military.armies.path[i].removeAll()
            world.military.armies.moveProgressDays[i] = 0
            world.military.armies.moveStepDays[i] = 0
            return true
        }
        let path = findPath(world, from: start, to: destination, army: army)
        guard let firstHop = path.first else { return false }
        world.military.armies.path[i] = path
        world.military.armies.moveProgressDays[i] = 0
        world.military.armies.moveStepDays[i] = stepDays(world, from: start, to: firstHop, army: army)
        return true
    }

    /// Advances all marching armies by one day and resolves clashes with rebel vassal hosts.
    public static func runDaily(_ world: inout World, date: GameDate, random: inout GameRandom) {
        var arrivedProvinces = Set<ProvinceID>()
        for i in 0..<world.military.armies.count where world.military.armies.alive[i] {
            let aid = ArmyID(Int32(i))
            if world.military.isInBattle(aid) { continue }
            guard let nextHop = world.military.armies.path[i].first else { continue }
            if world.military.armies.moveStepDays[i] <= 0 {
                let cur = world.military.armies.province[i]
                world.military.armies.moveStepDays[i] = stepDays(world, from: cur, to: nextHop, army: aid)
            }
            let pace = world.military.armies.isRetreating[i] ? 1.5 : 1.0
            world.military.armies.moveProgressDays[i] += pace
            if world.military.armies.moveProgressDays[i] >= world.military.armies.moveStepDays[i] {
                let cur = world.military.armies.province[i]
                world.military.armies.previousProvince[i] = cur
                world.military.armies.province[i] = nextHop
                world.military.armies.path[i].removeFirst()
                world.military.armies.moveProgressDays[i] = 0

                // Check if hostile forces block further advance in `nextHop`.
                let owner = world.military.armies.owner[i]
                let hitHostile = !world.military.armies.isRetreating[i]
                    && !world.military.armies.isRebel[i]
                    && world.military.armies(in: nextHop).contains { other in
                        let j = Int(other.rawValue)
                        return !world.military.armies.isRebel[j]
                            && !world.military.armies.isRetreating[j]
                            && world.diplomacy.isAtWar(owner, world.military.armies.owner[j])
                    }
                if hitHostile {
                    world.military.armies.path[i].removeAll()
                    world.military.armies.moveStepDays[i] = 0
                } else if let following = world.military.armies.path[i].first {
                    world.military.armies.moveStepDays[i] = stepDays(world, from: nextHop, to: following, army: aid)
                } else {
                    world.military.armies.moveStepDays[i] = 0
                    if world.military.armies.isRetreating[i] {
                        world.military.armies.isRetreating[i] = false
                    }
                }
                arrivedProvinces.insert(nextHop)
            }
        }

        for pid in arrivedProvinces.sorted(by: { $0.index < $1.index }) {
            resolveRebelClash(&world, in: pid, date: date, random: &random)
        }
    }

    // MARK: - Supply Limit, Attrition, Reinforcement & Upkeep

    /// Maximum number of soldiers `province` can feed and quarter without
    /// monthly starvation and camp disease attrition.
    public static func supplyLimit(_ world: World, in province: ProvinceID) -> Int {
        let p = province.index
        let pop = world.provinces.population[p]
        let terrain = world.provinces.terrain[p]
        var limit = 3_000.0
        limit += pop * 0.05
        limit += MarketModel.terrainFood(terrain) * 4_000.0

        // Local staple harvest output adds supply capacity.
        for k in world.economy.producers.range(for: province) where world.economy.producers.isStaple[k] {
            limit += world.economy.producers.output[k] * 250.0
        }

        if world.provinces.isCoastal[p] {
            limit += 1_500.0
        }
        if let port = world.economy.buildingType(key: "port") {
            limit += Double(world.economy.buildings.level(province, port)) * 1_500.0
        }
        if let caravan = world.economy.buildingType(key: "caravanserai") {
            limit += Double(world.economy.buildings.level(province, caravan)) * 1_500.0
        }
        limit += Double(world.provinces.fortLevel[p]) * 1_000.0

        return Int((limit / 100.0).rounded()) * 100
    }

    /// Total soldiers of all armies currently standing in `province`.
    public static func soldiersInProvince(_ world: World, _ province: ProvinceID) -> Int {
        var total = 0
        for aid in world.military.armies(in: province) {
            total += world.military.armies.totalMen(of: aid)
        }
        return total
    }

    /// Monthly upkeep in ducats for a single regiment.
    public static func regimentUpkeep(_ world: World, _ regiment: Regiment) -> Double {
        let u = world.military.unit(regiment.type)
        let strengthRatio = Double(regiment.men) / Double(max(1, u.maxMen))
        let mult: Double
        switch regiment.origin {
        case .professional: mult = 1.0
        case .mercenary:    mult = ArmyModel.mercenaryUpkeepMultiplier
        case .levy:         mult = ArmyModel.levyUpkeepMultiplier
        }
        return u.upkeep * strengthRatio * mult * ArmyModel.upkeepScale
    }

    /// Monthly upkeep in ducats for an entire army.
    public static func armyUpkeep(_ world: World, _ army: ArmyID) -> Double {
        let i = Int(army.rawValue)
        guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { return 0 }
        if world.military.armies.isRebel[i] { return 0 }
        var sum = 0.0
        for r in world.military.armies.regiments[i] {
            sum += regimentUpkeep(world, r)
        }
        return sum
    }

    /// Monthly military tick:
    /// 1. Recompute maxManpower and recover monthly manpower
    /// 2. Check province supply limits: apply attrition if over-stacked, or reinforce if supplied
    /// 3. Deduct army upkeep from treasury and add to `lastMonthlyExpenses`
    /// 4. Check great vassal open revolts and clashes
    public static func runMonthly(_ world: inout World, date: GameDate, random: inout GameRandom) {
        let C = world.countries.count
        if world.military.manpower.count != C {
            world.military.resize(countries: C)
        }

        // 1. Manpower recovery & commander cleanup for dead characters.
        for c in world.countries.ids {
            let maxMP = calculateMaxManpower(world, c)
            world.military.maxManpower[c.index] = maxMP
            let gain = monthlyManpowerGain(world, c)
            world.military.manpower[c.index] = min(maxMP, world.military.manpower[c.index] + gain)
            world.military.lastAttritionLosses[c.index] = 0
        }
        for i in 0..<world.military.armies.count where world.military.armies.alive[i] {
            if let cmd = world.military.armies.commander[i], !world.people.characters.isAlive(cmd) {
                world.military.armies.commander[i] = nil
            }
        }

        // 2. Supply limit, attrition & reinforcement per province.
        var armiesByProvince: [ProvinceID: [ArmyID]] = [:]
        for i in 0..<world.military.armies.count where world.military.armies.alive[i] {
            armiesByProvince[world.military.armies.province[i], default: []].append(ArmyID(Int32(i)))
        }

        for (pid, aids) in armiesByProvince.sorted(by: { $0.key.index < $1.key.index }) {
            let limit = supplyLimit(world, in: pid)
            var totalMen = 0
            for aid in aids { totalMen += world.military.armies.totalMen(of: aid) }

            if totalMen > limit {
                // Over supply limit: starvation & camp disease attrition.
                let overRatio = Double(totalMen - limit) / Double(max(1, limit))
                let terrain = world.provinces.terrain[pid.index]
                let diseaseExtra = (terrain == .desert || terrain == .marsh) ? 0.01 : 0.0
                let rate = min(0.15, 0.02 + overRatio * 0.05 + diseaseExtra)

                for aid in aids {
                    let i = Int(aid.rawValue)
                    let owner = world.military.armies.owner[i]
                    var surviving: [Regiment] = []
                    for var reg in world.military.armies.regiments[i] {
                        let lost = max(1, Int((Double(reg.men) * rate).rounded()))
                        let actualLost = min(reg.men, lost)
                        reg.men -= actualLost
                        if !world.military.armies.isRebel[i] {
                            world.military.lastAttritionLosses[owner.index] += actualLost
                        }
                        if reg.men > 0 {
                            surviving.append(reg)
                        }
                    }
                    if surviving.isEmpty {
                        world.military.armies.remove(aid)
                    } else {
                        world.military.armies.regiments[i] = surviving
                    }
                }
            } else {
                // Within supply limit: reinforce depleted regiments in friendly territory & recover morale.
                let provOwner = world.provinces.owner[pid.index]
                let isOccupied = world.provinces.occupiedBy[pid.index] != nil
                for aid in aids {
                    let i = Int(aid.rawValue)
                    guard world.military.armies.alive[i] else { continue }
                    if world.military.isInBattle(aid) { continue }
                    let owner = world.military.armies.owner[i]
                    let isFriendly = (provOwner == owner && !isOccupied) && !world.military.armies.isRebel[i]
                    for rIdx in world.military.armies.regiments[i].indices {
                        var reg = world.military.armies.regiments[i][rIdx]
                        let u = world.military.unit(reg.type)
                        reg.morale = min(u.morale, reg.morale + 0.5)
                        if isFriendly && reg.men < u.maxMen {
                            let needed = u.maxMen - reg.men
                            let step = max(10, u.maxMen / 10)
                            let want = min(needed, step)
                            switch reg.origin {
                            case .professional:
                                let avail = Int(world.military.manpower[owner.index])
                                let add = min(want, avail)
                                if add > 0 {
                                    reg.men += add
                                    world.military.manpower[owner.index] -= Double(add)
                                }
                            case .mercenary:
                                let cost = u.cost * 0.1
                                if world.countries.treasury[owner.index] >= cost {
                                    reg.men += want
                                    world.countries.treasury[owner.index] -= cost
                                }
                            case .levy:
                                break
                            }
                        }
                        world.military.armies.regiments[i][rIdx] = reg
                    }
                }
            }
        }

        // 3. Monthly army upkeep.
        var upkeep = Array(repeating: 0.0, count: C)
        for i in 0..<world.military.armies.count where world.military.armies.alive[i] && !world.military.armies.isRebel[i] {
            let c = world.military.armies.owner[i].index
            upkeep[c] += armyUpkeep(world, ArmyID(Int32(i)))
        }
        for c in 0..<C {
            world.countries.treasury[c] -= upkeep[c]
            world.military.lastArmyUpkeep[c] = upkeep[c]
            world.countries.lastMonthlyExpenses[c] += upkeep[c]
        }

        // 4. Great vassal open revolts & clashes.
        checkVassalRevolts(&world, date: date, random: &random)
        let armyIndex = world.military.armyIndexByProvince(provinceCount: world.provinces.count)
        for p in world.provinces.ids where armyIndex[p.index].count >= 2 {
            resolveRebelClash(&world, in: p, date: date, random: &random)
        }
    }

    // MARK: - Great Vassal Open Revolts & Combat Power

    /// Combat strength of `army` combining regiment attack, defence, morale,
    /// commander Martial skill, Marshal bonus, and realm `Modifier.armyQuality`.
    public static func combatPower(_ world: World, _ army: ArmyID) -> Double {
        let i = Int(army.rawValue)
        guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { return 0 }
        var raw = 0.0
        for reg in world.military.armies.regiments[i] {
            let u = world.military.unit(reg.type)
            let menK = Double(reg.men) / 1_000.0
            raw += menK * (u.attack + u.defence) * max(0.5, reg.morale)
        }
        let owner = world.military.armies.owner[i]
        var quality = 1.0
        if !world.military.armies.isRebel[i] {
            quality += world.government.modifier(owner, .armyQuality)
            if let m = world.countries.council[owner.index][CouncilSeat.marshal.rawValue],
               world.people.characters.isAlive(m) {
                quality += Double(world.people.characters.skill(m, .martial) - 5) * 0.01
            }
        }
        if let cmd = world.military.armies.commander[i], world.people.characters.isAlive(cmd) {
            quality += Double(world.people.characters.skill(cmd, .martial)) * 0.025
        }
        return raw * max(0.4, quality)
    }

    /// True if `vassal` is currently leading a rebel army in open revolt.
    public static func isRevolting(_ world: World, _ vassal: CharacterID) -> Bool {
        for i in 0..<world.military.armies.count where world.military.armies.alive[i] && world.military.armies.isRebel[i] {
            if world.military.armies.rebelLeader[i] == vassal { return true }
        }
        return false
    }

    /// Raises `vassal`'s held provinces (or `provinces`) in open armed rebellion against `country`.
    @discardableResult
    public static func triggerVassalRevolt(
        _ world: inout World,
        vassal: CharacterID,
        against country: CountryID,
        in provinces: [ProvinceID]? = nil,
        date: GameDate
    ) -> ArmyID? {
        guard !isRevolting(world, vassal), world.people.characters.isAlive(vassal) else { return nil }
        let held = provinces ?? VassalSystem.holdings(world, of: vassal)
        guard let seat = held.first else { return nil }

        var regs: [Regiment] = []
        for pid in held {
            let men = max(600, rawLevyMen(world, in: pid, for: country))
            deductMenFromPops(&world, in: pid, men: men)
            regs.append(contentsOf: buildLevyRegiments(world, country: country, province: pid, totalMen: men))
        }
        // Add the vassal's personal household guard so every revolt is a real threat.
        let cav = world.military.unit("cavalry")!
        regs.append(Regiment(type: cav.id, origin: .professional, men: cav.maxMen, morale: cav.morale))

        let vName = world.people.characters.fullName(vassal)
        let aid = world.military.armies.append(
            name: "\(vName)'s Revolt",
            owner: country,
            province: seat,
            commander: vassal,
            regiments: regs,
            isRebel: true,
            rebelLeader: vassal
        )
        world.people.record(
            date,
            country,
            "\(vName) raises banners in open revolt at \(world.provinces.name[seat.index])!"
        )
        return aid
    }

    public static func checkVassalRevolts(_ world: inout World, date: GameDate, random: inout GameRandom) {
        for c in world.countries.ids {
            for v in VassalSystem.vassals(world, of: c) {
                guard !isRevolting(world, v) else { continue }
                let op = VassalSystem.opinionOfLiege(world, v, c)
                if op < ArmyModel.revoltOpinionBelow && random.unit() < ArmyModel.monthlyRevoltChance {
                    triggerVassalRevolt(&world, vassal: v, against: c, date: date)
                }
            }
        }
    }

    /// Resolves a clash when a loyal crown army and a rebel vassal army of the
    /// same country meet in `province`.
    public static func resolveRebelClash(
        _ world: inout World,
        in province: ProvinceID,
        date: GameDate,
        random: inout GameRandom
    ) {
        let here = world.military.armies(in: province)
        guard here.count >= 2 else { return }

        let rebels = here.filter { world.military.armies.isRebel[Int($0.rawValue)] }
        let loyals = here.filter { !world.military.armies.isRebel[Int($0.rawValue)] }
        guard let rebelId = rebels.first else { return }
        let rIdx = Int(rebelId.rawValue)
        let country = world.military.armies.owner[rIdx]
        let crownHere = loyals.filter { world.military.armies.owner[Int($0.rawValue)] == country }
        guard !crownHere.isEmpty else { return }

        let rebelPower = rebels.reduce(0.0) { $0 + combatPower(world, $1) }
        let crownPower = crownHere.reduce(0.0) { $0 + combatPower(world, $1) }
        let roll = 0.9 + random.unit() * 0.2
        let pName = world.provinces.name[province.index]
        let leader = world.military.armies.rebelLeader[rIdx]
        let leaderName = leader.map { world.people.characters.fullName($0) } ?? "The rebel lord"

        if crownPower * roll >= rebelPower {
            // Crown crushes the rebellion.
            let lossRatio = min(0.35, 0.15 * (rebelPower / max(1.0, crownPower)))
            for cid in crownHere {
                applyCasualtyRatio(&world, army: cid, ratio: lossRatio)
            }
            for rid in rebels where world.military.armies.owner[Int(rid.rawValue)] == country {
                applyCasualtyRatio(&world, army: rid, ratio: 0.30)
                disband(&world, army: rid)
            }
            if let v = leader {
                for held in VassalSystem.holdings(world, of: v) {
                    VassalSystem.revoke(&world, held, date: date, justified: true)
                }
                world.people.characters.favour[v.index] = -100
            }
            world.people.record(date, country, "\(leaderName)'s rebellion is crushed at \(pName); their lands are forfeited to the crown.")
        } else {
            // Rebels drive back the royal army.
            let lossRatio = min(0.35, 0.15 * (crownPower / max(1.0, rebelPower)))
            for rid in rebels where world.military.armies.owner[Int(rid.rawValue)] == country {
                applyCasualtyRatio(&world, army: rid, ratio: lossRatio)
            }
            let retreatTarget = world.countries.capital[country.index]
                ?? world.provinces.neighbors[province.index].first
                ?? province
            for cid in crownHere {
                applyCasualtyRatio(&world, army: cid, ratio: 0.25)
                let cIdx = Int(cid.rawValue)
                if world.military.armies.alive[cIdx] && retreatTarget != province {
                    world.military.armies.province[cIdx] = retreatTarget
                    world.military.armies.path[cIdx].removeAll()
                }
            }
            world.people.record(date, country, "\(leaderName)'s rebels rout the royal army at \(pName).")
        }
    }

    private static func applyCasualtyRatio(_ world: inout World, army: ArmyID, ratio: Double) {
        let i = Int(army.rawValue)
        guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { return }
        var surviving: [Regiment] = []
        for var reg in world.military.armies.regiments[i] {
            let lost = Int((Double(reg.men) * ratio).rounded())
            reg.men -= min(reg.men, lost)
            if reg.men > 0 {
                surviving.append(reg)
            }
        }
        if surviving.isEmpty {
            world.military.armies.remove(army)
        } else {
            world.military.armies.regiments[i] = surviving
        }
    }

    // MARK: - AI

    /// Monthly military AI for computer-controlled realms:
    /// 1. Assigns the best available commander to un-led armies
    /// 2. Marches crown armies (raising levies if needed) to crush vassal revolts
    /// 3. Disbands idle levies at peace and spreads over-stacked armies
    /// 4. Recruits affordable standing regiments when manpower and budget allow
    public static func runAI(_ world: inout World, month: Int, date: GameDate) {
        for c in world.countries.ids where !world.humanCountries.contains(c) {
            let crownArmies = world.military.armies(of: c)
            let rebelArmies = world.military.rebelArmies(of: c)

            // 1. Assign commanders to un-commanded armies.
            if crownArmies.contains(where: { world.military.armies.commander[Int($0.rawValue)] == nil }) {
                let candidates = commanderCandidates(world, c, date: date)
                let used: Set<CharacterID> = Set(
                    crownArmies.compactMap { world.military.armies.commander[Int($0.rawValue)] }
                )
                var free = candidates.filter { !used.contains($0) }
                for aid in crownArmies where world.military.armies.commander[Int(aid.rawValue)] == nil {
                    guard let best = free.first else { break }
                    free.removeFirst()
                    assignCommander(&world, army: aid, commander: best)
                }
            }

            // 2. Crush active vassal revolts.
            if let firstRebel = rebelArmies.first {
                let rebelProv = world.military.armies.province[Int(firstRebel.rawValue)]
                let rebelMen = world.military.armies.totalMen(of: firstRebel)
                if world.military.totalMen(of: c) < Int(Double(rebelMen) * 1.3) {
                    raiseAllLevies(&world, c)
                }
                for aid in world.military.armies(of: c) {
                    let idx = Int(aid.rawValue)
                    if world.military.armies.path[idx].isEmpty && world.military.armies.province[idx] != rebelProv {
                        orderMove(&world, army: aid, to: rebelProv)
                    }
                }
                continue
            }

            // 3. At peace with no revolts: disband raised levies so pops work the land.
            if world.diplomacy.activeWars(for: c).isEmpty && world.military.totalMen(of: c, origin: .levy) > 0 {
                disbandLevies(&world, of: c)
            }

            // Avoid over-stacking in provinces beyond their supply limit.
            for aid in world.military.armies(of: c) {
                let idx = Int(aid.rawValue)
                guard world.military.armies.alive[idx], world.military.armies.path[idx].isEmpty else { continue }
                let prov = world.military.armies.province[idx]
                if soldiersInProvince(world, prov) > supplyLimit(world, in: prov) {
                    let myMen = world.military.armies.totalMen(of: aid)
                    if let nb = world.provinces.neighbors[prov.index].first(where: {
                        world.provinces.owner[$0.index] == c
                            && soldiersInProvince(world, $0) + myMen <= supplyLimit(world, in: $0)
                    }) {
                        orderMove(&world, army: aid, to: nb)
                    }
                }
            }

            // 4. Periodic recruitment of standing regiments (1/12th of countries per month).
            guard c.index % 12 == month % 12 else { continue }
            let income = world.countries.lastMonthlyIncome[c.index]
            let expenses = world.countries.lastMonthlyExpenses[c.index]
            let surplus = income - expenses
            let reserve = max(80.0, income * 8.0)
            guard surplus > 1.5,
                  world.countries.treasury[c.index] > reserve,
                  world.military.manpower[c.index] >= 2_000 else { continue }

            let targetStanding = Int((world.military.maxManpower[c.index] * 0.55).rounded())
            guard world.military.totalMen(of: c) < targetStanding,
                  let cap = world.countries.capital[c.index],
                  world.provinces.owner[cap.index] == c else { continue }

            let unlocked = availableUnits(world, for: c).filter { $0.category != .artillery }
            guard let chosen = unlocked.max(by: { ($0.attack + $0.defence) < ($1.attack + $1.defence) }) else { continue }
            if soldiersInProvince(world, cap) + chosen.maxMen <= supplyLimit(world, in: cap) {
                _ = recruitProfessional(&world, c, in: cap, unit: chosen.id)
            }
        }
    }
}
