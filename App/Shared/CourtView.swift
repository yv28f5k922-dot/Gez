import GezCore
import SwiftUI

/// Your ruler and family, the council, and marriages.
struct CourtPanel: View {
    @Environment(GameModel.self) private var model
    /// Off for snapshots (the image renderer can't draw scroll views).
    var scrolls = true
    @State var marrying: CharacterID?

    var body: some View {
        let _ = model.revision
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Court").font(.title3.bold())
                Spacer()
                Button {
                    model.showCourt = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            if let player = model.playerCountry, let shown = model.viewedCharacter ?? model.world.countries.ruler[player.index] {
                PersonCard(person: shown, country: player)
                if shown != model.world.countries.ruler[player.index] {
                    Button("Back to your ruler") { model.viewedCharacter = nil }.font(.caption)
                }
                Divider()
                council(player)
                Divider()
                vassals(player)
                Divider()
                marriages(player)
                Divider()
                chronicle(player)
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
        .frame(width: 380)
        .foregroundStyle(Palette.ink)
        .background(Palette.parchment.opacity(0.97), in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
    }

    private func council(_ c: CountryID) -> some View {
        let w = model.world
        let ch = w.people.characters
        let ruler = w.countries.ruler[c.index]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Council").font(.callout.bold())
                Spacer()
                Text(String(format: "Tax %+.0f%% · learning %.1f/yr",
                            CharacterSystem.taxBonus(w, c) * 100, CharacterSystem.learningPerYear(w, c)))
                    .font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
            }
            ForEach(CouncilSeat.allCases, id: \.self) { seat in
                let who = w.countries.council[c.index][seat.rawValue]
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(seat.displayName).font(.caption.bold())
                        if let who {
                            Button(ch.fullName(who)) { model.viewedCharacter = who }
                                .buttonStyle(.plain).font(.caption)
                        } else {
                            Text("Empty").font(.caption).foregroundStyle(.red.opacity(0.8))
                        }
                    }
                    Spacer()
                    if let who {
                        Text("\(seat.skill.displayName) \(ch.skill(who, seat.skill))")
                            .font(.caption2.monospacedDigit())
                        if let r = ruler {
                            let o = CharacterSystem.opinion(w, who, of: r)
                            Text(o >= 0 ? "♥\(o)" : "✗\(-o)")
                                .font(.caption2)
                                .foregroundStyle(o >= 0 ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                                .help("Opinion of your ruler")
                        }
                    }
                    Menu("Change") {
                        let candidates = CharacterSystem.councilCandidates(w, c, date: model.date)
                            .sorted { ch.skill($0, seat.skill) > ch.skill($1, seat.skill) }
                            .prefix(12)
                        ForEach(Array(candidates), id: \.index) { x in
                            Button("\(ch.fullName(x)) (\(seat.skill.displayName) \(ch.skill(x, seat.skill)))") {
                                model.appoint(seat, x)
                            }
                        }
                        Divider()
                        Button("Invite someone new to court") { model.appointNewcomer(seat) }
                        if who != nil { Button("Leave empty") { model.appoint(seat, nil) } }
                    }
                    .font(.caption)
                    .fixedSize()
                }
                .help(seat.effectText)
            }
        }
    }

