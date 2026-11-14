import Foundation

extension GameRandom {
    /// A number in 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// Births, deaths, marriages, succession and councils.
public enum CharacterSystem {
    public static let adultAge = 16

    public static func defaultLaw(_ g: GovernmentType) -> SuccessionLaw {
        switch g {
        case .monarchy: return .primogeniture
        case .steppeHorde, .tribal: return .seniority
        case .republic, .theocracy: return .elective
        }
    }

    // MARK: Health

    /// Chance of dying within a year at this age (medieval adult mortality
    /// roughly doubling every ten years; dangerous childhood).
    public static func yearlyDeathChance(age: Int, sickly: Bool) -> Double {
        var q = 0.00093 * exp(0.0693 * Double(age))
        if age < 5 { q += 0.06 } else if age < 15 { q += 0.01 }
        if sickly { q *= 2 }
        return min(0.9, q)
    }

    // MARK: Effects of rulers and councils

    /// Extra tax from a good ruler and steward (a bad one costs).
    public static func taxBonus(_ world: World, _ c: CountryID) -> Double {
        var bonus = 0.0
        let ch = world.people.characters
        if let r = world.countries.ruler[c.index] { bonus += Double(ch.skill(r, .stewardship) - 5) * 0.015 }
        if let s = world.countries.council[c.index][CouncilSeat.steward.rawValue] {
            bonus += Double(ch.skill(s, .stewardship) - 5) * 0.01
        }
        return min(0.25, max(-0.15, bonus))
    }

    /// Learning points a year from the ruler and the chaplain.
    public static func learningPerYear(_ world: World, _ c: CountryID) -> Double {
        var l = 0.0
        let ch = world.people.characters
        if let r = world.countries.ruler[c.index] { l += Double(ch.skill(r, .learning)) / 8 }
        if let s = world.countries.council[c.index][CouncilSeat.chaplain.rawValue] {
            l += Double(ch.skill(s, .learning)) / 4
        }
        return l
    }

    /// How much `a` likes `b` (−100…100): shared traits, clashing traits, family.
    public static func opinion(_ world: World, _ a: CharacterID, of b: CharacterID) -> Int {
        let ch = world.people.characters
        let tr = world.people.traits
        var o = 0
        for t in ch.traits[a.index] {
            if ch.traits[b.index].contains(t) { o += 10 }
            if let opp = tr.opposite[t.index], ch.traits[b.index].contains(opp) { o -= 15 }
        }
        let family = ch.spouses[a.index].contains(b) || ch.children[a.index].contains(b)
            || ch.children[b.index].contains(a) || ch.siblings(a).contains(b)
        if family { o += 20 }
        if ch.religion[a.index] != ch.religion[b.index] { o -= ch.religion[a.index].family == ch.religion[b.index].family ? 5 : 20 }
        return max(-100, min(100, o))
    }

    // MARK: Succession

    /// Who inherits if the ruler dies now (nil = nobody; a relative will be found or made).
    public static func heir(_ world: World, _ c: CountryID, date: GameDate) -> CharacterID? {
        heir(world, c, date: date, charsByCourt: nil, charsByDynasty: nil)
    }

