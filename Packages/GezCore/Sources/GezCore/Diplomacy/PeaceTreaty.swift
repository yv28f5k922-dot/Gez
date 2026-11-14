import Foundation

/// A single demand included in a peace treaty offer.
public enum PeaceDemand: Sendable, Equatable, Hashable, Codable {
    /// Transfer province ownership from the losing side to `to`.
    case cedeProvince(province: ProvinceID, to: CountryID)
    /// Return a lawful core province from the losing side to `to`.
    case returnCore(province: ProvinceID, to: CountryID)
    /// One-time ducat indemnity transferred from loser to winner.
    case ducatIndemnity(amount: Double)
    /// War reparations: loser pays 10% of monthly income to winner for 10 years.
    case warReparations
    /// Force loser to become a vassal of winner.
    case makeVassal
    /// Force loser to become a tributary of winner.
    case makeTributary
    /// Force loser to break existing diplomatic treaties with a third country.
    case annulTreaty(with: CountryID)
    /// Release a country holding cores inside the loser's territory as a sovereign state.
    case releaseNation(country: CountryID)
}

/// Proposed or enacted peace deal ending (or exiting) a war.
public struct PeaceOffer: Sendable, Equatable, Codable {
    public var warID: String
    public var winner: CountryID
    public var loser: CountryID
    public var demands: [PeaceDemand]

    public init(warID: String, winner: CountryID, loser: CountryID, demands: [PeaceDemand]) {
        self.warID = warID
        self.winner = winner
        self.loser = loser
        self.demands = demands
    }
}

/// Evaluation of whether the AI/target will accept a peace offer.
public struct PeaceEvaluation: Sendable, Equatable {
    public var willAccept: Bool
    public var score: Int
    public var totalCost: Int
    public var factors: [(name: String, score: Int)]

    public init(willAccept: Bool, score: Int, totalCost: Int, factors: [(name: String, score: Int)]) {
        self.willAccept = willAccept
        self.score = score
        self.totalCost = totalCost
        self.factors = factors
    }

    public static func == (lhs: PeaceEvaluation, rhs: PeaceEvaluation) -> Bool {
        guard lhs.willAccept == rhs.willAccept,
              lhs.score == rhs.score,
              lhs.totalCost == rhs.totalCost,
              lhs.factors.count == rhs.factors.count else {
            return false
        }
        for (a, b) in zip(lhs.factors, rhs.factors) {
            if a.name != b.name || a.score != b.score { return false }
        }
        return true
    }
}

/// Failure reasons when proposing or executing a peace treaty.
public enum PeaceTreatyError: Error, Sendable, Equatable {
    case warNotFound
    case notBelligerents
    case exceedsMaxCost(cost: Int)
    case invalidDemand(String)
    case rejected(evaluation: PeaceEvaluation)
}

// MARK: - War Score, Cost, Truce & AE Helpers

extension Diplomacy {

