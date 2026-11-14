/// People: rulers, heirs, families and councils. The 1453 cast comes from
/// `Resources/characters1453.json` (built by `tools/characters/chargen.py`
/// from `data/characters/`).

public struct CharacterID: Hashable, Sendable, Codable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

public struct TraitID: Hashable, Sendable, Codable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

public enum Skill: Int, CaseIterable, Sendable {
    case diplomacy, martial, stewardship, intrigue, learning

    public var displayName: String {
        switch self {
        case .diplomacy: return "Diplomacy"
        case .martial: return "Martial"
        case .stewardship: return "Stewardship"
        case .intrigue: return "Intrigue"
        case .learning: return "Learning"
        }
    }
}

public enum CouncilSeat: Int, CaseIterable, Sendable {
    case chancellor, marshal, steward, spymaster, chaplain

    public var skill: Skill {
        switch self {
        case .chancellor: return .diplomacy
        case .marshal: return .martial
        case .steward: return .stewardship
        case .spymaster: return .intrigue
        case .chaplain: return .learning
        }
    }

    public var displayName: String {
        switch self {
        case .chancellor: return "Chancellor"
        case .marshal: return "Marshal"
        case .steward: return "Steward"
        case .spymaster: return "Spymaster"
        case .chaplain: return "Court Chaplain"
        }
    }

    public var effectText: String {
        switch self {
        case .chancellor: return "Diplomacy (relations, marriages; more with diplomacy in Phase 7)"
        case .marshal: return "Martial: +1.5% manpower & +1% army quality per point above 5"
        case .steward: return "Stewardship: +1% tax per point above 5"
        case .spymaster: return "Intrigue (plots, later)"
        case .chaplain: return "Learning: learning points each year"
        }
    }
}

public enum SuccessionLaw: String, CaseIterable, Sendable, Codable {
    /// Eldest son, then brothers, nephews, daughters, then the nearest of the dynasty.
    case primogeniture
    /// As primogeniture, but never women.
    case salic
    /// The eldest man of the dynasty.
    case seniority
    /// The court picks the ablest candidate.
    case elective

    public var displayName: String {
        switch self {
        case .primogeniture: return "Primogeniture"
        case .salic: return "Salic primogeniture"
        case .seniority: return "Seniority"
        case .elective: return "Elective"
        }
    }
}

public struct TraitTable: Sendable {
    public private(set) var key: [String] = []
    public private(set) var name: [String] = []
    public private(set) var opposite: [TraitID?] = []
    /// Skill changes (diplomacy, martial, stewardship, intrigue, learning).
    public private(set) var skills: [[Int]] = []

    public init() {}

    public var count: Int { key.count }

    public mutating func add(key: String, name: String, skills: [Int]) {
        self.key.append(key)
        self.name.append(name)
        self.opposite.append(nil)
        self.skills.append(skills)
    }

    public mutating func setOpposite(_ t: TraitID, _ o: TraitID) {
        opposite[t.index] = o
    }

    public func id(forKey key: String) -> TraitID? {
        self.key.firstIndex(of: key).map(TraitID.init)
    }
}

public struct CharacterTable: Sendable, Codable {
    public private(set) var key: [String] = []
    public var name: [String] = []
    /// Family name or house; "of <town>" for lesser people; nil for none.
    public var dynasty: [String?] = []
    public var female: [Bool] = []
    public var birth: [GameDate] = []
    public var death: [GameDate?] = []
    public var father: [CharacterID?] = []
    public var mother: [CharacterID?] = []
    public var spouses: [[CharacterID]] = []
    public var children: [[CharacterID]] = []
    public var culture: [CultureID] = []
    public var religion: [Religion] = []
    public var traits: [[TraitID]] = []
    /// Diplomacy, martial, stewardship, intrigue, learning (0–20).
    public var skills: [[Int]] = []
    /// The country whose court the person belongs to.
    public var court: [CountryID?] = []
    /// Made up where history is silent.
    public var invented: [Bool] = []
    public var note: [String?] = []
    /// Born outside marriage: inherits land only when no lawful child is left.
    public var illegitimate: [Bool] = []
    /// Private wealth in ducats (vassals keep part of their provinces' tax).
    public var gold: [Double] = []
    /// Lasting goodwill (+) or grudge (−) toward their liege, fading each month.
    public var favour: [Int] = []

