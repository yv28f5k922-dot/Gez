public struct CultureID: Hashable, Sendable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

public struct CultureTable: Sendable {
    public private(set) var key: [String] = []
    public private(set) var name: [String] = []
    /// Culture family, e.g. "south_slavic", "turkic".
    public private(set) var family: [String] = []
    private var indexByKey: [String: CultureID] = [:]

    public init() {}

    public var count: Int { key.count }

    @discardableResult
    public mutating func add(key: String, name: String, family: String) -> CultureID {
        let id = CultureID(count)
        self.key.append(key)
        self.name.append(name)
        self.family.append(family)
        indexByKey[key] = id
        return id
    }

    public func id(forKey key: String) -> CultureID? { indexByKey[key] }

    /// All family names, in first-seen order.
    public var families: [String] {
        var seen = Set<String>()
        return family.filter { seen.insert($0).inserted }
    }
}

public enum SocialClass: String, CaseIterable, Sendable {
    case nobles, clergy, burghers, peasants, slaves

    public var displayName: String {
        switch self {
        case .nobles: return "Nobles"
        case .clergy: return "Clergy"
        case .burghers: return "Burghers"
        case .peasants: return "Peasants"
        case .slaves: return "Slaves"
        }
    }
}

/// A Sufi brotherhood's presence in a province, strength 0 to 1.
public struct SufiPresence: Hashable, Sendable {
    public var order: SufiOrder
    public var strength: Double
    public init(order: SufiOrder, strength: Double) {
        self.order = order
        self.strength = strength
    }
}

/// Every group of people in the world: one row per (province, culture,
/// religion, sect, social class). Rows for a province are stored together;
/// `range(for:)` gives them.
public struct PopTable: Sendable {
    public private(set) var province: [ProvinceID] = []
    public var culture: [CultureID] = []
    public var religion: [Religion] = []
    public var sect: [Sect?] = []
    public var socialClass: [SocialClass] = []
    public var size: [Double] = []
    private var ranges: [Range<Int>] = []

    public init() {}

    public var count: Int { size.count }

    public func range(for p: ProvinceID) -> Range<Int> {
        p.index < ranges.count ? ranges[p.index] : 0..<0
    }

    /// Pops must be added province by province, in province order.
    public mutating func beginProvince(_ p: ProvinceID) {
        precondition(p.index == ranges.count, "pops must be added in province order")
        ranges.append(count..<count)
    }

    public mutating func add(culture: CultureID, religion: Religion, sect: Sect?, socialClass: SocialClass, size: Double) {
        precondition(!ranges.isEmpty, "call beginProvince first")
        let p = ProvinceID(ranges.count - 1)
        province.append(p)
        self.culture.append(culture)
        self.religion.append(religion)
        self.sect.append(sect)
        self.socialClass.append(socialClass)
        self.size.append(size)
        let r = ranges[ranges.count - 1]
        ranges[ranges.count - 1] = r.lowerBound..<(r.upperBound + 1)
    }
}

/// Who lives somewhere, summed up.
public struct PopBreakdown: Sendable {
    public var total: Double = 0
    public var byCulture: [CultureID: Double] = [:]
    public var byReligion: [Religion: Double] = [:]
    public var bySect: [Sect: Double] = [:]
    public var byClass: [SocialClass: Double] = [:]

    public init() {}

    /// Largest first, as fractions of the total.
    public func cultureShares() -> [(CultureID, Double)] {
        sortedShares(byCulture)
    }

    public func religionShares() -> [(Religion, Double)] {
        sortedShares(byReligion)
    }

    public func classShares() -> [(SocialClass, Double)] {
        SocialClass.allCases.compactMap { c in
            guard let v = byClass[c], v > 0, total > 0 else { return nil }
            return (c, v / total)
        }
    }

    private func sortedShares<K: Hashable>(_ d: [K: Double]) -> [(K, Double)] {
        guard total > 0 else { return [] }
        return d.map { ($0.key, $0.value / total) }.sorted { $0.1 > $1.1 }
    }
}

extension World {
    public func breakdown(of provinceIDs: [ProvinceID]) -> PopBreakdown {
        var b = PopBreakdown()
        for p in provinceIDs {
            for i in pops.range(for: p) {
                let s = pops.size[i]
                b.total += s
                b.byCulture[pops.culture[i], default: 0] += s
                b.byReligion[pops.religion[i], default: 0] += s
                if let sect = pops.sect[i] { b.bySect[sect, default: 0] += s }
                b.byClass[pops.socialClass[i], default: 0] += s
            }
        }
        return b
    }

