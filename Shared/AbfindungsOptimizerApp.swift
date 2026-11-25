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

// MARK: - Formatting & Haptics

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

// MARK: - Domain Models

enum PreExitGkvStatus: String, CaseIterable, Identifiable, Codable {
    case pflicht = "Pflichtversichert"
    case freiwillig = "Freiwillig GKV"
    case pkv = "Privat (PKV)"
    var id: String { rawValue }
}

enum PostAlg1GkvMode: String, CaseIterable, Identifiable, Codable {
    case mindestbeitrag = "Mindestbeitrag (~280 €/Mo)"
    case familienversicherung = "Familienvers. (0 €/Mo)"
    case individuell = "Individuell"
    var id: String { rawValue }
}

enum SolverMode: String, CaseIterable, Identifiable, Codable {
    case manual = "Manuell"
    case optimal = "Optimal-Netto"
    case liquidity = "Liquidität"
    case retirement = "Altersvorsorge"
    var id: String { rawValue }
}

enum ChurchTaxOption: Double, CaseIterable, Identifiable, Codable {
    case none = 0.0
    case byBw = 0.08
    case other = 0.09
    var id: Double { rawValue }

    var shortLabel: String {
        switch self {
        case .none: return "0 %"
        case .byBw: return "8 % (BY/BW)"
        case .other: return "9 %"
        }
    }
}

struct SimulationInput: Codable, Equatable {
    // Section A: Basis & Severance
    var altesMonatsgehalt: Double = 7_500
    var fristMonate: Int = 5
    var bruttoAbfindung: Double = 150_000
    var agFiktivGehalt: Double = 90_000
    var payoutMonth2027: Int = 4 // 1..12
    var neuesGehalt2027: Double = 0 // Additional salary from NEW job in 2027

    // Family, Tax & GKV
    var isSplitting: Bool = false
    var partnerGehalt2027: Double = 0
    var kinderZahl: Double = 0.0 // 0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0
    var churchRate: Double = 0.0 // 0.0, 0.08, 0.09
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
    let delta: Double
    let isTotal: Bool
}

struct RunwayPhaseBar: Identifiable {
    let id = UUID()
    let strategy: String
    let phase: String
    let startMonth: Double
    let endMonth: Double
    let colorName: String
}

struct DualSeriesPoint: Identifiable {
    let id = UUID()
    let x: Double // Month index (Reichweite) or Year index (Switch)
    let standardVal: Double
    let sprinterVal: Double

    var sharedMin: Double {
        if standardVal >= 0 && sprinterVal >= 0 {
            return min(standardVal, sprinterVal)
        }
        return 0
    }
    var sprinterAheadLow: Double { min(standardVal, sprinterVal) }
    var sprinterAheadHigh: Double { sprinterVal > standardVal ? sprinterVal : min(standardVal, sprinterVal) }
    var standardAheadLow: Double { min(standardVal, sprinterVal) }
    var standardAheadHigh: Double { standardVal > sprinterVal ? standardVal : min(standardVal, sprinterVal) }
}

struct SimulationResult {
    // 2027 Gross Breakdown
    var oldJobMonths2027: Int = 0
    var oldJobGross2027: Double = 0
    var totalGross2027: Double = 0

    // Core KPIs
    var effectiveAbfindung: Double = 0
    var sprinterBonusGross: Double = 0
    var sofortNetto2027: Double = 0
    var upfrontPayrollTax: Double = 0
    var finanzamtRefundOct2028: Double = 0
    var optimalNettoTotal: Double = 0
    var endLiquidity2028: Double = 0
    var totalTaxFinal: Double = 0
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
    var iabSweetSpotPurchase: Double = 0
    var partnerSplittingBreakEvenMax: Double = 0

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
    private let kfbPerChild2027: Double = 10_056 // 7.128 KFB + 2.928 BEA
    private let kindergeldPerChild2027: Double = 3_204 // 12 * 267 €

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
            // Apply Rürup sweet-spot up to cap, keeping PV-IAB at 0 €
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

    func applyIabSweetSpot() {
        triggerLightHaptic()
        var next = input
        next.taxOptimizationEnabled = true
        next.solverMode = .manual
        next.pvIabPurchase = min(pvIabMaxPurchase, (result.iabSweetSpotPurchase / 1_000).rounded() * 1_000)
        input = next
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
            return floor(0.42 * x - 11_135.63)
        }
        return floor(0.45 * x - 19_685.63)
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
            // R 34.2 Abs. 1 EStR negative base spillover
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
        let estNoKfb = calcFuenftelESt(rawBaseZve, abfindung: abfindung, isSplitting: isSplitting)
        let kfbTotal = kinderZahl * kfbPerChild2027
        let kgTotal = kinderZahl * kindergeldPerChild2027

        let estWithKfb = kinderZahl > 0
            ? calcFuenftelESt(rawBaseZve - kfbTotal, abfindung: abfindung, isSplitting: isSplitting)
            : estNoKfb

        // § 31 EStG Günstigerprüfung
        let estSaving = estNoKfb - estWithKfb
        let kfbWon = kinderZahl > 0 && (estSaving > kgTotal)
        let estEffective = kfbWon ? (estWithKfb + kgTotal) : estNoKfb

        // § 51a Abs. 2 EStG: Soli & Kirchensteuer always use fictional ESt after KFB
        let soli = calcSolz2027(estWithKfb, isSplitting: isSplitting)
        let church = estWithKfb * churchRate

        let soliNoKfb = calcSolz2027(estNoKfb, isSplitting: isSplitting)
        let churchNoKfb = estNoKfb * churchRate
        let kinderNetGain = (kfbWon ? (estSaving - kgTotal) : 0) + (soliNoKfb - soli) + (churchNoKfb - church)