    private func marriages(_ c: CountryID) -> some View {
        let w = model.world
        let ch = w.people.characters
        let family = CharacterSystem.marriageableFamily(w, c, date: model.date)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Marriages").font(.callout.bold())
            if family.isEmpty {
                Text("No one in the ruling family is free to marry.")
                    .font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
            }
            HStack(spacing: 4) {
                ForEach(family, id: \.index) { x in
                    Button {
                        marrying = x
                    } label: {
                        Text("\(ch.name[x.index]), \(ch.age(x, on: model.date))")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(marrying == x ? Palette.ink.opacity(0.85) : Palette.ink.opacity(0.1), in: Capsule())
                            .foregroundStyle(marrying == x ? Palette.parchment : Palette.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let x = marrying, family.contains(x) {
                let matches = model.marriageCandidates(for: x)
                if matches.isEmpty {
                    Text("No suitable match abroad right now.").font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
                }
                ForEach(matches, id: \.index) { m in
                    HStack(spacing: 6) {
                        if let court = ch.court[m.index] {
                            CountryArmsView(world: w, country: court).frame(height: 16)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Button(ch.fullName(m)) { model.viewedCharacter = m }.buttonStyle(.plain)
                            Text("\(ch.age(m, on: model.date)) · \(ch.court[m.index].map { w.countries.name[$0.index] } ?? "")\(roleText(m))")
                                .font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
                        }
                        Spacer()
                        Button("Propose") {
                            model.propose(x, m)
                            marrying = nil
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func vassals(_ c: CountryID) -> some View {
        let w = model.world
        let ch = w.people.characters
        let list = VassalSystem.vassals(w, of: c)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Vassals").font(.callout.bold())
                Spacer()
                Text(String(format: "keep %.0f%% of their tax", VassalModel.keepShare * 100))
                    .font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
            }
            if list.isEmpty {
                Text("No great vassals: all land is the crown's. Grant provinces from the province panel.")
                    .font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
            }
            ForEach(list, id: \.index) { v in
                let o = VassalSystem.opinionOfLiege(w, v, c)
                let stance = VassalSystem.stance(w, v, c)
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Button(ch.fullName(v)) { model.viewedCharacter = v }.buttonStyle(.plain).font(.caption.bold())
                        Text(VassalSystem.holdings(w, of: v).map { w.provinces.name[$0.index] }.joined(separator: ", ")
                             + String(format: " · %.0f ducats", ch.gold[v.index]))
                            .font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
                    }
                    Spacer()
                    Text(stance.displayName).font(.caption2)
                        .foregroundStyle(stance == .loyal ? Palette.ink.opacity(0.6) : Color.red.opacity(0.85))
                    Text(o >= 0 ? "♥\(o)" : "✗\(-o)")
                        .font(.caption2)
                        .foregroundStyle(o >= 0 ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                        .help("Opinion of your ruler")
                }
            }
        }
    }

    private func chronicle(_ c: CountryID) -> some View {
        let w = model.world
        let entries = w.people.chronicle.filter { $0.country == c }.suffix(8).reversed()
        return VStack(alignment: .leading, spacing: 3) {
            Text("Chronicle").font(.callout.bold())
            if entries.isEmpty {
                Text("Nothing of note yet.").font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                Text("\(e.date.day) \(GameDate.monthNames[e.date.month - 1].prefix(3)) \(String(e.date.year)): \(e.text)")
                    .font(.caption2)
            }
        }
    }

    private func roleText(_ x: CharacterID) -> String {
        let w = model.world
        guard let c = w.people.characters.court[x.index] else { return "" }
        if w.countries.ruler[c.index] == x { return " · ruler" }
        if w.countries.heir[c.index] == x { return " · heir" }
        return ""
    }
}

/// One person: name, age, house, traits, skills and family.
struct PersonCard: View {
    @Environment(GameModel.self) private var model
    let person: CharacterID
    let country: CountryID

    var body: some View {
        let w = model.world
        let ch = w.people.characters
        let date = model.date
        let x = person
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(Palette.ink.opacity(ch.female[x.index] ? 0.25 : 0.4))
                    Text(String(ch.name[x.index].prefix(1))).font(.title2.bold()).foregroundStyle(Palette.parchment)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ch.fullName(x)).font(.headline)
                    Text(subtitle(x)).font(.caption).foregroundStyle(Palette.ink.opacity(0.7))
                    if ch.invented[x.index] {
                        Text("Invented (history does not record them)").font(.caption2).foregroundStyle(Palette.ink.opacity(0.5))
                    } else if let note = ch.note[x.index] {
                        Text(note).font(.caption2).foregroundStyle(Palette.ink.opacity(0.55))
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach(Skill.allCases, id: \.self) { s in
                    VStack(spacing: 0) {
                        Text("\(ch.skill(x, s))").font(.callout.bold().monospacedDigit())
                        Text(String(s.displayName.prefix(3))).font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
                    }
                    .help(s.displayName)
                }
            }
            FlowRow(ch.traits[x.index].map { w.people.traits.name[$0.index] })
            let ruler = w.countries.ruler[country.index]
            if x == ruler {
                let heir = w.countries.heir[country.index]
                Text("\(w.countries.succession[country.index].displayName) · heir: \(heir.map { "\(ch.fullName($0)) (\(ch.age($0, on: date)))" } ?? "none")")
                    .font(.caption)
            }
            familyLine("Spouse", ch.spouses[x.index])
            familyLine("Children", ch.children[x.index])
            familyLine("Siblings", ch.siblings(x))
            familyLine("Parents", [ch.father[x.index], ch.mother[x.index]].compactMap { $0 })
            let held = VassalSystem.holdings(w, of: x)
            if !held.isEmpty {
                Text("Holds \(held.map { w.provinces.name[$0.index] }.joined(separator: ", ")) · \(Int(ch.gold[x.index])) ducats")
                    .font(.caption)
            }
            if ch.illegitimate[x.index] {
                Text("Born outside marriage").font(.caption2).foregroundStyle(Palette.ink.opacity(0.55))
            }
        }
    }

    private func subtitle(_ x: CharacterID) -> String {
        let ch = model.world.people.characters
        var parts: [String] = []
        if let d = ch.death[x.index] {
            parts.append("Died \(d.year) aged \(ch.age(x, on: model.date))")
        } else {
            parts.append("Age \(ch.age(x, on: model.date))")
        }
        if let d = ch.dynasty[x.index], !d.hasPrefix("of ") { parts.append(d) }
        parts.append(ch.religion[x.index].displayName)
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func familyLine(_ label: String, _ people: [CharacterID]) -> some View {
        if !people.isEmpty {
            let ch = model.world.people.characters
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label).font(.caption.bold()).frame(width: 58, alignment: .leading)
                FlowButtons(items: people.map { p in
                    (p, ch.isAlive(p) ? "\(ch.name[p.index]) (\(ch.age(p, on: model.date)))" : "\(ch.name[p.index]) †")
                }) { model.viewedCharacter = $0 }
            }
        }
    }
}

/// Wrapped tappable names.
struct FlowButtons: View {
    let items: [(CharacterID, String)]
    let action: (CharacterID) -> Void

    static func chunk(_ items: [(CharacterID, String)], maxChars: Int) -> [[(CharacterID, String)]] {
        var lines: [[(CharacterID, String)]] = [[]]
        var width = 0
        for item in items {
            if width + item.1.count > maxChars && !lines[lines.count - 1].isEmpty {
                lines.append([])
                width = 0
            }
            lines[lines.count - 1].append(item)
            width += item.1.count + 2
        }
        return lines.filter { !$0.isEmpty }
    }

    var body: some View {
        let indexed = Self.chunk(items, maxChars: 36)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(indexed.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 6) {
                    ForEach(line, id: \.0.index) { item in
                        Button(item.1) { action(item.0) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .underline()
                    }
                }
            }
        }
    }
}

/// Who holds a province, with grant and revoke for the player's own land.
struct HolderRow: View {
    @Environment(GameModel.self) private var model
    let province: ProvinceID

    var body: some View {
        let w = model.world
        let ch = w.people.characters
        let i = province.index
        let mine = model.playerCountry != nil && w.provinces.owner[i] == model.playerCountry
        HStack(spacing: 6) {
            Text("Held by").font(.caption.bold())
            if let h = w.provinces.holder[i] {
                Button(ch.fullName(h)) {
                    model.viewedCharacter = h
                    model.showCourt = true
                }
                .buttonStyle(.plain).font(.caption).underline()
                if let c = w.provinces.owner[i] {
                    Text(VassalSystem.stance(w, h, c).displayName).font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
                }
            } else {
                Text(w.provinces.owner[i] == nil ? "No one" : "The crown").font(.caption)
            }
            Spacer()
            if mine, let c = model.playerCountry {
                if w.provinces.holder[i] != nil {
                    Button("Revoke") { model.revoke(province) }
                        .font(.caption)
                        .help("Take it back: all your vassals will trust you less")
                } else {
                    Menu("Grant") {
                        let candidates = VassalSystem.grantCandidates(w, c, date: model.date)
                            .sorted { ch.skills[$0.index].reduce(0, +) > ch.skills[$1.index].reduce(0, +) }
                            .prefix(12)
                        ForEach(Array(candidates), id: \.index) { x in
                            Button("\(ch.fullName(x)) (\(ch.age(x, on: model.date)))") { model.grant(province, to: x) }
                        }
                    }
                    .font(.caption)
                    .fixedSize()
                }
            }
        }
    }
}
