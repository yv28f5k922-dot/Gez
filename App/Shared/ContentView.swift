import SwiftUI
import GezCore

struct ContentView: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            ZStack(alignment: .bottomLeading) {
                MapView()
                if let province = model.selectedProvince {
                    ProvincePanel(province: province)
                        .padding()
                }
            }
        }
        .background(Palette.sea)
    }
}

enum Palette {
    static let sea = Color(red: 0.55, green: 0.66, blue: 0.70)
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
                Circle()
                    .fill(Palette.color(countries.color[player.index]))
                    .frame(width: 18, height: 18)
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

// MARK: - Province panel

struct ProvincePanel: View {
    @Environment(GameModel.self) private var model
    let province: ProvinceID

    var body: some View {
        let _ = model.revision
        let p = model.world.provinces
        let c = model.world.countries
        let i = province.index
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(p.name[i]).font(.title3.bold())
                Spacer()
                Button {
                    model.selectedProvince = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            if let owner = p.owner[i] {
                HStack(spacing: 6) {
                    Circle().fill(Palette.color(c.color[owner.index])).frame(width: 12, height: 12)
                    Text(c.name[owner.index])
                }
            }
            Divider()
            row("Population", String(format: "%.0f", p.population[i]))
            row("Base tax", String(format: "%.1f / year", p.baseTax[i]))
            row("Production", String(format: "%.1f / year", p.production[i]))
            row("Fort level", "\(p.fortLevel[i])")
            row("Terrain", p.terrain[i].rawValue.capitalized)
            row("Religion", p.religion[i].rawValue.capitalized)
        }
        .padding(14)
        .frame(width: 280)
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
}
