import GezCore
import SwiftUI

// MARK: - Province economy

/// What a province makes, what it is worth, and how content its people are.
struct EconomySection: View {
    @Environment(GameModel.self) private var model
    let province: ProvinceID

    var body: some View {
        let world = model.world
        let eco = world.economy
        let p = world.provinces
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Economy").font(.callout.bold())
                Spacer()
                if let m = world.market(of: province) {
                    Button {
                        model.openMarket = m
                    } label: {
                        Label(eco.markets.name[m.index] + " market", systemImage: "scalemass")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink.opacity(0.8))
                    .help("Show prices in this market")
                }
            }
            ForEach(Array(eco.producers.range(for: province)), id: \.self) { k in
                let g = eco.producers.good[k]
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.color(eco.goods.color[g.index]))
                        .frame(width: 10, height: 10)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Palette.ink.opacity(0.4), lineWidth: 0.5))
                    Text(eco.goods.name[g.index])
                    Spacer()
                    Text(Self.amount(eco.producers.output[k] * 12))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                    Text(String(format: "%.1f", eco.producers.value[k] * 12))
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.caption.monospacedDigit())
            }
            let T = eco.buildings.typeCount
            ForEach(eco.buildingTypes.indices.filter { eco.buildings.level(province, BuildingTypeID($0)) > 0 && eco.buildingTypes[$0].effect.workshopRecipe != nil }, id: \.self) { t in
                let slot = province.index * T + t
                if let r = eco.buildingTypes[t].effect.workshopRecipe {
                    let g = eco.recipes[r].output
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.color(eco.goods.color[g.index]))
                            .frame(width: 10, height: 10)
                        Text(eco.goods.name[g.index])
                        Image(systemName: "hammer").font(.caption2).foregroundStyle(Palette.ink.opacity(0.5))
                        Spacer()
                        Text(Self.amount(eco.workshopOutput[slot] * 12))
                            .foregroundStyle(Palette.ink.opacity(0.6))
                        Text(String(format: "%.1f", eco.workshopValue[slot] * 12))
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.caption.monospacedDigit())
                }
            }
            HStack {
                Text("Worth").foregroundStyle(Palette.ink.opacity(0.7))
                Spacer()
                Text(String(format: "%.1f / year · tax %.1f", p.production[province.index], p.baseTax[province.index]))
                    .monospacedDigit()
            }
            .font(.caption)
            HStack(spacing: 10) {
                ForEach([SocialClass.peasants, .burghers, .clergy, .nobles], id: \.self) { cls in
                    if let s = world.satisfaction(of: cls, in: [province]) {
                        VStack(spacing: 0) {
                            Text(Self.mood(s)).font(.caption)
                            Text(cls.displayName).font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
                        }
                        .help("\(cls.displayName): \(Int((s * 100).rounded()))% of their needs met")
                    }
                }
            }
        }
    }

    static func amount(_ units: Double) -> String {
        units >= 100 ? String(format: "%.0f u", units) : String(format: "%.1f u", units)
    }

    static func mood(_ s: Double) -> String {
        "\(Int((s * 100).rounded()))%"
    }
}

// MARK: - Market panel

/// Prices, supply and demand of every good in one market.
struct MarketPanel: View {
    @Environment(GameModel.self) private var model
    let market: MarketID
    /// Off for snapshots (the image renderer can't draw scroll views).
    var scrolls = true
    @State private var category: GoodCategory? = nil

