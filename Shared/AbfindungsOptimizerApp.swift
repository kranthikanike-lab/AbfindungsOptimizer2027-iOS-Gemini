import SwiftUI
import Charts
import UIKit

// MARK: - App Entry Point

@main
struct AbfindungsOptimizerApp: App {
    @StateObject private var engine = TaxEngineHost()

    var body: some Scene {
        WindowGroup {
            MainTabContainerView()
                .environmentObject(engine)
        }
    }
}

// MARK: - Formatting, Haptics & Helpers

private func eur(_ value: Double, showPlus: Bool = false) -> String {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.locale = Locale(identifier: "de_DE")
    nf.maximumFractionDigits = 0
    let absStr = nf.string(from: NSNumber(value: abs(value).rounded())) ?? "0"
    if value < -0.5 { return "-\(absStr) €" }
    if showPlus && value > 0.5 { return "+\(absStr) €" }
    return "\(absStr) €"
}

private func pct(_ value: Double) -> String {
    String(format: "%.1f %%", value).replacingOccurrences(of: ".", with: ",")
}

private func triggerLightHaptic() {
    let gen = UIImpactFeedbackGenerator(style: .light)
    gen.impactOccurred()
}

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Domain Models

enum PreExitGkvStatus: String, CaseIterable, Identifiable, Codable {
    case pflicht = "Pflichtversichert"
    case freiwillig = "Freiwillig GKV"
    case pkv = "Privat (PKV)"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pflicht: return "Pflicht GKV"
        case .freiwillig: return "Freiwillig GKV"
        case .pkv: return "Privat (PKV)"
        }
    }
}

enum PostAlg1GkvMode: String, CaseIterable, Identifiable, Codable {
    case mindestbeitrag = "Mindestbeitrag (~280 €/Mo)"
    case familienversicherung = "Familienvers. (0 €/Mo)"
    case individuell = "Individuell"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mindestbeitrag: return "Mindest ~280 €"
        case .familienversicherung: return "Familie 0 €"
        case .individuell: return "Individuell"
        }
    }
}

enum SolverMode: String, CaseIterable, Identifiable, Codable {
    case manual = "Manuell"
    case liquidity = "Liquidität"
    case optimal = "Optimal-Netto"
    case retirement = "Altersvorsorge"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .manual: return "slider.horizontal.3"
        case .liquidity: return "banknote.fill"
        case .optimal: return "sparkles"
        case .retirement: return "shield.lefthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .manual: return .blue
        case .liquidity: return .green
        case .optimal: return .purple
        case .retirement: return .teal
        }
    }

    var shortHint: String {
        switch self {
        case .manual:
            return "Freie Steuerung aller 4 Regler nach Ihren eigenen Vorgaben."
        case .liquidity:
            return "Rürup bis Cash-Plus Sweet-Spot; bAV, DRV & PV-IAB bleiben bei 0 €."
        case .optimal:
            return "bAV & Rürup voll ausgeschöpft + PV-IAB (§ 7g) für das Rest-Basiseinkommen."
        case .retirement:
            return "Maximiert bAV, Rürup & 30.000 € DRV V0210 — komplett ohne PV-IAB."
        }
    }
}

enum ChurchTaxOption: Double, CaseIterable, Identifiable, Codable {
    case none = 0.0
    case byBw = 0.08
    case other = 0.09
    var id: Double { rawValue }

    var shortLabel: String {
        switch self {
        case .none: return "0 %"
        case .byBw: return "8 % BY"
        case .other: return "9 %"
        }
    }
}

enum ChartStrategyFilter: String, CaseIterable, Identifiable {
    case both = "Beide"
    case standard = "Standard"
    case sprinter = "Sprinter"
    var id: String { rawValue }
}

struct PDFExportOptions {
    var includeReichweite: Bool = true
    var includeJobSwitch: Bool = true
}

struct SimulationInput: Codable, Equatable {
    // Section A: Basis & Severance
    var altesMonatsgehalt: Double = 7_500
    var fristMonate: Int = 5
    var bruttoAbfindung: Double = 150_000
    var agFiktivGehalt: Double = 0
    var payoutMonth2027: Int = 4
    var neuesGehalt2027: Double = 0
    var newJobStartMonth2027: Int = 0
    var newJobMonthlyGross: Double = 6_500
    var claimAlg1In2027: Bool = true

    // Family, Tax & GKV
    var isSplitting: Bool = false
    var partnerGehalt2027: Double = 0
    var kinderZahl: Double = 0.0
    var churchRate: Double = 0.0
    var kvZusatzbeitragPct: Double = 2.5
    var preExitGkv: PreExitGkvStatus = .pflicht

    // Sprinter Option
    var turboEnabled: Bool = false
    var turboFaktor: Double = 1.5
    var includeAlg1Loss: Bool = true

    // Section B: Tax Optimization Levers
    var taxOptimizationEnabled: Bool = false
    var solverMode: SolverMode = .manual
    var bavAmount: Double = 0
    var drvV0210Amount: Double = 0
    var ruerupAmount: Double = 0
    var pvIabPurchase: Double = 0

    // Section C: Reichweite (Runway)
    var monthlyExpenses: Double = 3_500
    var upfrontSpend2027: Double = 0
    var alg1ClaimMonths: Int = 12
    var postAlg1GkvMode: PostAlg1GkvMode = .mindestbeitrag
    var customPostGkvMonthly: Double = 280
    var realReturnPct: Double = 0.0
    var includeSalarySurplus: Bool = true

    // Section D: Job-Switch / Break-Even
    var switchNewAnnualGross: Double = 65_000
    var switchStartDelayMonths: Int = 3
    var switchAnnualGrowthPct: Double = 2.5

    var alg1SatzPct: Double { kinderZahl > 0 ? 67.0 : 60.0 }
}

struct WaterfallStep: Identifiable {
    let id = UUID()
    let label: String
    let start: Double
    let end: Double
    let delta: Double
    let isTotal: Bool
}

struct RunwayPhaseBar: Identifiable {
    let id = UUID()
    let strategy: String
    let phase: String
    let startMonth: Double
    let endMonth: Double
    let isLast: Bool
    let endDateLabel: String

    var duration: Double { max(0, endMonth - startMonth) }
}

struct DualSeriesPoint: Identifiable {
    let id = UUID()
    let x: Double
    let label: String
    let standardVal: Double
    let sprinterVal: Double

    var sharedPositive: Double {
        (standardVal > 0 && sprinterVal > 0) ? min(standardVal, sprinterVal) : 0
    }
    var sprinterAheadLow: Double { min(standardVal, sprinterVal) }
    var sprinterAheadHigh: Double { sprinterVal > standardVal ? sprinterVal : min(standardVal, sprinterVal) }
    var standardAheadLow: Double { min(standardVal, sprinterVal) }
    var standardAheadHigh: Double { standardVal > sprinterVal ? standardVal : min(standardVal, sprinterVal) }
}

struct SimulationResult {
    // 2027 Gross, ALG-1 (§ 32b) & Net Salary Breakdown
    var oldJobMonths2027: Int = 0
    var oldJobGross2027: Double = 0
    var newJobMonths2027: Int = 0
    var newJobGross2027: Double = 0
    var alg1Months2027: Int = 0
    var alg1Ersatzleistung2027: Double = 0
    var progressionRatePct2027: Double = 0
    var totalGross2027: Double = 0
    var netSalary2027: Double = 0
    var effectiveAgFiktiv: Double = 0
    var isAgFiktivAutoDefault: Bool = true

    // Core KPIs & Table 1 / 2 / 3 Fields
    var effectiveAbfindung: Double = 0
    var sprinterBonusGross: Double = 0
    var barBruttoVorSteuer: Double = 0
    var sofortNetto2027: Double = 0
    var upfrontPayrollTax: Double = 0
    var upfrontTaxRatePct: Double = 0
    var finanzamtRefundOct2028: Double = 0
    var optimalNettoTotal: Double = 0
    var totalTaxFinal: Double = 0
    var finalTaxRatePct: Double = 0
    var ruhensGkvTotal: Double = 0
    var kontoCashEnd2027: Double = 0
    var endLiquidity2028: Double = 0
    var kinderBenefitNet: Double = 0
    var kinderFreibetragWon: Bool = false

    // Effective Levers & Savings
    var solvedBav: Double = 0
    var solvedDrv: Double = 0
    var solvedRuerup: Double = 0
    var solvedPvPurchase: Double = 0

    var bavSavings: Double = 0
    var bavSavingsPct: Double = 0
    var bavMaxCapSavings: Double = 0
    var bavMaxCapPct: Double = 0

    var drvSavings: Double = 0
    var drvSavingsPct: Double = 0
    var ruerupSavings: Double = 0
    var ruerupSavingsPct: Double = 0
    var iabSavings: Double = 0
    var iabSavingsPct: Double = 0

    var ruerupMaxCap: Double = 32_308
    var ruerupCapRemaining: Double = 32_308
    var ruerupSweetSpot: Double = 0
    var iabSweetSpotPurchase: Double = 0
    var partnerSplittingBreakEvenMax: Double = 0
    var splittingAdvantageEur: Double = 0

    // Sprinter Waterfall
    var ruhenszeitMonths: Int = 0
    var sprinterNetGain: Double = 0
    var waterfallSteps: [WaterfallStep] = []

    // Section C: Reichweite
    var effectivePostGkvMonthly: Double = 280
    var standardRunwayMonths: Double = 0
    var sprinterRunwayMonths: Double = 0
    var standardDepletionDate: String = "–"
    var sprinterDepletionDate: String = "–"
    var standardAlg1EndDate: String = "–"
    var sprinterAlg1EndDate: String = "–"
    var standardBridgeSafe: Bool = true
    var sprinterBridgeSafe: Bool = true
    var runwayPhaseBars: [RunwayPhaseBar] = []
    var runwayCurve: [DualSeriesPoint] = []
    var faRefundMonthIndex: Double = 21

    // Section D: Job-Switch
    var breakEvenYearStandard: Double? = nil
    var breakEvenYearSprinter: Double? = nil
    var breakEvenDateStandard: String? = nil
    var breakEvenDateSprinter: String? = nil
    var switchCurve: [DualSeriesPoint] = []
    var switchDeltaYear5Std: Double = 0
    var switchDeltaYear5Spr: Double = 0
    var switchDeltaYear10Std: Double = 0
    var switchDeltaYear10Spr: Double = 0
}

// MARK: - 2027 Statutory German Tax, § 32b Progressionsvorbehalt, Solver & Runway Engine

final class TaxEngineHost: ObservableObject {
    private static let storageKey = "abfindungspilot_input_v27_2_2"

    @Published var input: SimulationInput {
        didSet {
            saveInput()
            recalculate()
        }
    }
    @Published private(set) var result = SimulationResult()

