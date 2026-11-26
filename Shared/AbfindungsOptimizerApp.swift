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
        case .mindestbeitrag: return "Mindest (~280 €)"
        case .familienversicherung: return "Familie (0 €)"
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

struct SimulationInput: Codable, Equatable {
    // Section A: Basis & Severance
    var altesMonatsgehalt: Double = 7_500
    var fristMonate: Int = 5
    var bruttoAbfindung: Double = 150_000
    var agFiktivGehalt: Double = 90_000
    var payoutMonth2027: Int = 4
    var neuesGehalt2027: Double = 0

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
    var includeAlg1Loss: Bool = false

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
    // 2027 Gross & Net Salary Breakdown
    var oldJobMonths2027: Int = 0
    var oldJobGross2027: Double = 0
    var totalGross2027: Double = 0
    var netSalary2027: Double = 0

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
    var switchCurve: [DualSeriesPoint] = []
    var switchDeltaYear5Std: Double = 0
    var switchDeltaYear5Spr: Double = 0
    var switchDeltaYear10Std: Double = 0
    var switchDeltaYear10Spr: Double = 0
}

// MARK: - 2027 Statutory German Tax, Solver & Runway Engine

final class TaxEngineHost: ObservableObject {
    private static let storageKey = "abfindungspilot_input_v27_1"

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

    // MARK: Core § 32a / § 34 / § 31 EStG Math

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

    private func calcSolz2027(_ est: Double, isSplitting: Bool) -> Double {
        let fg = isSplitting ? solzFreigrenzeSingle * 2.0 : solzFreigrenzeSingle
        if est <= fg { return 0 }
        return min((est - fg) * 0.119, est * 0.055)
    }

    private func calcFuenftelESt(_ rawBaseZve: Double, abfindung: Double, isSplitting: Bool) -> Double {
        let abf = max(0, abfindung)
        if rawBaseZve >= 0 {
            let baseEst = calcTariff2027(rawBaseZve, isSplitting: isSplitting)
            let fifthEst = calcTariff2027(rawBaseZve + abf / 5.0, isSplitting: isSplitting)
            return baseEst + max(0, 5.0 * (fifthEst - baseEst))
        } else {
            let combined = rawBaseZve + abf
            if combined <= 0 { return 0 }
            return 5.0 * calcTariff2027(combined / 5.0, isSplitting: isSplitting)
        }
    }

    private func calcTotalTaxWithKinder(
        rawBaseZve: Double,
        abfindung: Double,
        isSplitting: Bool,
        churchRate: Double,
        kinderZahl: Double
    ) -> (totalTax: Double, estFinal: Double, soli: Double, church: Double, kinderNetGain: Double, kfbWon: Bool) {
        let estNoKfb = calcFuenft