        return (estEffective + soli + church, estEffective, soli, church, max(0, kinderNetGain), kfbWon)
    }

    private func calcUpfrontPayrollTax(
        agFiktiv: Double,
        taxableAbfindung: Double,
        isSplitting: Bool,
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

        let baseEst = calcTariff2027(baseZve, isSplitting: isSplitting)
        let totalEst = calcTariff2027(baseZve + abf, isSplitting: isSplitting)
        let abfEst = max(0, totalEst - baseEst)

        // § 51a EStG KFB effect on Soli & KiSt
        let kfb = kinderZahl * kfbPerChild2027
        let baseEstKfb = calcTariff2027(max(0, baseZve - kfb), isSplitting: isSplitting)
        let totalEstKfb = calcTariff2027(max(0, baseZve + abf - kfb), isSplitting: isSplitting)

        let abfSoli = max(0, calcSolz2027(totalEstKfb, isSplitting: isSplitting) - calcSolz2027(baseEstKfb, isSplitting: isSplitting))
        let abfChurch = max(0, totalEstKfb - baseEstKfb) * churchRate
        return abfEst + abfSoli + abfChurch
    }

    private func pvEmployeeRate(kinderZahl: Double) -> Double {
        let kids = Int(ceil(kinderZahl))
        if kids == 0 { return 0.024 } // incl. Kinderlosenzuschlag
        if kids == 1 { return 0.018 }
        if kids == 2 { return 0.0155 }
        return 0.013
    }

    private func monthlyNetSalary(annualGross: Double, isSplitting: Bool, churchRate: Double, kinderZahl: Double) -> Double {
        if annualGross <= 0 { return 0 }
        let rv = min(annualGross, bbgRvYear) * 0.093
        let alv = min(annualGross, bbgRvYear) * 0.013
        let kv = min(annualGross, bbgKvYear) * (0.073 + input.kvZusatzbeitragPct / 200.0)
        let pv = min(annualGross, bbgKvYear) * pvEmployeeRate(kinderZahl: kinderZahl)
        let social = rv + alv + kv + pv
        let zve = max(0, annualGross - min(annualGross, anPauschbetrag) - (rv + kv + pv))
        let tax = calcTotalTaxWithKinder(rawBaseZve: zve, abfindung: 0, isSplitting: isSplitting, churchRate: churchRate, kinderZahl: kinderZahl).totalTax
        return max(0, (annualGross - social - tax) / 12.0)
    }

    private func computeOldJobMonths2027(for inp: SimulationInput, sprinter: Bool) -> Int {
        let preExit = max(0, inp.payoutMonth2027 - 1)
        return sprinter ? preExit : min(12, preExit + inp.fristMonate)
    }

    private func computeRuerupCap(for inp: SimulationInput) -> Double {
        let oldMonths = computeOldJobMonths2027(for: inp, sprinter: inp.turboEnabled)
        let totalGross = Double(oldMonths) * inp.altesMonatsgehalt + inp.neuesGehalt2027
        let rvTotal = min(totalGross, bbgRvYear) * 0.186
        let limit = inp.isSplitting ? ruerupMaxSingle * 2.0 : ruerupMaxSingle
        return max(0, limit - rvTotal)
    }

    private func voluntaryGkvMonthly() -> Double {
        if input.preExitGkv == .pkv { return 900 }
        let monthlyBbgKv = bbgKvYear / 12.0
        let pvTotal = input.kinderZahl > 0 ? 0.036 : 0.042
        return monthlyBbgKv * (0.146 + input.kvZusatzbeitragPct / 100.0 + pvTotal)
    }

    private func monthlyAlg1Net() -> Double {
        let cappedMonthly = min(input.altesMonatsgehalt, bbgRvYear / 12.0)
        let netFactor = 0.64 // Simplified statutory SGB III net approximation after 20% SV + LSt
        return cappedMonthly * netFactor * (input.alg1SatzPct / 100.0)
    }

    // MARK: Master Recalculation

    func recalculate() {
        var r = SimulationResult()

        // 1. 2027 Gross Income Split (Auto Alt-AG + Optional New Job)
        let oldMonths = computeOldJobMonths2027(for: input, sprinter: input.turboEnabled)
        let oldGross = Double(oldMonths) * input.altesMonatsgehalt
        let totalGross = oldGross + input.neuesGehalt2027
        r.oldJobMonths2027 = oldMonths
        r.oldJobGross2027 = oldGross
        r.totalGross2027 = totalGross

        // 2. Effective Severance & Sprinter Bonus
        let sprinterBonus = input.turboEnabled
            ? Double(input.fristMonate) * input.altesMonatsgehalt * input.turboFaktor
            : 0
        let effectiveAbf = input.bruttoAbfindung + sprinterBonus
        r.sprinterBonusGross = sprinterBonus
        r.effectiveAbfindung = effectiveAbf

        // 3. Base Deductions & Ruhenszeit GKV
        let rvBase = min(totalGross, bbgRvYear)
        let kvBase = min(totalGross, bbgKvYear)
        let socialDeductibles = rvBase * 0.093 + kvBase * (0.073 + input.kvZusatzbeitragPct / 200.0 + pvEmployeeRate(kinderZahl: input.kinderZahl))
        let anPauschale = min(totalGross, anPauschbetrag)

        let ruhensMonths = input.turboEnabled ? input.fristMonate : 0
        r.ruhenszeitMonths = ruhensMonths
        let billableGkvMonths = (input.preExitGkv == .pflicht) ? max(0, ruhensMonths - 1) : ruhensMonths
        let ruhensGkvTotal = Double(billableGkvMonths) * voluntaryGkvMonthly()

        let partnerZve: Double = {
            guard input.isSplitting && input.partnerGehalt2027 > 0 else { return 0 }
            let pRv = min(input.partnerGehalt2027, bbgRvYear) * 0.093
            let pKv = min(input.partnerGehalt2027, bbgKvYear) * (0.073 + input.kvZusatzbeitragPct / 200.0 + pvEmployeeRate(kinderZahl: input.kinderZahl))
            return max(0, input.partnerGehalt2027 - min(input.partnerGehalt2027, anPauschbetrag) - pRv - pKv)
        }()

        let rawBaseBeforeLevers = totalGross + partnerZve - anPauschale - socialDeductibles - ruhensGkvTotal

        // 4. Rürup Cap & Solver Gate
        let ruerupCap = computeRuerupCap(for: input)
        r.ruerupMaxCap = ruerupCap

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

        // 5. Upfront 2027 Payroll Withholding (bAV & 50% DRV reduce taxable severance before payroll)
        let taxableAbfForPayroll = max(0, effectiveAbf - effBav - effDrv * 0.5)
        let upfrontTax = calcUpfrontPayrollTax(
            agFiktiv: input.agFiktivGehalt,
            taxableAbfindung: taxableAbfForPayroll,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )
        r.upfrontPayrollTax = upfrontTax
        r.sofortNetto2027 = max(0, effectiveAbf - effBav - effDrv - upfrontTax)

        // 6. Final 2028 Finanzamt Assessment (§ 34 Fünftelregelung + R 34.2 + § 31 Kinder + KiSt)
        let taxableAbfFinal = max(0, effectiveAbf - effBav - effDrv * 0.5)
        let rawBaseWithLevers = rawBaseBeforeLevers - effRuerup - (effPv * 0.5)

        let taxBaseOnly = calcTotalTaxWithKinder(
            rawBaseZve: rawBaseBeforeLevers,
            abfindung: 0,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax

        let taxFinalObj = calcTotalTaxWithKinder(
            rawBaseZve: rawBaseWithLevers,
            abfindung: taxableAbfFinal,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )

        let abfTaxFinal = max(0, taxFinalObj.totalTax - taxBaseOnly)
        r.totalTaxFinal = abfTaxFinal
        r.kinderBenefitNet = taxFinalObj.kinderNetGain
        r.kinderFreibetragWon = taxFinalObj.kfbWon

        r.finanzamtRefundOct2028 = upfrontTax - abfTaxFinal
        r.optimalNettoTotal = effectiveAbf - abfTaxFinal
        r.endLiquidity2028 = r.sofortNetto2027 + r.finanzamtRefundOct2028 - effRuerup - ruhensGkvTotal

        // 7. Standalone Lever Attribution & bAV Max-Cap Preview
        // bAV immediate 2027 payroll savings
        let upfrontNoBav = calcUpfrontPayrollTax(
            agFiktiv: input.agFiktivGehalt,
            taxableAbfindung: max(0, effectiveAbf - effDrv * 0.5),
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )
        let bavSav = max(0, upfrontNoBav - upfrontTax)
        r.bavSavings = bavSav
        r.bavSavingsPct = effBav > 0 ? (bavSav / effBav) * 100.0 : 0

        let maxBavCap = min(bavMaxTotal, effectiveAbf)
        let upfrontAtMaxBav = calcUpfrontPayrollTax(
            agFiktiv: input.agFiktivGehalt,
            taxableAbfindung: max(0, effectiveAbf - maxBavCap),
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )
        let upfrontAtZeroBav = calcUpfrontPayrollTax(
            agFiktiv: input.agFiktivGehalt,
            taxableAbfindung: effectiveAbf,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )
        r.bavMaxCapSavings = max(0, upfrontAtZeroBav - upfrontAtMaxBav)
        r.bavMaxCapPct = maxBavCap > 0 ? (r.bavMaxCapSavings / maxBavCap) * 100.0 : 0

        // DRV, Rürup, PV-IAB marginal final tax savings
        let taxNoDrv = calcTotalTaxWithKinder(
            rawBaseZve: rawBaseWithLevers,
            abfindung: max(0, effectiveAbf - effBav),
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax
        r.drvSavings = max(0, taxNoDrv - taxFinalObj.totalTax)
        r.drvSavingsPct = effDrv > 0 ? (r.drvSavings / effDrv) * 100.0 : 0

        let taxNoRuerup = calcTotalTaxWithKinder(
            rawBaseZve: rawBaseWithLevers + effRuerup,
            abfindung: taxableAbfFinal,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax
        r.ruerupSavings = max(0, taxNoRuerup - taxFinalObj.totalTax)
        r.ruerupSavingsPct = effRuerup > 0 ? (r.ruerupSavings / effRuerup) * 100.0 : 0

        let taxNoIab = calcTotalTaxWithKinder(
            rawBaseZve: rawBaseWithLevers + effPv * 0.5,
            abfindung: taxableAbfFinal,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        ).totalTax
        r.iabSavings = max(0, taxNoIab - taxFinalObj.totalTax)
        r.iabSavingsPct = effPv > 0 ? (r.iabSavings / effPv) * 100.0 : 0

        // 8. Exact Binary-Search Splitting Break-Even Partner Gross
        r.partnerSplittingBreakEvenMax = findMaxPartnerGrossForSplitting(
            ownBaseZve: rawBaseBeforeLevers - partnerZve - effRuerup - effPv * 0.5,
            abfindung: taxableAbfFinal
        )

        // 9. Sprinter Waterfall Bridge
        let lostNetSalary = Double(input.fristMonate) * monthlyNetSalary(
            annualGross: input.altesMonatsgehalt * 12.0,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )
        let alg1Loss = input.includeAlg1Loss ? min(Double(input.fristMonate), 12.0 / 4.333) * monthlyAlg1Net() : 0
        let sprinterTaxDelta = max(0, sprinterBonus * 0.36)
        let sprinterNet = sprinterBonus - sprinterTaxDelta - lostNetSalary - ruhensGkvTotal - alg1Loss
        r.sprinterNetGain = sprinterNet
        r.waterfallSteps = [
            WaterfallStep(label: "Sprinter-Prämie", delta: sprinterBonus, isTotal: false),
            WaterfallStep(label: "Steuer-Effekt", delta: -sprinterTaxDelta, isTotal: false),
            WaterfallStep(label: "Entg. Netto-Gehalt", delta: -lostNetSalary, isTotal: false),
            WaterfallStep(label: "GKV Ruhenszeit", delta: -ruhensGkvTotal, isTotal: false),
            WaterfallStep(label: "ALG-1 Kürzung", delta: -alg1Loss, isTotal: false),
            WaterfallStep(label: "Sprinter-Bilanz", delta: sprinterNet, isTotal: true)
        ]

        // 10. Section C: Reichweite (Standard vs. Sprinter)
        computeReichweite(into: &r, effBav: effBav, effDrv: effDrv, effRuerup: effRuerup, effPv: effPv)

        // 11. Section D: Job-Switch / Break-Even (Standard vs. Sprinter)
        computeJobSwitch(into: &r, effBav: effBav, effDrv: effDrv, effRuerup: effRuerup, effPv: effPv)

        self.result = r
    }

    private func findMaxPartnerGrossForSplitting(ownBaseZve: Double, abfindung: Double) -> Double {
        var lo = 0.0
        var hi = 250_000.0
        for _ in 0..<22 {
            let mid = (lo + hi) / 2.0
            let pRv = min(mid, bbgRvYear) * 0.093
            let pKv = min(mid, bbgKvYear) * (0.073 + input.kvZusatzbeitragPct / 200.0 + pvEmployeeRate(kinderZahl: input.kinderZahl))
            let pZve = max(0, mid - min(mid, anPauschbetrag) - pRv - pKv)

            let joint = calcTotalTaxWithKinder(
                rawBaseZve: ownBaseZve + pZve,
                abfindung: abfindung,
                isSplitting: true,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            ).totalTax

            let sepOwn = calcTotalTaxWithKinder(
                rawBaseZve: ownBaseZve,
                abfindung: abfindung,
                isSplitting: false,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            ).totalTax
            let sepPartner = calcTotalTaxWithKinder(
                rawBaseZve: pZve,
                abfindung: 0,
                isSplitting: false,
                churchRate: input.churchRate,
                kinderZahl: 0
            ).totalTax

            if joint <= (sepOwn + sepPartner) {
                lo = mid
            } else {
                hi = mid
            }
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

    private func computeReichweite(into r: inout SimulationResult, effBav: Double, effDrv: Double, effRuerup: Double, effPv: Double) {
        let alg1 = monthlyAlg1Net()
        let postGkv: Double = {
            switch input.postAlg1GkvMode {
            case .mindestbeitrag: return 280
            case .familienversicherung: return 0
            case .individuell: return input.customPostGkvMonthly
            }
        }()
        let netSalMonthly = monthlyNetSalary(
            annualGross: input.altesMonatsgehalt * 12.0,
            isSplitting: input.isSplitting,
            churchRate: input.churchRate,
            kinderZahl: input.kinderZahl
        )
        let monthlyRate = input.realReturnPct / 100.0 / 12.0
        let startOffset = max(0, input.payoutMonth2027 - 1)
        let faOffset = 21 - startOffset // Oct 2028 = month index 21 from Jan 2027
        r.faRefundMonthIndex = Double(max(1, faOffset))

        func simulateRunway(isSprinter: Bool) -> (months: Double, alg1End: Int, bridgeSafe: Bool, series: [Double], bars: [RunwayPhaseBar]) {
            let label = isSprinter ? "Sprinter" : "Standard"
            let abfGross = input.bruttoAbfindung + (isSprinter ? Double(input.fristMonate) * input.altesMonatsgehalt * input.turboFaktor : 0)
            let taxPay = calcUpfrontPayrollTax(
                agFiktiv: input.agFiktivGehalt,
                taxableAbfindung: max(0, abfGross - effBav - effDrv * 0.5),
                isSplitting: input.isSplitting,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            )
            let sofort = max(0, abfGross - effBav - effDrv - taxPay)

            let salMonths27 = computeOldJobMonths2027(for: input, sprinter: isSprinter)
            let gross27 = Double(salMonths27) * input.altesMonatsgehalt
            let rv27 = min(gross27, bbgRvYear) * 0.093
            let kv27 = min(gross27, bbgKvYear) * (0.073 + input.kvZusatzbeitragPct / 200.0 + pvEmployeeRate(kinderZahl: input.kinderZahl))
            let ruhens = isSprinter ? input.fristMonate : 0
            let billableGkv = (input.preExitGkv == .pflicht) ? max(0, ruhens - 1) : ruhens
            let ruhensGkv = Double(billableGkv) * voluntaryGkvMonthly()
            let baseZve = gross27 - min(gross27, anPauschbetrag) - rv27 - kv27 - ruhensGkv

            let baseTax = calcTotalTaxWithKinder(rawBaseZve: baseZve, abfindung: 0, isSplitting: input.isSplitting, churchRate: input.churchRate, kinderZahl: input.kinderZahl).totalTax
            let finalTax = calcTotalTaxWithKinder(rawBaseZve: baseZve - effRuerup - effPv * 0.5, abfindung: max(0, abfGross - effBav - effDrv * 0.5), isSplitting: input.isSplitting, churchRate: input.churchRate, kinderZahl: input.kinderZahl).totalTax
            let faRefund = max(0, taxPay - max(0, finalTax - baseTax))

            var cash = max(0, sofort - effRuerup - input.upfrontSpend2027)
            let noticePhase = isSprinter ? 0 : input.fristMonate
            let alg1Dur = isSprinter && input.includeAlg1Loss
                ? max(0, input.alg1ClaimMonths - Int((12.0 / 4.333).rounded()))
                : input.alg1ClaimMonths

            var series: [Double] = [cash]
            var bridgeSafe = true
            var depletedMonth: Double = 72

            for m in 1...72 {
                if m == max(1, faOffset) {
                    cash += faRefund
                }
                if m <= noticePhase {
                    if input.includeSalarySurplus {
                        cash += max(0, netSalMonthly - input.monthlyExpenses)
                    }
                } else if m <= noticePhase + ruhens {
                    let gkvThisMonth = (input.preExitGkv == .pflicht && m == noticePhase + 1) ? 0 : voluntaryGkvMonthly()
                    cash -= (input.monthlyExpenses + gkvThisMonth)
                } else if m <= noticePhase + ruhens + alg1Dur {
                    cash -= max(0, input.monthlyExpenses - alg1)
                } else {
                    cash -= (input.monthlyExpenses + postGkv)
                }

                if cash > 0 {
                    cash *= (1.0 + monthlyRate)
                }
                if m < max(1, faOffset) && cash < 0 {
                    bridgeSafe = false
                }
                if cash <= 0 && depletedMonth == 72 {
                    depletedMonth = Double(m)
                }
                series.append(max(0, cash))
            }

            var bars: [RunwayPhaseBar] = []
            var cursor = 0.0
            if noticePhase > 0 {
                let end = min(depletedMonth, cursor + Double(noticePhase))
                bars.append(RunwayPhaseBar(strategy: label, phase: "Gehalt/Frist", startMonth: cursor, endMonth: end, colorName: "blue"))
                cursor = end
            }
            if ruhens > 0 && cursor < depletedMonth {
                let end = min(depletedMonth, cursor + Double(ruhens))
                bars.append(RunwayPhaseBar(strategy: label, phase: "Ruhenszeit", startMonth: cursor, endMonth: end, colorName: "orange"))
                cursor = end
            }
            if alg1Dur > 0 && cursor < depletedMonth {
                let end = min(depletedMonth, cursor + Double(alg1Dur))
                bars.append(RunwayPhaseBar(strategy: label, phase: "ALG 1", startMonth: cursor, endMonth: end, colorName: "cyan"))
                cursor = end
            }
            if cursor < depletedMonth {
                bars.append(RunwayPhaseBar(strategy: label, phase: "Privatier", startMonth: cursor, endMonth: depletedMonth, colorName: "green"))
            }

            let alg1End = startOffset + noticePhase + ruhens + alg1Dur
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
            pts.append(DualSeriesPoint(x: Double(m), standardVal: std.series[m], sprinterVal: spr.series[m]))
        }
        r.runwayCurve = pts
    }

    private func computeJobSwitch(into r: inout SimulationResult, effBav: Double, effDrv: Double, effRuerup: Double, effPv: Double) {
        let oldAnnual = input.altesMonatsgehalt * 12.0
        let newAnnual = input.switchNewAnnualGross
        let growth = input.switchAnnualGrowthPct / 100.0
        let alg1 = monthlyAlg1Net()

        func simulateSwitch(isSprinter: Bool) -> (curve: [Double], breakEvenYear: Double?) {
            let abfGross = input.bruttoAbfindung + (isSprinter ? Double(input.fristMonate) * input.altesMonatsgehalt * input.turboFaktor : 0)
            let taxPay = calcUpfrontPayrollTax(
                agFiktiv: input.agFiktivGehalt,
                taxableAbfindung: max(0, abfGross - effBav - effDrv * 0.5),
                isSplitting: input.isSplitting,
                churchRate: input.churchRate,
                kinderZahl: input.kinderZahl
            )
            let sofort = max(0, abfGross - effBav - effDrv - taxPay)
            let salMonths27 = computeOldJobMonths2027(for: input, sprinter: isSprinter)
            let gross27 = Double(salMonths27) * input.altesMonatsgehalt
            let rv27 = min(gross27, bbgRvYear) * 0.093
            let kv27 = min(gross27, bbgKvYear) * (0.073 + input.kvZusatzbeitragPct / 200.0 + pvEmployeeRate(kinderZahl: input.kinderZahl))
            let ruhens = isSprinter ? input.fristMonate : 0
            let billableGkv = (input.preExitGkv == .pflicht) ? max(0, ruhens - 1) : ruhens
            let ruhensGkv = Double(billableGkv) * voluntaryGkvMonthly()
            let baseZve = gross27 - min(gross27, anPauschbetrag) - rv27 - kv27 - ruhensGkv
            let baseTax = calcTotalTaxWithKinder(rawBaseZve: baseZve, abfindung: 0, isSplitting: input.isSplitting, churchRate: input.churchRate, kinderZahl: input.kinderZahl).totalTax
            let finalTax = calcTotalTaxWithKinder(rawBaseZve: baseZve - effRuerup - effPv * 0.5, abfindung: max(0, abfGross - effBav - effDrv * 0.5), isSplitting: input.isSplitting, churchRate: input.churchRate, kinderZahl: input.kinderZahl).totalTax
            let faRefund = max(0, taxPay - max(0, finalTax - baseTax))

            var delta = sofort - effRuerup - ruhensGkv
            var curve: [Double] = [delta]
            var breakEven: Double? = nil

            for yr in 1...15 {
                if yr == 2 { delta += faRefund }
                let oldNetYr = monthlyNetSalary(annualGross: oldAnnual * pow(1.0 + growth, Double(yr - 1)), isSplitting: input.isSplitting, churchRate: input.churchRate, kinderZahl: input.kinderZahl) * 12.0
                let newNetYr = monthlyNetSalary(annualGross: newAnnual * pow(1.0 + growth, Double(yr - 1)), isSplitting: input.isSplitting, churchRate: input.churchRate, kinderZahl: input.kinderZahl) * 12.0

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
        r.switchDeltaYear5Std = std.curve[5]
        r.switchDeltaYear5Spr = spr.curve[5]
        r.switchDeltaYear10Std = std.curve[10]
        r.switchDeltaYear10Spr = spr.curve[10]

        var pts: [DualSeriesPoint] = []
        for y in 0...15 {
            pts.append(DualSeriesPoint(x: Double(y), standardVal: std.curve[y], sprinterVal: spr.curve[y]))
        }
        r.switchCurve = pts
    }
}

// MARK: - Root 5-Tab Navigation Container

struct MainTabContainerView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @AppStorage("abfindungs_theme") private var themeMode: String = "dark"
    @State private var selectedTab: Int = 0
    @State private var selectedInfoTopic: StatutoryTopic?
    @State private var showPdfSheet = false
    @State private var pdfURL: URL?

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
                    .navigationTitle("AbfindungsPilot")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { sharedToolbar }
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
                ResultsTabView(selectedInfoTopic: $selectedInfoTopic, onExportPDF: generatePDFReport)
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
        .sheet(isPresented: $showPdfSheet) {
            if let pdfURL {
                ShareSheet(items: [pdfURL])
            }
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
                generatePDFReport()
            } label: {
                Image(systemName: "doc.richtext")
            }
        }
    }

    private func generatePDFReport() {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AbfindungsPilot_2027_Report.pdf")
        let inp = engine.input
        let res = engine.result

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 18),
                    .foregroundColor: UIColor.label
                ]
                let subAttrs: [NSAttributedString.Key: Any] = [
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

                "AbfindungsPilot 2027 – Executive Summary (v27.1)".draw(at: CGPoint(x: 40, y: 36), withAttributes: titleAttrs)
                "1. Kernergebnisse & 2027 Einkommen".draw(at: CGPoint(x: 40, y: 70), withAttributes: subAttrs)

                let block1 = """
                Basis-Abfindung Brutto: \(eur(inp.bruttoAbfindung))  |  Effektiv (inkl. Sprinter): \(eur(res.effectiveAbfindung))
                2027 Brutto gesamt: \(eur(res.totalGross2027)) (\(res.oldJobMonths2027) Mon. Alt-AG \(eur(res.oldJobGross2027)) + Neu-Job \(eur(inp.neuesGehalt2027)))
                Tarif: \(inp.isSplitting ? "Splittingtarif" : "Grundtarif")  |  Kinderfreibeträge: \(String(format: "%.1f", inp.kinderZahl))  |  Kirchensteuer: \(pct(inp.churchRate * 100))

                • Sofort-Netto 2027 (nach AG-Einbehalt): \(eur(res.sofortNetto2027))
                • Finanzamt-Erstattung Okt. 2028 (§ 34 EStG): \(eur(res.finanzamtRefundOct2028, showPlus: true))
                • Optimal-Netto Gesamt: \(eur(res.optimalNettoTotal))
                • End-Liquidität Ende 2028: \(eur(res.endLiquidity2028))
                """
                block1.draw(in: CGRect(x: 40, y: 92, width: 515, height: 145), withAttributes: bodyAttrs)

                "2. Steuer-Optimierung (§§ 3 Nr. 63, 10, 7g EStG & V0210)".draw(at: CGPoint(x: 40, y: 245), withAttributes: subAttrs)
                let block2 = """
                • bAV-Umwandlung: \(eur(res.solvedBav))  →  Sofort-Ersparnis 2027: \(eur(res.bavSavings, showPlus: true)) (\(pct(res.bavSavingsPct)))
                • DRV V0210 (AG-Direkt): \(eur(res.solvedDrv))  →  Steuer-Ersparnis: \(eur(res.drvSavings, showPlus: true)) (\(pct(res.drvSavingsPct)))
                • Rürup / Basisrente: \(eur(res.solvedRuerup))  →  Steuer-Ersparnis: \(eur(res.ruerupSavings, showPlus: true)) (\(pct(res.ruerupSavingsPct)))
                • PV-IAB (50 % Abzug): \(eur(res.solvedPvPurchase))  →  Steuer-Ersparnis: \(eur(res.iabSavings, showPlus: true)) (\(pct(res.iabSavingsPct)))
                """
                block2.draw(in: CGRect(x: 40, y: 267, width: 515, height: 95), withAttributes: bodyAttrs)

                "3. Reichweite & Gehalts-Switch Break-Even".draw(at: CGPoint(x: 40, y: 375), withAttributes: subAttrs)
                let stdBe = res.breakEvenYearStandard.map { String(format: "%.1f J.", $0) } ?? "> 15 J."
                let sprBe = res.breakEvenYearSprinter.map { String(format: "%.1f J.", $0) } ?? "> 15 J."
                let block3 = """
                • Reichweite Standard (Frist): \(String(format: "%.0f", res.standardRunwayMonths)) Mon. (bis \(res.standardDepletionDate))
                • Reichweite Sprinter (Sofort): \(String(format: "%.0f", res.sprinterRunwayMonths)) Mon. (bis \(res.sprinterDepletionDate))
                • Gehalts-Switch (\(eur(inp.switchNewAnnualGross))/J.): Standard \(stdBe)  |  Sprinter \(sprBe)
                """
                block3.draw(in: CGRect(x: 40, y: 397, width: 515, height: 75), withAttributes: bodyAttrs)

                let disclaimer = "Hinweis (§ 2 StBerG): Unverbindliche mathematische Modellrechnung auf Basis der gesetzlichen Rechengrößen 2027. Keine Steuer- oder Rechtsberatung."
                disclaimer.draw(in: CGRect(x: 40, y: 780, width: 515, height: 40), withAttributes: footAttrs)
            }
            self.pdfURL = url
            self.showPdfSheet = true
        } catch {
            print("PDF export error: \(error)")
        }
    }
}