    // 2027 Statutory Constants
    private let b1Single: Double = 12_564
    private let b2Single: Double = 18_000
    private let b3Single: Double = 70_600
    private let b4Single: Double = 285_000
    private let solzFreigrenzeSingle: Double = 19_450
    private let anPauschbetrag: Double = 1_430
    private let bbgRvYear: Double = 106_200
    private let bbgKvYear: Double = 76_500
    let bavMaxTotal: Double = 50_976
    private let ruerupMaxSingle: Double = 32_308
    let pvIabMaxPurchase: Double = 400_000
    private let kfbPerChild2027: Double = 10_056
    private let kindergeldPerChild2027: Double = 3_204

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(SimulationInput.self, from: data) {
            self.input = decoded
        } else {
            self.input = SimulationInput()
        }
        recalculate()
    }

    private func saveInput() {
        if let data = try? JSONEncoder().encode(input) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: Presets & Quick Actions

    func applyPreset(_ preset: String) {
        triggerLightHaptic()
        if preset == "reset" {
            input = SimulationInput()
            return
        }
        var next = input
        switch preset {
        case "standard":
            next.turboEnabled = false
            next.newJobStartMonth2027 = 0
            next.neuesGehalt2027 = 0
            next.taxOptimizationEnabled = false
            next.solverMode = .manual
            next.bavAmount = 0
            next.drvV0210Amount = 0
            next.ruerupAmount = 0
            next.pvIabPurchase = 0
        case "sprinter":
            next.turboEnabled = true
            next.turboFaktor = 1.5
            next.newJobStartMonth2027 = 0
            next.neuesGehalt2027 = 0
            next.taxOptimizationEnabled = true
            next.solverMode = .manual
            next.bavAmount = 0
            next.drvV0210Amount = 0
            next.pvIabPurchase = 0
            let cap = computeRuerupCap(for: next)
            next.ruerupAmount = min(cap, 20_000)
        case "privatier":
            next.turboEnabled = true
            next.turboFaktor = 1.5
            next.newJobStartMonth2027 = 0
            next.neuesGehalt2027 = 0
            next.monthlyExpenses = 3_200
            next.taxOptimizationEnabled = true
            next.solverMode = .liquidity
            next.bavAmount = 0
            next.drvV0210Amount = 0
            next.pvIabPurchase = 0
        default:
            break
        }
        input = next
    }

    func setTaxOptimizationEnabled(_ enabled: Bool) {
        triggerLightHaptic()
        var next = input
        next.taxOptimizationEnabled = enabled
        if !enabled {
            next.solverMode = .manual
            next.bavAmount = 0
            next.drvV0210Amount = 0
            next.ruerupAmount = 0
            next.pvIabPurchase = 0
        }
        input = next
    }

    func updateManualLever(_ mutate: (inout SimulationInput) -> Void) {
        var next = input
        if next.solverMode != .manual {
            next.bavAmount = result.solvedBav
            next.drvV0210Amount = result.solvedDrv
            next.ruerupAmount = result.solvedRuerup
            next.pvIabPurchase = result.solvedPvPurchase
            next.solverMode = .manual
        }
        mutate(&next)
        input = next
    }

    func applyRuerupSweetSpot() {
        triggerLightHaptic()
        updateManualLever { next in
            next.taxOptimizationEnabled = true
            next.ruerupAmount = min(result.ruerupMaxCap, (result.ruerupSweetSpot / 500.0).rounded() * 500.0)
        }
    }

    func applyIabSweetSpot() {
        triggerLightHaptic()
        updateManualLever { next in
            next.taxOptimizationEnabled = true
            next.pvIabPurchase = min(pvIabMaxPurchase, (result.iabSweetSpotPurchase / 1_000.0).rounded() * 1_000.0)
        }
    }

    // MARK: Core § 32a / § 32b / § 34 / § 31 EStG Math

    private func calcSingleTariff2027(_ zve: Double) -> Double {
        let x = floor(max(0, zve))
        if x <= b1Single { return 0 }
        if x <= b2Single {
            let y = (x - b1Single) / 10_000.0
            return floor((919.8 * y + 1_400.0) * y)
        }
        if x <= b3Single {
            let z = (x - b2Single) / 10_000.0
            let yMax = (b2Single - b1Single) / 10_000.0
            let taxAtB2 = floor((919.8 * yMax + 1_400.0) * yMax)
            return floor((171.1 * z + 2_400.0) * z + taxAtB2)
        }
        if x <= b4Single {
            return floor(0.42 * x - 11_261.23)
        }
        return floor(0.45 * x - 19_811.23)
    }

    private func calcTariff2027(_ zve: Double, isSplitting: Bool) -> Double {
        isSplitting ? 2.0 * calcSingleTariff2027(zve / 2.0) : calcSingleTariff2027(zve)
    }

    private func calcProgressionTariff2027(zve: Double, progressionIncome: Double, isSplitting: Bool) -> Double {
        let cleanZve = max(0, zve)
        let prog = max(0, progressionIncome)
        guard prog > 0 else {
            return calcTariff2027(cleanZve, isSplitting: isSplitting)
        }
        let combined = cleanZve + prog
        guard combined > 0 else { return 0 }
        let taxOnCombined = calcTariff2027(combined, isSplitting: isSplitting)
        let specialRate = taxOnCombined / combined
        return floor(specialRate * cleanZve)
    }

    private func calcSolz2027(_ est: Double, isSplitting: Bool) -> Double {
        let fg = isSplitting ? solzFreigrenzeSingle * 2.0 : solzFreigrenzeSingle
        if est <= fg { return 0 }
        return min((est - fg) * 0.119, est * 0.055)
    }

    private func calcFuenftelESt(
        _ rawBaseZve: Double,
        abfindung: Double,
        progressionIncome: Double = 0,
        isSplitting: Bool
    ) -> Double {
        let abf = max(0, abfindung)
        let prog = max(0, progressionIncome)
        if rawBaseZve >= 0 {
            let baseEst = calcProgressionTariff2027(zve: rawBaseZve, progressionIncome: prog, isSplitting: isSplitting)
            let fifthEst = calcProgressionTariff2027(zve: rawBaseZve + abf / 5.0, progressionIncome: prog, isSplitting: isSplitting)
            return baseEst + max(0, 5.0 * (fifthEst - baseEst))
        } else {
            let combined = rawBaseZve + abf
            if combined <= 0 { return 0 }
            return 5.0 * calcProgressionTariff2027(zve: combined / 5.0, progressionIncome: prog / 5.0, isSplitting: isSplitting)
        }
    }

    private func calcTotalTaxWithKinder(
        rawBaseZve: Double,
        abfindung: Double,
        progressionIncome: Double = 0,
        isSplitting: Bool,
        churchRate: Double,
        kinderZahl: Double
    ) -> (totalTax: Double, estFinal: Double, soli: Double, church: Double, kinderNetGain: Double, kfbWon: Bool) {
        let estNoKfb = calcFuenftelESt(rawBaseZve, abfindung: abfindung, progressionIncome: progressionIncome, isSplitting: isSplitting)
        let kfbTotal = kinderZahl * kfbPerChild2027
        let kgTotal = kinderZahl * kindergeldPerChild2027

        let estWithKfb = kinderZahl > 0
            ? calcFuenftelESt(rawBaseZve - kfbTotal, abfindung: abfindung, progressionIncome: progressionIncome, isSplitting: isSplitting)
            : estNoKfb

        let estSaving = estNoKfb - estWithKfb
        let kfbWon = kinderZahl > 0 && (estSaving > kgTotal)
        let estEffective = kfbWon ? (estWithKfb + kgTotal) : estNoKfb

        let soli = calcSolz2027(estWithKfb, isSplitting: isSplitting)
        let church = estWithKfb * churchRate

        let soliNoKfb = calcSolz2027(estNoKfb, isSplitting: isSplitting)
        let churchNoKfb = estNoKfb * churchRate
        let kinderNetGain = (kfbWon ? (estSaving - kgTotal) : 0) + (soliNoKfb - soli) + (churchNoKfb - church)

        return (estEffective + soli + church, estEffective, soli, church, max(0, kinderNetGain), kfbWon)
    }

    private var useSplittingForPayroll: Bool {
        input.isSplitting && input.partnerGehalt2027 <= 0
    }

    private func effectiveAgFiktiv(for inp: SimulationInput, totalGross2027: Double) -> (amount: Double, isAuto: Bool) {
        if inp.agFiktivGehalt > 0 {
            return (inp.agFiktivGehalt, false)
        }
        let autoBase = max(inp.altesMonatsgehalt * 12.0, totalGross2027)
        let rounded = max(30_000, min(200_000, (autoBase / 2_500.0).rounded() * 2_500.0))
        return (rounded, true)
    }

    private func calcUpfrontPayrollTax(
        agFiktiv: Double,
        taxableAbfindung: Double,
        useSplittingPayroll: Bool,
        churchRate: Double,
        kinderZahl: Double
    ) -> Double {
        let abf = max(0, taxableAbfindung)
        if abf <= 0 { return 0 }
        let rvBase = min(agFiktiv, bbgRvYear)
        let kvBase = min(agFiktiv, bbgKvYear)
        let pvRate = pvEmployeeRate(kinderZahl: kinderZahl)
        let anSocial = rvBase * 0.093 + kvBase * (0.073 + input.kvZusatzbeitragPct / 200.0 + pvRate)
        let baseZve = max(0, agFiktiv - min(agFiktiv, anPauschbetrag) - anSocial)

        let baseEst = calcTariff2027(baseZve, isSplitting: useSplittingPayroll)
        let totalEst = calcTariff2027(baseZve + abf, isSplitting: useSplittingPayroll)
        let abfEst = max(0, totalEst - baseEst)

        let kfb = kinderZahl * kfbPerChild2027
        let baseEstKfb = calcTariff2027(max(0, baseZve - kfb), isSplitting: useSplittingPayroll)
        let totalEstKfb = calcTariff2027(max(0, baseZve + abf - kfb), isSplitting: useSplittingPayroll)

        let abfSoli = max(0, calcSolz2027(totalEstKfb, isSplitting: useSplittingPayroll) - calcSolz2027(baseEstKfb, isSplitting: useSplittingPayroll))
        let abfChurch = max(0, totalEstKfb - baseEstKfb) * churchRate
        return abfEst + abfSoli + abfChurch
    }

    private func pvEmployeeRate(kinderZahl: Double) -> Double {
        let kids = Int(ceil(kinderZahl))
        if kids == 0 { return 0.024 }
        if kids == 1 { return 0.018 }
        if kids == 2 { return 0.0155 }
        return 0.013
    }

    private func employeeSocialAndZve(gross: Double, kinderZahl: Double) -> (socialTotal: Double, deductibleSocial: Double, zve: Double) {
        if gross <= 0 { return (0, 0, 0) }
        let rv = min(gross, bbgRvYear) * 0.093
        let alv = min(gross, bbgRvYear) * 0.013
        let kv = min(gross, bbgKvYear) * (0.073 + input.kvZusatzbeitragPct / 200.0)
        let pv = min(gross, bbgKvYear) * pvEmployeeRate(kinderZahl: kinderZahl)
        let deductible = rv + kv + pv
        let zve = max(0, gross - min(gross, anPauschbetrag) - deductible)
        return (rv + alv + kv + pv, deductible, zve)
    }

    private func annualNetSalary(annualGross: Double, isSplitting: Bool, churchRate: Double, kinderZahl: Double) -> Double {
        if annualGross <= 0 { return 0 }
        let s = employeeSocialAndZve(gross: annualGross, kinderZahl: kinderZahl)
        let tax = calcTotalTaxWithKinder(rawBaseZve: s.zve, abfindung: 0, isSplitting: isSplitting, churchRate: churchRate, kinderZahl: kinderZahl).totalTax
        return max(0, annualGross - s.socialTotal - tax)
    }

    private func computeOldJobMonths2027(for inp: SimulationInput, sprinter: Bool) -> Int {
        let preExit = max(0, inp.payoutMonth2027 - 1)
        return sprinter ? preExit : min(12, preExit + inp.fristMonate)
    }

    private func compute2027Timeline(for inp: SimulationInput, sprinter: Bool) -> (
        oldMonths: Int,
        oldGross: Double,
        newMonths: Int,
        newGross: Double,
        alg1Months: Int,
        alg1Ersatz: Double
    ) {
        let oldMonths = computeOldJobMonths2027(for: inp, sprinter: sprinter)
        let oldGross = Double(oldMonths) * inp.altesMonatsgehalt

        let hasNewJob = inp.newJobStartMonth2027 >= 2 && inp.newJobStartMonth2027 <= 12
        let newMonths: Int
        let newGross: Double
        if hasNewJob {
            newMonths = max(0, 13 - inp.newJobStartMonth2027)
            newGross = Double(newMonths) * inp.newJobMonthlyGross
        } else {
            newMonths = 0
            newGross = max(0, inp.neuesGehalt2027)
        }

        let ruhensDuration = sprinter ? inp.fristMonate : 0
        let sperrDuration = (sprinter && inp.includeAlg1Loss) ? Int((12.0 / 4.333).rounded()) : 0
        let unpaidBlockEnd = oldMonths + ruhensDuration + sperrDuration

        var alg1Months = 0
        if inp.claimAlg1In2027 {
            for month in 1...12 {
                if month <= oldMonths { continue }
                if hasNewJob && month >= inp.newJobStartMonth2027 { continue }
                if month <= unpaidBlockEnd { continue }
                if alg1Months < inp.alg1ClaimMonths {
                    alg1Months += 1
                }
            }
        }

        let alg1Ersatz = Double(alg1Months) * monthlyAlg1Net()
        return (oldMonths, oldGross, newMonths, newGross, alg1Months, alg1Ersatz)
    }

    private func computeRuerupCap(for inp: SimulationInput) -> Double {
        let tl = compute2027Timeline(for: inp, sprinter: inp.turboEnabled)
        let totalGross = tl.oldGross + tl.newGross
        let ownRv = min(totalGross, bbgRvYear) * 0.186
        let partnerRv = inp.isSplitting ? min(inp.partnerGehalt2027, bbgRvYear) * 0.186 : 0
        let limit = inp.isSplitting ? ruerupMaxSingle * 2.0 : ruerupMaxSingle
        return max(0, limit - ownRv - partnerRv)
    }

    private func voluntaryGkvMonthly() -> Double {
        if input.preExitGkv == .pkv { return 900 }
        let monthlyBbgKv = bbgKvYear / 12.0
        let pvTotal = input.kinderZahl > 0 ? 0.036 : 0.042
        return monthlyBbgKv * (0.146 + input.kvZusatzbeitragPct / 100.0 + pvTotal)
    }

    private func currentPostAlg1GkvMonthly() -> Double {
        switch input.postAlg1GkvMode {
        case .mindestbeitrag: return 280
        case .familienversicherung: return 0
        case .individuell: return max(0, input.customPostGkvMonthly)
        }
    }

    private func monthlyAlg1Net() -> Double {
        let cappedAnnual = min(input.altesMonatsgehalt * 12.0, bbgRvYear)
        if cappedAnnual <= 0 { return 0 }
        let svFlat = cappedAnnual * 0.20
        let emp = employeeSocialAndZve(gross: cappedAnnual, kinderZahl: input.kinderZahl)
        let lst = calcTariff2027(emp.zve, isSplitting: useSplittingForPayroll)
        let soli = calcSolz2027(lst, isSplitting: useSplittingForPayroll)
        let leistungsentgeltYear = max(0, cappedAnnual - svFlat - lst - soli)
        return (leistungsentgeltYear / 12.0) * (input.alg1SatzPct / 100.0)
    }

    // MARK: Master Recalculation

    func recalculate() {
        var r = SimulationResult()
        r.effectivePostGkvMonthly = currentPostAlg1GkvMonthly()

        let tl = compute2027Timeline(for: input, sprinter: input.turboEnabled)
        let totalGross = tl.oldGross + tl.newGross
        r.oldJobMonths2027 = tl.oldMonths
        r.oldJobGross2027 = tl.oldGross
        r.newJobMonths2027 = tl.newMonths
        r.newJobGross2027 = tl.newGross
        r.alg1Months2027 = tl.alg1Months
        r.alg1Ersatzleistung2027 = tl.alg1Ersatz
        r.totalGross2027 = totalGross
        r.netSalary2027 = annualNetSalary(
            annualGross: totalGross,
            isSplitting: useSplittingForPayroll,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )

        let agFiktivInfo = effectiveAgFiktiv(for: input, totalGross2027: totalGross)
        r.effectiveAgFiktiv = agFiktivInfo.amount
        r.isAgFiktivAutoDefault = agFiktivInfo.isAuto

        let sprinterBonus = input.turboEnabled
            ? Double(input.fristMonate) * input.altesMonatsgehalt * input.turboFaktor
            : 0
        let effectiveAbf = input.bruttoAbfindung + sprinterBonus
        r.sprinterBonusGross = sprinterBonus
        r.effectiveAbfindung = effectiveAbf

        let emp = employeeSocialAndZve(gross: totalGross, kinderZahl: input.kinderZahl)
        let ruhensMonths = input.turboEnabled ? input.fristMonate : 0
        r.ruhenszeitMonths = ruhensMonths
        let billableGkvMonths = (input.preExitGkv == .pflicht) ? max(0, ruhensMonths - 1) : ruhensMonths
        let ruhensGkvTotal = Double(billableGkvMonths) * voluntaryGkvMonthly()
        r.ruhensGkvTotal = ruhensGkvTotal

        let partnerZve: Double = {
            guard input.isSplitting && input.partnerGehalt2027 > 0 else { return 0 }
            return employeeSocialAndZve(gross: input.partnerGehalt2027, kinderZahl: input.kinderZahl).zve
        }()

        let payrollBaseZve = emp.zve + partnerZve
        let rawBaseBeforeLevers = payrollBaseZve - ruhensGkvTotal

        let ruerupCap = computeRuerupCap(for: input)
        r.ruerupMaxCap = ruerupCap
        r.ruerupSweetSpot = min(ruerupCap, max(0, rawBaseBeforeLevers))

        var effBav = 0.0
        var effDrv = 0.0
        var effRuerup = 0.0
        var effPv = 0.0

        if input.taxOptimizationEnabled {
            switch input.solverMode {
            case .manual:
                effBav = min(input.bavAmount, min(bavMaxTotal, effectiveAbf))
                effDrv = min(input.drvV0210Amount, max(0, effectiveAbf - effBav))
                effRuerup = min(input.ruerupAmount, ruerupCap)
                effPv = min(input.pvIabPurchase, pvIabMaxPurchase)
            case .optimal:
                effBav = min(bavMaxTotal, effectiveAbf)
                effDrv = 0
                effRuerup = ruerupCap
                let remBase = max(0, rawBaseBeforeLevers - effRuerup)
                effPv = min(pvIabMaxPurchase, remBase * 2.0)
            case .liquidity:
                effBav = 0
                effDrv = 0
                effRuerup = min(ruerupCap, max(0, rawBaseBeforeLevers))
                effPv = 0
            case .retirement:
                effBav = min(bavMaxTotal, effectiveAbf)
                effDrv = min(30_000, max(0, effectiveAbf - effBav))
                effRuerup = ruerupCap
                effPv = 0
            }
        }

        r.solvedBav = effBav
        r.solvedDrv = effDrv
        r.solvedRuerup = effRuerup
        r.solvedPvPurchase = effPv
        r.ruerupCapRemaining = max(0, ruerupCap - effRuerup)
        r.iabSweetSpotPurchase = min(pvIabMaxPurchase, max(0, (rawBaseBeforeLevers - effRuerup) * 2.0))

        let barBrutto = max(0, effectiveAbf - effBav - effDrv)
        r.barBruttoVorSteuer = barBrutto
        let taxableAbfForPayroll = max(0, effectiveAbf - effBav - effDrv * 0.5)
        let upfrontTax = calcUpfrontPayrollTax(
            agFiktiv: r.effectiveAgFiktiv,
            taxableAbfindung: taxableAbfForPayroll,
            useSplittingPayroll: useSplittingForPayroll,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )
        r.upfrontPayrollTax = upfrontTax
        r.upfrontTaxRatePct = barBrutto > 0 ? (upfrontTax / barBrutto) * 100.0 : 0
        r.sofortNetto2027 = max(0, barBrutto - upfrontTax)

        let taxableAbfFinal = max(0, effectiveAbf - effBav - effDrv * 0.5)
        let rawBaseWithLevers = rawBaseBeforeLevers - effRuerup - (effPv * 0.5)

        let taxPaidOnBasePayroll = calcTotalTaxWithKinder(
            rawBaseZve: payrollBaseZve,
            abfindung: 0,
            progressionIncome: 0,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax

        let taxFinalObj = calcTotalTaxWithKinder(
            rawBaseZve: rawBaseWithLevers,
            abfindung: taxableAbfFinal,
            progressionIncome: r.alg1Ersatzleistung2027,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )

        let progDenom = max(1, max(0, rawBaseWithLevers) + r.alg1Ersatzleistung2027)
        let progTariff = calcTariff2027(max(0, rawBaseWithLevers) + r.alg1Ersatzleistung2027, isSplitting: input.isSplitting)
        r.progressionRatePct2027 = r.alg1Ersatzleistung2027 > 0 ? (progTariff / progDenom) * 100.0 : 0

        let abfTaxFinal = taxFinalObj.totalTax - taxPaidOnBasePayroll
        r.totalTaxFinal = abfTaxFinal
        r.finalTaxRatePct = effectiveAbf > 0 ? (abfTaxFinal / effectiveAbf) * 100.0 : 0
        r.kinderBenefitNet = taxFinalObj.kinderNetGain
        r.kinderFreibetragWon = taxFinalObj.kfbWon

        r.finanzamtRefundOct2028 = (taxPaidOnBasePayroll + upfrontTax) - taxFinalObj.totalTax
        r.optimalNettoTotal = effectiveAbf - abfTaxFinal

        r.kontoCashEnd2027 = r.sofortNetto2027 + r.netSalary2027 + r.alg1Ersatzleistung2027 - effRuerup - ruhensGkvTotal
        r.endLiquidity2028 = r.kontoCashEnd2027 + r.finanzamtRefundOct2028

        let upfrontNoBav = calcUpfrontPayrollTax(
            agFiktiv: r.effectiveAgFiktiv,
            taxableAbfindung: max(0, effectiveAbf - effDrv * 0.5),
            useSplittingPayroll: useSplittingForPayroll,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )
        let bavSav = max(0, upfrontNoBav - upfrontTax)
        r.bavSavings = bavSav
        r.bavSavingsPct = effBav > 0 ? (bavSav / effBav) * 100.0 : 0

        let maxBavCap = min(bavMaxTotal, effectiveAbf)
        let upfrontAtMaxBav = calcUpfrontPayrollTax(
            agFiktiv: r.effectiveAgFiktiv,
            taxableAbfindung: max(0, effectiveAbf - maxBavCap),
            useSplittingPayroll: useSplittingForPayroll,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )
        let upfrontAtZeroBav = calcUpfrontPayrollTax(
            agFiktiv: r.effectiveAgFiktiv,
            taxableAbfindung: effectiveAbf,
            useSplittingPayroll: useSplittingForPayroll,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )
        r.bavMaxCapSavings = max(0, upfrontAtZeroBav - upfrontAtMaxBav)
        r.bavMaxCapPct = maxBavCap > 0 ? (r.bavMaxCapSavings / maxBavCap) * 100.0 : 0

        let taxNoDrv = calcTotalTaxWithKinder(
            rawBaseZve: rawBaseWithLevers,
            abfindung: max(0, effectiveAbf - effBav),
            progressionIncome: r.alg1Ersatzleistung2027,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax
        r.drvSavings = max(0, taxNoDrv - taxFinalObj.totalTax)
        r.drvSavingsPct = effDrv > 0 ? (r.drvSavings / effDrv) * 100.0 : 0

        let taxNoRuerup = calcTotalTaxWithKinder(
            rawBaseZve: rawBaseWithLevers + effRuerup,
            abfindung: taxableAbfFinal,
            progressionIncome: r.alg1Ersatzleistung2027,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax
        r.ruerupSavings = max(0, taxNoRuerup - taxFinalObj.totalTax)
        r.ruerupSavingsPct = effRuerup > 0 ? (r.ruerupSavings / effRuerup) * 100.0 : 0

        let taxNoIab = calcTotalTaxWithKinder(
            rawBaseZve: rawBaseWithLevers + effPv * 0.5,
            abfindung: taxableAbfFinal,
            progressionIncome: r.alg1Ersatzleistung2027,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax
        r.iabSavings = max(0, taxNoIab - taxFinalObj.totalTax)
        r.iabSavingsPct = effPv > 0 ? (r.iabSavings / effPv) * 100.0 : 0

        let ownSingleRuerupCap = max(0, ruerupMaxSingle - min(totalGross, bbgRvYear) * 0.186)
        let ownSingleRuerup = min(effRuerup, ownSingleRuerupCap)
        let ownBaseWithLeversSingle = emp.zve - ruhensGkvTotal - ownSingleRuerup - effPv * 0.5
        let ownBaseWithLeversSplit = emp.zve - ruhensGkvTotal - effRuerup - effPv * 0.5

        r.partnerSplittingBreakEvenMax = findMaxPartnerGrossForSplitting(
            ownPayrollBaseZve: emp.zve,
            ownBaseWithLeversSingle: ownBaseWithLeversSingle,
            ownBaseWithLeversSplit: ownBaseWithLeversSplit,
            abfindung: taxableAbfFinal,
            progressionIncome: r.alg1Ersatzleistung2027
        )
        if input.isSplitting {
            let singleBaseTax = calcTotalTaxWithKinder(
                rawBaseZve: emp.zve,
                abfindung: 0,
                progressionIncome: r.alg1Ersatzleistung2027,
                isSplitting: false,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            ).totalTax
            let singleTotalTax = calcTotalTaxWithKinder(
                rawBaseZve: ownBaseWithLeversSingle,
                abfindung: taxableAbfFinal,
                progressionIncome: r.alg1Ersatzleistung2027,
                isSplitting: false,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            ).totalTax
            let abfTaxSingle = singleTotalTax - singleBaseTax
            r.splittingAdvantageEur = abfTaxSingle - abfTaxFinal
        } else {
            r.splittingAdvantageEur = 0
        }

        computeSprinterWaterfall(into: &r, partnerZve: partnerZve, effBav: effBav, effDrv: effDrv, effRuerup: effRuerup, effPv: effPv)
        computeReichweite(into: &r, partnerZve: partnerZve, effBav: effBav, effDrv: effDrv, effRuerup: effRuerup, effPv: effPv)
        computeJobSwitch(into: &r, partnerZve: partnerZve, effBav: effBav, effDrv: effDrv, effRuerup: effRuerup, effPv: effPv)

        self.result = r
    }

    private func computeSprinterWaterfall(
        into r: inout SimulationResult,
        partnerZve: Double,
        effBav: Double,
        effDrv: Double,
        effRuerup: Double,
        effPv: Double
    ) {
        let bonusGross = Double(input.fristMonate) * input.altesMonatsgehalt * input.turboFaktor
        let baseTaxableAbf = max(0, input.bruttoAbfindung - effBav - effDrv * 0.5)
        let fullTaxableAbf = max(0, input.bruttoAbfindung + bonusGross - effBav - effDrv * 0.5)

        let stdTl = compute2027Timeline(for: input, sprinter: false)
        let sprTl = compute2027Timeline(for: input, sprinter: true)

        let stdGross = stdTl.oldGross + stdTl.newGross
        let sprGross = sprTl.oldGross + sprTl.newGross

        let stdEmp = employeeSocialAndZve(gross: stdGross, kinderZahl: input.kinderZahl)
        let sprEmp = employeeSocialAndZve(gross: sprGross, kinderZahl: input.kinderZahl)

        let billableGkvMonths = (input.preExitGkv == .pflicht) ? max(0, input.fristMonate - 1) : input.fristMonate
        let gkvCost = Double(billableGkvMonths) * voluntaryGkvMonthly()

        let stdZveLevers = stdEmp.zve + partnerZve - effRuerup - effPv * 0.5
        let sprZveLevers = sprEmp.zve + partnerZve - gkvCost - effRuerup - effPv * 0.5

        let taxStdBase = calcTotalTaxWithKinder(rawBaseZve: stdZveLevers, abfindung: baseTaxableAbf, progressionIncome: stdTl.alg1Ersatz, isSplitting: input.isSplitting, churchRate: input.churchRate, kinderZahl: input.kinderZahl).totalTax
        let taxSprBase = calcTotalTaxWithKinder(rawBaseZve: sprZveLevers, abfindung: baseTaxableAbf, progressionIncome: sprTl.alg1Ersatz, isSplitting: input.isSplitting, churchRate: input.churchRate, kinderZahl: input.kinderZahl).totalTax
        let taxSprFull = calcTotalTaxWithKinder(rawBaseZve: sprZveLevers, abfindung: fullTaxableAbf, progressionIncome: sprTl.alg1Ersatz, isSplitting: input.isSplitting, churchRate: input.churchRate, kinderZahl: input.kinderZahl).totalTax

        let extraTaxOnBonus = max(0, taxSprFull - taxSprBase)
        let nettoPraemie = max(0, bonusGross - extraTaxOnBonus)

        let netSalStd = annualNetSalary(annualGross: stdGross, isSplitting: useSplittingForPayroll, churchRate: input.churchRate, kinderZahl: input.kinderZahl) + stdTl.alg1Ersatz
        let netSalSpr = annualNetSalary(annualGross: sprGross, isSplitting: useSplittingForPayroll, churchRate: input.churchRate, kinderZahl: input.kinderZahl) + sprTl.alg1Ersatz
        let lostNetSalary = max(0, netSalStd - netSalSpr)

        let wealthNoTurbo = (stdGross - stdEmp.socialTotal) + stdTl.alg1Ersatz + baseTaxableAbf - taxStdBase
        let wealthSprBase = (sprGross - sprEmp.socialTotal) + sprTl.alg1Ersatz + baseTaxableAbf - taxSprBase
        let fuenftelAdvantage = (wealthSprBase - wealthNoTurbo) + lostNetSalary

        let rvLoss = Double(input.fristMonate) * min(input.altesMonatsgehalt, bbgRvYear / 12.0) * 0.186
        let alg1Loss = input.includeAlg1Loss ? min(Double(input.fristMonate), 12.0 / 4.333) * monthlyAlg1Net() : 0

        var rawItems: [(String, Double)] = [
            ("+ Netto-Prämie", nettoPraemie),
            ("+ Fünftel-Hebel", fuenftelAdvantage),
            ("− Netto-Gehalt", -lostNetSalary),
            ("− GKV Ruhenszeit", -gkvCost),
            ("− RV-Punkte", -rvLoss)
        ]
        if input.includeAlg1Loss && alg1Loss > 0 {
            rawItems.append(("− ALG-1 Sperrzeit", -alg1Loss))
        }

        var cursor = 0.0
        var steps: [WaterfallStep] = []
        for (label, delta) in rawItems {
            let next = cursor + delta
            steps.append(WaterfallStep(label: label, start: min(cursor, next), end: max(cursor, next), delta: delta, isTotal: false))
            cursor = next
        }
        r.sprinterNetGain = cursor
        steps.append(WaterfallStep(label: "= Sprinter-Bilanz", start: min(0, cursor), end: max(0, cursor), delta: cursor, isTotal: true))
        r.waterfallSteps = steps
    }

    private func findMaxPartnerGrossForSplitting(
        ownPayrollBaseZve: Double,
        ownBaseWithLeversSingle: Double,
        ownBaseWithLeversSplit: Double,
        abfindung: Double,
        progressionIncome: Double
    ) -> Double {
        let singleBaseTax = calcTotalTaxWithKinder(
            rawBaseZve: ownPayrollBaseZve,
            abfindung: 0,
            progressionIncome: progressionIncome,
            isSplitting: false,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax
        let singleTotalTax = calcTotalTaxWithKinder(
            rawBaseZve: ownBaseWithLeversSingle,
            abfindung: abfindung,
            progressionIncome: progressionIncome,
            isSplitting: false,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax
        let abfTaxSingle = singleTotalTax - singleBaseTax

        let splitAtZeroBase = calcTotalTaxWithKinder(
            rawBaseZve: ownPayrollBaseZve,
            abfindung: 0,
            progressionIncome: progressionIncome,
            isSplitting: true,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax
        let splitAtZeroTotal = calcTotalTaxWithKinder(
            rawBaseZve: ownBaseWithLeversSplit,
            abfindung: abfindung,
            progressionIncome: progressionIncome,
            isSplitting: true,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax
        if (splitAtZeroTotal - splitAtZeroBase) >= abfTaxSingle - 1.0 {
            return 0
        }

        var lo = 0.0
        var hi = 250_000.0
        for _ in 0..<22 {
            let mid = (lo + hi) / 2.0
            let pZve = employeeSocialAndZve(gross: mid, kinderZahl: input.kinderZahl).zve
            let splitBaseTax = calcTotalTaxWithKinder(
                rawBaseZve: ownPayrollBaseZve + pZve,
                abfindung: 0,
                progressionIncome: progressionIncome,
                isSplitting: true,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            ).totalTax
            let splitTotalTax = calcTotalTaxWithKinder(
                rawBaseZve: ownBaseWithLeversSplit + pZve,
                abfindung: abfindung,
                progressionIncome: progressionIncome,
                isSplitting: true,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            ).totalTax
            let abfTaxSplit = splitTotalTax - splitBaseTax

            if abfTaxSplit < abfTaxSingle - 1.0 { lo = mid } else { hi = mid }
        }
        return (lo / 500.0).rounded() * 500.0
    }

    private func formatMonthOffset(_ monthsFromJan2027: Int) -> String {
        let names = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
        let total = max(0, monthsFromJan2027)
        let year = 2027 + total / 12
        let m = total % 12
        return "\(names[m]) \(year)"
    }

    private func computeReichweite(into r: inout SimulationResult, partnerZve: Double, effBav: Double, effDrv: Double, effRuerup: Double, effPv: Double) {
        let alg1 = monthlyAlg1Net()
        let postGkv = currentPostAlg1GkvMonthly()
        let netSalMonthly = annualNetSalary(
            annualGross: input.altesMonatsgehalt * 12.0,
            isSplitting: useSplittingForPayroll,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ) / 12.0
        let monthlyRate = input.realReturnPct / 100.0 / 12.0
        let startOffset = max(0, input.payoutMonth2027 - 1)
        let faOffset = 21 - startOffset
        r.faRefundMonthIndex = Double(max(1, faOffset))

        func simulateRunway(isSprinter: Bool) -> (months: Double, alg1End: Int, bridgeSafe: Bool, series: [Double], bars: [RunwayPhaseBar]) {
            let label = isSprinter ? "Sprinter" : "Standard"
            let abfGross = input.bruttoAbfindung + (isSprinter ? Double(input.fristMonate) * input.altesMonatsgehalt * input.turboFaktor : 0)
            let tl = compute2027Timeline(for: input, sprinter: isSprinter)
            let gross27 = tl.oldGross + tl.newGross
            let agFiktiv = effectiveAgFiktiv(for: input, totalGross2027: gross27).amount

            let taxPay = calcUpfrontPayrollTax(
                agFiktiv: agFiktiv,
                taxableAbfindung: max(0, abfGross - effBav - effDrv * 0.5),
                useSplittingPayroll: useSplittingForPayroll,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            )
            let sofort = max(0, abfGross - effBav - effDrv - taxPay)

            let emp27 = employeeSocialAndZve(gross: gross27, kinderZahl: input.kinderZahl)
            let ruhens = isSprinter ? input.fristMonate : 0
            let sperr = (isSprinter && input.includeAlg1Loss) ? Int((12.0 / 4.333).rounded()) : 0
            let billableGkv = (input.preExitGkv == .pflicht) ? max(0, ruhens - 1) : ruhens
            let ruhensGkv = Double(billableGkv) * voluntaryGkvMonthly()
            let payrollBase = emp27.zve + partnerZve
            let baseZve = payrollBase - ruhensGkv

            let baseTax = calcTotalTaxWithKinder(rawBaseZve: payrollBase, abfindung: 0, isSplitting: input.isSplitting, churchRate: input.churchRate, kinderZahl: input.kinderZahl).totalTax
            let finalTax = calcTotalTaxWithKinder(
                rawBaseZve: baseZve - effRuerup - effPv * 0.5,
                abfindung: max(0, abfGross - effBav - effDrv * 0.5),
                progressionIncome: tl.alg1Ersatz,
                isSplitting: input.isSplitting,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            ).totalTax
            let faSettlement = (baseTax + taxPay) - finalTax

            // Day-0 upfront spend deducted right at the beginning
            var cash = max(0, sofort - effRuerup - input.upfrontSpend2027)

            let noticePhase = isSprinter ? 0 : input.fristMonate
            let severanceBridgeMonths = netSalMonthly > 0 ? max(0, Int((cash / netSalMonthly).rounded(.down))) : 0
            let sprinterBridgeMonths: Int = {
                guard isSprinter else { return 0 }
                if sperr > 0 && severanceBridgeMonths < sperr {
                    return min(severanceBridgeMonths, sperr)
                }
                return input.fristMonate
            }()
            let alg1Dur = max(0, input.alg1ClaimMonths - sperr)

            var series: [Double] = [cash]
            var bridgeSafe = true
            var depletedMonth: Double = 72

            for m in 1...72 {
                if m == max(1, faOffset) { cash += faSettlement }

                if !isSprinter {
                    if m <= noticePhase {
                        if input.includeSalarySurplus { cash += max(0, netSalMonthly - input.monthlyExpenses) }
                    } else if m <= noticePhase + alg1Dur {
                        cash -= max(0, input.monthlyExpenses - alg1)
                    } else {
                        cash -= (input.monthlyExpenses + postGkv)
                    }
                } else {
                    if m <= sprinterBridgeMonths {
                        let gkvThisMonth = (input.preExitGkv == .pflicht && m == 1) ? 0 : voluntaryGkvMonthly()
                        cash -= max(0, input.monthlyExpenses - netSalMonthly + gkvThisMonth)
                    } else if m <= sprinterBridgeMonths + alg1Dur {
                        cash -= max(0, input.monthlyExpenses - alg1)
                    } else {
                        cash -= (input.monthlyExpenses + postGkv)
                    }
                }

                if cash > 0 { cash *= (1.0 + monthlyRate) }
                if m < max(1, faOffset) && cash < 0 { bridgeSafe = false }
                if cash <= 0 && depletedMonth == 72 { depletedMonth = Double(m) }
                series.append(max(0, cash))
            }

            let endLabel = depletedMonth >= 72 ? "> 6 J." : formatMonthOffset(startOffset + Int(depletedMonth))
            var rawSegments: [(String, Double, Double)] = []
            var cursor = 0.0

            if !isSprinter {
                if noticePhase > 0 {
                    let end = min(depletedMonth, cursor + Double(noticePhase))
                    rawSegments.append(("Gehalt/Frist", cursor, end))
                    cursor = end
                }
            } else if sprinterBridgeMonths > 0 {
                let end = min(depletedMonth, cursor + Double(sprinterBridgeMonths))
                rawSegments.append(("Ruhenszeit", cursor, end))
                cursor = end
            }

            if alg1Dur > 0 && cursor < depletedMonth {
                let end = min(depletedMonth, cursor + Double(alg1Dur))
                rawSegments.append(("ALG 1", cursor, end))
                cursor = end
            }
            if cursor < depletedMonth {
                rawSegments.append(("Privatier", cursor, depletedMonth))
            }

            let bars: [RunwayPhaseBar] = rawSegments.enumerated().map { idx, seg in
                RunwayPhaseBar(
                    strategy: label,
                    phase: seg.0,
                    startMonth: seg.1,
                    endMonth: seg.2,
                    isLast: idx == rawSegments.count - 1,
                    endDateLabel: endLabel
                )
            }

            let initialSpan = isSprinter ? sprinterBridgeMonths : noticePhase
            let alg1End = startOffset + initialSpan + alg1Dur
            return (depletedMonth, alg1End, bridgeSafe, series, bars)
        }

        let std = simulateRunway(isSprinter: false)
        let spr = simulateRunway(isSprinter: true)

        r.standardRunwayMonths = std.months
        r.sprinterRunwayMonths = spr.months
        r.standardDepletionDate = std.months >= 72 ? "> 6 Jahre" : formatMonthOffset(startOffset + Int(std.months))
        r.sprinterDepletionDate = spr.months >= 72 ? "> 6 Jahre" : formatMonthOffset(startOffset + Int(spr.months))
        r.standardAlg1EndDate = formatMonthOffset(std.alg1End)
        r.sprinterAlg1EndDate = formatMonthOffset(spr.alg1End)
        r.standardBridgeSafe = std.bridgeSafe
        r.sprinterBridgeSafe = spr.bridgeSafe
        r.runwayPhaseBars = std.bars + spr.bars

        let maxPlot = min(72, max(24, Int(max(std.months, spr.months)) + 4))
        var pts: [DualSeriesPoint] = []
        for m in 0...maxPlot {
            pts.append(DualSeriesPoint(
                x: Double(m),
                label: formatMonthOffset(startOffset + m),
                standardVal: std.series[m],
                sprinterVal: spr.series[m]
            ))
        }
        r.runwayCurve = pts
    }

    private func computeJobSwitch(into r: inout SimulationResult, partnerZve: Double, effBav: Double, effDrv: Double, effRuerup: Double, effPv: Double) {
        let oldAnnual = input.altesMonatsgehalt * 12.0
        let newAnnual = input.switchNewAnnualGross
        let growth = input.switchAnnualGrowthPct / 100.0
        let alg1 = monthlyAlg1Net()
        let startOffset = max(0, input.payoutMonth2027 - 1)

        func simulateSwitch(isSprinter: Bool) -> (curve: [Double], breakEvenYear: Double?) {
            let abfGross = input.bruttoAbfindung + (isSprinter ? Double(input.fristMonate) * input.altesMonatsgehalt * input.turboFaktor : 0)
            let tl = compute2027Timeline(for: input, sprinter: isSprinter)
            let gross27 = tl.oldGross + tl.newGross
            let agFiktiv = effectiveAgFiktiv(for: input, totalGross2027: gross27).amount

            let taxPay = calcUpfrontPayrollTax(
                agFiktiv: agFiktiv,
                taxableAbfindung: max(0, abfGross - effBav - effDrv * 0.5),
                useSplittingPayroll: useSplittingForPayroll,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            )
            let sofort = max(0, abfGross - effBav - effDrv - taxPay)
            let emp27 = employeeSocialAndZve(gross: gross27, kinderZahl: input.kinderZahl)
            let ruhens = isSprinter ? input.fristMonate : 0
            let billableGkv = (input.preExitGkv == .pflicht) ? max(0, ruhens - 1) : ruhens
            let ruhensGkv = Double(billableGkv) * voluntaryGkvMonthly()
            let payrollBase = emp27.zve + partnerZve
            let baseZve = payrollBase - ruhensGkv
            let baseTax = calcTotalTaxWithKinder(rawBaseZve: payrollBase, abfindung: 0, isSplitting: input.isSplitting, churchRate: input.churchRate, kinderZahl: input.kinderZahl).totalTax
            let finalTax = calcTotalTaxWithKinder(
                rawBaseZve: baseZve - effRuerup - effPv * 0.5,
                abfindung: max(0, abfGross - effBav - effDrv * 0.5),
                progressionIncome: tl.alg1Ersatz,
                isSplitting: input.isSplitting,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            ).totalTax
            let faSettlement = (baseTax + taxPay) - finalTax

            var delta = sofort - effRuerup - ruhensGkv
            var curve: [Double] = [delta]
            var breakEven: Double? = nil

            for yr in 1...15 {
                if yr == 2 { delta += faSettlement }
                let oldNetYr = annualNetSalary(annualGross: oldAnnual * pow(1.0 + growth, Double(yr - 1)), isSplitting: useSplittingForPayroll, churchRate: input.churchRate, kinderZahl: input.kinderZahl)
                let newNetYr = annualNetSalary(annualGross: newAnnual * pow(1.0 + growth, Double(yr - 1)), isSplitting: useSplittingForPayroll, churchRate: input.churchRate, kinderZahl: input.kinderZahl)

                var yearDiff = newNetYr - oldNetYr
                if yr == 1 && input.switchStartDelayMonths > 0 {
                    let gap = Double(min(12, input.switchStartDelayMonths))
                    let gapIncome = isSprinter ? 0 : alg1
                    yearDiff = ((12.0 - gap) / 12.0) * newNetYr + (gap * gapIncome) - oldNetYr
                }
                let prev = delta
                delta += yearDiff
                if breakEven == nil && prev >= 0 && delta < 0 {
                    let frac = prev / max(1, prev - delta)
                    breakEven = Double(yr - 1) + frac
                }
                curve.append(delta)
            }
            return (curve, breakEven)
        }

        let std = simulateSwitch(isSprinter: false)
        let spr = simulateSwitch(isSprinter: true)

        r.breakEvenYearStandard = std.breakEvenYear
        r.breakEvenYearSprinter = spr.breakEvenYear
        r.breakEvenDateStandard = std.breakEvenYear.map { formatMonthOffset(startOffset + Int(($0 * 12.0).rounded())) }
        r.breakEvenDateSprinter = spr.breakEvenYear.map { formatMonthOffset(startOffset + Int(($0 * 12.0).rounded())) }
        r.switchDeltaYear5Std = std.curve[5]
        r.switchDeltaYear5Spr = spr.curve[5]
        r.switchDeltaYear10Std = std.curve[10]
        r.switchDeltaYear10Spr = spr.curve[10]

        var pts: [DualSeriesPoint] = []
        for y in 0...15 {
            pts.append(DualSeriesPoint(
                x: Double(y),
                label: "Jahr \(y) (\(2027 + y))",
                standardVal: std.curve[y],
                sprinterVal: spr.curve[y]
            ))
        }
        r.switchCurve = pts
    }
}

// MARK: - Root 5-Tab Navigation Container & Settings / Multi-Page PDF Exporter

struct MainTabContainerView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @AppStorage("abfindungs_theme") private var themeMode: String = "dark"
    @State private var selectedTab: Int = 0
    @State private var selectedInfoTopic: StatutoryTopic?
    @State private var showSettingsSheet: Bool = false
    @State private var pdfOptions = PDFExportOptions()
    @State private var pdfShareItem: IdentifiableURL?

    private var resolvedColorScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                InputsTabView(selectedInfoTopic: $selectedInfoTopic)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("AbfindungsPilot")
                                .font(.headline.weight(.bold))
                                .lineLimit(1)
                        }
                        sharedToolbar
                    }
            }
            .tabItem { Label("Eingaben", systemImage: "slider.horizontal.3") }
            .tag(0)

            NavigationStack {
                TaxOptimizationTabView(selectedInfoTopic: $selectedInfoTopic)
                    .navigationTitle("Steuer-Hebel")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { sharedToolbar }
            }
            .tabItem { Label("Steuer", systemImage: "wand.and.stars") }
            .tag(1)

            NavigationStack {
                ResultsTabView(
                    selectedInfoTopic: $selectedInfoTopic,
                    onOpenPDFOptions: { showSettingsSheet = true }
                )
                .navigationTitle("Ergebnis 2027")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { sharedToolbar }
            }
            .tabItem { Label("Ergebnis", systemImage: "chart.pie.fill") }
            .tag(2)

            NavigationStack {
                ReichweiteTabView(selectedInfoTopic: $selectedInfoTopic)
                    .navigationTitle("Reichweite")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { sharedToolbar }
            }
            .tabItem { Label("Reichweite", systemImage: "hourglass") }
            .tag(3)

            NavigationStack {
                JobSwitchTabView(selectedInfoTopic: $selectedInfoTopic)
                    .navigationTitle("Job-Switch")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { sharedToolbar }
            }
            .tabItem { Label("Switch", systemImage: "arrow.left.arrow.right") }
            .tag(4)
        }
        .preferredColorScheme(resolvedColorScheme)
        .sheet(item: $selectedInfoTopic) { topic in
            StatutoryInfoSheetView(topic: topic)
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsAndPDFSheetView(
                selectedTab: selectedTab,
                themeMode: $themeMode,
                pdfOptions: $pdfOptions,
                onOpenRecht2027: {
                    showSettingsSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        selectedInfoTopic = .recht2027
                    }
                },
                onExportPDF: { opts in
                    pdfOptions = opts
                    showSettingsSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        generateMultiPagePDFReport(options: opts)
                    }
                }
            )
        }
        .sheet(item: $pdfShareItem) { item in
            ShareSheet(items: [item.url])
        }
    }

    @ToolbarContentBuilder
    private var sharedToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                selectedInfoTopic = .recht2027
            } label: {
                Label("Recht 2027", systemImage: "scale.3d")
                    .font(.caption.weight(.semibold))
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                themeMode = (themeMode == "dark") ? "light" : "dark"
            } label: {
                Image(systemName: themeMode == "dark" ? "sun.max.fill" : "moon.fill")
                    .foregroundStyle(themeMode == "dark" ? .yellow : .indigo)
            }
            Button {
                showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }

    private func generateMultiPagePDFReport(options: PDFExportOptions) {
        triggerLightHaptic()
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AbfindungsPilot_2027_v27_2_1_Report.pdf")
        let inp = engine.input
        let res = engine.result

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 17),
            .foregroundColor: UIColor.label
        ]
        let sectionAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.systemBlue
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.5),
            .foregroundColor: UIColor.darkGray
        ]
        let footAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 8.5),
            .foregroundColor: UIColor.gray
        ]

        func drawHeader(pageTitle: String, pageNum: Int) {
            "AbfindungsPilot 2027 (v27.2.1) – \(pageTitle)".draw(at: CGPoint(x: 36, y: 32), withAttributes: titleAttrs)
            "Seite \(pageNum)".draw(at: CGPoint(x: 520, y: 36), withAttributes: footAttrs)
        }

        func drawFooter() {
            let disclaimer = "Hinweis (§ 2 StBerG): Unverbindliche mathematische Modellrechnung auf Basis der Rechengrößen 2027 (inkl. § 32b & § 34 EStG). Keine Steuer- oder Rechtsberatung."
            disclaimer.draw(in: CGRect(x: 36, y: 792, width: 523, height: 32), withAttributes: footAttrs)
        }

        var pageCounter = 0

        do {
            try renderer.writePDF(to: url) { ctx in
                pageCounter += 1
                ctx.beginPage()
                drawHeader(pageTitle: "1. Eingaben & 2027-Zeitstrahl", pageNum: pageCounter)
                "Basisdaten & Abfindung".draw(at: CGPoint(x: 36, y: 68), withAttributes: sectionAttrs)
                let p1a = """
                • Abfindung Brutto: \(eur(inp.bruttoAbfindung))  |  Sprinter: \(inp.turboEnabled ? "Aktiv (\(String(format: "%.1fx", inp.turboFaktor)))" : "Aus")
                • Altes Monatsbrutto: \(eur(inp.altesMonatsgehalt))  |  Austritt: Monat \(inp.payoutMonth2027)/2027  |  Kündigungsfrist: \(inp.fristMonate) Mon.
                • AG-Fiktivgehalt (LSt): \(eur(res.effectiveAgFiktiv)) (\(res.isAgFiktivAutoDefault ? "Auto-Default" : "Manuell"))
                """
                p1a.draw(in: CGRect(x: 36, y: 88, width: 523, height: 75), withAttributes: bodyAttrs)

                "2027 Einkommen, Neu-Job & ALG-1 (§ 32b Progressionsvorbehalt)".draw(at: CGPoint(x: 36, y: 175), withAttributes: sectionAttrs)
                let newJobInfo = inp.newJobStartMonth2027 >= 2
                    ? "Start Monat \(inp.newJobStartMonth2027)/2027 mit \(eur(inp.newJobMonthlyGross))/Mo (\(res.newJobMonths2027) Mon. = \(eur(res.newJobGross2027)))"
                    : "Kein Neu-Job-Startmonat (Zusätzl. 2027: \(eur(res.newJobGross2027)))"
                let p1b = """
                • Alt-AG 2027: \(res.oldJobMonths2027) Mon. = \(eur(res.oldJobGross2027))
                • Neu-Job 2027: \(newJobInfo)
                • ALG-1 in 2027 (§ 32b): \(res.alg1Months2027) Mon. = \(eur(res.alg1Ersatzleistung2027)) (steuerfrei, besonderer Steuersatz \(pct(res.progressionRatePct2027)))
                • Summe 2027 Brutto: \(eur(res.totalGross2027))  |  Netto-Gehalt 2027: \(eur(res.netSalary2027))
                """
                p1b.draw(in: CGRect(x: 36, y: 195, width: 523, height: 105), withAttributes: bodyAttrs)

                "Familie, Steuertarif & Krankenversicherung".draw(at: CGPoint(x: 36, y: 312), withAttributes: sectionAttrs)
                let p1c = """
                • Tarif: \(inp.isSplitting ? "Splittingtarif" : "Grundtarif")  |  Partner-Gehalt 2027: \(eur(inp.partnerGehalt2027))
                • Kinderfreibeträge: \(String(format: "%.1f", inp.kinderZahl))  |  Kirchensteuer: \(pct(inp.churchRate * 100))
                • GKV vor Austritt: \(inp.preExitGkv.displayName)  |  KV-Zusatzbeitrag: \(pct(inp.kvZusatzbeitragPct))
                """
                p1c.draw(in: CGRect(x: 36, y: 332, width: 523, height: 80), withAttributes: bodyAttrs)
                drawFooter()

                pageCounter += 1
                ctx.beginPage()
                drawHeader(pageTitle: "2. Steuer-Optimierung", pageNum: pageCounter)
                "Modus & Steuer-Hebel".draw(at: CGPoint(x: 36, y: 68), withAttributes: sectionAttrs)
                let p2a = """
                • Optimierung aktiv: \(inp.taxOptimizationEnabled ? "Ja (Modus: \(inp.solverMode.rawValue))" : "Nein (alle Hebel 0 €)")
                • Rürup-Maximalrahmen (§ 10 Abs. 3): \(eur(res.ruerupMaxCap))  |  Rest: \(eur(res.ruerupCapRemaining))  |  Sweet-Spot: \(eur(res.ruerupSweetSpot))
                • IAB Sweet-Spot (zvE → 0 €): \(eur(res.iabSweetSpotPurchase)) Kaufpreis (50 % Abzug)
                """
                p2a.draw(in: CGRect(x: 36, y: 88, width: 523, height: 80), withAttributes: bodyAttrs)

                "Einzelwirkung der 4 Hebel".draw(at: CGPoint(x: 36, y: 180), withAttributes: sectionAttrs)
                let p2b = """
                • 1. bAV-Umwandlung (§ 3 Nr. 63): \(eur(res.solvedBav))  →  Sofort-Ersparnis 2027: \(eur(res.bavSavings, showPlus: true)) (\(pct(res.bavSavingsPct)))
                • 2. Rürup / Basisrente (§ 10): \(eur(res.solvedRuerup))  →  Steuer-Ersparnis: \(eur(res.ruerupSavings, showPlus: true)) (\(pct(res.ruerupSavingsPct)))
                • 3. DRV-Ausgleich (V0210): \(eur(res.solvedDrv))  →  Steuer-Ersparnis: \(eur(res.drvSavings, showPlus: true)) (\(pct(res.drvSavingsPct)))
                • 4. PV-Investition (50 % IAB § 7g): \(eur(res.solvedPvPurchase))  →  Steuer-Ersparnis: \(eur(res.iabSavings, showPlus: true)) (\(pct(res.iabSavingsPct))) · 0 € Cash 2027
                """
                p2b.draw(in: CGRect(x: 36, y: 200, width: 523, height: 110), withAttributes: bodyAttrs)
                drawFooter()

                pageCounter += 1
                ctx.beginPage()
                drawHeader(pageTitle: "3. Vollständiges Ergebnis 2027/2028", pageNum: pageCounter)
                "1. Sofort-Abrechnung AG (2027)".draw(at: CGPoint(x: 36, y: 68), withAttributes: sectionAttrs)
                let t1 = """
                • Effektive Abfindung Brutto: \(eur(res.effectiveAbfindung))  |  Bar-Brutto vor Steuer: \(eur(res.barBruttoVorSteuer))
                • AG Lohnsteuer-Einbehalt (\(pct(res.upfrontTaxRatePct))): \(eur(-res.upfrontPayrollTax))  →  Sofort-Netto 2027: \(eur(res.sofortNetto2027))
                """
                t1.draw(in: CGRect(x: 36, y: 88, width: 523, height: 60), withAttributes: bodyAttrs)

                "2. Endabrechnung Finanzamt (2028, inkl. § 34 & § 32b)".draw(at: CGPoint(x: 36, y: 158), withAttributes: sectionAttrs)
                let t2 = """
                • Endgültige Abfindungssteuer (\(pct(res.finalTaxRatePct))): \(eur(-res.totalTaxFinal))  |  Optimal-Netto Gesamt: \(eur(res.optimalNettoTotal))
                • FA-Erstattung / Saldo Okt. 2028: \(eur(res.finanzamtRefundOct2028, showPlus: true))
                """
                t2.draw(in: CGRect(x: 36, y: 178, width: 523, height: 60), withAttributes: bodyAttrs)

                "3. Harter Liquiditäts-Zeitstrahl".draw(at: CGPoint(x: 36, y: 248), withAttributes: sectionAttrs)
                let t3 = """
                • Sofort-Netto \(eur(res.sofortNetto2027)) + Netto-Gehalt \(eur(res.netSalary2027)) + ALG-1 2027 \(eur(res.alg1Ersatzleistung2027)) − Rürup \(eur(res.solvedRuerup)) − GKV Ruhenszeit \(eur(res.ruhensGkvTotal))
                • KONTO-CASH am 31.12.2027: \(eur(res.kontoCashEnd2027))  |  BAR-LIQUIDITÄT Ende 2028: \(eur(res.endLiquidity2028))
                """
                t3.draw(in: CGRect(x: 36, y: 268, width: 523, height: 75), withAttributes: bodyAttrs)
                drawFooter()

                if options.includeReichweite {
                    pageCounter += 1
                    ctx.beginPage()
                    drawHeader(pageTitle: "4. Reichweite & Cash-Burn", pageNum: pageCounter)
                    let p4 = """
                    • Monatl. Netto-Ausgaben: \(eur(inp.monthlyExpenses))  |  Einmal-Abfluss 2027: \(eur(inp.upfrontSpend2027))  |  ALG-1 Anspruch: \(inp.alg1ClaimMonths) Mon. (\(Int(inp.alg1SatzPct)) %)
                    • GKV nach ALG 1: \(eur(res.effectivePostGkvMonthly))/Mo  |  Real-Zins / Inflation p.a.: \(pct(inp.realReturnPct))
                    • Standard (Frist): \(String(format: "%.0f", res.standardRunwayMonths)) Mon. (bis \(res.standardDepletionDate)) · Brücke Okt. 28: \(res.standardBridgeSafe ? "Sicher" : "Engpass")
                    • Sprinter (Sofort): \(String(format: "%.0f", res.sprinterRunwayMonths)) Mon. (bis \(res.sprinterDepletionDate)) · Brücke Okt. 28: \(res.sprinterBridgeSafe ? "Sicher" : "Engpass")
                    """
                    p4.draw(in: CGRect(x: 36, y: 74, width: 523, height: 125), withAttributes: bodyAttrs)
                    drawFooter()
                }

                if options.includeJobSwitch {
                    pageCounter += 1
                    ctx.beginPage()
                    drawHeader(pageTitle: "5. Job-Switch & Break-Even", pageNum: pageCounter)
                    let stdBe = res.breakEvenYearStandard.map { y in
                        let yrs = String(format: "%.1f Jahre", y)
                        return res.breakEvenDateStandard.map { "\(yrs) (\($0))" } ?? yrs
                    } ?? "> 15 Jahre"
                    let sprBe = res.breakEvenYearSprinter.map { y in
                        let yrs = String(format: "%.1f Jahre", y)
                        return res.breakEvenDateSprinter.map { "\(yrs) (\($0))" } ?? yrs
                    } ?? "> 15 Jahre"
                    let p5 = """
                    • Neues Jahresbrutto: \(eur(inp.switchNewAnnualGross))  |  Pause: \(inp.switchStartDelayMonths) Mon.  |  Wachstum p.a.: \(pct(inp.switchAnnualGrowthPct))
                    • Break-Even: Standard \(stdBe)  |  Sprinter \(sprBe)
                    • Nach 5 Jahren: Standard \(eur(res.switchDeltaYear5Std, showPlus: true))  |  Sprinter \(eur(res.switchDeltaYear5Spr, showPlus: true))
                    • Nach 10 Jahren: Standard \(eur(res.switchDeltaYear10Std, showPlus: true))  |  Sprinter \(eur(res.switchDeltaYear10Spr, showPlus: true))
                    """
                    p5.draw(in: CGRect(x: 36, y: 74, width: 523, height: 120), withAttributes: bodyAttrs)
                    drawFooter()
                }
            }
            self.pdfShareItem = IdentifiableURL(url: url)
        } catch {
            print("PDF export error: \(error)")
        }
    }
}