    /// War score percentage cost (0...100) for a single `PeaceDemand`.
    public func peaceDemandCost(
        _ demand: PeaceDemand,
        loser: CountryID,
        war: War,
        in world: World
    ) -> Int {
        switch demand {
        case .cedeProvince(let pid, let recipient):
            let dev = max(1, world.provinces.development[pid.index])
            var cost = Double(min(45, max(4, dev * 3)))
            if world.provinces.claims[pid.index].contains(recipient) {
                cost *= 0.90
            }
            if war.casusBelli == .reconquest && world.provinces.cores[pid.index].contains(recipient) {
                cost *= 0.75
            }
            // Unoccupied provinces cost +50% war score
            let isOccupied = world.provinces.occupiedBy[pid.index].map { war.areEnemies($0, loser) } ?? false
            if !isOccupied {
                cost *= 1.50
            }
            return min(100, max(3, Int(cost.rounded())))

        case .returnCore(let pid, _):
            let dev = max(1, world.provinces.development[pid.index])
            var cost = Double(min(40, max(3, Int((Double(dev) * 2.2).rounded()))))
            if war.casusBelli == .reconquest {
                cost *= 0.75
            }
            return min(100, max(3, Int(cost.rounded())))

        case .ducatIndemnity(let amount):
            // 5% per 50 ducats, minimum 5%, max 25%
            return min(25, max(5, Int((amount / 10.0).rounded())))

        case .warReparations:
            return 10

        case .makeVassal:
            let dev = max(1, world.totalDevelopment(of: loser))
            var cost = Double(dev) * 2.5
            if war.casusBelli == .subjugation {
                cost *= 0.5
            }
            return max(15, Int(cost.rounded()))

        case .makeTributary:
            let dev = max(1, world.totalDevelopment(of: loser))
            var cost = Double(dev) * 1.2
            if war.casusBelli == .tribute {
                cost *= 0.65
            }
            return min(85, max(12, Int(cost.rounded())))

        case .annulTreaty:
            return 10

        case .releaseNation(let country):
            var sum = 0
            for p in world.provinces(ownedBy: loser) where world.provinces.cores[p.index].contains(country) {
                let dev = max(1, world.provinces.development[p.index])
                sum += max(3, Int((Double(dev) * 2.0).rounded()))
            }
            return min(100, max(5, sum))
        }
    }

    /// Total war score percentage cost across all demands in an offer.
    public func totalPeaceCost(for offer: PeaceOffer, war: War, in world: World) -> Int {
        offer.demands.reduce(0) { $0 + peaceDemandCost($1, loser: offer.loser, war: war, in: world) }
    }

    /// Truce length in years (5 to 15) scaled linearly with total peace score cost (0...100).
    public func truceDurationYears(forPeaceCost cost: Int) -> Int {
        let clamped = max(0, min(100, cost))
        return 5 + (clamped / 10)
    }

    /// Computes aggressive expansion generated by `winner` enforcing `offer`.
    public func aggressiveExpansionForPeace(
        _ offer: PeaceOffer,
        war: War,
        in world: World
    ) -> Double {
        var totalAE = 0.0
        for demand in offer.demands {
            switch demand {
            case .cedeProvince(let pid, let recipient):
                if war.casusBelli == .reconquest && world.provinces.cores[pid.index].contains(recipient) {
                    continue // Zero AE for returning cores in reconquest
                }
                let cost = Double(peaceDemandCost(demand, loser: offer.loser, war: war, in: world))
                var mod = 0.75
                if war.casusBelli == .claim && world.provinces.claims[pid.index].contains(recipient) {
                    mod = 0.65
                } else if war.casusBelli == .holyWar {
                    mod = 0.60
                } else if war.casusBelli == .coalition {
                    mod = 0.35
                }
                totalAE += cost * mod

            case .makeVassal:
                let cost = Double(peaceDemandCost(demand, loser: offer.loser, war: war, in: world))
                let mod = (war.casusBelli == .subjugation) ? 0.35 : 0.60
                totalAE += cost * mod

            case .returnCore, .releaseNation, .ducatIndemnity, .warReparations, .annulTreaty, .makeTributary:
                break
            }
        }
        return totalAE
    }