    static func heir(
        _ world: World,
        _ c: CountryID,
        date: GameDate,
        charsByCourt: [[CharacterID]]?,
        charsByDynasty: [String: [CharacterID]]?
    ) -> CharacterID? {
        guard let ruler = world.countries.ruler[c.index] else { return nil }
        let ch = world.people.characters
        let law = world.countries.succession[c.index]
        func alive(_ x: CharacterID) -> Bool { ch.isAlive(x) && x != ruler }
        func byAge(_ xs: [CharacterID]) -> [CharacterID] { xs.sorted { ch.birth[$0.index] < ch.birth[$1.index] } }
        func maleLine(_ x: CharacterID, depth: Int = 0) -> CharacterID? {
            for son in byAge(ch.children[x.index].filter { !ch.female[$0.index] }) {
                if alive(son) { return son }
                if depth < 3, let s = maleLine(son, depth: depth + 1) { return s }
            }
            return nil
        }
        let dynasty = ch.dynasty[ruler.index]
        func dynastyMen() -> [CharacterID] {
            guard let d = dynasty, !d.hasPrefix("of ") else { return [] }
            let pool = charsByDynasty?[d] ?? ch.ids
            return pool.filter { ch.dynasty[$0.index] == d && !ch.female[$0.index] && alive($0) }
        }

        switch law {
        case .elective:
            var candidates = Set<CharacterID>()
            for x in world.countries.council[c.index].compactMap({ $0 }) where alive(x) { candidates.insert(x) }
            let courtPool = charsByCourt?[c.index] ?? ch.ids
            for x in courtPool where ch.court[x.index] == c && alive(x) && !ch.female[x.index]
                && ch.age(x, on: date) >= 25 { candidates.insert(x) }
            return candidates.max { a, b in
                let sa = ch.skills[a.index].reduce(0, +), sb = ch.skills[b.index].reduce(0, +)
                return sa != sb ? sa < sb : a.index > b.index
            }
        case .seniority:
            let men = dynastyMen().filter { ch.age($0, on: date) >= adultAge }
            if let eldest = byAge(men).first { return eldest }
            return maleLine(ruler)
        case .primogeniture, .salic:
            if let son = maleLine(ruler) { return son }
            if let father = ch.father[ruler.index] {
                for brother in byAge(ch.children[father.index].filter { !ch.female[$0.index] && $0 != ruler }) {
                    if alive(brother) { return brother }
                    if let nephew = maleLine(brother) { return nephew }
                }
            }
            if law == .primogeniture,
               let daughter = byAge(ch.children[ruler.index].filter { ch.female[$0.index] && alive($0) }).first {
                return daughter
            }
            return byAge(dynastyMen()).first
        }
    }

    /// Makes a new adult person for a court (a distant cousin, a new doge, a courtier).
    @discardableResult
    public static func invent(_ world: inout World, court c: CountryID, date: GameDate, random: inout GameRandom,
                              dynasty: String?, female: Bool = false, age: Int? = nil) -> CharacterID {
        let culture = world.countries.ruler[c.index].map { world.people.characters.culture[$0.index] }
            ?? world.provinces.majorityCulture[world.countries.capital[c.index]?.index ?? 0]
        let religion = world.countries.religion[c.index]
        let years = age ?? (25 + Int(random.next() % 25))
        let name = pickName(world, culture: culture, religion: religion, female: female, random: &random)
        let birth = GameDate(year: date.year - years, month: 1 + Int(random.next() % 12), day: 1 + Int(random.next() % 28))
        let traits = randomTraits(world, random: &random)
        let id = world.people.characters.add(
            key: "gen\(world.people.characters.count)", name: name, dynasty: dynasty, female: female, birth: birth,
            culture: culture, religion: religion, traits: traits,
            skills: skills(world, traits: traits, random: &random), court: c, invented: true)
        return id
    }

    static func pickName(_ world: World, culture: CultureID, religion: Religion, female: Bool, random: inout GameRandom) -> String {
        let family = world.cultures.family[culture.index]
        let key = religion.family == .muslim && world.people.names.male["\(family)@muslim"] != nil ? "\(family)@muslim" : family
        let list = (female ? world.people.names.female[key] : world.people.names.male[key])
            ?? (female ? world.people.names.female["arab"] : world.people.names.male["arab"]) ?? ["Unnamed"]
        return list[Int(random.next() % UInt64(list.count))]
    }

    static func randomTraits(_ world: World, random: inout GameRandom) -> [TraitID] {
        let tr = world.people.traits
        var out: [TraitID] = []
        let n = 1 + Int(random.next() % 2)
        for _ in 0..<n {
            let t = TraitID(Int(random.next() % UInt64(tr.count)))
            if out.contains(t) || tr.key[t.index] == "blind" { continue }
            if let o = tr.opposite[t.index], out.contains(o) { continue }
            out.append(t)
        }
        return out
    }

