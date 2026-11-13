import Foundation

/// Tuning for great vassals: nobles who hold provinces for their liege.
public enum VassalModel {
    /// Share of a held province's tax the vassal keeps for himself.
    public static let keepShare = 0.4
    /// Below this opinion of the liege a vassal stops sending taxes.
    public static let refuseBelow = -25
    /// Below this opinion a scheming vassal plots against the ruler's life.
    public static let plotBelow = -50
    /// Lowest intrigue skill for a vassal to try a plot.
    public static let plotIntrigue = 8
    /// Monthly chance that a plotting vassal strikes.
    public static let plotChance = 0.01
    /// Goodwill from being granted land, and grudges from losing it.
    public static let grantFavour = 40
    public static let revokeFavour = -80
    public static let revokeOthersFavour = -20
}

public enum VassalStance: Equatable, Sendable {
    case loyal, discontent, refusing, plotting

    public var displayName: String {
        switch self {
        case .loyal: return "Loyal"
        case .discontent: return "Discontent"
        case .refusing: return "Refuses taxes"
        case .plotting: return "Plotting"
        }
    }
}

/// Holding, inheriting, granting and revoking land; vassal moods and plots.
public enum VassalSystem {

    // MARK: Queries

    /// Provinces this person holds.
    public static func holdings(_ world: World, of x: CharacterID) -> [ProvinceID] {
        world.provinces.ids.filter { world.provinces.holder[$0.index] == x }
    }

    /// The great vassals of a country, most land first.
    public static func vassals(_ world: World, of c: CountryID) -> [CharacterID] {
        var count: [CharacterID: Int] = [:]
        for p in 0..<world.provinces.count where world.provinces.owner[p] == c {
            if let h = world.provinces.holder[p] { count[h, default: 0] += 1 }
        }
        return count.keys.sorted { count[$0]! != count[$1]! ? count[$0]! > count[$1]! : $0.index < $1.index }
    }

    /// The realm a vassal's land lies in (the owner of the first province they hold).
    public static func liege(_ world: World, of x: CharacterID) -> CountryID? {
        for p in 0..<world.provinces.count where world.provinces.holder[p] == x {
            return world.provinces.owner[p]
        }
        return nil
    }

    /// Share of tax a vassal of this realm keeps (laws can change it).
    public static func keepShare(_ world: World, _ c: CountryID) -> Double {
        max(0.05, min(0.8, VassalModel.keepShare + world.government.modifier(c, .vassalKeep)))
    }

    /// What a vassal thinks of their liege's ruler (−100…100).
    public static func opinionOfLiege(_ world: World, _ x: CharacterID, _ c: CountryID) -> Int {
        guard let r = world.countries.ruler[c.index] else { return 0 }
        let ch = world.people.characters
        var o = CharacterSystem.opinion(world, x, of: r) + ch.favour[x.index] + 10
        if let d = ch.dynasty[x.index], !d.hasPrefix("of "), d == ch.dynasty[r.index] { o += 15 }
        o += Int(world.government.modifier(c, .vassalOpinion).rounded())
        // The nobility's tax: heavy angers, light pleases.
        o -= Int(((world.countries.taxLevel[c.index][TaxClass.nobles.rawValue] - 1) * 30).rounded())
        return max(-100, min(100, o))
    }

    public static func stance(_ world: World, _ x: CharacterID, _ c: CountryID) -> VassalStance {
        let o = opinionOfLiege(world, x, c)
        if o < VassalModel.plotBelow && world.people.characters.skill(x, .intrigue) >= VassalModel.plotIntrigue {
            return .plotting
        }
        if o < VassalModel.refuseBelow { return .refusing }
        if o < 0 { return .discontent }
        return .loyal
    }

