import GezCore
import SwiftUI

/// Government window: stability, estates and privileges, laws, reforms.
struct GovernmentPanel: View {
    @Environment(GameModel.self) private var model
    /// Off for snapshots (the image renderer can't draw scroll views).
    var scrolls = true
    @State var openEstate: EstateID?
    @State var message: String?

    var body: some View {
        let _ = model.revision
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Government").font(.title3.bold())
                Spacer()
                Button {
                    model.showGovernment = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            if let c = model.playerCountry {
                Text(model.world.countries.government[c.index].displayName)
                    .font(.caption).foregroundStyle(Palette.ink.opacity(0.65))
                stability(c)
                Divider()
                estates(c)
                Divider()
                laws(c)
                Divider()
                reforms(c)
                if let message {
                    Text(message).font(.caption).foregroundStyle(.red.opacity(0.85))
                }
            }
        }
        Group {
            if scrolls {
                ScrollView { content }.frame(maxHeight: 660)
            } else {
                content
            }
        }
        .padding(14)
        .frame(width: 400)
        .foregroundStyle(Palette.ink)
        .background(Palette.parchment.opacity(0.97), in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
    }

    // MARK: Stability

    private func stability(_ c: CountryID) -> some View {
        let w = model.world
        let s = w.government.stability[c.index]
        let cost = GovernmentSystem.stabilityCost(w, c)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Stability").font(.callout.bold())
                Spacer()
                Text(String(format: "%+d", s)).font(.title3.bold().monospacedDigit())
                    .foregroundStyle(s < 0 ? Color.red.opacity(0.85) : Palette.ink)
            }
            Text(String(format: "Each point: tax %+.0f%%, contentment %+.0f, reforms %+.2f a month. Falls when rulers die without an adult heir, laws of succession change, privileges are revoked, estates seize power or you go bankrupt.",
                        GovernmentModel.stabilityTax * 100, GovernmentModel.stabilityMood * 100, GovernmentModel.stabilityReform))
                .font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
            Button {
                model.raiseStability()
            } label: {
                Text(String(format: "Raise stability (%.0f ducats)", cost))
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Palette.ink.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(s >= GovernmentModel.maxStability || w.countries.treasury[c.index] < cost)
        }
    }

    // MARK: Estates

    private func estates(_ c: CountryID) -> some View {
        let w = model.world
        let g = w.government
        let list = g.estates[c.index].sorted { g.power[c.index][$0.index] > g.power[c.index][$1.index] }
        return VStack(alignment: .leading, spacing: 5) {
            Text("Estates").font(.callout.bold())
            powerBar(label: "Crown", share: g.crownPower[c.index], loyalty: nil)
            ForEach(list, id: \.index) { e in
                let def = g.rules.estates[e.index]
                let loyalty = g.loyalty[c.index][e.index]
                Button {
                    openEstate = openEstate == e ? nil : e
                } label: {
                    powerBar(label: def.name, share: g.power[c.index][e.index], loyalty: loyalty)
                }
                .buttonStyle(.plain)
                if openEstate == e {
                    estateDetail(c, e)
                }
            }
            Text("Tap an estate for its privileges. Loyal estates (60+) help you; disloyal ones (below 30) hurt, and if strong may seize privileges.")
                .font(.caption2).foregroundStyle(Palette.ink.opacity(0.55))
        }
    }