    static func skills(_ world: World, traits: [TraitID], random: inout GameRandom) -> [Int] {
        (0..<Skill.allCases.count).map { s in
            let fromTraits = traits.reduce(0) { $0 + world.people.traits.skills[$1.index][s] }
            return max(0, min(20, 5 + fromTraits + Int(random.next() % 5) - 2))
        }
    }

    /// The ruler died (or left): the heir takes over, or someone is found.
    static func succeed(_ world: inout World, _ c: CountryID, date: GameDate, random: inout GameRandom) {
        let old = world.countries.ruler[c.index]
        // A smooth succession needs a known, adult heir; otherwise the realm is shaken.
        let smooth = world.countries.heir[c.index].map {
            world.people.characters.isAlive($0) && world.people.characters.age($0, on: date) >= adultAge
        } ?? false
        if !smooth && c.index < world.government.count {
            GovernmentSystem.changeStability(&world, c, by: -1)
        }
        var next = world.countries.heir[c.index].flatMap { world.people.characters.isAlive($0) ? $0 : nil }
            ?? heir(world, c, date: date)
        if next == nil {
            let dynasty = old.flatMap { world.people.characters.dynasty[$0.index] }
            let isDynastic = world.countries.succession[c.index] != .elective
            next = invent(&world, court: c, date: date, random: &random, dynasty: isDynastic ? dynasty : nil)
        }
        guard let ruler = next else { return }
        world.countries.ruler[c.index] = ruler
        world.people.characters.court[ruler.index] = world.people.characters.court[ruler.index] ?? c
        // A council member who becomes ruler leaves the council.
        for s in CouncilSeat.allCases where world.countries.council[c.index][s.rawValue] == ruler {
            world.countries.council[c.index][s.rawValue] = nil
        }
        world.countries.heir[c.index] = heir(world, c, date: date)
    }

    /// Someone dies now (events, battles, executions): councils and thrones
    /// are refilled at once.
    public static func kill(_ world: inout World, _ x: CharacterID, date: GameDate, random: inout GameRandom) {
        guard world.people.characters.isAlive(x) else { return }
        world.people.characters.death[x.index] = date
        VassalSystem.passOn(&world, from: x, date: date)
        for c in world.countries.ids {
            for s in CouncilSeat.allCases where world.countries.council[c.index][s.rawValue] == x {
                world.countries.council[c.index][s.rawValue] = nil
            }
        }
        for c in world.countries.ids where world.countries.ruler[c.index] == x {
            succeed(&world, c, date: date, random: &random)
        }
        for c in world.countries.ids where world.countries.heir[c.index] == x {
            world.countries.heir[c.index] = heir(world, c, date: date)
        }
    }

    // MARK: Monthly