    /// Who takes a holder's land when they die: lawful sons (and their sons),
    /// brothers and nephews, daughters (not under Salic law), then sons born
    /// outside marriage. Nil = it returns to the crown.
    public static func landHeir(_ world: World, of x: CharacterID, realm c: CountryID?) -> CharacterID? {
        let ch = world.people.characters
        func byAge(_ xs: [CharacterID]) -> [CharacterID] { xs.sorted { ch.birth[$0.index] < ch.birth[$1.index] } }
        func eligible(_ y: CharacterID) -> Bool {
            guard ch.isAlive(y), y != x else { return false }
            if let c, world.countries.ruler[c.index] == y { return false }
            return true
        }
        func maleLine(_ y: CharacterID, depth: Int = 0, bastards: Bool = false) -> CharacterID? {
            for son in byAge(ch.children[y.index].filter { !ch.female[$0.index] && ch.illegitimate[$0.index] == bastards }) {
                if eligible(son) { return son }
                if depth < 3, !bastards, let s = maleLine(son, depth: depth + 1) { return s }
            }
            return nil
        }
        if let son = maleLine(x) { return son }
        if let father = ch.father[x.index] {
            for brother in byAge(ch.children[father.index].filter { !ch.female[$0.index] && !ch.illegitimate[$0.index] && $0 != x }) {
                if eligible(brother) { return brother }
                if let nephew = maleLine(brother) { return nephew }
            }
        }
        let salic = c.map { world.countries.succession[$0.index] == .salic } ?? false
        if !salic, let daughter = byAge(ch.children[x.index].filter { ch.female[$0.index] && !ch.illegitimate[$0.index] && eligible($0) }).first {
            return daughter
        }
        return maleLine(x, bastards: true)
    }

    /// Adults of the court who could be given land.
    public static func grantCandidates(_ world: World, _ c: CountryID, date: GameDate) -> [CharacterID] {
        let ch = world.people.characters
        return ch.ids.filter {
            ch.court[$0.index] == c && ch.isAlive($0) && $0 != world.countries.ruler[c.index]
                && ch.age($0, on: date) >= CharacterSystem.adultAge
        }
    }

    // MARK: Actions

    /// Gives a crown province to a courtier, who becomes (or stays) a vassal.
    @discardableResult
    public static func grant(_ world: inout World, _ p: ProvinceID, to x: CharacterID, date: GameDate) -> Bool {
        guard let c = world.provinces.owner[p.index], world.provinces.holder[p.index] == nil,
              world.people.characters.isAlive(x), world.countries.ruler[c.index] != x else { return false }
        world.provinces.holder[p.index] = x
        world.people.characters.favour[x.index] = min(100, world.people.characters.favour[x.index] + VassalModel.grantFavour)
        world.people.record(date, c, "\(world.people.characters.fullName(x)) is granted \(world.provinces.name[p.index]).")
        return true
    }

    /// Takes a province back into the crown's hands. The holder holds a
    /// grudge, and every other vassal of the realm grows wary.
    @discardableResult
    public static func revoke(_ world: inout World, _ p: ProvinceID, date: GameDate, justified: Bool = false) -> Bool {
        guard let c = world.provinces.owner[p.index], let x = world.provinces.holder[p.index] else { return false }
        world.provinces.holder[p.index] = nil
        if !justified {
            world.people.characters.favour[x.index] = max(-100, world.people.characters.favour[x.index] + VassalModel.revokeFavour)
            for v in vassals(world, of: c) where v != x {
                world.people.characters.favour[v.index] = max(-100, world.people.characters.favour[v.index] + VassalModel.revokeOthersFavour)
            }
        }
        world.people.record(date, c, "\(world.provinces.name[p.index]) is taken from \(world.people.characters.fullName(x)).")
        return true
    }

    /// A holder died: their land passes to their heir, or back to the crown.
    static func passOn(_ world: inout World, from x: CharacterID, date: GameDate) {
        let held = holdings(world, of: x)
        guard let first = held.first else { return }
        let realm = world.provinces.owner[first.index]
        let next = landHeir(world, of: x, realm: realm)
        for p in held { world.provinces.holder[p.index] = next }
        let names = held.map { world.provinces.name[$0.index] }.joined(separator: ", ")
        if let next {
            world.people.record(date, realm, "\(world.people.characters.fullName(next)) inherits \(names).")
        } else {
            world.people.record(date, realm, "\(names) returns to the crown.")
        }
    }

