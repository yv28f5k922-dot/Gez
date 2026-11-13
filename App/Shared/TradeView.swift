import GezCore
import SwiftUI

/// Your merchants' routes, a planner for new ones, tolls and embargoes.
struct TradePanel: View {
    @Environment(GameModel.self) private var model
    /// Off for snapshots (the image renderer can't draw scroll views).
    var scrolls = true

    var body: some View {
        let _ = model.revision
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trade").font(.title3.bold())
                Spacer()
                Button {
                    model.showTrade = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            if let player = model.playerCountry {
                capacity(player)
                Divider()
                routes(player)
                Divider()
                planner(player)
                Divider()
                policy(player)
            }
        }
        Group {
            if scrolls {
                ScrollView { content }.frame(maxHeight: 640)
            } else {
                content
            }
        }
        .padding(14)
        .frame(width: 380)
        .foregroundStyle(Palette.ink)
        .background(Palette.parchment.opacity(0.97), in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
    }

    private func capacity(_ c: CountryID) -> some View {
        let w = model.world
        let used = w.tradeCapacityUsed(c), total = w.tradeCapacity(c)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Merchant capacity").font(.callout)
                Spacer()
                Text(String(format: "%.0f / %.0f", used, total)).monospacedDigit()
            }
            ProgressView(value: min(used, total), total: max(total, 1))
            Text(String(format: "Last month: merchants %+.1f, tolls %+.1f", w.countries.lastTrade[c.index], w.countries.lastTolls[c.index]))
                .font(.caption).foregroundStyle(Palette.ink.opacity(0.65))
            Text("Market halls, ports, roads and caravanserais add capacity; owning a market town adds more.")
                .font(.caption2).foregroundStyle(Palette.ink.opacity(0.55))
        }
    }

    private func routes(_ c: CountryID) -> some View {
        let w = model.world
        let eco = w.economy
        let mine = eco.routes.enumerated().filter { $0.element.owner == c }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Your routes").font(.callout.bold())
            if mine.isEmpty {
                Text("None yet. Plan one below, or tap a good in a market's price list.")
                    .font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
            }
            ForEach(mine, id: \.offset) { entry in
                let index = entry.offset, r = entry.element
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.color(eco.goods.color[r.good.index]))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(eco.goods.name[r.good.index]): \(eco.markets.name[r.from.index]) → \(eco.markets.name[r.to.index])")
                            .lineLimit(1)
                        Text(r.path.isEmpty ? "Blocked: no open way"
                             : String(format: "%.0f of %.0f a year · %+.1f a year%@", r.moved * 12, r.volume, r.profit * 12,
                                      r.monthsLosing > 0 ? " · losing money" : ""))
                            .font(.caption2)
                            .foregroundStyle(r.path.isEmpty || r.monthsLosing > 0 ? Color.red.opacity(0.8) : Palette.ink.opacity(0.6))
                    }
                    Spacer()
                    Button {
                        model.cancelRoute(index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Stop this route")
                }
                .font(.caption)
            }
        }
    }

    private func planner(_ c: CountryID) -> some View {
        let w = model.world
        let eco = w.economy
        let estimate: (profit: Double, path: [MarketID], capacity: Double)? = {
            guard let g = model.draftGood, let a = model.draftFrom, let b = model.draftTo else { return nil }
            return w.routeEstimate(owner: c, good: g, from: a, to: b, volume: model.draftVolume)
        }()
        let markets = eco.markets.ids.sorted { eco.markets.name[$0.index] < eco.markets.name[$1.index] }
        return VStack(alignment: .leading, spacing: 5) {
            Text("New route").font(.callout.bold())
            HStack {
                Text("Good").frame(width: 44, alignment: .leading)
                Menu(model.draftGood.map { eco.goods.name[$0.index] } ?? "Choose…") {
                    ForEach(GoodCategory.allCases, id: \.self) { cat in
                        Section(cat.displayName) {
                            ForEach(eco.goods.ids.filter { eco.goods.category[$0.index] == cat }, id: \.index) { g in
                                Button(eco.goods.name[g.index]) { model.draftGood = g }
                            }
                        }
                    }
                }
            }
            HStack {
                Text("From").frame(width: 44, alignment: .leading)
                Menu(model.draftFrom.map { eco.markets.name[$0.index] } ?? "Choose…") {
                    ForEach(sourceSuggestions(c), id: \.index) { m in
                        Button(sourceLabel(m)) { model.draftFrom = m }
                    }
                    Divider()
                    ForEach(markets, id: \.index) { m in
                        Button(eco.markets.name[m.index]) { model.draftFrom = m }
                    }
                }
            }
            HStack {
                Text("To").frame(width: 44, alignment: .leading)
                Menu(model.draftTo.map { eco.markets.name[$0.index] } ?? "Choose…") {
                    ForEach(markets, id: \.index) { m in
                        Button(eco.markets.name[m.index]) { model.draftTo = m }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Amount").frame(width: 52, alignment: .leading)
                ForEach(TradeSystem.volumes, id: \.self) { v in
                    Button {
                        model.draftVolume = v
                    } label: {
                        Text("\(Int(v))/yr")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(model.draftVolume == v ? Palette.ink.opacity(0.85) : Palette.ink.opacity(0.1), in: Capsule())
                            .foregroundStyle(model.draftVolume == v ? Palette.parchment : Palette.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.callout)
            if let g = model.draftGood, let a = model.draftFrom, let b = model.draftTo {
                if let e = estimate {
                    Text(String(format: "Buy at %.1f, sell at %.1f · about %+.0f ducats a year · uses %.0f capacity",
                                eco.markets.price(a, g), eco.markets.price(b, g), e.profit, e.capacity))
                        .font(.caption)
                        .foregroundStyle(e.profit > 0 ? Palette.ink : Color.red.opacity(0.8))
                    Text("Via " + e.path.map { eco.markets.name[$0.index] }.joined(separator: " → "))
                        .font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
                    Button {
                        model.createRoute()
                    } label: {
                        Text("Start route").font(.callout.bold())
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Palette.ink.opacity(0.85), in: Capsule())
                            .foregroundStyle(Palette.parchment)
                    }
                    .buttonStyle(.plain)
                    .disabled(w.tradeCapacityUsed(c) + e.capacity > w.tradeCapacity(c))
                } else {
                    Text(a == b ? "Pick two different markets." : "No open way between these markets.")
                        .font(.caption).foregroundStyle(.red.opacity(0.8))
                }
            }
        }
    }

    /// The five markets where the chosen good is cheapest compared with the
    /// destination (best buys first).
    private func sourceSuggestions(_ c: CountryID) -> [MarketID] {
        let eco = model.world.economy
        guard let g = model.draftGood else { return [] }
        return eco.markets.ids
            .filter { $0 != model.draftTo && eco.markets.supply[eco.markets.slot($0, g)] > 0 }
            .sorted { eco.markets.price($0, g) < eco.markets.price($1, g) }
            .prefix(5).map { $0 }
    }

    private func sourceLabel(_ m: MarketID) -> String {
        let eco = model.world.economy
        guard let g = model.draftGood else { return eco.markets.name[m.index] }
        return String(format: "%@ (%.1f)", eco.markets.name[m.index], eco.markets.price(m, g))
    }

    private func policy(_ c: CountryID) -> some View {
        let w = model.world
        let embargoed = w.countries.embargoes[c.index].sorted { $0.index < $1.index }
        let traders = Set(w.economy.routes.map(\.owner)).subtracting([c])
            .sorted { w.countries.name[$0.index] < w.countries.name[$1.index] }
        return VStack(alignment: .leading, spacing: 5) {
            Text("Your markets").font(.callout.bold())
            Picker("Tolls", selection: Binding(get: { w.countries.tollPolicy[c.index] }, set: { model.setTollPolicy($0) })) {
                ForEach(TollPolicy.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            Text("Foreign merchants passing through your market towns pay tolls. Closing them keeps foreigners out entirely.")
                .font(.caption2).foregroundStyle(Palette.ink.opacity(0.55))
            HStack {
                Text("Embargoes").font(.callout)
                Spacer()
                Menu("Add…") {
                    ForEach(traders, id: \.index) { o in
                        Button(w.countries.name[o.index]) { model.toggleEmbargo(o) }
                    }
                }
            }
            if embargoed.isEmpty {
                Text("None").font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
            }
            ForEach(embargoed, id: \.index) { o in
                HStack {
                    CountryArmsView(world: w, country: o).frame(height: 16)
                    Text(w.countries.name[o.index]).font(.caption)
                    Spacer()
                    Button("Lift") { model.toggleEmbargo(o) }.font(.caption)
                }
            }
        }
    }
}
