import GezCore
import SwiftUI

struct ContentView: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            ZStack(alignment: .bottomLeading) {
                MapCanvasView()
                if let province = model.selectedProvince {
                    ProvincePanel(province: province)
                        .padding(12)
                } else if let sea = model.selectedSea {
                    SeaPanel(sea: sea)
                        .padding(12)
                }
            }
            .overlay(alignment: .topTrailing) {
                MapModeBar().padding(12)
            }
        }
        .background(MapPalette.waterColor)
    }
}

enum Palette {
    static let parchment = Color(red: 0.93, green: 0.88, blue: 0.76)
    static let ink = Color(red: 0.20, green: 0.15, blue: 0.10)

    static func color(_ rgb: RGB) -> Color {
        Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

// MARK: - Top bar

struct TopBar: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        let _ = model.revision
        HStack(spacing: 16) {
            if let player = model.playerCountry {
                let countries = model.world.countries
                CoatOfArmsView(arms: model.world.arms(of: player))
                    .frame(height: 28)
                Text(countries.name[player.index])
                    .font(.headline)
                Label(
                    String(format: "%.0f  (%+.1f)", countries.treasury[player.index], countries.lastMonthlyIncome[player.index]),
                    systemImage: "dollarsign.circle"
                )
                .monospacedDigit()
            }
            Spacer()
            Text(model.date.description)
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 150, alignment: .trailing)
            SpeedControls()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(Palette.ink)
        .background(Palette.parchment)
    }
}

struct SpeedControls: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.speed == .paused ? "play.fill" : "pause.fill")
                    .frame(width: 28, height: 28)
            }
            .keyboardShortcut(.space, modifiers: [])

            ForEach(Array(GameSpeed.allCases.dropFirst()), id: \.self) { speed in
                Button {
                    model.speed = speed
                } label: {
                    Text("\(speed.rawValue)")
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.speed == speed ? Palette.ink.opacity(0.85) : Palette.ink.opacity(0.1))
                        )
                        .foregroundStyle(model.speed == speed ? Palette.parchment : Palette.ink)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(speed.rawValue)")), modifiers: [])
            }

            // Hidden shortcuts: + and - like EU4.
            Button("") { model.faster() }
                .keyboardShortcut("=", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
            Button("") { model.slower() }
                .keyboardShortcut("-", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Map modes

struct MapModeBar: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MapMode.allCases) { mode in
                Button {
                    model.mapMode = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.mapMode == mode ? Palette.ink.opacity(0.85) : .clear)
                        )
                        .foregroundStyle(model.mapMode == mode ? Palette.parchment : Palette.ink)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(mode.shortcut, modifiers: [])
                .help(mode.title)
                .accessibilityLabel(mode.title)
            }
        }
        .padding(4)
        .background(Palette.parchment.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 3)
    }
}

// MARK: - Province panel

struct ProvincePanel: View {
    @Environment(GameModel.self) private var model
    let province: ProvinceID