    public static func runMonthly(_ world: inout World, date: GameDate, random: inout GameRandom) {
        var ch = world.people.characters
        let sicklyTrait = world.people.traits.id(forKey: "sickly")
        var died: [CharacterID] = []
        // Deaths.
        for i in 0..<ch.count where ch.death[i] == nil {
            let id = CharacterID(i)
            let q = yearlyDeathChance(age: ch.age(id, on: date), sickly: sicklyTrait.map { ch.traits[i].contains($0) } ?? false)
            if random.unit() < q / 12 {
                ch.death[i] = date
                died.append(id)
            }
        }
        // Births.
        var births: [(mother: CharacterID, father: CharacterID)] = []
        for i in 0..<ch.count where ch.female[i] && ch.death[i] == nil {
            let mother = CharacterID(i)
            let age = ch.age(mother, on: date)
            guard (16...42).contains(age), let husband = ch.livingSpouses(mother).first else { continue }
            let chance = age < 35 ? 0.28 : 0.12
            if random.unit() < chance / 12 { births.append((mother, husband)) }
        }
        world.people.characters = ch
        for (mother, father) in births {
            bear(&world, mother: mother, father: father, date: date, random: &random)
        }

        // Councils lose the dead; rulers die and are succeeded.
        let deadSet = Set(died)
        for c in world.countries.ids {
            for s in CouncilSeat.allCases {
                if let x = world.countries.council[c.index][s.rawValue], deadSet.contains(x) {
                    world.countries.council[c.index][s.rawValue] = nil
                }
            }
            if let r = world.countries.ruler[c.index], deadSet.contains(r) {
                succeed(&world, c, date: date, random: &random)
            }
        }
        // Heirs are kept current; computer countries fill empty seats.
        let countryCount = world.countries.count
        var charsByCourt = [[CharacterID]](repeating: [], count: countryCount)
        var charsByDynasty: [String: [CharacterID]] = [:]
        let allChars = world.people.characters
        for i in 0..<allChars.count where allChars.death[i] == nil {
            let id = CharacterID(i)
            if let court = allChars.court[i], court.index < countryCount {
                charsByCourt[court.index].append(id)
            }
            if let d = allChars.dynasty[i], !d.hasPrefix("of ") {
                charsByDynasty[d, default: []].append(id)
            }
        }
        var firstProvByCountry = [ProvinceID?](repeating: nil, count: countryCount)
        for p in 0..<world.provinces.count {
            if let o = world.provinces.owner[p], firstProvByCountry[o.index] == nil {
                firstProvByCountry[o.index] = ProvinceID(p)
            }
        }

        for c in world.countries.ids {
            world.countries.heir[c.index] = heir(
                world,
                c,
                date: date,
                charsByCourt: charsByCourt,
                charsByDynasty: charsByDynasty
            )
            if !world.humanCountries.contains(c) {
                fillCouncil(
                    &world,
                    c,
                    date: date,
                    random: &random,
                    courtPool: charsByCourt[c.index],
                    firstProvince: firstProvByCountry[c.index]
                )
            }
        }
    }

    static func bear(_ world: inout World, mother: CharacterID, father: CharacterID, date: GameDate, random: inout GameRandom) {
        let ch = world.people.characters
        let female = random.next() % 2 == 0
        // Royal habit: often named after a grandparent.
        var name = pickName(world, culture: ch.culture[father.index], religion: ch.religion[father.index], female: female, random: &random)
        if random.unit() < 0.35 {
            let grand = female ? ch.mother[father.index] ?? ch.mother[mother.index] : ch.father[father.index]
            if let g = grand { name = ch.name[g.index].components(separatedBy: " ").first ?? name }
        }
        var traits: [TraitID] = []
        let parentTraits = ch.traits[father.index] + ch.traits[mother.index]
        if !parentTraits.isEmpty && random.unit() < 0.5 {
            traits.append(parentTraits[Int(random.next() % UInt64(parentTraits.count))])
        }
        for t in randomTraits(world, random: &random) where !traits.contains(t) && traits.count < 2 {
            if let o = world.people.traits.opposite[t.index], traits.contains(o) { continue }
            traits.append(t)
        }
        let id = world.people.characters.add(
            key: "gen\(world.people.characters.count)", name: name, dynasty: ch.dynasty[father.index], female: female,
            birth: date, culture: ch.culture[father.index], religion: ch.religion[father.index], traits: traits,
            skills: skills(world, traits: traits, random: &random), court: ch.court[father.index] ?? ch.court[mother.index],
            invented: true)
        world.people.characters.father[id.index] = father
        world.people.characters.mother[id.index] = mother
        world.people.characters.children[father.index].append(id)
        world.people.characters.children[mother.index].append(id)
    }