    public func breakdown(of province: ProvinceID) -> PopBreakdown {
        breakdown(of: [province])
    }

    public func breakdown(ofState state: StateID) -> PopBreakdown {
        breakdown(of: states.provinces[state.index])
    }

    public func breakdown(ofCountry country: CountryID) -> PopBreakdown {
        breakdown(of: provinces(ownedBy: country))
    }

    /// Recomputes each province's cached population and majority religion
    /// and culture from its pops.
    public mutating func refreshProvinceSummaries() {
        for p in 0..<provinces.count {
            let id = ProvinceID(p)
            var total = 0.0
            var byReligion: [Religion: Double] = [:]
            var byCulture: [CultureID: Double] = [:]
            for i in pops.range(for: id) {
                total += pops.size[i]
                byReligion[pops.religion[i], default: 0] += pops.size[i]
                byCulture[pops.culture[i], default: 0] += pops.size[i]
            }
            provinces.population[p] = total
            if let top = byReligion.max(by: { a, b in a.value == b.value ? a.key.rawValue > b.key.rawValue : a.value < b.value }) {
                provinces.religion[p] = top.key
            }
            if let top = byCulture.max(by: { a, b in a.value == b.value ? a.key.index > b.key.index : a.value < b.value }) {
                provinces.majorityCulture[p] = top.key
            }
        }
    }
}

/// How a province's people divide into social classes at the start.
public enum ClassSplit {
    public struct Targets: Sendable {
        public var nobles: Double
        public var clergy: Double
        public var burghers: Double
        public var slaves: Double
    }

    /// Fractions of the whole population for each class except peasants
    /// (peasants are everyone left).
    public static func targets(development: Int, government: GovernmentType?, slavery: Double) -> Targets {
        let nobles: Double = government == .steppeHorde ? 0.04 : 0.015
        let clergy: Double = government == .theocracy ? 0.04 : 0.015
        let burghers = 0.02 + 0.016 * Double(min(max(development, 1), 10))
        return Targets(nobles: nobles, clergy: clergy, burghers: burghers, slaves: max(0, slavery))
    }

    /// Splits each group into classes. Nobles come mostly from the ruler's
    /// religion; merchant diasporas (Jewish, Armenian, Italian) are more
    /// often burghers; slaves are more often from outside the ruler's faith.
    public static func split(
        groups: [(culture: CultureID, family: String, religion: Religion, sect: Sect?, size: Double)],
        targets: Targets,
        rulerReligion: Religion?
    ) -> [(group: Int, socialClass: SocialClass, size: Double)] {
        let total = groups.reduce(0) { $0 + $1.size }
        guard total > 0 else { return [] }
        var remaining = groups.map(\.size)
        var out: [(Int, SocialClass, Double)] = []

        func allocate(_ socialClass: SocialClass, fraction: Double, weight: (Int) -> Double) {
            let want = total * fraction
            guard want > 0 else { return }
            let weights = groups.indices.map { weight($0) * groups[$0].size }
            let sum = weights.reduce(0, +)
            guard sum > 0 else { return }
            for g in groups.indices where weights[g] > 0 {
                let amount = min(want * weights[g] / sum, remaining[g] * 0.9)
                if amount > 0 {
                    out.append((g, socialClass, amount))
                    remaining[g] -= amount
                }
            }
        }

        allocate(.nobles, fraction: targets.nobles) { g in
            groups[g].religion == rulerReligion ? 4 : 1
        }
        allocate(.clergy, fraction: targets.clergy) { _ in 1 }
        allocate(.burghers, fraction: targets.burghers) { g in
            switch groups[g].family {
            case "jewish", "armenian": return 3
            case "italian": return 2
            default: return 1
            }
        }
        allocate(.slaves, fraction: targets.slaves) { g in
            guard let ruler = rulerReligion else { return 1 }
            return groups[g].religion.family == ruler.family ? 0.5 : 2
        }
        for g in groups.indices where remaining[g] > 0 {
            out.append((g, .peasants, remaining[g]))
        }
        return out
    }
}