    private func powerBar(label: String, share: Double, loyalty: Double?) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption.bold()).frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ink.opacity(0.1))
                    Capsule().fill(Palette.ink.opacity(0.55)).frame(width: geo.size.width * min(1, max(0.01, share)))
                }
            }
            .frame(height: 8)
            Text(String(format: "%.0f%%", share * 100)).font(.caption2.monospacedDigit()).frame(width: 32, alignment: .trailing)
            if let loyalty {
                Text(String(format: "♥%.0f", loyalty))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(loyalty >= GovernmentModel.loyalAt ? Color.green.opacity(0.85)
                                     : loyalty < GovernmentModel.disloyalBelow ? Color.red.opacity(0.85) : Palette.ink.opacity(0.7))
                    .frame(width: 34, alignment: .trailing)
            } else {
                Spacer().frame(width: 34)
            }
        }
    }

    private func estateDetail(_ c: CountryID, _ e: EstateID) -> some View {
        let w = model.world
        let g = w.government
        let def = g.rules.estates[e.index]
        let target = GovernmentSystem.loyaltyTarget(w, c, e)
        return VStack(alignment: .leading, spacing: 3) {
            Text(String(format: "Loyalty heading to %.0f. Contentment of their people: %.0f%%.", target, g.contentment[c.index][e.index] * 100))
                .font(.caption2)
            Text("When loyal: " + effectsText(def.loyal, w)).font(.caption2).foregroundStyle(Palette.ink.opacity(0.65))
            Text("When disloyal: " + effectsText(def.disloyal, w)).font(.caption2).foregroundStyle(Palette.ink.opacity(0.65))
            ForEach(g.rules.privileges(of: e), id: \.self) { p in
                let pd = g.rules.privileges[p]
                let granted = g.privileges[c.index].contains(p)
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(pd.name).font(.caption.bold())
                        Text(privilegeText(pd, w, c)).font(.caption2).foregroundStyle(Palette.ink.opacity(0.65))
                    }
                    Spacer()
                    if granted {
                        Button("Revoke") { model.revokePrivilege(p) }
                            .font(.caption)
                            .help("−1 stability; they will resent it for years")
                    } else {
                        Button("Grant") { model.grantPrivilege(p) }.font(.caption)
                    }
                }
            }
        }
        .padding(8)
        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func privilegeText(_ p: PrivilegeDef, _ w: World, _ c: CountryID) -> String {
        var parts = [String(format: "loyalty %+.0f, power %+.0f%%", p.loyalty, p.power * 100)]
        let fx = effectsText(p.effects, w)
        if fx != "nothing else" { parts.append(fx) }
        if p.gold != 0 {
            let ducats = w.countries.lastMonthlyIncome[c.index] * p.gold
            parts.append(String(format: "%@ %.0f ducats once", ducats > 0 ? "gain" : "costs", abs(ducats)))
        }
        return parts.joined(separator: "; ")
    }

    // MARK: Laws

    private func laws(_ c: CountryID) -> some View {
        let w = model.world
        let g = w.government
        let gov = w.countries.government[c.index]
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Laws").font(.callout.bold())
                Spacer()
                Text(String(format: "Change: %.0f ducats, %d months", GovernmentSystem.lawChangeCost(w, c), GovernmentModel.lawChangeMonths))
                    .font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
            }
            ForEach(Array(g.rules.lawAreas.enumerated()), id: \.offset) { a, area in
                let current = area.options[g.laws[c.index][a]]
                let pending = g.pending[c.index].first { $0.area == a }
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(area.name).font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
                        Text(current.name).font(.caption.bold())
                        Text(effectsText(current.effects, w)).font(.caption2).foregroundStyle(Palette.ink.opacity(0.65))
                        if let pending {
                            Text("Changing to \(area.options[pending.option].name) in \(pending.monthsLeft) months")
                                .font(.caption2).foregroundStyle(.blue.opacity(0.8))
                        }
                    }
                    Spacer()
                    Menu("Change") {
                        ForEach(Array(area.options.enumerated()), id: \.offset) { o, option in
                            if o != g.laws[c.index][a] && option.allowed(for: gov) {
                                Button("\(option.name): \(effectsText(option.effects, w))") {
                                    message = model.changeLaw(area: a, option: o)?.reason
                                }
                            }
                        }
                    }
                    .font(.caption)
                    .fixedSize()
                    .disabled(pending != nil)
                }
            }
        }
    }

    // MARK: Reforms

    private func reforms(_ c: CountryID) -> some View {
        let w = model.world
        let g = w.government
        let tree = g.rules.reforms[w.countries.government[c.index]] ?? []
        let progress = g.reformProgress[c.index]
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Reforms").font(.callout.bold())
                Spacer()
                Text(String(format: "Progress %.0f (+%.2f a month)", progress, GovernmentSystem.monthlyReformProgress(w, c)))
                    .font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
            }
            ForEach(Array(g.reforms[c.index].enumerated()), id: \.offset) { t, o in
                if t < tree.count {
                    let r = tree[t].options[o]
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Tier \(t + 1): \(r.name)").font(.caption.bold())
                        Text(effectsText(r.effects, w)).font(.caption2).foregroundStyle(Palette.ink.opacity(0.65))
                    }
                }
            }
            if let next = GovernmentSystem.nextTier(w, c) {
                Text(String(format: "Tier %d needs %.0f progress", next.index + 1, next.tier.cost))
                    .font(.caption.bold()).padding(.top, 2)
                ForEach(Array(next.tier.options.enumerated()), id: \.offset) { o, r in
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(r.name).font(.caption.bold())
                            Text(effectsText(r.effects, w) + (r.becomes.map { "; becomes a \($0.displayName.lowercased())" } ?? ""))
                                .font(.caption2).foregroundStyle(Palette.ink.opacity(0.65))
                        }
                        Spacer()
                        Button("Adopt") { model.adoptReform(o) }
                            .font(.caption)
                            .disabled(progress < next.tier.cost)
                    }
                }
            } else {
                Text("All reforms taken.").font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
            }
        }
    }

    // MARK: Text

    private func effectsText(_ fx: Effects, _ w: World) -> String {
        var parts: [String] = []
        for m in Modifier.allCases where fx[m] != 0 {
            let v = fx[m]
            if m == .noDebase {
                parts.append(m.displayName)
            } else if m.isMood {
                parts.append(String(format: "%@ %+.0f", m.displayName, v * 100))
            } else if m.isPoints {
                parts.append(String(format: "%@ %+.1f", m.displayName, v))
            } else if m == .inflationDecay {
                parts.append(String(format: "%@ %+.1f%%", m.displayName, v * 100))
            } else {
                parts.append(String(format: "%@ %+.0f%%", m.displayName, v * 100))
            }
        }
        let estates = w.government.rules.estates
        for (i, v) in fx.loyalty.enumerated() where v != 0 {
            parts.append(String(format: "%@ loyalty %+.0f", estates[i].name, v))
        }
        for (i, v) in fx.power.enumerated() where v != 0 {
            parts.append(String(format: "%@ power %+.0f%%", estates[i].name, v * 100))
        }
        return parts.isEmpty ? "nothing else" : parts.joined(separator: ", ")
    }
}