    // MARK: Monthly

    public static func runMonthly(_ world: inout World, date: GameDate, random: inout GameRandom) {
        // Land of the dead passes on; a vassal who became the ruler merges it into the crown.
        var seen = Set<CharacterID>()
        for p in 0..<world.provinces.count {
            guard let h = world.provinces.holder[p], seen.insert(h).inserted else { continue }
            if !world.people.characters.isAlive(h) {
                passOn(&world, from: h, date: date)
            }
        }
        for p in 0..<world.provinces.count {
            guard let h = world.provinces.holder[p] else { continue }
            if let c = world.provinces.owner[p], world.countries.ruler[c.index] == h {
                world.provinces.holder[p] = nil
            } else if world.provinces.owner[p] == nil {
                world.provinces.holder[p] = nil
            }
        }
        // Grudges and gratitude fade.
        for i in 0..<world.people.characters.count where world.people.characters.favour[i] != 0 {
            world.people.characters.favour[i] += world.people.characters.favour[i] > 0 ? -1 : 1
        }
        // Moods: who refuses taxes, who plots.
        var refusing = Set<CharacterID>()
        for c in world.countries.ids {
            for v in vassals(world, of: c) {
                let s = stance(world, v, c)
                if s == .refusing || s == .plotting {
                    refusing.insert(v)
                    if !world.people.refusing.contains(v) {
                        world.people.record(date, c, "\(world.people.characters.fullName(v)) refuses to send taxes.")
                    }
                }
                if s == .plotting && random.unit() < VassalModel.plotChance {
                    plot(&world, by: v, against: c, date: date, random: &random)
                }
            }
        }
        world.people.refusing = refusing
    }

    /// A vassal strikes at the ruler. Their intrigue against the spymaster's
    /// (and their gold for bribes) decides it; if caught, they lose their land.
    static func plot(_ world: inout World, by v: CharacterID, against c: CountryID, date: GameDate, random: inout GameRandom) {
        guard let ruler = world.countries.ruler[c.index] else { return }
        let ch = world.people.characters
        let guardSkill = world.countries.council[c.index][CouncilSeat.spymaster.rawValue].map { ch.skill($0, .intrigue) } ?? 4
        let bribes = min(0.15, ch.gold[v.index] / 100 * 0.05)
        let chance = max(0.05, min(0.6, 0.3 + Double(ch.skill(v, .intrigue) - guardSkill) * 0.05 + bribes))
        let plotter = ch.fullName(v), victim = ch.fullName(ruler)
        if random.unit() < chance {
            world.people.record(date, c, "\(victim) dies, poisoned in a plot by \(plotter).")
            CharacterSystem.kill(&world, ruler, date: date, random: &random)
        } else {
            world.people.record(date, c, "A plot by \(plotter) against \(victim) is uncovered.")
            for p in holdings(world, of: v) { revoke(&world, p, date: date, justified: true) }
            world.people.characters.favour[v.index] = -100
        }
    }

    // MARK: Yearly

    /// Vassal families marry among the local nobility, so lines go on.
    public static func runYearly(_ world: inout World, date: GameDate, random: inout GameRandom) {
        var families: [CharacterID] = []
        for c in world.countries.ids {
            for v in vassals(world, of: c) {
                families.append(v)
                families += world.people.characters.children[v.index]
            }
        }
        for x in families {
            let ch = world.people.characters
            guard ch.isAlive(x), ch.livingSpouses(x).isEmpty, let court = ch.court[x.index] else { continue }
            let age = ch.age(x, on: date)
            guard age >= 16, age <= (ch.female[x.index] ? 30 : 45), random.unit() < 0.4 else { continue }
            let home = holdings(world, of: x).first ?? world.provinces(ownedBy: court).first
            let spouse = CharacterSystem.invent(&world, court: court, date: date, random: &random,
                                                dynasty: home.map { "of \(world.provinces.name[$0.index])" },
                                                female: !ch.female[x.index], age: max(16, age - 3))
            CharacterSystem.marry(&world, x, spouse)
        }
    }
}