// MARK: - Settings & Multi-Page PDF Sheet

struct SettingsAndPDFSheetView: View {
    let selectedTab: Int
    @Binding var themeMode: String
    @Binding var pdfOptions: PDFExportOptions
    let onOpenRecht2027: () -> Void
    let onExportPDF: (PDFExportOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftOptions: PDFExportOptions

    init(
        selectedTab: Int,
        themeMode: Binding<String>,
        pdfOptions: Binding<PDFExportOptions>,
        onOpenRecht2027: @escaping () -> Void,
        onExportPDF: @escaping (PDFExportOptions) -> Void
    ) {
        self.selectedTab = selectedTab
        self._themeMode = themeMode
        self._pdfOptions = pdfOptions
        self.onOpenRecht2027 = onOpenRecht2027
        self.onExportPDF = onExportPDF
        self._draftOptions = State(initialValue: pdfOptions.wrappedValue)
    }

    private var activeTabGuide: (title: String, summary: String) {
        switch selectedTab {
        case 0:
            return ("Eingaben & § 32b Zeitstrahl", "Starten Sie mit Abfindung, Gehalt, Austritt und Frist. Wählen Sie bei Bedarf den Neu-Job-Startmonat in 2027 — Lückenmonate mit ALG 1 werden automatisch im § 32b Progressionsvorbehalt berücksichtigt.")
        case 1:
            return ("Steuer-Hebel", "Steuern Sie bAV, Rürup, DRV V0210 und PV-IAB manuell oder per Modus-Vorgabe.")
        case 2:
            return ("Ergebnis 2027 / 2028", "Zeigt AG-Einbehalt, § 34 Fünftelregelung, § 32b Wirkung, die FA-Erstattung im Oktober 2028 und den Liquiditäts-Zeitstrahl.")
        case 3:
            return ("Reichweite / Cash-Burn", "Simuliert Ihre Liquiditätsreichweite ohne Job inklusive Puffer-/Mindestzeitlogik, 9M ALG 1, GKV und Oktober-2028-Brücke.")
        default:
            return ("Job-Switch", "Vergleicht den Vermögensverlauf bei Gehaltswechsel inklusive Startpause und Break-Even-Punkt.")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Aktuelle Ansicht · Leitfaden") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeTabGuide.title)
                            .font(.subheadline.weight(.semibold))
                        Text(activeTabGuide.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Section("A4 PDF-Report (Mehrseitig · v27.2.1)") {
                    Text("Seiten 1–3 (Eingaben, Steuer, Ergebnis) sind immer enthalten:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Seite 4: Reichweite / Cash-Burn einfügen", isOn: $draftOptions.includeReichweite)
                    Toggle("Seite 5: Job-Switch einfügen", isOn: $draftOptions.includeJobSwitch)
                    Button {
                        onExportPDF(draftOptions)
                    } label: {
                        Label("PDF-Report erstellen & teilen", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                Section("Darstellung & Recht 2027") {
                    Picker("Design", selection: $themeMode) {
                        Text("Dunkel").tag("dark")
                        Text("Hell").tag("light")
                        Text("System").tag("system")
                    }
                    .pickerStyle(.segmented)

                    Button {
                        onOpenRecht2027()
                    } label: {
                        Label("Recht 2027 & Rechengrößen anzeigen", systemImage: "scale.3d")
                    }
                }

                Section("Rechtlicher Hinweis (§ 2 StBerG)") {
                    Text("Unverbindliche Modellrechnung auf Basis der gesetzlichen Parameter 2027. Keine Steuer- oder Rechtsberatung.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen & Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Sticky Bottom KPI Bar

struct StickyKPIBar: View {
    @EnvironmentObject var engine: TaxEngineHost

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                kpiCol(title: "Sofort 2027", value: eur(engine.result.sofortNetto2027), color: .orange)
                Divider().frame(height: 26)
                kpiCol(title: "FA Okt. 2028", value: eur(engine.result.finanzamtRefundOct2028, showPlus: true), color: engine.result.finanzamtRefundOct2028 >= 0 ? .green : .red)
                Divider().frame(height: 26)
                kpiCol(title: "Optimal-Netto", value: eur(engine.result.optimalNettoTotal), color: .blue)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
        }
    }

    private func kpiCol(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.callout.bold())
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Reusable Compact Slider Row

struct CompactSliderRow: View {
    let title: String
    var subtitle: String? = nil
    var topic: StatutoryTopic? = nil
    @Binding var selectedInfoTopic: StatutoryTopic?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var valueFormatter: (Double) -> String = { eur($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if let topic {
                            InfoIconButton(topic: topic, selectedTopic: $selectedInfoTopic)
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                Text(valueFormatter(value))
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Tab 1: Eingaben (Single-Line Pickers, Smart Defaults & § 32b Timeline)

struct InputsTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var selectedInfoTopic: StatutoryTopic?

    private let kinderOptions: [Double] = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
    private let monthNames = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 6) {
                    presetBtn("Standard", icon: "doc.text", key: "standard", tint: .blue)
                    presetBtn("Sprinter", icon: "bolt.fill", key: "sprinter", tint: .orange)
                    presetBtn("Privatier", icon: "sun.horizon.fill", key: "privatier", tint: .green)
                    Button {
                        engine.applyPreset("reset")
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.weight(.bold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.secondary.opacity(0.14))
                            .foregroundStyle(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Zurücksetzen")
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
            } header: {
                Text("Schnell-Szenarien (ohne PV-IAB)").font(.caption.weight(.semibold))
            }

            Section {
                CompactSliderRow(
                    title: "Abfindung Brutto",
                    selectedInfoTopic: $selectedInfoTopic,
                    value: $engine.input.bruttoAbfindung,
                    range: 10_000...400_000,
                    step: 5_000
                )

                CompactSliderRow(
                    title: "Altes Monatsbrutto",
                    selectedInfoTopic: $selectedInfoTopic,
                    value: $engine.input.altesMonatsgehalt,
                    range: 3_000...20_000,
                    step: 250
                )

                HStack(spacing: 8) {
                    Text("Austrittsmonat 2027")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Picker("", selection: $engine.input.payoutMonth2027) {
                        ForEach(1...12, id: \.self) { m in
                            Text("\(monthNames[m - 1]) 2027").tag(m)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .lineLimit(1)
                }

                Stepper(value: $engine.input.fristMonate, in: 1...12) {
                    HStack {
                        Text("Kündigungsfrist")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text("\(engine.input.fristMonate) Mon.")
                            .font(.subheadline.bold())
                            .monospacedDigit()
                    }
                }

                HStack(spacing: 8) {
                    Text("Neuer Job in 2027")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Picker("", selection: $engine.input.newJobStartMonth2027) {
                        Text("Kein Neu-Job").tag(0)
                        ForEach(2...12, id: \.self) { m in
                            Text("Ab \(monthNames[m - 1]) 2027").tag(m)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .lineLimit(1)
                }

                if engine.input.newJobStartMonth2027 >= 2 {
                    CompactSliderRow(
                        title: "Neues Monatsbrutto",
                        subtitle: "\(engine.result.newJobMonths2027) Mon. in 2027 = \(eur(engine.result.newJobGross2027))",
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.newJobMonthlyGross,
                        range: 2_000...20_000,
                        step: 250
                    )
                } else {
                    CompactSliderRow(
                        title: "Zusätzl. Gehalt 2027 (Neu-Job)",
                        subtitle: "Nur zusätzliches Brutto aus neuem Job in 2027",
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.neuesGehalt2027,
                        range: 0...150_000,
                        step: 2_500
                    )
                }

                Toggle(isOn: $engine.input.claimAlg1In2027) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("ALG-1 in 2027 beziehen (§ 32b)")
                            .font(.subheadline.weight(.medium))
                        Text(engine.result.alg1Months2027 > 0
                             ? "\(engine.result.alg1Months2027) Lücken-Mon. = \(eur(engine.result.alg1Ersatzleistung2027)) (Progressionsvorbehalt)"
                             : "Keine anrechenbaren Lücken-Monate in 2027")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    let newJobSummary = engine.input.newJobStartMonth2027 >= 2
                        ? "\(eur(engine.result.newJobGross2027)) Neu-Job (\(engine.result.newJobMonths2027) M.)"
                        : "\(eur(engine.result.newJobGross2027)) Zusätzl. 2027"
                    Text("2027: \(eur(engine.result.oldJobGross2027)) Alt-AG (\(engine.result.oldJobMonths2027) M.) + \(newJobSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if engine.result.alg1Months2027 > 0 {
                        Text("ALG 1: \(engine.result.alg1Months2027) M. = \(eur(engine.result.alg1Ersatzleistung2027)) · Progression \(pct(engine.result.progressionRatePct2027)) (§ 32b)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.cyan)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("A · Basisdaten, Neu-Job & ALG-1 (§ 32b)").font(.caption.weight(.semibold))
            }

            Section {
                HStack(spacing: 8) {
                    Text("Steuertarif")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    InfoIconButton(topic: .tarifSplitting, selectedTopic: $selectedInfoTopic)
                    Spacer(minLength: 6)
                    Picker("", selection: $engine.input.isSplitting) {
                        Text("Grundtarif").tag(false)
                        Text("Splitting").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 175)
                }

                if engine.input.isSplitting {
                    CompactSliderRow(
                        title: "Gehalt Partner/in 2027",
                        subtitle: engine.result.partnerSplittingBreakEvenMax > 0
                            ? "Abfindungs-Vorteil bis ca. \(eur(engine.result.partnerSplittingBreakEvenMax))"
                            : "Kein Abfindungs-Vorteil durch Splitting",
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.partnerGehalt2027,
                        range: 0...150_000,
                        step: 2_500
                    )

                    let adv = engine.result.splittingAdvantageEur
                    let bannerColor: Color = adv > 1 ? .green : (adv < -1 ? .red : .secondary)
                    let bannerIcon = adv > 1 ? "checkmark.circle.fill" : (adv < -1 ? "exclamationmark.triangle.fill" : "equal.circle.fill")
                    let bannerText: String = {
                        if adv > 1 {
                            return "Abfindungs-Vorteil: \(eur(adv, showPlus: true)) gegenüber Grundtarif"
                        } else if adv < -1 {
                            return "Fünftel-Falle (Abfindung): \(eur(adv)) Nachteil — Grundtarif günstiger"
                        } else {
                            return "Neutral (0 €): Kein Splitting-Vorteil auf die Abfindung"
                        }
                    }()

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: bannerIcon)
                            .font(.caption)
                            .foregroundStyle(bannerColor)
                            .padding(.top, 1)
                        Text(bannerText)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(bannerColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(bannerColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Kinderfreibeträge")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text("ALG 1: \(Int(engine.input.alg1SatzPct)) % · § 31 Günstigerprüfung")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Picker("", selection: $engine.input.kinderZahl) {
                        ForEach(kinderOptions, id: \.self) { k in
                            Text(k == floor(k) ? "\(Int(k))" : String(format: "%.1f", k).replacingOccurrences(of: ".", with: ","))
                                .tag(k)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text("Kirchensteuer")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Picker("", selection: $engine.input.churchRate) {
                        ForEach(ChurchTaxOption.allCases) { opt in
                            Text(opt.shortLabel).tag(opt.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 215)
                }

                HStack(spacing: 8) {
                    Text("GKV vor Austritt")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    InfoIconButton(topic: .preExitGkv, selectedTopic: $selectedInfoTopic)
                    Spacer(minLength: 8)
                    Picker("", selection: $engine.input.preExitGkv) {
                        ForEach(PreExitGkvStatus.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .lineLimit(1)
                }

                CompactSliderRow(
                    title: "KV-Zusatzbeitrag",
                    selectedInfoTopic: $selectedInfoTopic,
                    value: $engine.input.kvZusatzbeitragPct,
                    range: 1.0...4.5,
                    step: 0.1,
                    valueFormatter: { pct($0) }
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("AG-Fiktivgehalt (LSt)")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        InfoIconButton(topic: .agFiktiv, selectedTopic: $selectedInfoTopic)
                        Spacer()
                        if !engine.result.isAgFiktivAutoDefault {
                            Button("Auto") {
                                engine.input.agFiktivGehalt = 0
                            }
                            .font(.caption.weight(.semibold))
                        }
                        Text(eur(engine.result.effectiveAgFiktiv))
                            .font(.subheadline.bold())
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { engine.result.effectiveAgFiktiv },
                            set: { engine.input.agFiktivGehalt = $0 }
                        ),
                        in: 30_000...200_000,
                        step: 2_500
                    )
                    .controlSize(.small)
                }
                .padding(.vertical, 1)
            } header: {
                Text("Familie, Kinder & Steuern").font(.caption.weight(.semibold))
            }

            Section {
                Toggle(isOn: $engine.input.turboEnabled) {
                    HStack(spacing: 5) {
                        Text("Sprinter-Option (Sofort-Austritt)")
                            .font(.subheadline.weight(.medium))
                        Button {
                            selectedInfoTopic = .alg1Rules
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Infos zu Sprinter-Option, Faktor, Ruhenszeit und Sperrzeit")
                    }
                }
                .tint(.orange)

                if engine.input.turboEnabled {
                    CompactSliderRow(
                        title: "Sprinter-Faktor",
                        subtitle: "Bonus: \(eur(engine.result.sprinterBonusGross, showPlus: true))",
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.turboFaktor,
                        range: 0.5...2.0,
                        step: 0.1,
                        valueFormatter: { String(format: "%.1fx", $0) }
                    )

                    Toggle(isOn: $engine.input.includeAlg1Loss) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("ALG-1 Sperrzeit abziehen (max. 12 Wo.)")
                                .font(.subheadline.weight(.medium))
                            Text(engine.input.includeAlg1Loss
                                 ? "Sperrzeit aktiv → \(max(0, engine.input.alg1ClaimMonths - 3)) Mon. ALG 1 nach Puffer"
                                 : "Ohne Sperrzeit → \(engine.input.alg1ClaimMonths) Mon. ALG 1 nach Ruhenszeit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Vorzeitiger Austritt").font(.caption.weight(.semibold))
            }
        }
        .listSectionSpacing(10)
        .safeAreaInset(edge: .bottom) {
            StickyKPIBar()
        }
    }

    private func presetBtn(_ title: String, icon: String, key: String, tint: Color) -> some View {
        Button {
            engine.applyPreset(key)
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(tint.opacity(0.14))
                .foregroundStyle(tint)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 2: Steuer-Optimierung

struct TaxOptimizationTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var selectedInfoTopic: StatutoryTopic?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { engine.input.taxOptimizationEnabled },
                    set: { engine.setTaxOptimizationEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Steuer-Optimierung aktivieren")
                            .font(.subheadline.weight(.semibold))
                        Text(engine.input.taxOptimizationEnabled
                             ? "Hebel aktiv — Deaktivieren setzt alle Werte auf 0 €"
                             : "Deaktiviert — alle 4 Hebel stehen sicher auf 0 €")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.green)
            } header: {
                Text("B · Steuer-Hebel Steuerung").font(.caption.weight(.semibold))
            }

            if engine.input.taxOptimizationEnabled {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(SolverMode.allCases) { mode in
                            let isSelected = engine.input.solverMode == mode
                            Button {
                                triggerLightHaptic()
                                engine.input.solverMode = mode
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: mode.icon)
                                        .font(.caption.weight(.semibold))
                                    Text(mode.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .padding(.horizontal, 8)
                                .background(isSelected ? mode.tint.opacity(0.20) : Color.secondary.opacity(0.10))
                                .foregroundStyle(isSelected ? mode.tint : .primary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? mode.tint : Color.clear, lineWidth: 1.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)

                    Text(engine.input.solverMode.shortHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    HStack(spacing: 4) {
                        Text("Optimierungs-Modus").font(.caption.weight(.semibold))
                        InfoIconButton(topic: .solverModes, selectedTopic: $selectedInfoTopic)
                    }
                }

                Section {
                    CompactSliderRow(
                        title: "1. bAV-Umwandlung",
                        subtitle: "Max. \(eur(engine.bavMaxTotal)) → bis zu \(eur(engine.result.bavMaxCapSavings, showPlus: true)) (\(pct(engine.result.bavMaxCapPct)))",
                        topic: .bav63,
                        selectedInfoTopic: $selectedInfoTopic,
                        value: Binding(
                            get: { engine.result.solvedBav },
                            set: { val in engine.updateManualLever { $0.bavAmount = val } }
                        ),
                        range: 0...engine.bavMaxTotal,
                        step: 1_000
                    )

                    if engine.result.solvedBav > 0 {
                        savingsPill(
                            label: "Sofort-Ersparnis (2027 LSt)",
                            amount: engine.result.bavSavings,
                            percent: engine.result.bavSavingsPct,
                            color: .blue
                        )
                    }
                }

                Section {
                    CompactSliderRow(
                        title: "2. Rürup / Basisrente",
                        subtitle: "Frei: \(eur(engine.result.ruerupCapRemaining)) von \(eur(engine.result.ruerupMaxCap))",
                        topic: .ruerup10,
                        selectedInfoTopic: $selectedInfoTopic,
                        value: Binding(
                            get: { engine.result.solvedRuerup },
                            set: { val in engine.updateManualLever { $0.ruerupAmount = val } }
                        ),
                        range: 0...max(1_000, engine.result.ruerupMaxCap),
                        step: 500
                    )

                    HStack(spacing: 6) {
                        Text("⚠️ Kapital dauerhaft gebunden")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                        Spacer()
                        if engine.result.solvedRuerup > 0 {
                            Text("\(eur(engine.result.ruerupSavings, showPlus: true)) (\(pct(engine.result.ruerupSavingsPct)))")
                                .font(.caption.bold())
                                .monospacedDigit()
                                .foregroundStyle(.green)
                        }
                    }

                    Button {
                        engine.applyRuerupSweetSpot()
                    } label: {
                        HStack {
                            Image(systemName: "target")
                            Text("Rürup Cash-Plus Sweet-Spot (\(eur(engine.result.ruerupSweetSpot)))")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Section {
                    CompactSliderRow(
                        title: "3. DRV-Ausgleich (V0210)",
                        subtitle: "50 % steuerfrei (§ 3 Nr. 28) · 50 % Fünftel",
                        topic: .drvV0210,
                        selectedInfoTopic: $selectedInfoTopic,
                        value: Binding(
                            get: { engine.result.solvedDrv },
                            set: { val in engine.updateManualLever { $0.drvV0210Amount = val } }
                        ),
                        range: 0...60_000,
                        step: 1_000
                    )

                    if engine.result.solvedDrv > 0 {
                        savingsPill(
                            label: "Steuer-Ersparnis DRV",
                            amount: engine.result.drvSavings,
                            percent: engine.result.drvSavingsPct,
                            color: .teal
                        )
                    }
                }

                Section {
                    CompactSliderRow(
                        title: "4. PV-Investition (50 % IAB)",
                        subtitle: "Abzug 2027: \(eur(engine.result.solvedPvPurchase * 0.5)) · 0 € Cash 2027",
                        topic: .pvIab7g,
                        selectedInfoTopic: $selectedInfoTopic,
                        value: Binding(
                            get: { engine.result.solvedPvPurchase },
                            set: { val in engine.updateManualLever { $0.pvIabPurchase = val } }
                        ),
                        range: 0...engine.pvIabMaxPurchase,
                        step: 5_000
                    )

                    if engine.result.solvedPvPurchase > 0 {
                        savingsPill(
                            label: "FA-Ersparnis PV-IAB",
                            amount: engine.result.iabSavings,
                            percent: engine.result.iabSavingsPct,
                            color: .green
                        )
                    }

                    Button {
                        engine.applyIabSweetSpot()
                    } label: {
                        HStack {
                            Image(systemName: "target")
                            Text("IAB Sweet-Spot anwenden (zvE → 0 €)")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .listSectionSpacing(10)
        .safeAreaInset(edge: .bottom) {
            StickyKPIBar()
        }
    }

    private func savingsPill(label: String, amount: Double, percent: Double, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
            Spacer()
            Text("\(eur(amount, showPlus: true)) (\(pct(percent)))")
                .font(.caption.bold())
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.14))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Tab 3: Ergebnis (KPIs, Side-by-Side Donuts, Waterfall & 3 Tables)

struct ResultsTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var selectedInfoTopic: StatutoryTopic?
    let onOpenPDFOptions: () -> Void

    @State private var showTable1 = true
    @State private var showTable2 = true
    @State private var showTable3 = true

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    kpiCard("Sofort-Netto 2027", value: eur(engine.result.sofortNetto2027), subtitle: "nach AG-Einbehalt", color: .orange)
                    kpiCard("FA-Erstattung Okt. 28", value: eur(engine.result.finanzamtRefundOct2028, showPlus: true), subtitle: "§ 34 & § 32b EStG", color: engine.result.finanzamtRefundOct2028 >= 0 ? .green : .red)
                    kpiCard("Optimal-Netto Gesamt", value: eur(engine.result.optimalNettoTotal), subtitle: "Steuerlast: \(eur(engine.result.totalTaxFinal))", color: .blue)
                    kpiCard("Bar-Liquidität Ende 28", value: eur(engine.result.endLiquidity2028), subtitle: "inkl. Netto-Gehalt 27", color: .purple)
                }

                SideBySideResultDonutsCard(
                    sofortNetto: engine.result.sofortNetto2027,
                    upfrontTax: engine.result.upfrontPayrollTax,
                    optimalNetto: engine.result.optimalNettoTotal,
                    finalTax: max(0, engine.result.totalTaxFinal)
                )

                if engine.input.taxOptimizationEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STEUER-HEBEL ERSPARNIS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            leverMiniCard("bAV (Sofort 2027)", amount: engine.result.bavSavings, pctVal: engine.result.bavSavingsPct, color: .blue)
                            leverMiniCard("Rürup (§ 10)", amount: engine.result.ruerupSavings, pctVal: engine.result.ruerupSavingsPct, color: .indigo)
                            leverMiniCard("DRV V0210", amount: engine.result.drvSavings, pctVal: engine.result.drvSavingsPct, color: .teal)
                            leverMiniCard("PV-IAB (§ 7g)", amount: engine.result.iabSavings, pctVal: engine.result.iabSavingsPct, color: .green)
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Abfindung: Brutto → Netto 2027/2028")
                            .font(.subheadline.weight(.semibold))
                        InfoIconButton(topic: .liquidityTimeline, selectedTopic: $selectedInfoTopic)
                    }
                    Chart {
                        BarMark(x: .value("Stufe", "Brutto"), y: .value("€", engine.result.effectiveAbfindung))
                            .foregroundStyle(.gray.opacity(0.6))
                        BarMark(x: .value("Stufe", "Sofort 27"), y: .value("€", engine.result.sofortNetto2027))
                            .foregroundStyle(.orange)
                        BarMark(x: .value("Stufe", "FA Okt. 28"), y: .value("€", max(0, engine.result.finanzamtRefundOct2028)))
                            .foregroundStyle(.green)
                        BarMark(x: .value("Stufe", "Optimal"), y: .value("€", engine.result.optimalNettoTotal))
                            .foregroundStyle(.blue)
                    }
                    .frame(height: 175)
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if engine.input.turboEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sprinter Netto-Brücke (Wasserfall)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(eur(engine.result.sprinterNetGain, showPlus: true))
                                .font(.subheadline.bold())
                                .monospacedDigit()
                                .foregroundStyle(engine.result.sprinterNetGain >= 0 ? .green : .red)
                        }
                        Chart(engine.result.waterfallSteps) { step in
                            BarMark(
                                xStart: .value("Start", step.start),
                                xEnd: .value("Ende", step.end),
                                y: .value("Position", step.label)
                            )
                            .foregroundStyle(
                                step.isTotal
                                    ? (step.delta >= 0 ? Color.blue : Color.red)
                                    : (step.delta >= 0 ? Color.green : Color.orange)
                            )
                            .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4))
                        }
                        .frame(height: 225)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                tableCard(
                    title: "1. Sofort-Abrechnung AG (2027)",
                    badge: eur(engine.result.sofortNetto2027),
                    badgeColor: .orange,
                    isExpanded: $showTable1
                ) {
                    tableRow("Basis-Abfindung Brutto", eur(engine.input.bruttoAbfindung))
                    if engine.input.turboEnabled {
                        tableRow("+ Sprinter-Prämie Brutto", eur(engine.result.sprinterBonusGross, showPlus: true), valueColor: .green)
                        tableRow("= Effektive Abfindung Brutto", eur(engine.result.effectiveAbfindung), bold: true)
                    }
                    if engine.result.solvedBav > 0 {
                        tableRow("− bAV-Umwandlung (§ 3 Nr. 63)", eur(-engine.result.solvedBav), valueColor: .blue)
                    }
                    if engine.result.solvedDrv > 0 {
                        tableRow("− DRV-Direktzahlung (V0210)", eur(-engine.result.solvedDrv), valueColor: .teal)
                    }
                    tableRow("= Bar-Brutto vor Steuer", eur(engine.result.barBruttoVorSteuer), bold: true)
                    tableRow("− AG Lohnsteuer-Einbehalt (\(pct(engine.result.upfrontTaxRatePct)))", eur(-engine.result.upfrontPayrollTax), valueColor: .red)
                    Divider()
                    tableRow("= Sofort-Netto 2027", eur(engine.result.sofortNetto2027), valueColor: .orange, bold: true)
                }

                tableCard(
                    title: "2. Endabrechnung Finanzamt (2028)",
                    badge: eur(engine.result.optimalNettoTotal),
                    badgeColor: .blue,
                    isExpanded: $showTable2
                ) {
                    tableRow("Effektive Abfindung Brutto", eur(engine.result.effectiveAbfindung))
                    tableRow("2027 Brutto (Alt-AG + Neu-Job)", eur(engine.result.totalGross2027))
                    if engine.result.alg1Months2027 > 0 {
                        tableRow("ALG-1 2027 (§ 32b · \(pct(engine.result.progressionRatePct2027)))", eur(engine.result.alg1Ersatzleistung2027), valueColor: .cyan)
                    }
                    if engine.result.totalTaxFinal >= 0 {
                        tableRow("− Endgültige Steuer (§ 34 · \(pct(engine.result.finalTaxRatePct)))", eur(-engine.result.totalTaxFinal), valueColor: .red)
                    } else {
                        tableRow("+ Steuer-Gutschrift (inkl. LSt-Erstattung)", eur(-engine.result.totalTaxFinal, showPlus: true), valueColor: .green)
                    }
                    if engine.input.kinderZahl > 0 {
                        tableRow(
                            "Kinder-Vorteil (\(engine.result.kinderFreibetragWon ? "KFB gewinnt" : "KiG + Soli/KiSt"))",
                            eur(engine.result.kinderBenefitNet, showPlus: true),
                            valueColor: .green
                        )
                    }
                    if engine.input.churchRate > 0 {
                        tableRow("Kirchensteuer-Satz berücksichtigt", pct(engine.input.churchRate * 100))
                    }
                    Divider()
                    tableRow("= Optimal-Netto Gesamt", eur(engine.result.optimalNettoTotal), valueColor: .blue, bold: true)
                    tableRow("+ FA-Erstattung Okt. 2028", eur(engine.result.finanzamtRefundOct2028, showPlus: true), valueColor: engine.result.finanzamtRefundOct2028 >= 0 ? .green : .red, bold: true)
                }

                tableCard(
                    title: "3. Harter Liquiditäts-Zeitstrahl",
                    badge: eur(engine.result.endLiquidity2028),
                    badgeColor: .purple,
                    isExpanded: $showTable3
                ) {
                    tableRow("Cash-In: Sofort-Netto Abfindung", eur(engine.result.sofortNetto2027), bold: true)
                    tableRow("+ Cash-In: Netto-Gehalt 2027", eur(engine.result.netSalary2027, showPlus: true), valueColor: .green)
                    if engine.result.alg1Ersatzleistung2027 > 0 {
                        tableRow("+ Cash-In: ALG 1 in 2027 (\(engine.result.alg1Months2027) M.)", eur(engine.result.alg1Ersatzleistung2027, showPlus: true), valueColor: .cyan)
                    }
                    if engine.result.solvedRuerup > 0 {
                        tableRow("− Cash-Out: Rürup-Einzahlung", eur(-engine.result.solvedRuerup), valueColor: .indigo)
                    }
                    if engine.result.solvedPvPurchase > 0 {
                        tableRow("Info: PV-IAB (3 J. Frist · 0 € Cash 2027)", "0 €", valueColor: .secondary)
                    }
                    if engine.result.ruhensGkvTotal > 0 {
                        tableRow("− Cash-Out: Freiwillige GKV (Ruhenszeit)", eur(-engine.result.ruhensGkvTotal), valueColor: .red)
                    }
                    Divider()
                    tableRow("= KONTO-CASH am 31.12.2027", eur(engine.result.kontoCashEnd2027), bold: true)
                    tableRow("+ Cash-In: FA-Erstattung Okt. 2028", eur(engine.result.finanzamtRefundOct2028, showPlus: true), valueColor: engine.result.finanzamtRefundOct2028 >= 0 ? .green : .red)
                    Divider()
                    tableRow("= BAR-LIQUIDITÄT Ende 2028", eur(engine.result.endLiquidity2028), valueColor: .purple, bold: true)
                }

                Button(action: onOpenPDFOptions) {
                    Label("A4 PDF-Report (Optionen & Export)", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func tableCard<Content: View>(
        title: String,
        badge: String,
        badgeColor: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(spacing: 7) {
                Divider().padding(.top, 4)
                content()
            }
            .padding(.top, 2)
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(badge)
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(badgeColor)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func tableRow(_ left: String, _ right: String, valueColor: Color = .primary, bold: Bool = false) -> some View {
        HStack {
            Text(left)
                .font(bold ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(right)
                .font(bold ? .caption.bold() : .caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
    }

    private func kpiCard(_ title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.headline.bold())
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func leverMiniCard(_ title: String, amount: Double, pctVal: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            Text(eur(amount, showPlus: true))
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(amount > 0 ? color : .secondary)
            Text(amount > 0 ? pct(pctVal) : "0,0 %")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Side-by-Side Interactive Donut Charts (Ergebnis · Matching Semantic Colors)

private struct DonutSliceItem: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

struct SideBySideResultDonutsCard: View {
    let sofortNetto: Double
    let upfrontTax: Double
    let optimalNetto: Double
    let finalTax: Double

    @State private var selectedAngle1: Double?
    @State private var selectedAngle2: Double?

    private var slices1: [DonutSliceItem] {
        [
            DonutSliceItem(label: "Sofort-Netto", value: max(0, sofortNetto), color: .green),
            DonutSliceItem(label: "LSt-Einbehalt", value: max(0, upfrontTax), color: .red)
        ]
    }

    private var slices2: [DonutSliceItem] {
        [
            DonutSliceItem(label: "Optimal-Netto", value: max(0, optimalNetto), color: .green),
            DonutSliceItem(label: "Endg. Steuer", value: max(0, finalTax), color: .red)
        ]
    }

    private func selectedSlice(in slices: [DonutSliceItem], angle: Double?) -> DonutSliceItem? {
        guard let angle else { return nil }
        var cumulative = 0.0
        for item in slices {
            cumulative += item.value
            if angle <= cumulative { return item }
        }
        return slices.last
    }

    var body: some View {
        HStack(spacing: 8) {
            donutCard(
                title: "1. AG-Abrechnung",
                total: max(0, sofortNetto + upfrontTax),
                slices: slices1,
                selectedAngle: $selectedAngle1
            )
            donutCard(
                title: "2. FA-Endabrechnung",
                total: max(0, optimalNetto + finalTax),
                slices: slices2,
                selectedAngle: $selectedAngle2
            )
        }
    }

    private func donutCard(
        title: String,
        total: Double,
        slices: [DonutSliceItem],
        selectedAngle: Binding<Double?>
    ) -> some View {
        let active = selectedSlice(in: slices, angle: selectedAngle.wrappedValue)
        let centerTitle = active?.label ?? "Gesamt"
        let centerValue = active?.value ?? total
        let centerPct = (active != nil && total > 0) ? " (\(pct((active!.value / total) * 100)))" : ""

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            ZStack {
                Chart(slices) { item in
                    SectorMark(
                        angle: .value("Betrag", item.value),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(item.color)
                    .opacity(active == nil || active?.label == item.label ? 1.0 : 0.45)
                }
                .chartAngleSelection(value: selectedAngle)
                .frame(height: 122)

                VStack(spacing: 1) {
                    Text(centerTitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(eur(centerValue))
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if !centerPct.isEmpty {
                        Text(centerPct)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(active?.color ?? .secondary)
                    }
                }
                .frame(maxWidth: 74)
            }

            VStack(spacing: 3) {
                ForEach(slices) { item in
                    let isHighlighted = active?.label == item.label
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 6, height: 6)
                        Text(item.label)
                            .font(.system(size: 10, weight: isHighlighted ? .bold : .regular))
                            .foregroundStyle(isHighlighted ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
                        Text(eur(item.value))
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }

            Text("Tippen/ziehen für Werte")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Tab 4: Reichweite

struct ReichweiteTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var selectedInfoTopic: StatutoryTopic?

    private var phaseMaxX: Double {
        let m = max(engine.result.standardRunwayMonths, engine.result.sprinterRunwayMonths, engine.result.faRefundMonthIndex)
        return max(18, m * 1.40)
    }

    private var winnerPill: (text: String, color: Color) {
        let diff = Int((engine.result.sprinterRunwayMonths - engine.result.standardRunwayMonths).rounded())
        if diff > 0 { return ("Sprinter +\(diff) Mon.", .green) }
        if diff < 0 { return ("Standard +\(abs(diff)) Mon.", .orange) }
        return ("Gleichstand", .secondary)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PARAMETER · ÜBERLEBEN OHNE JOB")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    CompactSliderRow(
                        title: "Monatl. Netto-Ausgaben",
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.monthlyExpenses,
                        range: 1_500...8_000,
                        step: 100
                    )

                    CompactSliderRow(
                        title: "Einmal-Abfluss 2027 (Day-0)",
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.upfrontSpend2027,
                        range: 0...80_000,
                        step: 1_000
                    )

                    Stepper(value: $engine.input.alg1ClaimMonths, in: 6...24, step: 3) {
                        HStack {
                            Text("ALG-1 Anspruch (\(Int(engine.input.alg1SatzPct)) %)")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text("\(engine.input.alg1ClaimMonths) Mon.")
                                .font(.subheadline.bold())
                                .monospacedDigit()
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("GKV nach ALG 1")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .layoutPriority(1)
                            InfoIconButton(topic: .postAlg1Gkv, selectedTopic: $selectedInfoTopic)
                            Spacer(minLength: 4)
                            Menu {
                                ForEach(PostAlg1GkvMode.allCases) { m in
                                    Button {
                                        engine.input.postAlg1GkvMode = m
                                    } label: {
                                        if engine.input.postAlg1GkvMode == m {
                                            Label(m.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(m.displayName)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(engine.input.postAlg1GkvMode.displayName)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.blue)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        Text("Beitrag nach ALG 1: \(eur(engine.result.effectivePostGkvMonthly))/Mo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if engine.input.postAlg1GkvMode == .individuell {
                        CompactSliderRow(
                            title: "Eigene GKV/PV nach ALG 1",
                            selectedInfoTopic: $selectedInfoTopic,
                            value: $engine.input.customPostGkvMonthly,
                            range: 0...1_400,
                            step: 20,
                            valueFormatter: { "\(eur($0))/Mo" }
                        )
                    }

                    CompactSliderRow(
                        title: "Real-Zins / Inflation p.a.",
                        topic: .realReturnInflation,
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.realReturnPct,
                        range: -3.0...6.0,
                        step: 0.5,
                        valueFormatter: { pct($0) }
                    )

                    Toggle("Gehalts-Überschuss in Frist sparen", isOn: $engine.input.includeSalarySurplus)
                        .font(.subheadline.weight(.medium))
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 8) {
                    runwayKpi("Standard (Frist)", months: engine.result.standardRunwayMonths, date: engine.result.standardDepletionDate, color: .orange)
                    runwayKpi("Sprinter (Sofort)", months: engine.result.sprinterRunwayMonths, date: engine.result.sprinterDepletionDate, color: .green)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Text("Lebensphasen-Zeitstrahl")
                            .font(.subheadline.weight(.semibold))
                        Button {
                            selectedInfoTopic = .reichweiteLogic
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Logik zu Abfindungs-Puffer, Mindestzeit und ALG 1")
                        Spacer()
                        Text(winnerPill.text)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(winnerPill.color.opacity(0.15))
                            .foregroundStyle(winnerPill.color)
                            .clipShape(Capsule())
                    }

                    Chart {
                        ForEach(engine.result.runwayPhaseBars) { bar in
                            BarMark(
                                xStart: .value("Start", bar.startMonth),
                                xEnd: .value("Ende", bar.endMonth),
                                y: .value("Strategie", bar.strategy)
                            )
                            .foregroundStyle(by: .value("Phase", bar.phase))
                            .cornerRadius(4)
                            .annotation(position: .overlay) {
                                if bar.duration >= max(5, phaseMaxX * 0.12) {
                                    Text("\(Int(bar.duration))M")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .fixedSize()
                                }
                            }
                            .annotation(position: .trailing, spacing: 4) {
                                if bar.isLast {
                                    HStack(spacing: 3) {
                                        Text(bar.strategy == "Sprinter" ? "🏃" : "🐢")
                                            .font(.caption)
                                            .scaleEffect(x: -1, y: 1)
                                        Text(bar.endDateLabel)
                                            .font(.caption2.bold())
                                            .monospacedDigit()
                                            .foregroundStyle(bar.strategy == "Sprinter" ? .green : .orange)
                                    }
                                    .fixedSize()
                                }
                            }
                        }

                        RuleMark(x: .value("FA Okt. 28", engine.result.faRefundMonthIndex))
                            .foregroundStyle(Color.purple.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .annotation(position: .top, alignment: .center, spacing: 4) {
                                Text("FA Okt. 28")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.purple)
                                    .fixedSize()
                            }
                    }
                    .chartXScale(domain: 0...phaseMaxX)
                    .chartForegroundStyleScale([
                        "Gehalt/Frist": Color.blue,
                        "Ruhenszeit": Color.orange,
                        "ALG 1": Color.cyan,
                        "Privatier": Color.green
                    ])
                    .padding(.top, 14)
                    .frame(height: 155)
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                ReichweiteAreaChartCard(
                    points: engine.result.runwayCurve,
                    faMarkerX: engine.result.faRefundMonthIndex,
                    stdDepleteX: engine.result.standardRunwayMonths < 72 ? engine.result.standardRunwayMonths : nil,
                    sprDepleteX: engine.result.sprinterRunwayMonths < 72 ? engine.result.sprinterRunwayMonths : nil
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("MEILENSTEINE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    milestoneRow("ALG 1 endet", std: engine.result.standardAlg1EndDate, spr: engine.result.sprinterAlg1EndDate)
                    milestoneRow("Geld aufgebraucht", std: engine.result.standardDepletionDate, spr: engine.result.sprinterDepletionDate)
                    milestoneRow("Okt. 2028 Brücke", std: engine.result.standardBridgeSafe ? "Sicher" : "Engpass", spr: engine.result.sprinterBridgeSafe ? "Sicher" : "Engpass")
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func runwayKpi(_ title: String, months: Double, date: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(months >= 72 ? "> 72 Mon." : "\(Int(months)) Mon.")
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(color)
            Text("bis \(date)").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func milestoneRow(_ label: String, std: String, spr: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("Std: \(std)").font(.caption.bold()).foregroundStyle(.orange)
            Text("·").foregroundStyle(.secondary)
            Text("Spr: \(spr)").font(.caption.bold()).foregroundStyle(.green)
        }
    }
}

// MARK: - Tab 5: Job-Switch

struct JobSwitchTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var selectedInfoTopic: StatutoryTopic?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PARAMETER · GEHALTS-SWITCH")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    CompactSliderRow(
                        title: "Neues Jahresbrutto",
                        subtitle: "Alt: \(eur(engine.input.altesMonatsgehalt * 12)) / Jahr",
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.switchNewAnnualGross,
                        range: 25_000...160_000,
                        step: 2_500
                    )

                    Stepper(value: $engine.input.switchStartDelayMonths, in: 0...12) {
                        HStack {
                            Text("Pause bis Neustart")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(engine.input.switchStartDelayMonths) Mon.")
                                .font(.subheadline.bold())
                                .monospacedDigit()
                        }
                    }

                    CompactSliderRow(
                        title: "Gehaltswachstum p.a. (symmetrisch)",
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.switchAnnualGrowthPct,
                        range: 0.0...6.0,
                        step: 0.5,
                        valueFormatter: { pct($0) }
                    )
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 8) {
                    beCard(
                        "Standard Break-Even",
                        year: engine.result.breakEvenYearStandard,
                        dateLabel: engine.result.breakEvenDateStandard,
                        color: .orange
                    )
                    beCard(
                        "Sprinter Break-Even",
                        year: engine.result.breakEvenYearSprinter,
                        dateLabel: engine.result.breakEvenDateSprinter,
                        color: .green
                    )
                }

                SwitchAreaChartCard(
                    points: engine.result.switchCurve,
                    stdCrossX: engine.result.breakEvenYearStandard,
                    sprCrossX: engine.result.breakEvenYearSprinter
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("VERGLEICH NACH JAHREN")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    switchRow("Nach 5 Jahren", std: engine.result.switchDeltaYear5Std, spr: engine.result.switchDeltaYear5Spr)
                    switchRow("Nach 10 Jahren", std: engine.result.switchDeltaYear10Std, spr: engine.result.switchDeltaYear10Spr)
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func beCard(_ title: String, year: Double?, dateLabel: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(year.map { String(format: "%.1f Jahre", $0).replacingOccurrences(of: ".", with: ",") } ?? "> 15 Jahre")
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(color)
            Text(dateLabel.map { "0 € erreicht: \($0)" } ?? "Dauerhaft im Plus")
                .font(.caption2.weight(dateLabel == nil ? .regular : .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func switchRow(_ label: String, std: Double, spr: Double) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("Std: \(eur(std, showPlus: true))").font(.caption.bold()).monospacedDigit().foregroundStyle(.orange)
            Text("·").foregroundStyle(.secondary)
            Text("Spr: \(eur(spr, showPlus: true))").font(.caption.bold()).monospacedDigit().foregroundStyle(.green)
        }
    }
}

// MARK: - Tailored Reichweite Area Chart

struct ReichweiteAreaChartCard: View {
    let points: [DualSeriesPoint]
    let faMarkerX: Double
    let stdDepleteX: Double?
    let sprDepleteX: Double?

    @State private var filter: ChartStrategyFilter = .both
    @State private var selectedX: Double?

    private var activePoint: DualSeriesPoint? {
        guard let selectedX else { return nil }
        return points.min(by: { abs($0.x - selectedX) < abs($1.x - selectedX) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Konto-Verlauf (€)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $filter) {
                    ForEach(ChartStrategyFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 195)
            }

            if let pt = activePoint {
                HStack(spacing: 8) {
                    Text(pt.label).font(.caption2.bold())
                    Spacer()
                    if filter != .sprinter {
                        Text("Std: \(eur(pt.standardVal))").font(.caption2.bold()).foregroundStyle(.orange)
                    }
                    if filter != .standard {
                        Text("Spr: \(eur(pt.sprinterVal))").font(.caption2.bold()).foregroundStyle(.green)
                    }
                }
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Tippen & ziehen für Monatswerte")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Chart {
                if filter == .both {
                    ForEach(points) { pt in
                        AreaMark(
                            x: .value("Monat", pt.x),
                            yStart: .value("Basis", 0),
                            yEnd: .value("Gemeinsam", pt.sharedPositive)
                        )
                        .foregroundStyle(by: .value("Bereich", "Gemeinsam"))
                    }
                    ForEach(points) { pt in
                        AreaMark(
                            x: .value("Monat", pt.x),
                            yStart: .value("SprLow", pt.sprinterAheadLow),
                            yEnd: .value("SprHigh", pt.sprinterAheadHigh)
                        )
                        .foregroundStyle(by: .value("Bereich", "Sprinter vorn"))
                    }
                    ForEach(points) { pt in
                        AreaMark(
                            x: .value("Monat", pt.x),
                            yStart: .value("StdLow", pt.standardAheadLow),
                            yEnd: .value("StdHigh", pt.standardAheadHigh)
                        )
                        .foregroundStyle(by: .value("Bereich", "Standard vorn"))
                    }
                } else if filter == .standard {
                    ForEach(points) { pt in
                        AreaMark(x: .value("Monat", pt.x), y: .value("Standard", pt.standardVal))
                            .foregroundStyle(by: .value("Bereich", "Standard vorn"))
                    }
                } else {
                    ForEach(points) { pt in
                        AreaMark(x: .value("Monat", pt.x), y: .value("Sprinter", pt.sprinterVal))
                            .foregroundStyle(by: .value("Bereich", "Sprinter vorn"))
                    }
                }

                if filter != .sprinter {
                    ForEach(points) { pt in
                        LineMark(
                            x: .value("Monat", pt.x),
                            y: .value("Standard", pt.standardVal),
                            series: .value("Linie", "Standard")
                        )
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                if filter != .standard {
                    ForEach(points) { pt in
                        LineMark(
                            x: .value("Monat", pt.x),
                            y: .value("Sprinter", pt.sprinterVal),
                            series: .value("Linie", "Sprinter")
                        )
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }

                RuleMark(x: .value("FA Okt. 28", faMarkerX))
                    .foregroundStyle(Color.purple.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        Text("FA Okt. 28")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.purple)
                            .fixedSize()
                    }

                if let pt = activePoint {
                    RuleMark(x: .value("Auswahl", pt.x))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }

                if filter != .sprinter, let stdX = stdDepleteX {
                    PointMark(x: .value("Monat", stdX), y: .value("Null", 0))
                        .foregroundStyle(Color.orange)
                        .symbolSize(50)
                }
                if filter != .standard, let sprX = sprDepleteX {
                    PointMark(x: .value("Monat", sprX), y: .value("Null", 0))
                        .foregroundStyle(Color.green)
                        .symbolSize(50)
                }
            }
            .chartForegroundStyleScale([
                "Gemeinsam": LinearGradient(
                    colors: [Color.blue.opacity(0.35), Color.blue.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                "Sprinter vorn": LinearGradient(
                    colors: [Color.green.opacity(0.38), Color.green.opacity(0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                "Standard vorn": LinearGradient(
                    colors: [Color.orange.opacity(0.38), Color.orange.opacity(0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            ])
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedX)
            .padding(.top, 14)
            .frame(height: 235)

            HStack(spacing: 12) {
                legendDot("Gemeinsam", color: .blue)
                legendDot("Sprinter vorn", color: .green)
                legendDot("Standard vorn", color: .orange)
                legendDot("FA Okt. 28", color: .purple)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func legendDot(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}

// MARK: - Tailored Job-Switch Area Chart (Auto-Cropped Past 0 € Break-Even)

struct SwitchAreaChartCard: View {
    let points: [DualSeriesPoint]
    let stdCrossX: Double?
    let sprCrossX: Double?

    @State private var filter: ChartStrategyFilter = .both
    @State private var selectedX: Double?

    private var maxPlotYear: Double {
        let relevantCross: Double? = {
            switch filter {
            case .standard:
                return stdCrossX
            case .sprinter:
                return sprCrossX
            case .both:
                if let s = stdCrossX, let p = sprCrossX { return max(s, p) }
                return stdCrossX ?? sprCrossX
            }
        }()
        guard let cross = relevantCross else { return 15.0 }
        return Double(min(15, max(4, Int(ceil(cross)) + 1)))
    }

    private var visiblePoints: [DualSeriesPoint] {
        points.filter { $0.x <= maxPlotYear }
    }

    private var activePoint: DualSeriesPoint? {
        guard let selectedX else { return nil }
        return visiblePoints.min(by: { abs($0.x - selectedX) < abs($1.x - selectedX) })
    }

    private func positiveTop(_ pt: DualSeriesPoint) -> Double {
        switch filter {
        case .both: return max(0, max(pt.standardVal, pt.sprinterVal))
        case .standard: return max(0, pt.standardVal)
        case .sprinter: return max(0, pt.sprinterVal)
        }
    }

    private func negativeBottom(_ pt: DualSeriesPoint) -> Double {
        switch filter {
        case .both: return min(0, min(pt.standardVal, pt.sprinterVal))
        case .standard: return min(0, pt.standardVal)
        case .sprinter: return min(0, pt.sprinterVal)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Vermögens-Vorsprung (€)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $filter) {
                    ForEach(ChartStrategyFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 195)
            }

            if let pt = activePoint {
                HStack(spacing: 8) {
                    Text(pt.label).font(.caption2.bold())
                    Spacer()
                    if filter != .sprinter {
                        Text("Std: \(eur(pt.standardVal, showPlus: true))").font(.caption2.bold()).foregroundStyle(.orange)
                    }
                    if filter != .standard {
                        Text("Spr: \(eur(pt.sprinterVal, showPlus: true))").font(.caption2.bold()).foregroundStyle(.green)
                    }
                }
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Tippen & ziehen für Jahreswerte")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(visiblePoints) { pt in
                    AreaMark(
                        x: .value("Jahr", pt.x),
                        yStart: .value("Null", 0),
                        yEnd: .value("Plus", positiveTop(pt))
                    )
                    .foregroundStyle(by: .value("Zone", "Plus"))
                }
                ForEach(visiblePoints) { pt in
                    AreaMark(
                        x: .value("Jahr", pt.x),
                        yStart: .value("Minus", negativeBottom(pt)),
                        yEnd: .value("Null", 0)
                    )
                    .foregroundStyle(by: .value("Zone", "Minus"))
                }

                if filter != .sprinter {
                    ForEach(visiblePoints) { pt in
                        LineMark(
                            x: .value("Jahr", pt.x),
                            y: .value("Standard", pt.standardVal),
                            series: .value("Linie", "Standard")
                        )
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                    }
                }
                if filter != .standard {
                    ForEach(visiblePoints) { pt in
                        LineMark(
                            x: .value("Jahr", pt.x),
                            y: .value("Sprinter", pt.sprinterVal),
                            series: .value("Linie", "Sprinter")
                        )
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                    }
                }

                RuleMark(y: .value("Break-Even", 0))
                    .foregroundStyle(Color.red.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                RuleMark(x: .value("FA Okt. 28", 2.0))
                    .foregroundStyle(Color.purple.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                if let pt = activePoint {
                    RuleMark(x: .value("Auswahl", pt.x))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }

                if filter != .sprinter, let stdX = stdCrossX, stdX <= maxPlotYear {
                    PointMark(x: .value("Jahr", stdX), y: .value("Null", 0))
                        .foregroundStyle(Color.orange)
                        .symbolSize(55)
                }
                if filter != .standard, let sprX = sprCrossX, sprX <= maxPlotYear {
                    PointMark(x: .value("Jahr", sprX), y: .value("Null", 0))
                        .foregroundStyle(Color.green)
                        .symbolSize(55)
                }
            }
            .chartXScale(domain: 0...maxPlotYear)
            .chartForegroundStyleScale([
                "Plus": LinearGradient(
                    colors: [Color.teal.opacity(0.32), Color.teal.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                "Minus": LinearGradient(
                    colors: [Color.red.opacity(0.08), Color.red.opacity(0.32)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            ])
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedX)
            .frame(height: 225)

            HStack(spacing: 12) {
                legendDot("Im Plus", color: .teal)
                legendDot("Im Minus", color: .red)
                legendDot("Standard", color: .orange)
                legendDot("Sprinter", color: .green)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func legendDot(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}

// MARK: - Native UIKit Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
