import GezCore
import SwiftUI

/// Armies, national manpower, commanders, levies, and recruitment (Phase 6).
struct ArmyPanel: View {
    @Environment(GameModel.self) private var model
    /// Off for snapshots (the image renderer can't draw scroll views).
    var scrolls = true

    var body: some View {
        let _ = model.revision
        let content = VStack(alignment: .leading, spacing: 8) {
            if let player = model.playerCountry {
                header
                manpowerSummary(player)
                Divider()
                armiesList(player)
                if !model.world.military.rebelArmies(of: player).isEmpty {
                    Divider()
                    rebelSection(player)
                }
                Divider()
                recruitSection(player)
            }
        }
        Group {
            if scrolls {
                ScrollView { content }.frame(maxHeight: 650)
            } else {
                content
            }
        }
        .padding(14)
        .frame(width: 390)
        .foregroundStyle(Palette.ink)
        .background(Palette.parchment.opacity(0.97), in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
    }

    private var header: some View {
        HStack {
            Text("Armies").font(.title3.bold())
            Spacer()
            Button {
                model.showArmies = false
                model.moveModeForArmy = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private func line(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.ink.opacity(bold ? 1 : 0.75))
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(bold ? .callout.bold() : .callout)
    }

    private func manpowerSummary(_ c: CountryID) -> some View {
        let w = model.world
        let mp = Int(w.military.manpower[c.index].rounded())
        let maxMP = Int(w.military.maxManpower[c.index].rounded())
        let gain = Int(ArmySystem.monthlyManpowerGain(w, c).rounded())
        let standing = w.military.totalMen(of: c, origin: .professional)
        let levies = w.military.totalMen(of: c, origin: .levy)
        let mercs = w.military.totalMen(of: c, origin: .mercenary)
        let upkeep = w.military.armies(of: c).reduce(0.0) { $0 + ArmySystem.armyUpkeep(w, $1) }
        let attrition = w.military.lastAttritionLosses[c.index]

        return VStack(alignment: .leading, spacing: 3) {
            line("National manpower", "\(mp.formatted()) / \(maxMP.formatted()) (+\(gain)/mo)", bold: true)
            line("Standing professionals", "\(standing.formatted()) men")
            line("Raised levies", "\(levies.formatted()) men")
            line("Mercenaries", "\(mercs.formatted()) / \(ArmySystem.mercenaryLimit(w, c).formatted()) men")
            line("Army upkeep", String(format: "−%.1f / month", upkeep))
            if attrition > 0 {
                Text("Lost \(attrition.formatted()) men to starvation & camp disease last month")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.85))
            }
            HStack(spacing: 6) {
                Button {
                    model.raiseAllLevies()
                } label: {
                    Text("Raise all levies")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Palette.ink.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

                if levies > 0 {
                    Button {
                        model.disbandLevies()
                    } label: {
                        Text("Disband levies")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Palette.ink.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }

    private func armiesList(_ c: CountryID) -> some View {
        let w = model.world
        let list = w.military.armies(of: c)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Field armies (\(list.count))").font(.callout.bold())
            if let moving = model.moveModeForArmy {
                let name = w.military.armies.name[Int(moving.rawValue)]
                HStack {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    Text("Click any province on the map to march \(name)")
                        .font(.caption.bold())
                    Spacer()
                    Button("Cancel") { model.moveModeForArmy = nil }
                        .font(.caption)
                }
                .padding(6)
                .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            }
            if list.isEmpty {
                Text("No armies in the field. Recruit standing regiments or raise levies below.")
                    .font(.caption).foregroundStyle(Palette.ink.opacity(0.65))
            }
            ForEach(list, id: \.rawValue) { aid in
                armyCard(aid, country: c)
            }
        }
    }

    private func armyCard(_ aid: ArmyID, country c: CountryID) -> some View {
        let w = model.world
        let i = Int(aid.rawValue)
        let prov = w.military.armies.province[i]
        let provName = w.provinces.name[prov.index]
        let men = w.military.armies.totalMen(of: aid)
        let limit = ArmySystem.supplyLimit(w, in: prov)
        let inProv = ArmySystem.soldiersInProvince(w, prov)
        let overSupply = inProv > limit
        let path = w.military.armies.path[i]
        let candidates = ArmySystem.commanderCandidates(w, c, date: model.date)
        let cmd = w.military.armies.commander[i]

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(w.military.armies.name[i]).font(.callout.bold())
                Spacer()
                Text("\(men.formatted()) men · \(String(format: "%.1f", ArmySystem.armyUpkeep(w, aid)))/mo")
                    .font(.caption.monospacedDigit())
            }
            HStack(spacing: 6) {
                Button {
                    model.select(province: prov)
                } label: {
                    Label(provName, systemImage: "mappin.and.ellipse")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)

                if let next = path.first, let dest = path.last {
                    let daysLeft = max(1, Int((w.military.armies.moveStepDays[i] - w.military.armies.moveProgressDays[i]).rounded(.up)))
                    Text("→ \(w.provinces.name[dest.index]) (next: \(w.provinces.name[next.index]), \(daysLeft)d)")
                        .font(.caption2)
                        .foregroundStyle(Palette.ink.opacity(0.75))
                }
                Spacer()
                Text("Supply \(inProv / 1000)k/\(limit / 1000)k")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(overSupply ? .red : Palette.ink.opacity(0.65))
            }
            HStack(spacing: 6) {
                Text("Commander:").font(.caption).foregroundStyle(Palette.ink.opacity(0.7))
                Menu {
                    Button("None") { model.assignCommander(nil, to: aid) }
                    ForEach(candidates, id: \.index) { ch in
                        let mSkill = w.people.characters.skill(ch, .martial)
                        Button("\(w.people.characters.fullName(ch)) (Martial \(mSkill))") {
                            model.assignCommander(ch, to: aid)
                        }
                    }
                } label: {
                    if let cmd {
                        let mSkill = w.people.characters.skill(cmd, .martial)
                        Text("\(w.people.characters.fullName(cmd)) (⚔︎\(mSkill))")
                            .font(.caption.bold())
                    } else {
                        Text("Assign commander…")
                            .font(.caption)
                    }
                }
                Spacer()
            }
            Text(regimentSummary(w, regiments: w.military.armies.regiments[i]))
                .font(.caption2)
                .foregroundStyle(Palette.ink.opacity(0.7))

            HStack(spacing: 6) {
                Button {
                    model.moveModeForArmy = (model.moveModeForArmy == aid) ? nil : aid
                } label: {
                    Text(model.moveModeForArmy == aid ? "Pick province…" : "March…")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Palette.ink.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

                if w.military.armies.regiments[i].count >= 2 {
                    Button {
                        model.split(army: aid)
                    } label: {
                        Text("Split")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Palette.ink.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                let othersHere = w.military.armies(in: prov).filter {
                    $0 != aid && w.military.armies.owner[Int($0.rawValue)] == c && !w.military.armies.isRebel[Int($0.rawValue)]
                }
                if !othersHere.isEmpty {
                    Button {
                        model.mergeArmies(into: aid)
                    } label: {
                        Text("Merge")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Palette.ink.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                Button {
                    model.disband(army: aid)
                } label: {
                    Text("Disband")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func regimentSummary(_ w: World, regiments: [Regiment]) -> String {
        var counts: [UnitTypeID: (count: Int, men: Int, origins: Set<RegimentOrigin>)] = [:]
        for r in regiments {
            var entry = counts[r.type] ?? (0, 0, [])
            entry.count += 1
            entry.men += r.men
            entry.origins.insert(r.origin)
            counts[r.type] = entry
        }
        return counts.keys.sorted(by: { $0.rawValue < $1.rawValue }).map { uid in
            let info = counts[uid]!
            let uName = w.military.unit(uid).name
            let tag = info.origins.contains(.levy) ? " [levy]" : (info.origins.contains(.mercenary) ? " [merc]" : "")
            return "\(info.count)× \(uName)\(tag) (\(info.men))"
        }.joined(separator: ", ")
    }

    private func rebelSection(_ c: CountryID) -> some View {
        let w = model.world
        let rebels = w.military.rebelArmies(of: c)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Vassal revolts (\(rebels.count))")
                .font(.callout.bold())
                .foregroundStyle(.red.opacity(0.85))
            ForEach(rebels, id: \.rawValue) { rid in
                let i = Int(rid.rawValue)
                let prov = w.military.armies.province[i]
                let men = w.military.armies.totalMen(of: rid)
                HStack {
                    Text(w.military.armies.name[i]).font(.caption.bold())
                    Spacer()
                    Text("\(men.formatted()) men at \(w.provinces.name[prov.index])")
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func recruitSection(_ c: CountryID) -> some View {
        let w = model.world
        let targetProv: ProvinceID? = {
            if let sel = model.selectedProvince, w.provinces.owner[sel.index] == c {
                return sel
            }
            return w.countries.capital[c.index]
        }()

        return VStack(alignment: .leading, spacing: 5) {
            if let p = targetProv, w.provinces.owner[p.index] == c {
                let pName = w.provinces.name[p.index]
                HStack {
                    Text("Muster in \(pName)").font(.callout.bold())
                    Spacer()
                    let availLevy = ArmySystem.availableLevyMen(w, in: p)
                    if availLevy >= ArmyModel.minLevyMen {
                        Button {
                            _ = model.raiseLevies(in: p)
                        } label: {
                            Text("Raise levy (\(availLevy))")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Palette.ink.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else if ArmySystem.hasRaisedLevies(w, in: p) {
                        Text("Levy raised").font(.caption2).foregroundStyle(Palette.ink.opacity(0.6))
                    }
                }

                let units = ArmySystem.availableUnits(w, for: c)
                ForEach(units, id: \.id.rawValue) { u in
                    let profCost = ArmySystem.recruitmentCost(w, c, p, u.id)
                    let mercCost = ArmySystem.mercenaryCost(w, c, u.id)
                    let profRefusal = ArmySystem.recruitRefusal(w, c, in: p, unit: u.id)
                    let canMerc = w.countries.treasury[c.index] >= mercCost
                        && w.military.totalMen(of: c, origin: .mercenary) + u.maxMen <= ArmySystem.mercenaryLimit(w, c)
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(u.name) (\(u.category.displayName))")
                                .font(.caption.bold())
                            Text(String(format: "⚔︎%.0f 🛡%.0f · spd %.2f · %d men", u.attack, u.defence, u.speed, u.maxMen))
                                .font(.caption2)
                                .foregroundStyle(Palette.ink.opacity(0.65))
                        }
                        Spacer()
                        Button {
                            _ = model.recruitProfessional(u.id, in: p)
                        } label: {
                            Text("Recruit \(Int(profCost))d")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Palette.ink.opacity(profRefusal == nil ? 0.14 : 0.05), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(profRefusal != nil)
                        .help(profRefusal?.reason ?? "Recruit standing professional regiment")

                        if u.category != .artillery {
                            Button {
                                _ = model.hireMercenary(u.id, in: p)
                            } label: {
                                Text("Merc \(Int(mercCost))d")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Palette.ink.opacity(canMerc ? 0.10 : 0.04), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canMerc)
                        }
                    }
                }
            } else {
                Text("Select one of your provinces to recruit regiments.")
                    .font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
            }
        }
    }
}
