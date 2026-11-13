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
                    if eco.producers.kind[k] == .craft {
                        Image(systemName: "hammer").font(.caption2).foregroundStyle(Palette.ink.opacity(0.5))
                            .help("Workshop")
                    }
                    Spacer()
                    Text(Self.amount(eco.producers.output[k] * 12))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                    Text(String(format: "%.1f", eco.producers.value[k] * 12))
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.caption.monospacedDigit())
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
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(goods, id: \.index) { g in
                        row(g, eco: eco)
                    }
                }
            }
            .frame(maxHeight: 360)
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
