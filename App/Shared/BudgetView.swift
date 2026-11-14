import GezCore
import SwiftUI

/// Income and spending, tax levels per class, loans and banks, coinage.
struct BudgetPanel: View {
    @Environment(GameModel.self) private var model
    /// Off for snapshots (the image renderer can't draw scroll views).
    var scrolls = true

    var body: some View {
        let _ = model.revision
        let content = VStack(alignment: .leading, spacing: 8) {
            if let player = model.playerCountry {
                header
                summary(player)
                Divider()
                taxes(player)
                Divider()
                coinage(player)
                Divider()
                loans(player)
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
        .frame(width: 360)
        .foregroundStyle(Palette.ink)
        .background(Palette.parchment.opacity(0.97), in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6)
    }

    private var header: some View {
        HStack {
            Text("Budget").font(.title3.bold())
            Spacer()
            Button {
                model.showBudget = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private func money(_ x: Double) -> String { String(format: "%.1f", x) }

    private func line(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.ink.opacity(bold ? 1 : 0.75))
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(bold ? .callout.bold() : .callout)
    }

    private func summary(_ c: CountryID) -> some View {
        let w = model.world
        let tax = w.countries.lastTax[c.index]
        let debasing = w.countries.debasing[c.index] ? w.countries.lastMonthlyIncome[c.index] * Finance.debaseOngoingIncome : 0
        let income = w.countries.lastMonthlyIncome[c.index] + debasing
        let spend = w.countries.lastMonthlyExpenses[c.index]
        return VStack(alignment: .leading, spacing: 3) {
            Text("Last month").font(.caption.bold()).foregroundStyle(Palette.ink.opacity(0.6))
            ForEach(TaxClass.allCases, id: \.self) { tc in
                line("Tax on \(tc.socialClass.displayName.lowercased())", money(tax[tc.rawValue]))
            }
            if w.countries.lastVassalTax[c.index] > 0 {
                line("Kept by vassals", "−" + money(w.countries.lastVassalTax[c.index]))
            }
            if debasing > 0 { line("Debased coin", money(debasing)) }
            line("Merchants", String(format: "%+.1f", w.countries.lastTrade[c.index]))
            line("Tolls", money(w.countries.lastTolls[c.index]))
            line("Building upkeep", "−" + money(w.countries.lastUpkeep[c.index]))
            line("Army upkeep", "−" + money(w.military.lastArmyUpkeep[c.index]))
            line("Interest", "−" + money(w.countries.lastInterest[c.index]))
            line("Balance", String(format: "%+.1f / month", income - spend), bold: true)
            line("Treasury", money(w.countries.treasury[c.index]))
            if w.countries.bankruptMonthsLeft[c.index] > 0 {
                Text("Bankrupt: no loans, income −25% and unrest for \(w.countries.bankruptMonthsLeft[c.index]) more months")
                    .font(.caption).foregroundStyle(.red.opacity(0.85))
            }
        }
    }

    private func taxes(_ c: CountryID) -> some View {
        let w = model.world
        return VStack(alignment: .leading, spacing: 4) {
            Text("Taxes").font(.callout.bold())
            Text("Higher taxes bring more money but make that class less content. Taxing nobles also angers your vassals.")
                .font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
            ForEach(TaxClass.allCases, id: \.self) { tc in
                let level = w.countries.taxLevel[c.index][tc.rawValue]
                HStack {
                    Text(tc.socialClass.displayName).frame(width: 72, alignment: .leading)
                    Slider(value: Binding(get: { level }, set: { model.setTax(tc, level: ($0 * 4).rounded() / 4) }),
                           in: 0...Finance.maxTaxLevel)
                    Text(Self.levelName(level)).font(.caption).frame(width: 70, alignment: .trailing)
                }
                .font(.callout)
                if let s = w.satisfaction(of: tc.socialClass, in: w.provinces(ownedBy: c)) {
                    Text("Content: \(Int((s * 100).rounded()))%")
                        .font(.caption2).foregroundStyle(Palette.ink.opacity(0.55))
                        .padding(.leading, 72)
                }
            }
        }
    }

    static func levelName(_ level: Double) -> String {
        switch level {
        case ..<0.01: return "None"
        case ..<0.76: return "Low"
        case ..<1.01: return "Normal"
        case ..<1.51: return "High"
        default: return "Crushing"
        }
    }

    private func coinage(_ c: CountryID) -> some View {
        let w = model.world
        let inflation = w.countries.inflation[c.index]
        let quick = max(10, w.countries.lastMonthlyIncome[c.index] * Finance.debaseOnceMonths)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Coinage").font(.callout.bold())
            line("Inflation", String(format: "%.1f%%", inflation * 100))
            Text("Inflation makes buildings (and later armies) dearer and angers burghers most. It falls slowly when you stop debasing.")
                .font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
            if !GovernmentSystem.canDebase(w, c) {
                Text("Your Sound money law forbids debasing the coin.")
                    .font(.caption).foregroundStyle(.red.opacity(0.8))
            }
            HStack {
                Button {
                    model.debaseOnce()
                } label: {
                    Text(String(format: "Debase once: +%.0f, +%.0f%% inflation", quick, Finance.debaseOnceInflation * 100))
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Palette.ink.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!GovernmentSystem.canDebase(w, c))
            }
            Toggle(isOn: Binding(get: { w.countries.debasing[c.index] }, set: { model.setDebasing($0) })) {
                Text(String(format: "Keep debasing (+%.0f%% income, +%.1f%% inflation a month)",
                            Finance.debaseOngoingIncome * 100, Finance.debaseOngoingInflation * 100))
                    .font(.caption)
            }
        }
    }

    private func loans(_ c: CountryID) -> some View {
        let w = model.world
        let mine = w.finance.loans.enumerated().filter { $0.element.country == c }
        let banks = w.finance.banks.ids.compactMap { b in w.loanRate(b, for: c).map { (b, $0) } }
            .sorted { $0.1 < $1.1 }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Loans").font(.callout.bold())
            if mine.isEmpty {
                Text("No debts.").font(.caption).foregroundStyle(Palette.ink.opacity(0.6))
            }
            ForEach(mine, id: \.offset) { entry in
                let index = entry.offset, loan = entry.element
                HStack(spacing: 6) {
                    Text(w.finance.banks.name[loan.bank.index]).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f at %.1f%% · %d mo", loan.principal, loan.rate * 100, loan.monthsLeft))
                        .monospacedDigit()
                    Button("Repay") { model.repay(loan: index) }
                        .disabled(w.countries.treasury[c.index] < loan.principal)
                }
                .font(.caption)
            }
            Text("Lenders who will deal with you").font(.caption.bold()).foregroundStyle(Palette.ink.opacity(0.6))
                .padding(.top, 4)
            if banks.isEmpty {
                Text("No bank will lend to you.").font(.caption).foregroundStyle(.red.opacity(0.8))
            }
            ForEach(banks, id: \.0.index) { entry in
                let bank = entry.0, rate = entry.1
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(w.finance.banks.name[bank.index]).font(.caption.bold())
                        Spacer()
                        Text(String(format: "%.1f%% a year · %.0f to lend", rate * 100, w.finance.banks.capital[bank.index]))
                            .font(.caption2).monospacedDigit()
                    }
                    HStack(spacing: 4) {
                        ForEach(Finance.loanSizes, id: \.self) { amount in
                            Button {
                                model.borrow(from: bank, amount: amount)
                            } label: {
                                Text("+\(Int(amount))")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Palette.ink.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(w.finance.banks.capital[bank.index] < amount)
                        }
                    }
                }
            }
        }
    }
}