    var body: some View {
        let _ = model.revision
        let eco = model.world.economy
        let mk = eco.markets
        let goods = eco.goods.ids.filter { g in
            let i = mk.slot(market, g)
            return (category == nil || eco.goods.category[g.index] == category)
                && (mk.supply[i] > 0.0005 || mk.demand[i] > 0.0005)
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(mk.name[market.index]) market").font(.title3.bold())
                Spacer()
                Button {
                    model.openMarket = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            Text("\(eco.provinces(in: market).count) provinces trade here")
                .font(.caption)
                .foregroundStyle(Palette.ink.opacity(0.65))
            HStack(spacing: 4) {
                chip("All", category == nil) { category = nil }
                ForEach(GoodCategory.allCases, id: \.self) { c in
                    chip(c.displayName, category == c) { category = c }
                }
            }
            HStack {
                Text("Good")
                Spacer()
                Text("Price").frame(width: 70, alignment: .trailing)
                Text("Supply").frame(width: 56, alignment: .trailing)
                Text("Demand").frame(width: 56, alignment: .trailing)
            }
            .font(.caption.bold())
            .foregroundStyle(Palette.ink.opacity(0.7))
            let list = VStack(spacing: 3) {
                ForEach(goods, id: \.index) { g in
                    row(g, eco: eco)
                }
            }
            if scrolls {
                ScrollView { list }.frame(maxHeight: 360)
            } else {
                list
            }
        }
        .padding(14)
        .frame(width: 380)
        .foregroundStyle(Palette.ink)
        .background(Palette.parchment.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
    }

    private func row(_ g: GoodID, eco: Economy) -> some View {
        let i = eco.markets.slot(market, g)
        let price = eco.markets.price[i]
        let ratio = price / eco.goods.basePrice[g.index]
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.color(eco.goods.color[g.index]))
                .frame(width: 10, height: 10)
            Text(eco.goods.name[g.index]).lineLimit(1)
            Spacer()
            Text(String(format: "%.1f", price))
            Text(ratio >= 1.15 ? "▲" : (ratio <= 0.87 ? "▼" : "·"))
                .foregroundStyle(ratio >= 1.15 ? Color.red.opacity(0.8) : (ratio <= 0.87 ? Color.green.opacity(0.8) : Palette.ink.opacity(0.4)))
                .frame(width: 14)
                .help(String(format: "%.0f%% of the normal price", ratio * 100))
            Text(EconomySection.amount(eco.markets.supply[i] * 12)).frame(width: 56, alignment: .trailing)
            Text(EconomySection.amount(eco.markets.demand[i] * 12)).frame(width: 56, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
    }

    private func chip(_ title: String, _ selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(selected ? Palette.ink.opacity(0.85) : Palette.ink.opacity(0.08), in: Capsule())
                .foregroundStyle(selected ? Palette.parchment : Palette.ink)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Buildings

extension World {
    /// Building names that fit the local faith ("Mosque", "Madrasa"...).
    func buildingName(_ t: BuildingTypeID, in p: ProvinceID) -> String {
        let type = economy.buildingTypes[t.index]
        let family = provinces.religion[p.index].family
        switch type.key {
        case "temple":
            switch family {
            case .christian: return "Church"
            case .muslim: return "Mosque"
            case .jewish: return "Synagogue"
            case .dharmic: return "Temple"
            default: return "Shrine"
            }
        case "college":
            return family == .muslim ? "Madrasa" : (family == .christian ? "University" : "College")
        default:
            return type.name
        }
    }
}

/// What stands in the province, what is being built, and (for your own
/// provinces) what you can build.
struct BuildingsSection: View {
    @Environment(GameModel.self) private var model
    let province: ProvinceID
    @State var showBuild = false
    @State var category: BuildingCategory = .production

    var body: some View {
        let world = model.world
        let eco = world.economy
        let types = eco.buildingTypes.indices.map(BuildingTypeID.init)
        let built = types.filter { eco.buildings.level(province, $0) > 0 }
        let building = eco.buildings.constructions.filter { $0.province == province }
        let isMine = world.provinces.owner[province.index] == model.playerCountry
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Buildings").font(.callout.bold())
                Spacer()
                Text("\(eco.buildings.slotsUsed(province)) / \(BuildingSystem.slots(world, province)) slots")
                    .font(.caption)
                    .foregroundStyle(Palette.ink.opacity(0.6))
            }
            FlowRow(built.map { t in "\(world.buildingName(t, in: province)) \(eco.buildings.level(province, t))" })
            ForEach(Array(building.enumerated()), id: \.offset) { _, c in
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill").font(.caption2)
                    Text("\(world.buildingName(c.type, in: province)) \(c.level)").font(.caption)
                    ProgressView(value: c.progress).frame(width: 70)
                    Text("\(c.monthsLeft) mo").font(.caption2.monospacedDigit())
                }
            }
            if isMine {
                Button {
                    showBuild.toggle()
                } label: {
                    Label(showBuild ? "Hide" : "Build…", systemImage: showBuild ? "chevron.up" : "plus.circle")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)
                if showBuild {
                    HStack(spacing: 4) {
                        ForEach(BuildingCategory.allCases, id: \.self) { c in
                            Button {
                                category = c
                            } label: {
                                Text(c.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(category == c ? Palette.ink.opacity(0.85) : Palette.ink.opacity(0.08), in: Capsule())
                                    .foregroundStyle(category == c ? Palette.parchment : Palette.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(types.filter { eco.buildingTypes[$0.index].category == category }, id: \.index) { t in
                        buildRow(t, world: world)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func buildRow(_ t: BuildingTypeID, world: World) -> some View {
        let player = model.playerCountry!
        // Hide what can never be built here (wrong coast, good, terrain...).
        let placeRefusal = BuildingSystem.refusal(world, player, province, t, checkMoney: false)
        let hidden: Set<BuildingSystem.Refusal> = [.needsCoast, .wrongGood, .wrongTerrain, .wrongReligion, .maxLevel, .notOwner]
        if placeRefusal.map({ !hidden.contains($0) }) ?? true {
            let refusal = BuildingSystem.refusal(world, player, province, t)
            let level = BuildingSystem.nextLevel(world, province, t)
            let type = world.economy.buildingTypes[t.index]
            Button {
                model.build(t, in: province)
            } label: {
                HStack(spacing: 6) {
                    Text("\(world.buildingName(t, in: province)) \(level)")
                    Spacer()
                    Text(String(format: "%.0f", BuildingSystem.cost(world, province, t)))
                        .monospacedDigit()
                    Image(systemName: "dollarsign.circle").font(.caption2)
                    Text("\(type.months(forLevel: level)) mo").monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .font(.caption)
                .padding(.vertical, 2)
                .opacity(refusal == nil ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(refusal != nil)
            .help(refusal?.reason ?? Self.effectText(type.effect, world: world))
        }
    }

    static func effectText(_ e: BuildingEffect, world: World) -> String {
        func pct(_ x: Double) -> String { "+\(Int((x * 100).rounded()))%" }
        switch e {
        case .staple(let x): return "\(pct(x)) staple food per level"
        case .trade(let x): return "\(pct(x)) trade good per level"
        case .fish(let x): return "\(pct(x)) fish per level"
        case .workshop(let r): return "Jobs for 2,500 burghers making \(world.economy.goods.name[world.economy.recipes[r].output.index])"
        case .crafts(let x): return "\(pct(x)) workshop output per level"
        case .tax(let x): return "\(pct(x)) tax per level"
        case .mood(let x): return "\(pct(x)) satisfaction per level"
        case .learning(let x): return "+\(x) learning a year per level"
        case .fort: return "Fort level +1"
        case .manpower(let x): return "+\(Int(x * 1000)) soldiers per level"
        case .ships(let x): return "+\(Int(x)) ships at a time per level"
        case .routes(let x): return "\(pct(x)) overland trade capacity per level"
        }
    }
}

/// Small wrapped tags.
struct FlowRow: View {
    let items: [String]
    init(_ items: [String]) { self.items = items }

    var body: some View {
        let lines = Self.chunk(items, maxChars: 40)
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 4) {
                    ForEach(line, id: \.self) { item in
                        Text(item)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    static func chunk(_ items: [String], maxChars: Int) -> [[String]] {
        var lines: [[String]] = [[]]
        var width = 0
        for item in items {
            if width + item.count > maxChars && !lines[lines.count - 1].isEmpty {
                lines.append([])
                width = 0
            }
            lines[lines.count - 1].append(item)
            width += item.count + 2
        }
        return lines.filter { !$0.isEmpty }
    }
}