// MARK: - Sticky Bottom KPI Bar (Orange Sofort / Green FA / Blue Optimal)

struct StickyKPIBar: View {
    @EnvironmentObject var engine: TaxEngineHost

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                kpiCol(title: "Sofort 2027", value: eur(engine.result.sofortNetto2027), color: .orange)
                Divider().frame(height: 28)
                kpiCol(title: "FA Okt. 2028", value: eur(engine.result.finanzamtRefundOct2028, showPlus: true), color: .green)
                Divider().frame(height: 28)
                kpiCol(title: "Optimal-Netto", value: eur(engine.result.optimalNettoTotal), color: .blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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

// MARK: - Reusable Compact Slider Row (iPhone 15–17 Typography Scale)

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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 2) {
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
                    }
                }
                Spacer(minLength: 6)
                Text(valueFormatter(value))
                    .font(.subheadline.bold())
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tab 1: Eingaben (Clean Basisdaten, Familie, Kinder, KiSt & Sprinter)

struct InputsTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var selectedInfoTopic: StatutoryTopic?

    private let kinderOptions: [Double] = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
    private let monthNames = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]

    var body: some View {
        Form {
            // Quick Presets
            Section {
                HStack(spacing: 8) {
                    presetBtn("Standard", icon: "doc.text", key: "standard", tint: .blue)
                    presetBtn("Sprinter", icon: "bolt.fill", key: "sprinter", tint: .orange)
                    presetBtn("Privatier", icon: "sun.horizon.fill", key: "privatier", tint: .green)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            } header: {
                Text("Schnell-Szenarien (ohne PV-IAB)").font(.caption.weight(.semibold))
            }

            // Section A: Basisdaten & 2027 Einkommen
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

                HStack {
                    Text("Austrittsmonat 2027")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("", selection: $engine.input.payoutMonth2027) {
                        ForEach(1...12, id: \.self) { m in
                            Text("\(monthNames[m - 1]) 2027").tag(m)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Stepper(value: $engine.input.fristMonate, in: 1...12) {
                    HStack {
                        Text("Kündigungsfrist")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(engine.input.fristMonate) Mon.")
                            .font(.subheadline.bold())
                            .monospacedDigit()
                    }
                }

                CompactSliderRow(
                    title: "AG-Fiktivgehalt (LSt)",
                    topic: .agFiktiv,
                    selectedInfoTopic: $selectedInfoTopic,
                    value: $engine.input.agFiktivGehalt,
                    range: 30_000...200_000,
                    step: 2_500
                )

                CompactSliderRow(
                    title: "Zusätzl. Gehalt 2027 (Neu-Job)",
                    subtitle: "Nur zusätzliches Brutto aus neuem Job in 2027",
                    selectedInfoTopic: $selectedInfoTopic,
                    value: $engine.input.neuesGehalt2027,
                    range: 0...150_000,
                    step: 2_500
                )

                // Live Auto-Calculated 2027 Gross Summary
                HStack {
                    Image(systemName: "sum")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("2027 Brutto gesamt: \(eur(engine.result.oldJobGross2027)) Alt-AG (\(engine.result.oldJobMonths2027) M.) + \(eur(engine.input.neuesGehalt2027)) Neu-Job")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("A · Basisdaten & 2027 Einkommen").font(.caption.weight(.semibold))
            }

            // Familie, Kinder & Kirchensteuer
            Section {
                HStack {
                    Text("Steuertarif")
                        .font(.subheadline.weight(.medium))
                    InfoIconButton(topic: .tarifSplitting, selectedTopic: $selectedInfoTopic)
                    Spacer()
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
                        subtitle: "Splitting-Vorteil bis ca. \(eur(engine.result.partnerSplittingBreakEvenMax))",
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.partnerGehalt2027,
                        range: 0...150_000,
                        step: 2_500
                    )
                }

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Kinderfreibeträge")
                            .font(.subheadline.weight(.medium))
                        Text("ALG 1: \(Int(engine.input.alg1SatzPct)) % · § 31 Günstigerprüfung")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $engine.input.kinderZahl) {
                        ForEach(kinderOptions, id: \.self) { k in
                            Text(k == floor(k) ? "\(Int(k))" : String(format: "%.1f", k).replacingOccurrences(of: ".", with: ","))
                                .tag(k)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Kirchensteuer")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("", selection: $engine.input.churchRate) {
                        ForEach(ChurchTaxOption.allCases) { opt in
                            Text(opt.shortLabel).tag(opt.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 215)
                }

                HStack {
                    Text("GKV vor Austritt")
                        .font(.subheadline.weight(.medium))
                    InfoIconButton(topic: .preExitGkv, selectedTopic: $selectedInfoTopic)
                    Spacer()
                    Picker("", selection: $engine.input.preExitGkv) {
                        ForEach(PreExitGkvStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Familie, Kinder & Steuern").font(.caption.weight(.semibold))
            }

            // Sprinter Option
            Section {
                Toggle(isOn: $engine.input.turboEnabled) {
                    HStack(spacing: 4) {
                        Text("Sprinter-Option (Sofort-Austritt)")
                            .font(.subheadline.weight(.medium))
                        InfoIconButton(topic: .sprinterLegal, selectedTopic: $selectedInfoTopic)
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
                        HStack(spacing: 4) {
                            Text("ALG-1 Sperrzeit abziehen (max. 12 Wo.)")
                                .font(.subheadline.weight(.medium))
                            InfoIconButton(topic: .alg1Rules, selectedTopic: $selectedInfoTopic)
                        }
                    }
                }
            } header: {
                Text("Vorzeitiger Austritt").font(.caption.weight(.semibold))
            }
        }
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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(tint.opacity(0.14))
                .foregroundStyle(tint)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 2: Steuer-Optimierung (Dedicated Tab with Hard Reset & bAV Max Return)

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
                    Picker("Auto-Solver", selection: Binding(
                        get: { engine.input.solverMode },
                        set: { mode in
                            triggerLightHaptic()
                            engine.input.solverMode = mode
                        }
                    )) {
                        ForEach(SolverMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Optimierungs-Modus").font(.caption.weight(.semibold))
                }

                // 1. bAV (§ 3 Nr. 63 EStG) with Live + Max-Cap Return Amount & %
                Section {
                    CompactSliderRow(
                        title: "1. bAV-Umwandlung",
                        subtitle: "Max. \(eur(engine.bavMaxTotal)) → bis zu \(eur(engine.result.bavMaxCapSavings, showPlus: true)) (\(pct(engine.result.bavMaxCapPct)))",
                        topic: .bav63,
                        selectedInfoTopic: $selectedInfoTopic,
                        value: Binding(
                            get: { engine.result.solvedBav },
                            set: {
                                engine.input.solverMode = .manual
                                engine.input.bavAmount = $0
                            }
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

                // 2. DRV V0210
                Section {
                    CompactSliderRow(
                        title: "2. DRV-Ausgleich (V0210)",
                        subtitle: "50 % steuerfrei (§ 3 Nr. 28) · 50 % Fünftel",
                        topic: .drvV0210,
                        selectedInfoTopic: $selectedInfoTopic,
                        value: Binding(
                            get: { engine.result.solvedDrv },
                            set: {
                                engine.input.solverMode = .manual
                                engine.input.drvV0210Amount = $0
                            }
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

                // 3. Rürup / Basisrente
                Section {
                    CompactSliderRow(
                        title: "3. Rürup / Basisrente",
                        subtitle: "Frei: \(eur(engine.result.ruerupCapRemaining)) von \(eur(engine.result.ruerupMaxCap))",
                        topic: .ruerup10,
                        selectedInfoTopic: $selectedInfoTopic,
                        value: Binding(
                            get: { engine.result.solvedRuerup },
                            set: {
                                engine.input.solverMode = .manual
                                engine.input.ruerupAmount = $0
                            }
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
                }

                // 4. PV-IAB (§ 7g EStG)
                Section {
                    CompactSliderRow(
                        title: "4. PV-Investition (50 % IAB)",
                        subtitle: "Abzug 2027: \(eur(engine.result.solvedPvPurchase * 0.5)) · 0 € Cash 2027",
                        topic: .pvIab7g,
                        selectedInfoTopic: $selectedInfoTopic,
                        value: Binding(
                            get: { engine.result.solvedPvPurchase },
                            set: {
                                engine.input.solverMode = .manual
                                engine.input.pvIabPurchase = $0
                            }
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

// MARK: - Tab 3: Ergebnis (4-Card KPI Grid, Lever Cards, Cashflow & Sprinter Waterfall)

struct ResultsTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var selectedInfoTopic: StatutoryTopic?
    let onExportPDF: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 4-Card KPI Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    kpiCard("Sofort-Netto 2027", value: eur(engine.result.sofortNetto2027), subtitle: "nach AG-Einbehalt", color: .orange)
                    kpiCard("FA-Erstattung Okt. 28", value: eur(engine.result.finanzamtRefundOct2028, showPlus: true), subtitle: "§ 34 Fünftelregelung", color: .green)
                    kpiCard("Optimal-Netto Gesamt", value: eur(engine.result.optimalNettoTotal), subtitle: "Steuerlast: \(eur(engine.result.totalTaxFinal))", color: .blue)
                    kpiCard("End-Liquidität 2028", value: eur(engine.result.endLiquidity2028), subtitle: "Konto nach Hebeln", color: .purple)
                }

                // Steuer-Hebel Value Cards
                if engine.input.taxOptimizationEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STEUER-HEBEL ERSPARNIS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            leverMiniCard("bAV (Sofort 2027)", amount: engine.result.bavSavings, pctVal: engine.result.bavSavingsPct, color: .blue)
                            leverMiniCard("DRV V0210", amount: engine.result.drvSavings, pctVal: engine.result.drvSavingsPct, color: .teal)
                            leverMiniCard("Rürup (§ 10)", amount: engine.result.ruerupSavings, pctVal: engine.result.ruerupSavingsPct, color: .indigo)
                            leverMiniCard("PV-IAB (§ 7g)", amount: engine.result.iabSavings, pctVal: engine.result.iabSavingsPct, color: .green)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // Cashflow Comparison Bar Chart
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
                    .frame(height: 180)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Sprinter Waterfall Chart
                if engine.input.turboEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sprinter Netto-Brücke")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(eur(engine.result.sprinterNetGain, showPlus: true))
                                .font(.subheadline.bold())
                                .monospacedDigit()
                                .foregroundStyle(engine.result.sprinterNetGain >= 0 ? .green : .red)
                        }
                        Chart(engine.result.waterfallSteps) { step in
                            BarMark(
                                x: .value("Betrag", step.delta),
                                y: .value("Position", step.label)
                            )
                            .foregroundStyle(step.isTotal ? Color.blue : (step.delta >= 0 ? Color.green : Color.orange))
                        }
                        .frame(height: 190)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // Breakdown Table
                VStack(alignment: .leading, spacing: 8) {
                    Text("DETAILS · ABRECHNUNG 2027 / 2028")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    detailRow("2027 Brutto (Alt-AG + Neu-Job)", eur(engine.result.totalGross2027))
                    detailRow("AG Lohnsteuer-Einbehalt 2027", eur(-engine.result.upfrontPayrollTax))
                    detailRow("Endgültige Steuerlast (§ 34 EStG)", eur(-engine.result.totalTaxFinal))
                    if engine.input.kinderZahl > 0 {
                        detailRow(
                            "Kinder-Vorteil (\(engine.result.kinderFreibetragWon ? "KFB gewinnt" : "KiG + Soli/KiSt"))",
                            eur(engine.result.kinderBenefitNet, showPlus: true)
                        )
                    }
                    if engine.input.churchRate > 0 {
                        detailRow("Kirchensteuer-Satz aktiv", pct(engine.input.churchRate * 100))
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Button(action: onExportPDF) {
                    Label("A4 PDF-Report teilen", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
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
        .padding(12)
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

    private func detailRow(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(right).font(.caption.bold()).monospacedDigit()
        }
    }
}

// MARK: - Tab 4: Reichweite (Inputs First → KPIs → Phase Bars → Multi-Layer Area Chart)

struct ReichweiteTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var selectedInfoTopic: StatutoryTopic?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 1. Inputs Card First
                VStack(alignment: .leading, spacing: 10) {
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
                        title: "Einmal-Abfluss 2027 (Kredit/Puffer)",
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.upfrontSpend2027,
                        range: 0...80_000,
                        step: 1_000
                    )

                    Stepper(value: $engine.input.alg1ClaimMonths, in: 6...24, step: 3) {
                        HStack {
                            Text("ALG-1 Anspruch (\(Int(engine.input.alg1SatzPct)) %)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(engine.input.alg1ClaimMonths) Mon.")
                                .font(.subheadline.bold())
                                .monospacedDigit()
                        }
                    }

                    HStack {
                        Text("GKV nach ALG 1")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Picker("", selection: $engine.input.postAlg1GkvMode) {
                            ForEach(PostAlg1GkvMode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    CompactSliderRow(
                        title: "Real-Zins / Inflation p.a.",
                        selectedInfoTopic: $selectedInfoTopic,
                        value: $engine.input.realReturnPct,
                        range: -3.0...6.0,
                        step: 0.5,
                        valueFormatter: { pct($0) }
                    )

                    Toggle("Gehalts-Überschuss in Frist sparen", isOn: $engine.input.includeSalarySurplus)
                        .font(.subheadline.weight(.medium))
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // 2. KPI Comparison Strip
                HStack(spacing: 10) {
                    runwayKpi("Standard (Frist)", months: engine.result.standardRunwayMonths, date: engine.result.standardDepletionDate, color: .orange)
                    runwayKpi("Sprinter (Sofort)", months: engine.result.sprinterRunwayMonths, date: engine.result.sprinterDepletionDate, color: .green)
                }

                // 3. Stacked Phase Bar Chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lebensphasen-Zeitstrahl (Monate)")
                        .font(.subheadline.weight(.semibold))
                    Chart(engine.result.runwayPhaseBars) { bar in
                        BarMark(
                            xStart: .value("Start", bar.startMonth),
                            xEnd: .value("Ende", bar.endMonth),
                            y: .value("Strategie", bar.strategy)
                        )
                        .foregroundStyle(by: .value("Phase", bar.phase))
                        .cornerRadius(4)
                    }
                    .chartForegroundStyleScale([
                        "Gehalt/Frist": Color.blue,
                        "Ruhenszeit": Color.orange,
                        "ALG 1": Color.cyan,
                        "Privatier": Color.green
                    ])
                    .frame(height: 130)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // 4. Multi-Layer Filled Area Konto-Verlauf Chart
                MultiLayerAreaChartCard(
                    title: "Konto-Verlauf (€)",
                    xAxisLabel: "Monate ab Austritt",
                    points: engine.result.runwayCurve,
                    faMarkerX: engine.result.faRefundMonthIndex,
                    showZeroBaseline: false,
                    stdCrossX: engine.result.standardRunwayMonths < 72 ? engine.result.standardRunwayMonths : nil,
                    sprCrossX: engine.result.sprinterRunwayMonths < 72 ? engine.result.sprinterRunwayMonths : nil
                )

                // 5. Milestone Table
                VStack(alignment: .leading, spacing: 6) {
                    Text("MEILENSTEINE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    milestoneRow("ALG 1 endet", std: engine.result.standardAlg1EndDate, spr: engine.result.sprinterAlg1EndDate)
                    milestoneRow("Geld aufgebraucht", std: engine.result.standardDepletionDate, spr: engine.result.sprinterDepletionDate)
                    milestoneRow("Okt. 2028 Brücke", std: engine.result.standardBridgeSafe ? "Sicher" : "Engpass", spr: engine.result.sprinterBridgeSafe ? "Sicher" : "Engpass")
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding()
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
        .padding(12)
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

// MARK: - Tab 5: Job-Switch (Inputs First → KPIs → Matching Multi-Layer Filled Area Chart)

struct JobSwitchTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var selectedInfoTopic: StatutoryTopic?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 1. Inputs Card First
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
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // 2. Break-Even KPI Comparison Cards
                HStack(spacing: 10) {
                    beCard("Standard Break-Even", year: engine.result.breakEvenYearStandard, color: .orange)
                    beCard("Sprinter Break-Even", year: engine.result.breakEvenYearSprinter, color: .green)
                }

                // 3. Multi-Layer Filled Area Chart (Matching Reichweite)
                MultiLayerAreaChartCard(
                    title: "Vermögens-Vorsprung (€ vs. Alt-Job)",
                    xAxisLabel: "Jahre",
                    points: engine.result.switchCurve,
                    faMarkerX: 2.0,
                    showZeroBaseline: true,
                    stdCrossX: engine.result.breakEvenYearStandard,
                    sprCrossX: engine.result.breakEvenYearSprinter
                )

                // 4. Break-Even Milestone Table
                VStack(alignment: .leading, spacing: 6) {
                    Text("VERGLEICH NACH JAHREN")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    switchRow("Nach 5 Jahren", std: engine.result.switchDeltaYear5Std, spr: engine.result.switchDeltaYear5Spr)
                    switchRow("Nach 10 Jahren", std: engine.result.switchDeltaYear10Std, spr: engine.result.switchDeltaYear10Spr)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func beCard(_ title: String, year: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(year.map { String(format: "%.1f Jahre", $0).replacingOccurrences(of: ".", with: ",") } ?? "> 15 Jahre")
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(color)
            Text(year == nil ? "Dauerhaft im Plus" : "0 € Schwelle erreicht")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
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

// MARK: - Shared Multi-Layer Filled Area Chart (Reichweite & Switch)

struct MultiLayerAreaChartCard: View {
    let title: String
    let xAxisLabel: String
    let points: [DualSeriesPoint]
    let faMarkerX: Double
    let showZeroBaseline: Bool
    let stdCrossX: Double?
    let sprCrossX: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Chart {
                ForEach(points) { pt in
                    // Shared minimum blue fill
                    AreaMark(
                        x: .value(xAxisLabel, pt.x),
                        yStart: .value("Base", 0),
                        yEnd: .value("Shared", pt.sharedMin)
                    )
                    .foregroundStyle(Color.blue.opacity(0.18))

                    // Sprinter ahead green delta band
                    AreaMark(
                        x: .value(xAxisLabel, pt.x),
                        yStart: .value("SprLow", pt.sprinterAheadLow),
                        yEnd: .value("SprHigh", pt.sprinterAheadHigh)
                    )
                    .foregroundStyle(Color.green.opacity(0.28))

                    // Standard ahead orange delta band
                    AreaMark(
                        x: .value(xAxisLabel, pt.x),
                        yStart: .value("StdLow", pt.standardAheadLow),
                        yEnd: .value("StdHigh", pt.standardAheadHigh)
                    )
                    .foregroundStyle(Color.orange.opacity(0.28))

                    // Solid trajectory lines
                    LineMark(
                        x: .value(xAxisLabel, pt.x),
                        y: .value("Standard", pt.standardVal),
                        series: .value("Linie", "Standard")
                    )
                    .foregroundStyle(Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    LineMark(
                        x: .value(xAxisLabel, pt.x),
                        y: .value("Sprinter", pt.sprinterVal),
                        series: .value("Linie", "Sprinter")
                    )
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                // FA Okt. 2028 vertical dashed purple marker
                RuleMark(x: .value("FA Okt. 2028", faMarkerX))
                    .foregroundStyle(Color.purple.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                // Optional 0 € Break-Even horizontal line
                if showZeroBaseline {
                    RuleMark(y: .value("Break-Even", 0))
                        .foregroundStyle(Color.red.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }

                // Zero-crossing dots
                if let stdX = stdCrossX {
                    PointMark(x: .value(xAxisLabel, stdX), y: .value("Null", 0))
                        .foregroundStyle(Color.orange)
                        .symbolSize(55)
                }
                if let sprX = sprCrossX {
                    PointMark(x: .value(xAxisLabel, sprX), y: .value("Null", 0))
                        .foregroundStyle(Color.green)
                        .symbolSize(55)
                }
            }
            .frame(height: 215)

            // Compact Legend
            HStack(spacing: 12) {
                legendDot("Gemeinsam", color: .blue)
                legendDot("Sprinter vorn", color: .green)
                legendDot("Standard vorn", color: .orange)
                legendDot("FA Okt. 28", color: .purple)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