    var body: some View {
        let _ = model.revision
        let world = model.world
        let p = world.provinces
        let c = world.countries
        let i = province.index
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.name[i]).font(.title3.bold())
                Spacer()
                Button {
                    model.select(province: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            Text("\(world.stateName(of: province)) · \(world.regionName(of: province))")
                .font(.subheadline)
                .foregroundStyle(Palette.ink.opacity(0.7))
            HStack(spacing: 6) {
                if let owner = p.owner[i] {
                    CoatOfArmsView(arms: world.arms(of: owner)).frame(height: 20)
                    Text(c.name[owner.index])
                    if c.capital[owner.index] == province {
                        Image(systemName: "star.fill").font(.caption).help("Capital")
                    }
                } else {
                    Circle().fill(Color(red: 0.77, green: 0.71, blue: 0.59)).frame(width: 12, height: 12)
                    Text("Unclaimed land")
                }
            }
            if let owner = p.owner[i] {
                Text(countryStatus(owner, world: world))
                    .font(.caption)
                    .foregroundStyle(Palette.ink.opacity(0.65))
            }
            Divider()
            row("Development", "\(p.development[i])")
            row("Base tax", String(format: "%.1f / year", p.baseTax[i]))
            row("Production", String(format: "%.1f / year", p.production[i]))
            row("Fort level", "\(p.fortLevel[i])")
            row("Terrain", p.terrain[i].rawValue.capitalized)
            row("Area", "\(p.areaKm2[i].formatted(.number.precision(.fractionLength(0)))) km²")
            row("Coast", p.isCoastal[i] ? "Yes" : "No")
            PeopleSection(province: province)
            row("Neighbours", "\(p.neighbors[i].count)")
            let riverSides = p.neighbors[i].filter { world.isRiverBorder(province, $0) }.count
            if riverSides > 0 {
                row("River borders", "\(riverSides)")
            }
        }
        .padding(14)
        .frame(width: 300)
        .foregroundStyle(Palette.ink)
        .background(Palette.parchment.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.ink.opacity(0.7))
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    /// "Monarchy · Vassal of Morocco", "Tribal confederation", ...
    private func countryStatus(_ country: CountryID, world: World) -> String {
        let c = world.countries
        var parts = [c.government[country.index].displayName]
        if let lord = c.overlord[country.index], let kind = c.subjectType[country.index] {
            switch kind {
            case .personalUnion: parts.append("Personal union with \(c.name[lord.index])")
            case .vassal: parts.append("Vassal of \(c.name[lord.index])")
            case .tributary: parts.append("Tributary of \(c.name[lord.index])")
            }
        }
        let subjects = c.subjects(of: country)
        if !subjects.isEmpty {
            parts.append("\(subjects.count) subject\(subjects.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - People

/// Who lives in the province, and in its state as a whole.
struct PeopleSection: View {
    @Environment(GameModel.self) private var model
    let province: ProvinceID
    @State private var showState = false

    var body: some View {
        let world = model.world
        let stateID = world.provinces.state[province.index]
        let b = showState ? world.breakdown(ofState: stateID) : world.breakdown(of: province)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(showState ? "People of \(world.states.name[stateID.index])" : "People")
                    .font(.callout.bold())
                Spacer()
                HStack(spacing: 0) {
                    toggleButton("Province", selected: !showState) { showState = false }
                    toggleButton("State", selected: showState) { showState = true }
                }
                .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            line("Population", Self.people(b.total))
            ForEach(Array(b.cultureShares().prefix(4).enumerated()), id: \.offset) { _, entry in
                shareLine(world.cultures.name[entry.0.index], entry.1)
            }
            Divider().opacity(0.4)
            ForEach(Array(b.religionShares().prefix(4).enumerated()), id: \.offset) { _, entry in
                shareLine(religionLabel(entry.0, b), entry.1, color: Palette.color(entry.0.color))
            }
            Divider().opacity(0.4)
            HStack(spacing: 8) {
                ForEach(Array(b.classShares().enumerated()), id: \.offset) { _, entry in
                    VStack(spacing: 0) {
                        Text(Self.percent(entry.1)).font(.caption.monospacedDigit())
                        Text(entry.0.displayName).font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
                    }
                }
            }
            let orders = showState ? [] : world.provinces.sufiOrders[province.index]
            if !orders.isEmpty {
                Text("Sufi orders: " + orders.map { "\($0.order.displayName) (\(Self.percent($0.strength)))" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Palette.ink.opacity(0.7))
            }
        }
        .padding(.vertical, 2)
    }

    private func toggleButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(selected ? Palette.ink.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? Palette.parchment : Palette.ink)
        }
        .buttonStyle(.plain)
    }

    /// "Sunni (Hanafi)" when one school dominates.
    private func religionLabel(_ religion: Religion, _ b: PopBreakdown) -> String {
        let sects = b.bySect.filter { $0.key.religion == religion }
        guard let top = sects.max(by: { $0.value < $1.value }), let total = b.byReligion[religion], total > 0,
              top.value / total > 0.5 else { return religion.displayName }
        return "\(religion.displayName) (\(top.key.displayName))"
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.ink.opacity(0.7))
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private func shareLine(_ label: String, _ share: Double, color: Color? = nil) -> some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(label).lineLimit(1)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ink.opacity(0.1))
                    Capsule().fill(Palette.ink.opacity(0.55)).frame(width: geo.size.width * share)
                }
            }
            .frame(width: 50, height: 5)
            Text(Self.percent(share)).monospacedDigit().frame(width: 38, alignment: .trailing)
        }
        .font(.caption)
    }

    static func percent(_ v: Double) -> String {
        v >= 0.095 || v == 0 ? "\(Int((v * 100).rounded()))%" : String(format: "%.1f%%", v * 100)
    }

    static func people(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.2f M", v / 1_000_000) }
        if v >= 10_000 { return "\(Int((v / 1000).rounded())) k" }
        return "\(Int(v.rounded()))"
    }
}

// MARK: - Sea panel

struct SeaPanel: View {
    @Environment(GameModel.self) private var model
    let sea: SeaZoneID

    var body: some View {
        let world = model.world
        let z = world.seaZones
        let coast = z.coast[sea.index]
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(z.name[sea.index]).font(.title3.bold())
                Spacer()
                Button { model.select(sea: nil) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            Text("Sea zone").font(.subheadline).foregroundStyle(Palette.ink.opacity(0.7))
            Divider()
            Text("Connects to").font(.callout.bold())
            Text(z.neighbors[sea.index].map { z.name[$0.index] }.joined(separator: ", "))
                .font(.callout)
            Text("Coast (\(coast.count) provinces)").font(.callout.bold()).padding(.top, 4)
            Text(coast.prefix(12).map { world.provinces.name[$0.index] }.joined(separator: ", ")
                 + (coast.count > 12 ? "…" : ""))
                .font(.callout)
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .foregroundStyle(Palette.ink)
        .background(Palette.parchment.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
    }
}