    public init() {}

    public var count: Int { key.count }
    public var ids: [CharacterID] { (0..<count).map(CharacterID.init) }

    @discardableResult
    public mutating func add(key: String, name: String, dynasty: String?, female: Bool, birth: GameDate,
                             culture: CultureID, religion: Religion, traits: [TraitID], skills: [Int],
                             court: CountryID?, invented: Bool, note: String? = nil) -> CharacterID {
        let id = CharacterID(count)
        self.key.append(key)
        self.name.append(name)
        self.dynasty.append(dynasty)
        self.female.append(female)
        self.birth.append(birth)
        self.death.append(nil)
        self.father.append(nil)
        self.mother.append(nil)
        self.spouses.append([])
        self.children.append([])
        self.culture.append(culture)
        self.religion.append(religion)
        self.traits.append(traits)
        self.skills.append(skills)
        self.court.append(court)
        self.invented.append(invented)
        self.note.append(note)
        self.illegitimate.append(false)
        self.gold.append(0)
        self.favour.append(0)
        return id
    }

    public func isAlive(_ c: CharacterID) -> Bool { death[c.index] == nil }

    public func age(_ c: CharacterID, on date: GameDate) -> Int {
        let end = death[c.index] ?? date
        var years = end.year - birth[c.index].year
        if (end.month, end.day) < (birth[c.index].month, birth[c.index].day) { years -= 1 }
        return max(0, years)
    }

    public func id(forKey key: String) -> CharacterID? {
        self.key.firstIndex(of: key).map(CharacterID.init)
    }

    public func fullName(_ c: CharacterID) -> String {
        guard let d = dynasty[c.index], !d.isEmpty else { return name[c.index] }
        // Real names often already include the house ("Francesco Sforza").
        if name[c.index].contains(d) || d.hasPrefix("House of") { return name[c.index] }
        return d.hasPrefix("of ") ? "\(name[c.index]) \(d)" : name[c.index]
    }

    public func skill(_ c: CharacterID, _ s: Skill) -> Int { skills[c.index][s.rawValue] }

    public func siblings(_ c: CharacterID) -> [CharacterID] {
        var out = Set<CharacterID>()
        for parent in [father[c.index], mother[c.index]].compactMap({ $0 }) {
            out.formUnion(children[parent.index])
        }
        out.remove(c)
        return out.sorted { birth[$0.index] < birth[$1.index] }
    }

    public mutating func marry(_ a: CharacterID, _ b: CharacterID) {
        if !spouses[a.index].contains(b) { spouses[a.index].append(b) }
        if !spouses[b.index].contains(a) { spouses[b.index].append(a) }
    }

    public func livingSpouses(_ c: CharacterID) -> [CharacterID] {
        spouses[c.index].filter { death[$0.index] == nil }
    }
}

/// Name lists for people born or invented during the game.
public struct NameLists: Sendable {
    public var male: [String: [String]] = [:]
    public var female: [String: [String]] = [:]
    public init() {}
}

/// Everyone, plus the traits and name lists.
public struct People: Sendable {
    public var traits = TraitTable()
    public var characters = CharacterTable()
    public var names = NameLists()
    /// Recent happenings at courts (newest last, kept short).
    public var chronicle: [ChronicleEntry] = []
    /// Vassals withholding their taxes this month (set by `VassalSystem`).
    public var refusing: Set<CharacterID> = []
    public init() {}

    public mutating func record(_ date: GameDate, _ country: CountryID?, _ text: String) {
        chronicle.append(ChronicleEntry(date: date, country: country, text: text))
        if chronicle.count > 200 { chronicle.removeFirst(chronicle.count - 200) }
    }
}

/// One line in the court chronicle ("Ladislaus Garai refuses to pay taxes").
public struct ChronicleEntry: Sendable, Equatable, Codable {
    public let date: GameDate
    public let country: CountryID?
    public let text: String
}