    /// Evaluates whether the losing country accepts a proposed peace offer.
    public func evaluatePeaceOffer(
        _ offer: PeaceOffer,
        date: GameDate,
        in world: World
    ) -> PeaceEvaluation {
        guard let war = wars.first(where: { $0.id == offer.warID }) else {
            return PeaceEvaluation(willAccept: false, score: -100, totalCost: 0, factors: [("War Not Found", -100)])
        }

        let totalCost = totalPeaceCost(for: offer, war: war, in: world)
        if totalCost > 100 {
            return PeaceEvaluation(willAccept: false, score: -999, totalCost: totalCost, factors: [("Exceeds 100% Max Cost", -999)])
        }

        var factors: [(name: String, score: Int)] = []

        // Winner's war score from their side (-100 ... +100)
        let winnerIsAttacker = war.isAttacker(offer.winner)
        let rawWS = winnerIsAttacker ? war.warScore : -war.warScore
        let winnerWSPercent = Int((rawWS * 100.0).rounded())

        // Base comparison: warscore vs demand cost
        factors.append(("War Score vs Treaty Cost", winnerWSPercent - totalCost))

        // Full occupation check on loser
        let loserProvs = world.provinces(ownedBy: offer.loser)
        let fullyOccupied = !loserProvs.isEmpty && loserProvs.allSatisfy { pid in
            if let occ = world.provinces.occupiedBy[pid.index] {
                return war.areEnemies(occ, offer.loser)
            }
            return false
        }
        if fullyOccupied {
            factors.append(("Total Occupation", 1000))
        } else {
            // Capital occupied bonus
            if let cap = world.countries.capital[offer.loser.index],
               let occ = world.provinces.occupiedBy[cap.index],
               war.areEnemies(occ, offer.loser) {
                factors.append(("Capital Occupied", 10))
            }

            // Remaining army check
            let loserMen = world.totalSoldiers(of: offer.loser)
            let winnerMen = world.totalSoldiers(of: offer.winner)
            if loserMen == 0 {
                factors.append(("No Standing Army", 20))
            } else if winnerMen >= loserMen * 2 {
                factors.append(("Military Superiority", 10))
            }

            // War duration modifier
            let monthsFought = max(0, (date.year - war.startDate.year) * 12 + (date.month - war.startDate.month))
            if monthsFought < 6 {
                factors.append(("Early War Enthusiasm", -15))
            } else if monthsFought >= 36 {
                factors.append(("War Exhaustion", 12))
            }

            // White peace bonus after stalemate
            if offer.demands.isEmpty && abs(winnerWSPercent) < 15 && monthsFought >= 6 {
                factors.append(("White Peace Willingness", 20))
            }
        }

        let totalScore = factors.reduce(0) { $0 + $1.score }
        return PeaceEvaluation(
            willAccept: totalScore >= 0,
            score: totalScore,
            totalCost: totalCost,
            factors: factors
        )
    }

    /// True if `country` is currently part of a coalition against `target`.
    public func isInCoalition(_ country: CountryID, against target: CountryID) -> Bool {
        coalitions[target]?.contains(country) ?? false
    }

    /// Coalition member countries against `target`, sorted by ID.
    public func coalitionMembers(against target: CountryID) -> [CountryID] {
        (coalitions[target] ?? []).sorted { $0.index < $1.index }
    }
}

// MARK: - Executing Peace Treaties on World

extension World {