    /// Candidates for a council seat: adults of the court, not the ruler,
    /// not already on the council.
    public static func councilCandidates(_ world: World, _ c: CountryID, date: GameDate) -> [CharacterID] {
        let ch = world.people.characters
        let seated = Set(world.countries.council[c.index].compactMap { $0 })
        return ch.ids.filter {
            ch.court[$0.index] == c && ch.isAlive($0) && $0 != world.countries.ruler[c.index]
                && !seated.contains($0) && ch.age($0, on: date) >= adultAge
        }
    }

    public static func appoint(_ world: inout World, _ c: CountryID, _ seat: CouncilSeat, _ who: CharacterID?) {
        if let who {
            for s in CouncilSeat.allCases where world.countries.council[c.index][s.rawValue] == who {
                world.countries.council[c.index][s.rawValue] = nil
            }
        }
        world.countries.council[c.index][seat.rawValue] = who
    }

    /// Fills empty seats with the ablest courtier, or a newcomer.
    public static func fillCouncil(_ world: inout World, _ c: CountryID, date: GameDate, random: inout GameRandom) {
        fillCouncil(
            &world,
            c,
            date: date,
            random: &random,
            courtPool: nil,
            firstProvince: world.provinces(ownedBy: c).first
        )
    }

    static func fillCouncil(
        _ world: inout World,
        _ c: CountryID,
        date: GameDate,
        random: inout GameRandom,
        courtPool: [CharacterID]?,
        firstProvince: ProvinceID?
    ) {
        for seat in CouncilSeat.allCases where world.countries.council[c.index][seat.rawValue] == nil {
            let skill = seat.skill
            let ch = world.people.characters
            let seated = Set(world.countries.council[c.index].compactMap { $0 })
            let pool = courtPool ?? ch.ids
            let best = pool.filter {
                ch.court[$0.index] == c && ch.isAlive($0) && $0 != world.countries.ruler[c.index]
                    && !seated.contains($0) && ch.age($0, on: date) >= adultAge
            }
            .max { ch.skill($0, skill) < ch.skill($1, skill) }
            if let b = best, ch.skill(b, skill) >= 6 {
                appoint(&world, c, seat, b)
            } else {
                let home = firstProvince.map { "of \(world.provinces.name[$0.index])" }
                let newcomer = invent(&world, court: c, date: date, random: &random, dynasty: home)
                appoint(&world, c, seat, newcomer)
            }
        }
    }

    // MARK: Marriage

    public enum MarriageRefusal: Equatable, Sendable {
        case alreadyMarried, sameSex, tooYoung, differentFaith, ageGap, dead, theyRefuse

        public var reason: String {
            switch self {
            case .alreadyMarried: return "Already married"
            case .sameSex: return "Must be a man and a woman"
            case .tooYoung: return "Too young to marry"
            case .differentFaith: return "Different faiths"
            case .ageGap: return "Too far apart in age"
            case .dead: return "No longer alive"
            case .theyRefuse: return "Their family looks higher"
            }
        }
    }

    static func isMarried(_ world: World, _ x: CharacterID) -> Bool {
        let ch = world.people.characters
        // Muslim men may have up to four wives.
        let limit = !ch.female[x.index] && ch.religion[x.index].family == .muslim ? 4 : 1
        return ch.livingSpouses(x).count >= limit
    }

    /// Would `b`'s family accept a match with `a` (from `a`'s country)?
    public static func marriageRefusal(_ world: World, _ a: CharacterID, _ b: CharacterID, date: GameDate) -> MarriageRefusal? {
        let ch = world.people.characters
        guard ch.isAlive(a), ch.isAlive(b) else { return .dead }
        if ch.female[a.index] == ch.female[b.index] { return .sameSex }
        if isMarried(world, a) || isMarried(world, b) { return .alreadyMarried }
        if ch.age(a, on: date) < 15 || ch.age(b, on: date) < 15 { return .tooYoung }
        if ch.religion[a.index].family != ch.religion[b.index].family { return .differentFaith }
        if abs(ch.age(a, on: date) - ch.age(b, on: date)) > 25 { return .ageGap }
        // Rulers and heirs of much bigger realms look higher.
        if let theirs = ch.court[b.index], let ours = ch.court[a.index] {
            let isGreat = world.countries.ruler[theirs.index] == b || world.countries.heir[theirs.index] == b
            if isGreat && power(world, theirs) > power(world, ours) * 2.5 { return .theyRefuse }
        }
        return nil
    }

