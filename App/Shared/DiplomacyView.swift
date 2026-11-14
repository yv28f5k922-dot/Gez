import GezCore
import SwiftUI

/// Diplomacy panel showing relation slots, target country standings, treaties,
/// coalition threats, and Casus Belli war declarations.
struct DiplomacyPanel: View {
    @Environment(GameModel.self) private var model
    var scrolls = true

    @State private var searchText = ""
    @State private var selectedCBIndex = 0
    @State private var confirmBreakTruce = false
    @State private var feedbackMessage: String?

    var body: some View {
        let _ = model.revision
        let content = VStack(alignment: .leading, spacing: 10) {
            if let player = model.playerCountry {
                header(player)
                targetPicker(player)
                if let target = model.selectedDiplomacyCountry, target != player {
                    Divider()
                    targetSection(player: player, target: target)
                } else {
                    Divider()
                    Text("Select a country above or click a foreign province on the map.")
                        .font(.callout)
                        .foregroundStyle(Palette.ink.opacity(0.7))
                }
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
        .frame(width: 400)
        .foregroundStyle(Palette.ink)
        .background(Palette.parchment.opacity(0.97), in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
    }

    private func header(_ player: CountryID) -> some View {
        let world = model.world
        let used = world.diplomacy.usedRelationSlots(for: player, world: world)
        let cap = world.diplomacy.relationSlots(for: player, world: world)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Diplomacy").font(.title3.bold())
                Text("Relation Slots: \(used) / \(cap)\(used > cap ? " (Over limit)" : "")")
                    .font(.caption)
                    .foregroundStyle(used > cap ? Color.red : Palette.ink.opacity(0.7))
            }
            Spacer()
            Button {
                model.showDiplomacy = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private func targetPicker(_ player: CountryID) -> some View {
        let world = model.world
        let sovereigns = world.countries.ids
            .filter { $0 != player && !world.provinces(ownedBy: $0).isEmpty }
            .filter { cid in
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return q.isEmpty || world.countries.name[cid.index].lowercased().contains(q)
                    || world.countries.tag[cid.index].lowercased().contains(q)
            }
            .sorted { a, b in
                let warA = world.diplomacy.isAtWar(player, a) ? 0 : 1
                let warB = world.diplomacy.isAtWar(player, b) ? 0 : 1
                if warA != warB { return warA < warB }
                let allyA = world.diplomacy.areAllies(player, a) ? 0 : 1
                let allyB = world.diplomacy.areAllies(player, b) ? 0 : 1
                if allyA != allyB { return allyA < allyB }
                return world.countries.name[a.index] < world.countries.name[b.index]
            }

        return VStack(alignment: .leading, spacing: 6) {
            TextField("Filter country name or tag…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.callout)

            Picker("Country", selection: Binding(
                get: { model.selectedDiplomacyCountry ?? sovereigns.first },
                set: {
                    model.selectedDiplomacyCountry = $0
                    selectedCBIndex = 0
                    confirmBreakTruce = false
                    feedbackMessage = nil
                }
            )) {
                ForEach(sovereigns, id: \.self) { cid in
                    let prefix = world.diplomacy.isAtWar(player, cid) ? "[WAR] "
                        : (world.diplomacy.areAllies(player, cid) ? "[ALLY] " : "")
                    Text("\(prefix)\(world.countries.name[cid.index]) (\(world.countries.tag[cid.index]))")
                        .tag(Optional(cid))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func targetSection(player: CountryID, target: CountryID) -> some View {
        let world = model.world
        let opinion = world.diplomacy.opinion(of: player, by: target)
        let trust = world.diplomacy.trust(of: player, by: target)
        let ae = Int(world.diplomacy.aggressiveExpansion(of: player, by: target).rounded())
        let activeTreaties = world.diplomacy.treaties.filter { $0.involves(player, target) }
        let atWar = world.diplomacy.isAtWar(player, target)
        let coalitionMembers = world.diplomacy.coalitions[player] ?? []

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CountryArmsView(world: world, country: target).frame(height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(world.countries.name[target.index]).font(.headline)
                    Text("\(world.countries.government[target.index].displayName) · \(world.countries.religion[target.index].rawValue.capitalized)")
                        .font(.caption)
                        .foregroundStyle(Palette.ink.opacity(0.7))
                }
                Spacer()
                if atWar {
                    Text("AT WAR")
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                } else if coalitionMembers.contains(target) {
                    Text("COALITION")
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 12) {
                statPill("Opinion", value: String(format: "%+d", opinion), color: opinion >= 0 ? .green : .red)
                statPill("Trust", value: "\(trust)", color: .blue)
                statPill("AE", value: "\(ae)", color: ae >= 50 ? .red : .orange)
            }

            if !activeTreaties.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active Treaties").font(.caption.bold())
                    ForEach(Array(activeTreaties.enumerated()), id: \.offset) { _, treaty in
                        let exp = treaty.expiry.map { " until \($0.description)" } ?? ""
                        Text("• \(treatyLabel(treaty, player: player))\(exp)")
                            .font(.caption)
                            .foregroundStyle(Palette.ink.opacity(0.8))
                    }
                }
            }

            Divider()
            actionsGrid(player: player, target: target, atWar: atWar)

            if !atWar {
                Divider()
                warDeclarationSection(player: player, target: target)
            } else if let war = world.diplomacy.activeWar(between: player, and: target) {
                Divider()
                Button {
                    model.showDiplomacy = false
                    model.showPeaceForWarID = war.id
                } label: {
                    Label("Negotiate Peace", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Palette.ink.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if let msg = feedbackMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
    }

    private func actionsGrid(player: CountryID, target: CountryID, atWar: Bool) -> some View {
        let world = model.world
        let allied = world.diplomacy.areAllies(player, target)
        let guaranteed = world.diplomacy.hasTreaty(.guarantee, between: player, and: target)
        let nap = world.diplomacy.hasTreaty(.nonAggression, between: player, and: target)
        let access = world.diplomacy.hasTreaty(.militaryAccess, between: player, and: target)

        return VStack(alignment: .leading, spacing: 6) {
            Text("Diplomatic Actions").font(.caption.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                actionButton(allied ? "Break Alliance" : "Form Alliance", disabled: atWar) {
                    model.toggleAlliance(with: target)
                }
                actionButton("Improve Relations (+15)", disabled: false) {
                    model.improveRelations(with: target)
                }
                actionButton(guaranteed ? "Revoke Guarantee" : "Guarantee", disabled: atWar) {
                    model.toggleGuarantee(with: target)
                }
                actionButton(nap ? "Break Non-Aggression" : "Non-Aggression Pact", disabled: atWar) {
                    model.toggleNonAggression(with: target)
                }
                actionButton(access ? "Revoke Mil. Access" : "Grant Mil. Access", disabled: atWar) {
                    model.toggleMilitaryAccess(with: target)
                }
                actionButton(world.countries.embargoes[player.index].contains(target) ? "Lift Embargo" : "Embargo", disabled: false) {
                    model.toggleEmbargo(target)
                }
            }
        }
    }

    private func warDeclarationSection(player: CountryID, target: CountryID) -> some View {
        let world = model.world
        let cbs = world.diplomacy.availableCasusBelli(attacker: player, defender: target, in: world)
        let safeIndex = min(selectedCBIndex, max(0, cbs.count - 1))
        let chosenCB = cbs.isEmpty ? nil : cbs[safeIndex]
        let validation = world.diplomacy.canDeclareWar(
            attacker: player,
            defender: target,
            breakTruce: confirmBreakTruce,
            world: world
        )

        return VStack(alignment: .leading, spacing: 6) {
            Text("Casus Belli & War").font(.caption.bold())
            if !cbs.isEmpty {
                Picker("Casus Belli", selection: Binding(
                    get: { safeIndex },
                    set: { selectedCBIndex = $0 }
                )) {
                    ForEach(Array(cbs.enumerated()), id: \.offset) { idx, cb in
                        Text(cb.name).tag(idx)
                    }
                }
                .pickerStyle(.menu)

                if let cb = chosenCB {
                    Text(cb.description)
                        .font(.caption)
                        .foregroundStyle(Palette.ink.opacity(0.75))
                }
            }

            switch validation {
            case .invalid(let reason):
                Text(reason).font(.caption).foregroundStyle(Color.red)
            case .requiresTruceBreak(let until):
                Toggle("Break active truce (expires \(until.description)): -3 Stability, +25 AE", isOn: $confirmBreakTruce)
                    .font(.caption)
            case .valid:
                EmptyView()
            }

            Button {
                guard let cb = chosenCB else { return }
                let res = model.declareWar(on: target, cb: cb, breakTruce: confirmBreakTruce)
                if case .failure(let err) = res {
                    feedbackMessage = err.description
                } else {
                    feedbackMessage = nil
                    confirmBreakTruce = false
                }
            } label: {
                Text("Declare War")
                    .font(.callout.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(canClickDeclare(validation) ? Color.red.opacity(0.85) : Palette.ink.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(canClickDeclare(validation) ? .white : Palette.ink.opacity(0.45))
            }
            .buttonStyle(.plain)
            .disabled(!canClickDeclare(validation) || chosenCB == nil)
        }
    }

    private func canClickDeclare(_ validation: WarDeclarationValidation) -> Bool {
        if case .valid = validation { return true }
        return false
    }

    private func statPill(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Palette.ink.opacity(0.7))
            Text(value).font(.callout.bold()).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func actionButton(_ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(Palette.ink.opacity(disabled ? 0.05 : 0.12), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(disabled ? Palette.ink.opacity(0.4) : Palette.ink)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func treatyLabel(_ treaty: Treaty, player: CountryID) -> String {
        switch treaty.type {
        case .alliance: return "Alliance"
        case .nonAggression: return "Non-Aggression Pact"
        case .truce: return "Truce"
        case .guarantee: return treaty.first == player ? "Guaranteeing them" : "Guaranteed by them"
        case .militaryAccess: return treaty.first == player ? "Granting Military Access" : "Have Military Access"
        }
    }
}

/// Active wars overview, war score breakdown, call-to-arms invitations, and incoming enemy peace offers.
struct WarsOverviewPanel: View {
    @Environment(GameModel.self) private var model
    var scrolls = true

    @State private var showAllWorldWars = false

    var body: some View {
        let _ = model.revision
        let content = VStack(alignment: .leading, spacing: 10) {
            if let player = model.playerCountry {
                header
                incomingOffersSection(player)
                Toggle("Show AI-only wars", isOn: $showAllWorldWars)
                    .font(.caption)
                Divider()
                warsList(player)
            }
        }
        Group {
            if scrolls {
                ScrollView { content }.frame(maxHeight: 620)
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

    private var header: some View {
        HStack {
            Text("Wars & Peace Offers").font(.title3.bold())
            Spacer()
            Button {
                model.showWars = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func incomingOffersSection(_ player: CountryID) -> some View {
        let offers = model.world.diplomacy.pendingPeaceOffers.filter { $0.loser == player }
        if !offers.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Incoming Peace Offers").font(.caption.bold()).foregroundStyle(.red)
                ForEach(Array(offers.enumerated()), id: \.offset) { _, offer in
                    let senderName = model.world.countries.name[offer.winner.index]
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(senderName) proposes peace:").font(.callout.bold())
                        if offer.demands.isEmpty {
                            Text("• White Peace").font(.caption)
                        } else {
                            ForEach(Array(offer.demands.enumerated()), id: \.offset) { _, d in
                                Text("• \(describeDemand(d, world: model.world))").font(.caption)
                            }
                        }
                        HStack {
                            Button("Accept") { model.respondToPendingPeaceOffer(offer, accept: true) }
                                .buttonStyle(.borderedProminent)
                            Button("Decline") { model.respondToPendingPeaceOffer(offer, accept: false) }
                                .buttonStyle(.bordered)
                        }
                        .font(.caption)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Divider()
        }
    }

    @ViewBuilder
    private func warsList(_ player: CountryID) -> some View {
        let world = model.world
        let wars = showAllWorldWars ? world.diplomacy.wars : world.diplomacy.activeWars(for: player)
        if wars.isEmpty {
            Text("No active wars.")
                .font(.callout)
                .foregroundStyle(Palette.ink.opacity(0.7))
        } else {
            ForEach(wars) { war in
                warCard(war, player: player, world: world)
                Divider()
            }
        }
    }

    private func warCard(_ war: War, player: CountryID, world: World) -> some View {
        let wsPct = Int((war.warScore * 100.0).rounded())
        let battlePct = Int((war.battleWarScore * 100.0).rounded())
        let tickingPct = Int((war.tickingWarScore * 100.0).rounded())
        let pAtt = war.primaryAttacker
        let pDef = war.primaryDefender

        let playerAlliesUncalled = world.countries.ids.filter { c in
            guard c != player,
                  !war.isParticipant(c),
                  world.diplomacy.areAllies(player, c),
                  war.isParticipant(player) else { return false }
            return true
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(war.name).font(.headline)
                Spacer()
                Text(String(format: "%+d%% WS", wsPct))
                    .font(.callout.bold())
                    .monospacedDigit()
                    .foregroundStyle(wsPct >= 0 ? .green : .red)
            }
            Text("Attackers: \(war.attackers.map { world.countries.tag[$0.index] }.joined(separator: ", "))")
                .font(.caption)
            Text("Defenders: \(war.defenders.map { world.countries.tag[$0.index] }.joined(separator: ", "))")
                .font(.caption)
            Text("Since \(war.startDate.description) · Battles \(battlePct)% · Goal \(tickingPct)%")
                .font(.caption2)
                .foregroundStyle(Palette.ink.opacity(0.7))

            if war.isParticipant(player) {
                HStack(spacing: 8) {
                    Button("Negotiate Peace") {
                        model.showPeaceForWarID = war.id
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Palette.ink.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Palette.parchment)
                    .buttonStyle(.plain)

                    if let firstEnemy = (war.isAttacker(player) ? pDef : pAtt) as CountryID? {
                        Button("Inspect \(world.countries.tag[firstEnemy.index])") {
                            model.openDiplomacy(with: firstEnemy)
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                    }
                }

                if !playerAlliesUncalled.isEmpty {
                    ForEach(playerAlliesUncalled, id: \.self) { ally in
                        let enemyLeader = war.isAttacker(player) ? pDef : pAtt
                        let eval = world.diplomacy.evaluateCallToArms(
                            ally: ally,
                            caller: player,
                            enemy: enemyLeader,
                            isDefensive: war.isDefender(player),
                            in: world
                        )
                        HStack {
                            Text("Call \(world.countries.name[ally.index]) (\(eval.willAccept ? "Accepts" : "Declines"))")
                                .font(.caption)
                            Spacer()
                            Button("Call") {
                                _ = model.callAllyToWar(ally, warID: war.id)
                            }
                            .font(.caption.bold())
                        }
                    }
                }
            }
        }
    }

    private func describeDemand(_ demand: PeaceDemand, world: World) -> String {
        switch demand {
        case .cedeProvince(let pid, let to):
            return "Cede \(world.provinces.name[pid.index]) to \(world.countries.name[to.index])"
        case .returnCore(let pid, let to):
            return "Return core \(world.provinces.name[pid.index]) to \(world.countries.name[to.index])"
        case .ducatIndemnity(let amount):
            return "\(Int(amount)) Ducats Indemnity"
        case .warReparations:
            return "War Reparations (10% income, 10 years)"
        case .makeVassal:
            return "Force Vassalization"
        case .makeTributary:
            return "Force Tributary"
        case .annulTreaty(let with):
            return "Annul treaties with \(world.countries.name[with.index])"
        case .releaseNation(let country):
            return "Release \(world.countries.name[country.index])"
        }
    }
}

/// Interactive peace treaty negotiator showing available war demands, costs,
/// truce length, aggressive expansion, and live acceptance factors.
struct PeaceNegotiationPanel: View {
    @Environment(GameModel.self) private var model
    let warID: String

    @State private var selectedProvinces: Set<ProvinceID> = []
    @State private var includeReparations = false
    @State private var indemnityAmount: Double = 0
    @State private var makeVassal = false
    @State private var annulPartners: Set<CountryID> = []
    @State private var rejectionMessage: String?

    var body: some View {
        let _ = model.revision
        let world = model.world
        if let player = model.playerCountry,
           let war = world.diplomacy.wars.first(where: { $0.id == warID }),
           war.isParticipant(player) {
            let loser = war.isAttacker(player) ? war.primaryDefender : war.primaryAttacker
            let loserProvs = world.provinces(ownedBy: loser).sorted { a, b in
                let aOcc = world.provinces.occupiedBy[a.index] == player ? 0 : 1
                let bOcc = world.provinces.occupiedBy[b.index] == player ? 0 : 1
                if aOcc != bOcc { return aOcc < bOcc }
                return world.provinces.name[a.index] < world.provinces.name[b.index]
            }
            let demands = buildDemands(player: player)
            let offer = PeaceOffer(warID: war.id, winner: player, loser: loser, demands: demands)
            let eval = world.diplomacy.evaluatePeaceOffer(offer, date: model.date, in: world)
            let truceYears = world.diplomacy.truceDurationYears(forPeaceCost: eval.totalCost)
            let ae = Int(world.diplomacy.aggressiveExpansionForPeace(offer, war: war, in: world).rounded())

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Peace Negotiation — \(world.countries.name[loser.index])")
                        .font(.title3.bold())
                    Spacer()
                    Button {
                        model.showPeaceForWarID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Territorial Demands").font(.caption.bold())
                        ForEach(loserProvs, id: \.self) { pid in
                            let cost = world.diplomacy.peaceDemandCost(.cedeProvince(province: pid, to: player), loser: loser, war: war, in: world)
                            let isOcc = world.provinces.occupiedBy[pid.index].map { war.areEnemies($0, loser) } ?? false
                            Toggle(isOn: Binding(
                                get: { selectedProvinces.contains(pid) },
                                set: { if $0 { selectedProvinces.insert(pid) } else { selectedProvinces.remove(pid) } }
                            )) {
                                HStack {
                                    Text(world.provinces.name[pid.index])
                                    if isOcc {
                                        Text("(Occupied)").font(.caption2).foregroundStyle(.green)
                                    }
                                    Spacer()
                                    Text("\(cost)%").monospacedDigit().foregroundStyle(Palette.ink.opacity(0.75))
                                }
                                .font(.caption)
                            }
                        }

                        Divider()
                        Text("Treaties & Concessions").font(.caption.bold())
                        Toggle("War Reparations (10% income, 10y)", isOn: $includeReparations)
                            .font(.caption)
                        Toggle("Force Vassalization", isOn: $makeVassal)
                            .font(.caption)

                        HStack {
                            Text("Ducats Indemnity: \(Int(indemnityAmount))")
                                .font(.caption)
                            Slider(value: $indemnityAmount, in: 0...200, step: 25)
                        }

                        let loserAllies = world.diplomacy.treaties
                            .filter { $0.type == .alliance && ($0.first == loser || $0.second == loser) }
                            .map { $0.first == loser ? $0.second : $0.first }
                            .sorted { $0.index < $1.index }
                        if !loserAllies.isEmpty {
                            ForEach(loserAllies, id: \.self) { ally in
                                Toggle("Annul alliance with \(world.countries.name[ally.index])", isOn: Binding(
                                    get: { annulPartners.contains(ally) },
                                    set: { if $0 { annulPartners.insert(ally) } else { annulPartners.remove(ally) } }
                                ))
                                .font(.caption)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)

                Divider()
                HStack {
                    Text("Cost: \(eval.totalCost) / 100%")
                        .foregroundStyle(eval.totalCost > 100 ? .red : Palette.ink)
                    Spacer()
                    Text("Truce: \(truceYears) yrs · AE: +\(ae)")
                }
                .font(.caption.bold())
                .monospacedDigit()

                VStack(alignment: .leading, spacing: 2) {
                    Text(eval.willAccept ? "They will accept (\(eval.score))" : "They refuse (\(eval.score))")
                        .font(.callout.bold())
                        .foregroundStyle(eval.willAccept ? .green : .red)
                    ForEach(Array(eval.factors.prefix(4).enumerated()), id: \.offset) { _, f in
                        Text("• \(f.name): \(f.score >= 0 ? "+" : "")\(f.score)")
                            .font(.caption2)
                            .foregroundStyle(Palette.ink.opacity(0.75))
                    }
                }

                if let err = rejectionMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                HStack {
                    Button("Cancel") {
                        model.showPeaceForWarID = nil
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Send Peace Offer") {
                        let res = model.proposePeace(offer)
                        if case .failure = res {
                            rejectionMessage = "Peace offer was rejected or invalid."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!eval.willAccept || eval.totalCost > 100)
                }
            }
            .padding(16)
            .frame(width: 430)
            .foregroundStyle(Palette.ink)
            .background(Palette.parchment.opacity(0.98), in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 10)
        }
    }

    private func buildDemands(player: CountryID) -> [PeaceDemand] {
        var demands: [PeaceDemand] = []
        for pid in selectedProvinces.sorted(by: { $0.index < $1.index }) {
            demands.append(.cedeProvince(province: pid, to: player))
        }
        if includeReparations {
            demands.append(.warReparations)
        }
        if indemnityAmount > 0 {
            demands.append(.ducatIndemnity(amount: indemnityAmount))
        }
        if makeVassal {
            demands.append(.makeVassal)
        }
        for partner in annulPartners.sorted(by: { $0.index < $1.index }) {
            demands.append(.annulTreaty(with: partner))
        }
        return demands
    }
}