    /// Executes a peace offer if accepted (or `forceAccept: true`), applying territorial transfers,
    /// core returns, indemnities, reparations, subjugations, treaty annulments, nation releases,
    /// scaled truces (5–15 yrs), and Aggressive Expansion / Coalition updates.
    ///
    /// Returns the truce length in years on success.
    @discardableResult
    public mutating func executePeaceTreaty(
        _ offer: PeaceOffer,
        date: GameDate,
        forceAccept: Bool = false
    ) -> Result<Int, PeaceTreatyError> {
        guard var war = diplomacy.wars.first(where: { $0.id == offer.warID }) else {
            return .failure(.warNotFound)
        }
        guard war.isParticipant(offer.winner),
              war.isParticipant(offer.loser),
              war.areEnemies(offer.winner, offer.loser) else {
            return .failure(.notBelligerents)
        }

        let totalCost = diplomacy.totalPeaceCost(for: offer, war: war, in: self)
        if totalCost > 100 {
            return .failure(.exceedsMaxCost(cost: totalCost))
        }

        if !forceAccept {
            let evaluation = diplomacy.evaluatePeaceOffer(offer, date: date, in: self)
            if !evaluation.willAccept {
                return .failure(.rejected(evaluation: evaluation))
            }
        }

        // Validate demand targets before mutating state
        for demand in offer.demands {
            switch demand {
            case .cedeProvince(let pid, _), .returnCore(let pid, _):
                if provinces.owner[pid.index] != offer.loser {
                    return .failure(.invalidDemand("Loser does not own \(provinces.name[pid.index])."))
                }
            default:
                break
            }
        }

        let truceYears = diplomacy.truceDurationYears(forPeaceCost: totalCost)
        let aeGenerated = diplomacy.aggressiveExpansionForPeace(offer, war: war, in: self)

        // 1. Apply each peace demand
        for demand in offer.demands {
            switch demand {
            case .cedeProvince(let pid, let recipient):
                transferProvince(pid, to: recipient, from: offer.loser)
                provinces.claims[pid.index].remove(recipient)

            case .returnCore(let pid, let recipient):
                transferProvince(pid, to: recipient, from: offer.loser)
                provinces.cores[pid.index].insert(recipient)
                provinces.claims[pid.index].remove(recipient)

            case .ducatIndemnity(let amount):
                let transfer = max(0.0, amount)
                countries.treasury[offer.loser.index] -= transfer
                countries.treasury[offer.winner.index] += transfer

            case .warReparations:
                let expiry = GameDate(year: date.year + 10, month: date.month, day: date.day)
                diplomacy.warReparations.removeAll { $0.payer == offer.loser && $0.receiver == offer.winner }
                diplomacy.warReparations.append(WarReparation(payer: offer.loser, receiver: offer.winner, until: expiry))

            case .makeVassal:
                countries.overlord[offer.loser.index] = offer.winner
                countries.subjectType[offer.loser.index] = .vassal
                diplomacy.setOpinion(of: offer.winner, by: offer.loser, value: max(-25, diplomacy.opinion(of: offer.winner, by: offer.loser)))

            case .makeTributary:
                countries.overlord[offer.loser.index] = offer.winner
                countries.subjectType[offer.loser.index] = .tributary

            case .annulTreaty(let other):
                diplomacy.removeTreaty(.alliance, between: offer.loser, and: other)
                diplomacy.removeTreaty(.guarantee, between: offer.loser, and: other)
                diplomacy.removeTreaty(.guarantee, between: other, and: offer.loser)
                diplomacy.removeTreaty(.nonAggression, between: offer.loser, and: other)
                diplomacy.removeTreaty(.militaryAccess, between: offer.loser, and: other)
                diplomacy.removeTreaty(.militaryAccess, between: other, and: offer.loser)
                diplomacy.modifyOpinion(of: other, by: offer.loser, delta: -25)

            case .releaseNation(let country):
                let targetProvs = provinces(ownedBy: offer.loser).filter { provinces.cores[$0.index].contains(country) }
                for pid in targetProvs {
                    transferProvince(pid, to: country, from: offer.loser)
                }
                countries.overlord[country.index] = nil
                countries.subjectType[country.index] = nil
                if countries.capital[country.index] == nil {
                    countries.capital[country.index] = targetProvs.max(by: { provinces.development[$0.index] < provinces.development[$1.index] })
                }
                diplomacy.setOpinion(of: offer.winner, by: country, value: 100)
                diplomacy.setTrust(of: offer.winner, by: country, value: 70)
            }
        }

        // Check if loser was fully annexed (0 provinces left)
        if provinces(ownedBy: offer.loser).isEmpty {
            cleanupAnnexedCountry(offer.loser)
        }

        // 2. Apply Aggressive Expansion and update coalitions immediately
        if aeGenerated > 0 {
            diplomacy.generateAggressiveExpansion(by: offer.winner, amount: aeGenerated, world: self)
            DiplomacySystem.updateCoalitions(&self)
        }

        // 3. Truce & War cleanup
        let truceExpiry = GameDate(year: date.year + truceYears, month: date.month, day: date.day)
        let isMainPeace = (offer.winner == war.primaryAttacker && offer.loser == war.primaryDefender)
            || (offer.winner == war.primaryDefender && offer.loser == war.primaryAttacker)

        if isMainPeace {
            // Establish truces across all belligerents
            for a in war.attackers {
                for d in war.defenders where a != d {
                    diplomacy.removeTreaty(.truce, between: a, and: d)
                    diplomacy.addTreaty(Treaty(first: a, second: d, type: .truce, expiry: truceExpiry, note: "Peace of \(war.name)"))
                }
            }
            // Clear occupations belonging to this war
            for p in 0..<provinces.count {
                if let occ = provinces.occupiedBy[p], let owner = provinces.owner[p] {
                    if war.areEnemies(occ, owner) {
                        provinces.occupiedBy[p] = nil
                        provinces.occupationTarget[p] = nil
                        provinces.occupationProgressDays[p] = 0
                    }
                }
            }
            diplomacy.endWar(id: war.id)
        } else {
            // Separate peace: loser leaves war with scaled truce against winner's side
            let opposingSide = war.isAttacker(offer.winner) ? war.attackers : war.defenders
            for opp in opposingSide where opp != offer.loser {
                diplomacy.removeTreaty(.truce, between: opp, and: offer.loser)
                diplomacy.addTreaty(Treaty(first: opp, second: offer.loser, type: .truce, expiry: truceExpiry, note: "Separate peace in \(war.name)"))
            }
            // Clear occupations involving loser
            for p in 0..<provinces.count {
                if provinces.occupiedBy[p] == offer.loser || (provinces.owner[p] == offer.loser && provinces.occupiedBy[p] != nil) {
                    provinces.occupiedBy[p] = nil
                    provinces.occupationTarget[p] = nil
                    provinces.occupationProgressDays[p] = 0
                }
            }
            war.attackers.removeAll { $0 == offer.loser }
            war.defenders.removeAll { $0 == offer.loser }
            if war.attackers.isEmpty || war.defenders.isEmpty {
                diplomacy.endWar(id: war.id)
            } else {
                diplomacy.updateWar(war)
            }
        }

        // Refresh coalition membership (truces remove coalition members)
        DiplomacySystem.updateCoalitions(&self)

        // Record in court chronicles
        let winName = countries.name[offer.winner.index]
        let loseName = countries.name[offer.loser.index]
        let summary = "Peace signed ending hostilities between \(winName) and \(loseName) (\(totalCost)% terms; \(truceYears)-year truce)."
        people.record(date, offer.winner, summary)
        people.record(date, offer.loser, summary)

        return .success(truceYears)
    }

    private mutating func transferProvince(_ pid: ProvinceID, to recipient: CountryID, from previousOwner: CountryID) {
        provinces.owner[pid.index] = recipient
        provinces.occupiedBy[pid.index] = nil
        provinces.occupationTarget[pid.index] = nil
        provinces.occupationProgressDays[pid.index] = 0
        provinces.holder[pid.index] = nil

        if countries.capital[previousOwner.index] == pid {
            let remaining = provinces(ownedBy: previousOwner)
            countries.capital[previousOwner.index] = remaining.max(by: {
                provinces.development[$0.index] < provinces.development[$1.index]
            })
        }
    }

    private mutating func cleanupAnnexedCountry(_ country: CountryID) {
        countries.capital[country.index] = nil
        countries.overlord[country.index] = nil
        countries.subjectType[country.index] = nil
        for aid in military.armies(of: country, includeRebels: true) {
            military.armies.remove(aid)
        }
        diplomacy.treaties.removeAll { $0.first == country || $0.second == country }
        diplomacy.warReparations.removeAll { $0.payer == country || $0.receiver == country }
        diplomacy.coalitions.removeValue(forKey: country)
        for key in diplomacy.coalitions.keys {
            diplomacy.coalitions[key]?.remove(country)
        }
    }
}