    static func power(_ world: World, _ c: CountryID) -> Double {
        var dev = 0.0
        for p in 0..<world.provinces.count where world.provinces.owner[p] == c {
            dev += Double(world.provinces.development[p])
        }
        return max(1, dev)
    }

    /// Marries the two; the wife joins the husband's court unless she rules.
    public static func marry(_ world: inout World, _ a: CharacterID, _ b: CharacterID) {
        world.people.characters.marry(a, b)
        let (wife, husband) = world.people.characters.female[a.index] ? (a, b) : (b, a)
        if let wc = world.people.characters.court[wife.index], world.countries.ruler[wc.index] == wife { return }
        world.people.characters.court[wife.index] = world.people.characters.court[husband.index]
    }

    /// Unmarried members of a ruler's close family (spouses' children,
    /// siblings, the ruler and heir) old enough to marry.
    public static func marriageableFamily(_ world: World, _ c: CountryID, date: GameDate) -> [CharacterID] {
        let ch = world.people.characters
        guard let r = world.countries.ruler[c.index] else { return [] }
        var fam = [r] + ch.children[r.index] + ch.siblings(r)
        if let h = world.countries.heir[c.index] { fam.append(h) }
        var seen = Set<CharacterID>()
        return fam.filter { seen.insert($0).inserted && ch.isAlive($0) && ch.age($0, on: date) >= 15 && !isMarried(world, $0) }
    }

    /// Yearly: computer countries marry off their families, best match first.
    public static func runYearly(_ world: inout World, date: GameDate, random: inout GameRandom) {
        let countryCount = world.countries.count
        var devByCountry = Array(repeating: 0.0, count: countryCount)
        var firstProvByCountry = Array<ProvinceID?>(repeating: nil, count: countryCount)
        for p in 0..<world.provinces.count {
            if let owner = world.provinces.owner[p], owner.index < countryCount {
                devByCountry[owner.index] += Double(world.provinces.development[p])
                if firstProvByCountry[owner.index] == nil {
                    firstProvByCountry[owner.index] = ProvinceID(p)
                }
            }
        }
        var pool: [CharacterID] = []
        pool.reserveCapacity(countryCount * 2)
        for c in world.countries.ids { pool += marriageableFamily(world, c, date: date) }
        for c in world.countries.ids where !world.humanCountries.contains(c) {
            for x in marriageableFamily(world, c, date: date) {
                guard !isMarried(world, x) else { continue }
                let ch = world.people.characters
                let age = ch.age(x, on: date)
                guard age <= (ch.female[x.index] ? 30 : 45) else { continue }
                let best = pool
                    .filter { ch.court[$0.index] != c && marriageRefusal(world, x, $0, date: date) == nil
                        && !(ch.court[$0.index].map { world.humanCountries.contains($0) } ?? false) }
                    .max {
                        let p0 = max(1.0, devByCountry[ch.court[$0.index]!.index])
                        let p1 = max(1.0, devByCountry[ch.court[$1.index]!.index])
                        return p0 < p1
                    }
                if let match = best, random.unit() < 0.6 {
                    marry(&world, x, match)
                } else if random.unit() < 0.3 {
                    // A local noble match.
                    let spouse = invent(&world, court: c, date: date, random: &random,
                                        dynasty: firstProvByCountry[c.index].map { "of \(world.provinces.name[$0.index])" },
                                        female: !ch.female[x.index], age: max(16, age - 3))
                    marry(&world, x, spouse)
                }
            }
        }
    }
}
