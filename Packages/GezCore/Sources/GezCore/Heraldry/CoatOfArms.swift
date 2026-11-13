/// Heraldic colours. Metals (or, argent) go on colours and the other way
/// round, the old "rule of tincture" that keeps arms readable.
public enum Tincture: String, CaseIterable, Sendable {
    case or, argent, gules, azure, vert, sable, purpure

    public var isMetal: Bool { self == .or || self == .argent }

    public var rgb: RGB {
        switch self {
        case .or: return RGB(222, 178, 52)
        case .argent: return RGB(238, 236, 228)
        case .gules: return RGB(178, 36, 40)
        case .azure: return RGB(32, 78, 160)
        case .vert: return RGB(28, 120, 62)
        case .sable: return RGB(30, 28, 28)
        case .purpure: return RGB(110, 50, 120)
        }
    }
}

public enum ShieldShape: String, Sendable {
    /// European heater shield (Christian realms).
    case heater
    /// Round shield (Muslim realms).
    case round
    /// Rectangular banner (Indian, steppe and tribal realms).
    case banner
}

public enum Division: String, CaseIterable, Sendable {
    case plain, perPale, perFess, perBend, quarterly, perChevron
}

public enum Ordinary: String, CaseIterable, Sendable {
    case none, cross, nordicCross, saltire, fess, pale, bend, chevron, chief, bordure
}

public enum Charge: String, CaseIterable, Sendable {
    case none, star, crescent, fleur, roundel, lozenge, tower, crown, sun, crossPattee, wheel
}

/// A country's arms, made from simple parts so it can be drawn anywhere.
public struct CoatOfArms: Hashable, Sendable {
    public var shape: ShieldShape
    public var field: Tincture
    public var division: Division
    public var secondField: Tincture
    public var ordinary: Ordinary
    public var ordinaryTincture: Tincture
    public var charge: Charge
    public var chargeTincture: Tincture
    /// 1 to 3 charges.
    public var chargeCount: Int

    public init(shape: ShieldShape, field: Tincture, division: Division, secondField: Tincture,
                ordinary: Ordinary, ordinaryTincture: Tincture, charge: Charge, chargeTincture: Tincture,
                chargeCount: Int) {
        self.shape = shape
        self.field = field
        self.division = division
        self.secondField = secondField
        self.ordinary = ordinary
        self.ordinaryTincture = ordinaryTincture
        self.charge = charge
        self.chargeTincture = chargeTincture
        self.chargeCount = chargeCount
    }
}

/// Makes arms for any country from its tag, map colour, religion and
/// government. The same inputs always give the same arms.
public enum HeraldryGenerator {
    public static func arms(tag: String, color: RGB, religion: Religion, government: GovernmentType) -> CoatOfArms {
        var rng = GameRandom(seed: seed(for: tag))
        func pick<T>(_ options: [T]) -> T { options[Int(rng.next() % UInt64(options.count))] }
        func chance(_ p: Double) -> Bool { Double(rng.next() % 10_000) / 10_000 < p }

        let family = religion.family
        let shape: ShieldShape
        switch (family, government) {
        case (_, .tribal), (_, .steppeHorde): shape = .banner
        case (.christian, _), (.jewish, _): shape = .heater
        case (.muslim, _), (.iranian, _): shape = .round
        default: shape = .banner
        }

        // Field: the heraldic colour closest to the map colour, so arms and
        // map agree.
        let field = nearestTincture(to: color)
        let contrast: [Tincture] = field.isMetal ? [.gules, .azure, .vert, .sable, .purpure] : [.or, .argent]
        let secondOptions: [Tincture] = field.isMetal ? contrast : [.or, .argent]

        var division: Division = .plain
        var ordinary: Ordinary = .none
        var charge: Charge = .none
        var count = 1

        switch family {
        case .christian:
            if chance(0.35) { division = pick([.perPale, .perFess, .perBend, .quarterly, .perChevron]) }
            if division == .plain || chance(0.3) {
                ordinary = pick([.cross, .saltire, .fess, .pale, .bend, .chevron, .chief, .bordure, .none])
                if ["DAN", "NOR", "SWE"].contains(tag) { ordinary = .nordicCross }
            }
            charge = pick([.fleur, .tower, .crown, .star, .roundel, .lozenge, .crossPattee, .none])
            if government == .theocracy { charge = pick([.crossPattee, .crown]) }
            count = charge == .none ? 0 : pick([1, 1, 3])
        case .muslim, .iranian:
            if chance(0.4) { ordinary = pick([.fess, .pale, .bordure, .chief]) }
            charge = pick([.crescent, .crescent, .star, .sun])
            count = pick([1, 1, 2, 3])
        case .dharmic:
            if chance(0.3) { division = pick([.perFess, .perPale]) }
            charge = pick([.sun, .wheel, .star, .roundel])
            count = 1
        case .jewish, .pagan:
            if chance(0.4) { division = pick([.perFess, .perPale, .perBend]) }
            charge = pick([.sun, .star, .lozenge, .roundel])
            count = pick([1, 1, 2])
        }

        // Rule of tincture: things on the field contrast with it.
        let onField = pick(contrast)
        var chargeTincture = onField
        if ordinary != .none && division == .plain {
            // Charges sit on the field beside the ordinary; keep them readable.
            chargeTincture = pick(contrast)
        }
        if division != .plain && charge != .none && ordinary == .none {
            // Charge straddles two fields: use a metal or sable that shows on both.
            chargeTincture = field.isMetal ? .sable : (secondOptions.first == .or ? .argent : .or)
        }
        return CoatOfArms(
            shape: shape,
            field: field,
            division: division,
            secondField: division == .plain ? field : pick(secondOptions),
            ordinary: ordinary,
            ordinaryTincture: onField,
            charge: charge,
            chargeTincture: chargeTincture,
            chargeCount: max(0, min(count, 3))
        )
    }

    static func nearestTincture(to c: RGB) -> Tincture {
        let lum = 0.299 * Double(c.r) + 0.587 * Double(c.g) + 0.114 * Double(c.b)
        let candidates: [Tincture] = lum > 205 ? [.argent, .or] : [.gules, .azure, .vert, .sable, .purpure, .or]
        return candidates.min { a, b in distance(a.rgb, c) < distance(b.rgb, c) }!
    }

    private static func distance(_ a: RGB, _ b: RGB) -> Int {
        let dr = Int(a.r) - Int(b.r), dg = Int(a.g) - Int(b.g), db = Int(a.b) - Int(b.b)
        return dr * dr * 3 + dg * dg * 4 + db * db * 2
    }

    /// FNV-1a hash of the tag: stable across runs and platforms.
    static func seed(for tag: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in tag.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }
}

extension World {
    public func arms(of country: CountryID) -> CoatOfArms {
        let c = countries
        return HeraldryGenerator.arms(
            tag: c.tag[country.index],
            color: c.color[country.index],
            religion: c.religion[country.index],
            government: c.government[country.index]
        )
    }
}
