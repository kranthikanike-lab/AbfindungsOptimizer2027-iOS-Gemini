import SwiftUI
import Charts

// MARK: - Data Models (2027 Statutory Engine)

enum SolverMode: String, CaseIterable, Identifiable {
    case manual = "Manuell"
    case optimal = "Optimal-Netto"
    case liquidity = "Liquiditäts-Fokus"
    case retirement = "Altersvorsorge"
    case custom = "Eigene Priorität"
    var id: String { rawValue }
}

struct SimulationInput {
    // Section A: Basisdaten & Sprinter 2027
    var altesMonatsgehalt: Double = 8333
    var fristMonate: Double = 5
    var bruttoAbfindung: Double = 150000
    var agFiktivGehalt: Double = 100000
    var neuesGehalt2027: Double = 25000
    var kvZusatzbeitragPct: Double = 2.5
    var preExitGkv: String = "Pflichtversichert (§ 19 Abs. 2 SGB V)"
    var isSplitting: Bool = false
    var partnerGehalt2027: Double = 0
    var turboEnabled: Bool = false
    var turboFaktor: Double = 1.5
    var alg1SatzPct: Double = 60.0
    var includeAlg1Loss: Bool = false

    // Section B: Auto-Solver & Steuer-Hebel
    var solverMode: SolverMode = .manual
    var customSolverOrder: [String] = ["bav", "drv", "ruerup", "iab"]
    var bavAmount: Double = 0
    var drvV0210Amount: Double = 0
    var ruerupAmount: Double = 0
    var pvIabPurchase: Double = 0

    // Section C: Reichweite (Cash-Burn & Runway)
    var payoutMonth2027: Int = 6 // Juni 2027
    var upfrontSpend2027: Double = 0 // Kredit-Tilgung / Urlaub / Puffer
    var monthlyExpenses: Double = 3500
    var alg1ClaimMonths: Double = 12
    var postAlg1GkvMode: String = "Mindestbeitrag"
    var customPostAlg1Gkv: Double = 650
    var realReturnPct: Double = 0.0
    var savePreExitSalarySurplus: Bool = true

    // Section D: Gehalts-Switch Break-Even
    var newJobGrossAnnual: Double = 66000
    var salaryGrowthPct: Double = 2.0
    var jobStartDelayMonths: Double = 0
}

struct WaterfallStep: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let isPositive: Bool
    let isTotal: Bool
}

struct RunwayPhaseSegment: Identifiable {
    let id = UUID()
    let strategy: String
    let phase: String
    let startMonth: Int
    let endMonth: Int
    let color: Color
}

struct RunwayComparisonPoint: Identifiable {
    let id = UUID()
    let month: Int
    let sprinterBalance: Double
    let standardBalance: Double
    let sharedMinBalance: Double
    let sprinterAheadStart: Double
    let sprinterAheadEnd: Double
    let standardAheadStart: Double
    let standardAheadEnd: Double
}

struct SimulationResult {
    var effectiveAbfindung: Double = 0
    var nettoPraemieSprinter: Double = 0
    var sofortNetto2027: Double = 0
    var agWithheldTax: Double = 0
    var finanzamtRefundOct2028: Double = 0
    var optimalNettoTotal: Double = 0
    var liquidityEnd2028: Double = 0
    var finalTaxRatePct: Double = 0
    var upfrontTaxRatePct: Double = 0

    // Solver resolved values
    var solvedBav: Double = 0
    var solvedDrv: Double = 0
    var solvedRuerup: Double = 0
    var solvedPvPurchase: Double = 0

    // Marginal savings & caps
    var bavSavings: Double = 0
    var drvSavings: Double = 0
    var ruerupSavings: Double = 0
    var iabSavings: Double = 0
    var ruerupCapRemaining: Double = 32308
    var iabSweetSpotDeduction: Double = 0

    // Splitting & Sprinter diagnostics
    var splittingDelta: Double = 0
    var partnerSplittingBreakEvenMax: Double = 0
    var sprinterNetDelta: Double = 0
    var ruhenszeitMonths: Double = 0
    var ruhensGkvMonthly: Double = 1320
    var waterfallSteps: [WaterfallStep] = []

    // Section C: Reichweite
    var standardRunwayMonths: Double = 0
    var sprinterRunwayMonths: Double = 0
    var lowestBalancePreRefund: Double = 0
    var bridgeDeficitOct2028: Double = 0
    var sprinterPayoutMonthIdx: Int = 5
    var standardPayoutMonthIdx: Int = 10
    var sprinterAlg1EndIdx: Int = 19
    var standardAlg1EndIdx: Int = 22
    var sprinterDepletedIdx: Int = 31
    var standardDepletedIdx: Int = 28
    var phaseSegments: [RunwayPhaseSegment] = []
    var comparisonCurve: [RunwayComparisonPoint] = []

    // Section D: Job-Switch Break-Even
    var monthlyNetLoss: Double = 0
    var oldMonthlyNet: Double = 0
    var newMonthlyNet: Double = 0
    var sprinterJobStartIdx: Int = 5
    var standardJobStartIdx: Int = 10
    var sprinterCushionAtStart: Double = 0
    var standardCushionAtStart: Double = 0
    var sprinterBreakEvenMonthIdx: Int? = nil
    var standardBreakEvenMonthIdx: Int? = nil
    var switchAxisTicks: [Int] = [0, 21, 48, 72, 96]
    var switchComparisonCurve: [RunwayComparisonPoint] = []
}

// MARK: - 2027 German Statutory Tax & Runway Engine

final class TaxEngineHost: ObservableObject {
    @Published var input = SimulationInput()
    @Published var result = SimulationResult()
    @Published var selectedSolver: SolverMode = .manual {
        didSet {
            input.solverMode = selectedSolver
            recalculate()
        }
    }

    private let bbgRv2027: Double = 106200
    private let bbgKv2027: Double = 76500
    private let anPauschbetrag2027: Double = 1430
    private let maxBav2027: Double = 50976
    private let maxRuerupSingle2027: Double = 32308

    init() {
        recalculate()
    }

    func applyPreset(_ preset: String) {
        var next = SimulationInput()
        switch preset {
        case "standard":
            next.turboEnabled = false
            next.neuesGehalt2027 = 25000
            input = next
            selectedSolver = .manual
        case "sprinter":
            next.turboEnabled = true
            next.turboFaktor = 1.5
            next.neuesGehalt2027 = 0
            input = next
            selectedSolver = .optimal
        case "privatier":
            next.turboEnabled = true
            next.turboFaktor = 1.5
            next.neuesGehalt2027 = 0
            next.monthlyExpenses = 3200
            input = next
            selectedSolver = .liquidity
        default:
            break
        }
        recalculate()
    }

    // § 32a EStG 2027 Income Tax Schedule
    private func getESt2027(zve: Double, splitting: Bool) -> Double {
        let x = max(0, splitting ? zve / 2.0 : zve)
        let b1 = 12564.0, b2 = 18000.0, b3 = 70600.0, b4 = 285000.0
        var s = 0.0
        if x <= b1 {
            s = 0
        } else if x <= b2 {
            let y = (x - b1) / 10000.0
            s = (919.8 * y + 1400.0) * y
        } else if x <= b3 {
            let z = (x - b2) / 10000.0
            let yMax = (b2 - b1) / 10000.0
            let taxB2 = (919.8 * yMax + 1400.0) * yMax
            s = (171.1 * z + 2400.0) * z + taxB2
        } else if x <= b4 {
            let yMax = (b2 - b1) / 10000.0
            let taxB2 = (919.8 * yMax + 1400.0) * yMax
            let zMax = (b3 - b2) / 10000.0
            let taxB3 = (171.1 * zMax + 2400.0) * zMax + taxB2
            s = 0.42 * (x - b3) + taxB3
        } else {
            let yMax = (b2 - b1) / 10000.0
            let taxB2 = (919.8 * yMax + 1400.0) * yMax
            let zMax = (b3 - b2) / 10000.0
            let taxB3 = (171.1 * zMax + 2400.0) * zMax + taxB2
            let taxB4 = 0.42 * (b4 - b3) + taxB3
            s = 0.45 * (x - b4) + taxB4
        }
        return max(0, splitting ? s * 2.0 : s)
    }

    private func getSoli2027(est: Double, splitting: Bool) -> Double {
        let fg = splitting ? 38900.0 : 19450.0
        if est <= fg { return 0 }
        return max(0, min((est - fg) * 0.119, est * 0.055))
    }

    private func calculateTotalTax(zveBase: Double, splitting: Bool, isFuenftel: Bool, abfindung: Double, progressionIncome: Double = 0) -> Double {
        if !isFuenftel || abfindung <= 0 {
            if progressionIncome <= 0 || zveBase <= 0 {
                let est = getESt2027(zve: max(0, zveBase), splitting: splitting)
                return est + getSoli2027(est: est, splitting: splitting)
            }
            let totalVirtual = max(1, zveBase + progressionIncome)
            let rate = getESt2027(zve: totalVirtual, splitting: splitting) / totalVirtual
            let est = max(0, zveBase * rate)
            return est + getSoli2027(est: est, splitting: splitting)
        }

        var estTotal = 0.0
        if progressionIncome <= 0 {
            if zveBase >= 0 {
                let estBase = getESt2027(zve: zveBase, splitting: splitting)
                let estStep = getESt2027(zve: zveBase + (abfindung / 5.0), splitting: splitting)
                estTotal = estBase + max(0, (estStep - estBase) * 5.0)
            } else {
                let combined = zveBase + abfindung
                estTotal = combined <= 0 ? 0 : getESt2027(zve: combined / 5.0, splitting: splitting) * 5.0
            }
        } else {
            let basePos = max(0, zveBase)
            let virt1 = basePos + progressionIncome
            let rate1 = virt1 > 0 ? getESt2027(zve: virt1, splitting: splitting) / virt1 : 0
            let est1 = basePos * rate1

            let sliceInc = max(0, zveBase + (abfindung / 5.0))
            let virt2 = sliceInc + progressionIncome
            let rate2 = virt2 > 0 ? getESt2027(zve: virt2, splitting: splitting) / virt2 : 0
            let est2 = sliceInc * rate2
            estTotal = est1 + max(0, (est2 - est1) * 5.0)
        }
        return estTotal + getSoli2027(est: estTotal, splitting: splitting)
    }

    private func getSozAbzug(brutto: Double, zb: Double) -> Double {
        guard brutto > 0 else { return 0 }
        let kvPvRate = (7.3 + zb / 2.0 + 2.4) / 100.0
        return min(brutto, bbgKv2027) * kvPvRate + min(brutto, bbgRv2027) * 0.093
    }

    private func getEmploymentZve(brutto: Double, zb: Double) -> Double {
        guard brutto > 0 else { return 0 }
        return max(0, brutto - getSozAbzug(brutto: brutto, zb: zb) - min(brutto, anPauschbetrag2027))
    }

    private func getGkvHoechstsatzMonat(zb: Double) -> Double {
        return (bbgKv2027 / 12.0) * ((14.6 + zb + 3.6) / 100.0)
    }

    private func getAlg1MonthlyNet(grossMonthly: Double, satzPct: Double) -> Double {
        let capped = min(grossMonthly, bbgRv2027 / 12.0)
        let approxNet = capped * 0.63
        return approxNet * (satzPct / 100.0)
    }

    func recalculate() {
        var r = SimulationResult()
        let spl = input.isSplitting
        let zb = input.kvZusatzbeitragPct
        let gkvMaxMo = getGkvHoechstsatzMonat(zb: zb)
        r.ruhensGkvMonthly = gkvMaxMo

        let praemieBrutto = input.turboEnabled ? (input.fristMonate * input.altesMonatsgehalt * input.turboFaktor) : 0
        let effectiveAbf = input.bruttoAbfindung + praemieBrutto
        r.effectiveAbfindung = effectiveAbf

        let rawRuhens = input.turboEnabled ? min(12.0, min(input.fristMonate, ceil((0.45 * effectiveAbf) / max(1, input.altesMonatsgehalt)))) : 0
        r.ruhenszeitMonths = rawRuhens
        let billableGkvMonths = (input.turboEnabled && input.preExitGkv.hasPrefix("Pflichtversichert"))
            ? max(0, rawRuhens - 1.0)
            : rawRuhens
        let totalGkvStrafe = billableGkvMonths * gkvMaxMo

        let actualGehalt = input.turboEnabled
            ? input.neuesGehalt2027
            : (input.altesMonatsgehalt * input.fristMonate) + input.neuesGehalt2027
        let partnerZve = spl ? getEmploymentZve(brutto: input.partnerGehalt2027, zb: zb) : 0
        let zveBasisActive = getEmploymentZve(brutto: actualGehalt, zb: zb) - totalGkvStrafe + partnerZve

        let maxRuerupTotal = (spl ? maxRuerupSingle2027 * 2.0 : maxRuerupSingle2027)
            - (min(actualGehalt, bbgRv2027) * 0.186)
            - (spl ? min(input.partnerGehalt2027, bbgRv2027) * 0.186 : 0)
        let ruerupCap = max(0, maxRuerupTotal)

        var bav = min(input.bavAmount, min(maxBav2027, effectiveAbf))
        var drv = min(input.drvV0210Amount, max(0, effectiveAbf - bav))
        var ruerup = min(input.ruerupAmount, ruerupCap)
        var pvPurchase = input.pvIabPurchase

        if selectedSolver != .manual {
            switch selectedSolver {
            case .optimal:
                bav = min(maxBav2027, effectiveAbf)
                drv = 0
                ruerup = min(ruerupCap, max(0, zveBasisActive))
                let remBase = max(0, zveBasisActive - ruerup)
                pvPurchase = min(400000, remBase * 2.0)
            case .liquidity:
                bav = 0
                drv = 0
                ruerup = min(ruerupCap, max(0, zveBasisActive))
                let remBase = max(0, zveBasisActive - ruerup)
                pvPurchase = min(400000, remBase * 2.0)
            case .retirement:
                bav = min(maxBav2027, effectiveAbf)
                drv = min(40000, max(0, effectiveAbf - bav))
                ruerup = ruerupCap
                pvPurchase = 0
            case .custom:
                var remAbf = effectiveAbf
                var remZve = max(0, zveBasisActive)
                bav = 0; drv = 0; ruerup = 0; pvPurchase = 0
                for key in input.customSolverOrder {
                    switch key {
                    case "bav":
                        bav = min(maxBav2027, remAbf)
                        remAbf -= bav
                    case "drv":
                        drv = min(40000, remAbf)
                        remAbf -= drv
                    case "ruerup":
                        ruerup = min(ruerupCap, remZve)
                        remZve = max(0, remZve - ruerup)
                    case "iab":
                        let ded = min(200000, remZve)
                        pvPurchase = ded * 2.0
                        remZve = max(0, remZve - ded)
                    default: break
                    }
                }
            case .manual:
                break
            }
            input.bavAmount = bav
            input.drvV0210Amount = drv
            input.ruerupAmount = ruerup
            input.pvIabPurchase = pvPurchase
        }

        r.solvedBav = bav
        r.solvedDrv = drv
        r.solvedRuerup = ruerup
        r.solvedPvPurchase = pvPurchase
        r.ruerupCapRemaining = max(0, ruerupCap - ruerup)

        let iabDeduction = pvPurchase / 2.0
        r.iabSweetSpotDeduction = max(0, zveBasisActive - ruerup)

        let drvTaxFree = drv * 0.5
        let taxableSeverance = max(0, effectiveAbf - bav - drvTaxFree)
        let cashSeveranceBeforeTax = max(0, effectiveAbf - bav - drv)

        let agZve = getEmploymentZve(brutto: input.agFiktivGehalt, zb: zb)
        let agTaxBase = calculateTotalTax(zveBase: agZve, splitting: false, isFuenftel: false, abfindung: 0)
        let agTaxWithAbf = calculateTotalTax(zveBase: agZve + taxableSeverance, splitting: false, isFuenftel: false, abfindung: 0)
        let agWithheld = max(0, agTaxWithAbf - agTaxBase)

        r.agWithheldTax = agWithheld
        r.sofortNetto2027 = max(0, cashSeveranceBeforeTax - agWithheld)
        r.upfrontTaxRatePct = taxableSeverance > 0 ? (agWithheld / taxableSeverance) * 100.0 : 0

        let agTaxNoBav = calculateTotalTax(zveBase: agZve + effectiveAbf, splitting: false, isFuenftel: false, abfindung: 0) - agTaxBase
        r.bavSavings = bav > 0 ? max(0, agTaxNoBav - agWithheld) * (bav / max(1, bav + drvTaxFree)) : 0
        r.drvSavings = drv > 0 ? max(0, agTaxNoBav - agWithheld) * (drvTaxFree / max(1, bav + drvTaxFree)) : 0

        let payrollTaxPaidOnSalary = calculateTotalTax(zveBase: getEmploymentZve(brutto: actualGehalt, zb: zb) + partnerZve, splitting: spl, isFuenftel: false, abfindung: 0)
        let netSalary2027 = actualGehalt - getSozAbzug(brutto: actualGehalt, zb: zb) - payrollTaxPaidOnSalary
        let totalTaxWithheld2027 = agWithheld + payrollTaxPaidOnSalary

        let zveAfterDeductions = zveBasisActive - ruerup - iabDeduction
        let finalTotalTax = calculateTotalTax(zveBase: zveAfterDeductions, splitting: spl, isFuenftel: true, abfindung: taxableSeverance)
        let refundOct2028 = max(0, totalTaxWithheld2027 - finalTotalTax)

        r.finanzamtRefundOct2028 = refundOct2028
        r.optimalNettoTotal = r.sofortNetto2027 + refundOct2028
        r.liquidityEnd2028 = r.sofortNetto2027 + netSalary2027 - ruerup - pvPurchase - totalGkvStrafe + refundOct2028

        let baseTaxOnly = calculateTotalTax(zveBase: zveAfterDeductions, splitting: spl, isFuenftel: false, abfindung: 0)
        let finalAbfTax = max(0, finalTotalTax - baseTaxOnly)
        r.finalTaxRatePct = taxableSeverance > 0 ? (finalAbfTax / taxableSeverance) * 100.0 : 0

        let taxWithoutRuerupAndIab = calculateTotalTax(zveBase: zveBasisActive, splitting: spl, isFuenftel: true, abfindung: taxableSeverance)
        let combinedOptSavings = max(0, taxWithoutRuerupAndIab - finalTotalTax)
        let standaloneRuerup = max(0, taxWithoutRuerupAndIab - calculateTotalTax(zveBase: zveBasisActive - ruerup, splitting: spl, isFuenftel: true, abfindung: taxableSeverance))
        let standaloneIab = max(0, taxWithoutRuerupAndIab - calculateTotalTax(zveBase: zveBasisActive - iabDeduction, splitting: spl, isFuenftel: true, abfindung: taxableSeverance))
        let standaloneSum = standaloneRuerup + standaloneIab
        r.ruerupSavings = standaloneSum > 0 ? combinedOptSavings * (standaloneRuerup / standaloneSum) : 0
        r.iabSavings = standaloneSum > 0 ? combinedOptSavings * (standaloneIab / standaloneSum) : 0

        if spl {
            let userSingleTax = calculateTotalTax(zveBase: getEmploymentZve(brutto: actualGehalt, zb: zb) - totalGkvStrafe - iabDeduction - min(ruerup, maxRuerupSingle2027), splitting: false, isFuenftel: true, abfindung: taxableSeverance)
            let partnerSingleTax = calculateTotalTax(zveBase: partnerZve, splitting: false, isFuenftel: false, abfindung: 0)
            r.splittingDelta = (userSingleTax + partnerSingleTax) - finalTotalTax
            r.partnerSplittingBreakEvenMax = max(45000, 115000 - (effectiveAbf * 0.25))
        }

        let alg1MoNet = getAlg1MonthlyNet(grossMonthly: input.altesMonatsgehalt, satzPct: input.alg1SatzPct)
        let rvLoss = input.turboEnabled ? (rawRuhens * min(input.altesMonatsgehalt, bbgRv2027 / 12.0) * 0.186) : 0
        let alg1Loss = (input.turboEnabled && input.includeAlg1Loss) ? (min(3.0, rawRuhens) * alg1MoNet) : 0

        let bgNoTurbo = (input.altesMonatsgehalt * input.fristMonate) + input.neuesGehalt2027
        let netSalNoTurbo = bgNoTurbo - getSozAbzug(brutto: bgNoTurbo, zb: zb) - calculateTotalTax(zveBase: getEmploymentZve(brutto: bgNoTurbo, zb: zb) + partnerZve, splitting: spl, isFuenftel: false, abfindung: 0)
        let netSalTurbo = input.neuesGehalt2027 - getSozAbzug(brutto: input.neuesGehalt2027, zb: zb) - calculateTotalTax(zveBase: getEmploymentZve(brutto: input.neuesGehalt2027, zb: zb) + partnerZve, splitting: spl, isFuenftel: false, abfindung: 0)
        let lostNetSalary = max(0, netSalNoTurbo - netSalTurbo)

        let nettoPraemie = max(0, praemieBrutto * 0.68)
        r.nettoPraemieSprinter = nettoPraemie
        let taxAdv = max(0, (bgNoTurbo - input.neuesGehalt2027) * 0.14)
        let sprinterNet = nettoPraemie + taxAdv - lostNetSalary - totalGkvStrafe - rvLoss - alg1Loss
        r.sprinterNetDelta = sprinterNet

        if input.turboEnabled {
            r.waterfallSteps = [
                WaterfallStep(label: "+ Netto-Prämie", value: nettoPraemie, isPositive: true, isTotal: false),
                WaterfallStep(label: "+ Fünftel-Vorteil", value: taxAdv, isPositive: true, isTotal: false),
                WaterfallStep(label: "− Gehalt (Netto)", value: -lostNetSalary, isPositive: false, isTotal: false),
                WaterfallStep(label: "− GKV/PV Lücke", value: -totalGkvStrafe, isPositive: false, isTotal: false),
                WaterfallStep(label: "− RV & ALG-1", value: -(rvLoss + alg1Loss), isPositive: false, isTotal: false),
                WaterfallStep(label: "= Netto-Delta", value: sprinterNet, isPositive: sprinterNet >= 0, isTotal: true)
            ]
        }

        // Section C: Reichweite Dual Simulation & Merged Area Comparison Curve
        let stdSim = simulateRunway(isSprinter: false, alg1MoNet: alg1MoNet, gkvMaxMo: gkvMaxMo)
        let sprSim = simulateRunway(isSprinter: true, alg1MoNet: alg1MoNet, gkvMaxMo: gkvMaxMo)

        r.standardRunwayMonths = stdSim.totalMonths
        r.sprinterRunwayMonths = sprSim.totalMonths
        r.lowestBalancePreRefund = min(stdSim.lowestPreRefund, sprSim.lowestPreRefund)
        r.bridgeDeficitOct2028 = max(0, -r.lowestBalancePreRefund)
        r.sprinterPayoutMonthIdx = sprSim.payoutMonthIdx
        r.standardPayoutMonthIdx = stdSim.payoutMonthIdx
        r.sprinterAlg1EndIdx = sprSim.alg1EndIdx
        r.standardAlg1EndIdx = stdSim.alg1EndIdx
        r.sprinterDepletedIdx = sprSim.depletedIdx
        r.standardDepletedIdx = stdSim.depletedIdx
        r.phaseSegments = sprSim.segments + stdSim.segments

        let maxPlotM = min(60, max(sprSim.depletedIdx, stdSim.depletedIdx) + 5)
        var compCurve: [RunwayComparisonPoint] = []
        for m in 0...maxPlotM {
            let sprVal = m < sprSim.balances.count ? sprSim.balances[m] : 0
            let stdVal = m < stdSim.balances.count ? stdSim.balances[m] : 0
            let shared = min(sprVal, stdVal)
            compCurve.append(
                RunwayComparisonPoint(
                    month: m,
                    sprinterBalance: sprVal,
                    standardBalance: stdVal,
                    sharedMinBalance: shared,
                    sprinterAheadStart: shared,
                    sprinterAheadEnd: max(shared, sprVal),
                    standardAheadStart: shared,
                    standardAheadEnd: max(shared, stdVal)
                )
            )
        }
        r.comparisonCurve = compCurve

        // Section D: Monthly Job-Switch Break-Even (Matching Reichweite Multi-Layer Area Curve)
        let oldNetAnnual = (input.altesMonatsgehalt * 12.0)
            - getSozAbzug(brutto: input.altesMonatsgehalt * 12.0, zb: zb)
            - calculateTotalTax(zveBase: getEmploymentZve(brutto: input.altesMonatsgehalt * 12.0, zb: zb), splitting: spl, isFuenftel: false, abfindung: 0)
        let newNetAnnual = input.newJobGrossAnnual
            - getSozAbzug(brutto: input.newJobGrossAnnual, zb: zb)
            - calculateTotalTax(zveBase: getEmploymentZve(brutto: input.newJobGrossAnnual, zb: zb), splitting: spl, isFuenftel: false, abfindung: 0)

        r.oldMonthlyNet = oldNetAnnual / 12.0
        r.newMonthlyNet = newNetAnnual / 12.0
        r.monthlyNetLoss = max(0, r.oldMonthlyNet - r.newMonthlyNet)

        let stdSw = simulateMonthlyCrossover(isSprinter: false, oldMonthlyNet: r.oldMonthlyNet, newMonthlyNet: r.newMonthlyNet, alg1MoNet: alg1MoNet, gkvMaxMo: gkvMaxMo)
        let sprSw = simulateMonthlyCrossover(isSprinter: true, oldMonthlyNet: r.oldMonthlyNet, newMonthlyNet: r.newMonthlyNet, alg1MoNet: alg1MoNet, gkvMaxMo: gkvMaxMo)

        r.standardJobStartIdx = stdSw.jobStartM
        r.sprinterJobStartIdx = sprSw.jobStartM
        r.standardCushionAtStart = stdSw.cushionAtStart
        r.sprinterCushionAtStart = sprSw.cushionAtStart
        r.standardBreakEvenMonthIdx = stdSw.breakevenMonthIdx
        r.sprinterBreakEvenMonthIdx = sprSw.breakevenMonthIdx

        let rawMaxBe = max(stdSw.breakevenMonthIdx ?? 96, sprSw.breakevenMonthIdx ?? 96)
        let maxSwitchM = min(240, max(48, rawMaxBe + 12))
        let stepM = max(12, maxSwitchM / 4)
        r.switchAxisTicks = Array(stride(from: 0, through: maxSwitchM, by: stepM))

        var swCurve: [RunwayComparisonPoint] = []
        for m in 0...maxSwitchM {
            let sprVal = m < sprSw.series.count ? sprSw.series[m] : (sprSw.series.last ?? 0)
            let stdVal = m < stdSw.series.count ? stdSw.series[m] : (stdSw.series.last ?? 0)
            let shared = min(sprVal, stdVal)
            swCurve.append(
                RunwayComparisonPoint(
                    month: m,
                    sprinterBalance: sprVal,
                    standardBalance: stdVal,
                    sharedMinBalance: shared,
                    sprinterAheadStart: shared,
                    sprinterAheadEnd: max(shared, sprVal),
                    standardAheadStart: shared,
                    standardAheadEnd: max(shared, stdVal)
                )
            )
        }
        r.switchComparisonCurve = swCurve

        self.result = r
    }

    private func simulateRunway(isSprinter: Bool, alg1MoNet: Double, gkvMaxMo: Double) -> (
        totalMonths: Double,
        totalWealthPool: Double,
        lowestPreRefund: Double,
        payoutMonthIdx: Int,
        alg1EndIdx: Int,
        depletedIdx: Int,
        segments: [RunwayPhaseSegment],
        balances: [Double]
    ) {
        let label = isSprinter ? "Sprinter (Sofort)" : "Standard (Frist)"
        let zb = input.kvZusatzbeitragPct
        let preMonths = Double(max(0, input.payoutMonth2027 - 1))
        let salMonths = isSprinter ? preMonths : (preMonths + input.fristMonate)
        let salMonths2027 = min(12.0, salMonths)

        let gross2027 = salMonths2027 * input.altesMonatsgehalt
        let praemie = isSprinter ? (input.fristMonate * input.altesMonatsgehalt * input.turboFaktor) : 0
        let effAbf = input.bruttoAbfindung + praemie
        let bav = min(input.bavAmount, min(maxBav2027, effAbf))
        let drv = min(input.drvV0210Amount, max(0, effAbf - bav))
        let taxableAbf = max(0, effAbf - bav - drv * 0.5)
        let cashAbfBeforeTax = max(0, effAbf - bav - drv)

        let agZve = getEmploymentZve(brutto: input.agFiktivGehalt, zb: zb)
        let agWithheld = max(0, calculateTotalTax(zveBase: agZve + taxableAbf, splitting: false, isFuenftel: false, abfindung: 0) - calculateTotalTax(zveBase: agZve, splitting: false, isFuenftel: false, abfindung: 0))
        let sofortNetto = max(0, cashAbfBeforeTax - agWithheld)

        let ruhens = isSprinter ? min(12.0, min(input.fristMonate, ceil((0.45 * effAbf) / max(1, input.altesMonatsgehalt)))) : 0
        let billableGkv = (isSprinter && input.preExitGkv.hasPrefix("Pflichtversichert")) ? max(0, ruhens - 1.0) : ruhens
        let alg1MonthsEff = max(0, input.alg1ClaimMonths - (isSprinter ? min(3.0, ruhens) : 0))

        let joblessStartMonthIndex = Int(salMonths)
        let alg1StartMonthIndex = joblessStartMonthIndex + Int(ruhens)
        let alg1EndMonthIndex = alg1StartMonthIndex + Int(alg1MonthsEff)
        let alg1MonthsIn2027 = max(0.0, min(alg1MonthsEff, Double(12 - alg1StartMonthIndex)))
        let prog2027 = alg1MonthsIn2027 * alg1MoNet

        let partnerZve = input.isSplitting ? getEmploymentZve(brutto: input.partnerGehalt2027, zb: zb) : 0
        let zve2027 = getEmploymentZve(brutto: gross2027, zb: zb) - (billableGkv * gkvMaxMo) + partnerZve - input.ruerupAmount - (input.pvIabPurchase / 2.0)
        let payrollSalTax = calculateTotalTax(zveBase: getEmploymentZve(brutto: gross2027, zb: zb) + partnerZve, splitting: input.isSplitting, isFuenftel: false, abfindung: 0)
        let finalTax2027 = calculateTotalTax(zveBase: zve2027, splitting: input.isSplitting, isFuenftel: true, abfindung: taxableAbf, progressionIncome: prog2027)
        let faRefundOct2028 = max(0, (agWithheld + payrollSalTax) - finalTax2027)

        let monthlyNetSalary = (gross2027 - getSozAbzug(brutto: gross2027, zb: zb) - payrollSalTax) / max(1, salMonths2027)
        let preExitSavingsPerMonth = input.savePreExitSalarySurplus ? max(0, monthlyNetSalary - input.monthlyExpenses) : 0

        let netPayoutDay1 = max(0, sofortNetto - input.ruerupAmount - input.pvIabPurchase - input.upfrontSpend2027)
        let totalWealthPool = netPayoutDay1 + (preExitSavingsPerMonth * salMonths) + faRefundOct2028

        let postAlg1Gkv: Double
        switch input.postAlg1GkvMode {
        case "Familienversicherung": postAlg1Gkv = 0
        case "Individuell": postAlg1Gkv = input.customPostAlg1Gkv
        default: postAlg1Gkv = 285
        }

        let monthlyRate = pow(1.0 + (input.realReturnPct / 100.0), 1.0 / 12.0) - 1.0
        var balances: [Double] = []
        var balance = 0.0
        var lowestPreRefund = Double.infinity
        var postAlg1Months = 0.0
        var depletedIdx = 71

        for m in 0..<72 {
            if m == joblessStartMonthIndex {
                balance += netPayoutDay1
            }
            if m == 21 {
                balance += faRefundOct2028
            }

            if m < joblessStartMonthIndex {
                balance += preExitSavingsPerMonth
                balances.append(max(0, balance))
                continue
            }

            let joblessM = Double(m - joblessStartMonthIndex)
            var burn = 0.0
            if joblessM < ruhens {
                let gkvCost = (joblessM < 1.0 && input.preExitGkv.hasPrefix("Pflichtversichert")) ? 0 : gkvMaxMo
                burn = input.monthlyExpenses + gkvCost
            } else if joblessM < (ruhens + alg1MonthsEff) {
                burn = max(0, input.monthlyExpenses - alg1MoNet)
            } else {
                burn = input.monthlyExpenses + postAlg1Gkv
                if balance > 0 {
                    postAlg1Months += 1.0
                }
            }

            balance = balance * (1.0 + monthlyRate) - burn
            if m >= joblessStartMonthIndex && m < 21 {
                lowestPreRefund = min(lowestPreRefund, balance)
            }
            balances.append(max(0, balance))

            if balance <= 0 && m > 21 {
                depletedIdx = m
                break
            }
        }

        if lowestPreRefund == Double.infinity {
            lowestPreRefund = netPayoutDay1
        }

        let totalRunway = ruhens + alg1MonthsEff + postAlg1Months
        var segments: [RunwayPhaseSegment] = []
        if joblessStartMonthIndex > 0 {
            segments.append(RunwayPhaseSegment(strategy: label, phase: "1. Gehaltsphase", startMonth: 0, endMonth: joblessStartMonthIndex, color: .indigo))
        }
        if Int(ruhens) > 0 {
            segments.append(RunwayPhaseSegment(strategy: label, phase: "2. Ruhenszeit (GKV)", startMonth: joblessStartMonthIndex, endMonth: alg1StartMonthIndex, color: .orange))
        }
        if Int(alg1MonthsEff) > 0 {
            segments.append(RunwayPhaseSegment(strategy: label, phase: "3. ALG-1 Bezug", startMonth: alg1StartMonthIndex, endMonth: alg1EndMonthIndex, color: .cyan))
        }
        if depletedIdx > alg1EndMonthIndex {
            segments.append(RunwayPhaseSegment(strategy: label, phase: "4. Privatiers-Phase", startMonth: alg1EndMonthIndex, endMonth: depletedIdx, color: .green))
        }

        return (totalRunway, totalWealthPool, lowestPreRefund, joblessStartMonthIndex, alg1EndMonthIndex, depletedIdx, segments, balances)
    }

    private func simulateMonthlyCrossover(
        isSprinter: Bool,
        oldMonthlyNet: Double,
        newMonthlyNet: Double,
        alg1MoNet: Double,
        gkvMaxMo: Double
    ) -> (jobStartM: Int, cushionAtStart: Double, breakevenMonthIdx: Int?, series: [Double]) {
        let zb = input.kvZusatzbeitragPct
        let preMonths = max(0, input.payoutMonth2027 - 1)
        let exitM = isSprinter ? preMonths : (preMonths + Int(input.fristMonate))
        let delayM = Int(input.jobStartDelayMonths)
        let jobStartM = exitM + delayM

        let praemie = isSprinter ? (input.fristMonate * input.altesMonatsgehalt * input.turboFaktor) : 0
        let effAbf = input.bruttoAbfindung + praemie
        let bav = min(input.bavAmount, min(maxBav2027, effAbf))
        let drv = min(input.drvV0210Amount, max(0, effAbf - bav))
        let taxableAbf = max(0, effAbf - bav - drv * 0.5)
        let cashAbfBeforeTax = max(0, effAbf - bav - drv)

        let agZve = getEmploymentZve(brutto: input.agFiktivGehalt, zb: zb)
        let agWithheld = max(0, calculateTotalTax(zveBase: agZve + taxableAbf, splitting: false, isFuenftel: false, abfindung: 0) - calculateTotalTax(zveBase: agZve, splitting: false, isFuenftel: false, abfindung: 0))
        let sofortNetto = max(0, cashAbfBeforeTax - agWithheld)

        let ruhens = isSprinter ? min(12, min(Int(input.fristMonate), Int(ceil((0.45 * effAbf) / max(1, input.altesMonatsgehalt))))) : 0
        let alg1Eligible = max(0, Int(input.alg1ClaimMonths) - (isSprinter ? min(3, ruhens) : 0))

        let oldSalMonths2027 = min(12, exitM)
        let newSalMonths2027 = max(0, 12 - min(12, jobStartM))
        let gapMonths2027 = max(0, min(12, jobStartM) - oldSalMonths2027)
        let ruhens2027 = min(ruhens, gapMonths2027)
        let grace2027 = (isSprinter && input.preExitGkv.hasPrefix("Pflichtversichert") && ruhens2027 > 0) ? 1 : 0
        let payableRuhens2027 = max(0, ruhens2027 - grace2027)
        let alg2027 = max(0, min(alg1Eligible, gapMonths2027 - ruhens2027))

        let newMonthlyGross = input.newJobGrossAnnual / 12.0
        let gross2027 = (Double(oldSalMonths2027) * input.altesMonatsgehalt) + (Double(newSalMonths2027) * newMonthlyGross)
        let partnerZve = input.isSplitting ? getEmploymentZve(brutto: input.partnerGehalt2027, zb: zb) : 0
        let taxPaid2027 = calculateTotalTax(zveBase: getEmploymentZve(brutto: gross2027, zb: zb) + partnerZve, splitting: input.isSplitting, isFuenftel: false, abfindung: 0)
        let zve2027 = getEmploymentZve(brutto: gross2027, zb: zb) - (Double(payableRuhens2027) * gkvMaxMo) + partnerZve - input.ruerupAmount - (input.pvIabPurchase / 2.0)
        let finalTax2027 = calculateTotalTax(zveBase: zve2027, splitting: input.isSplitting, isFuenftel: true, abfindung: taxableAbf, progressionIncome: Double(alg2027) * alg1MoNet)
        let faRefundOct2028 = max(0, (agWithheld + taxPaid2027) - finalTax2027)

        let postAlg1Gkv: Double
        switch input.postAlg1GkvMode {
        case "Familienversicherung": postAlg1Gkv = 0
        case "Individuell": postAlg1Gkv = input.customPostAlg1Gkv
        default: postAlg1Gkv = 285
        }

        let annualGrowth = input.salaryGrowthPct / 100.0
        let monthlyRealRate = (input.realReturnPct / 100.0) / 12.0
        let netDay1 = max(0, sofortNetto - input.ruerupAmount - input.pvIabPurchase - input.upfrontSpend2027)

        var advantage = 0.0
        var payoutDone = false
        var ref28Done = false
        var cushionAtStart = netDay1 + faRefundOct2028
        var breakevenIdx: Int? = nil
        var series: [Double] = []

        for m in 0..<260 {
            if !payoutDone && m == exitM {
                advantage += netDay1
                payoutDone = true
            }
            if !ref28Done && m == 21 {
                advantage += faRefundOct2028
                ref28Done = true
            }

            let yrIdx = m / 12
            let factor = pow(1.0 + annualGrowth, Double(yrIdx))
            let oldNetM = oldMonthlyNet * factor
            let newNetM = newMonthlyNet * factor

            if m < exitM {
                // Identical pre-exit salary
            } else if m < jobStartM {
                let gapIdx = m - exitM
                if gapIdx < ruhens {
                    let gkvCost = (isSprinter && input.preExitGkv.hasPrefix("Pflichtversichert") && gapIdx == 0) ? 0 : gkvMaxMo
                    advantage -= (oldNetM + gkvCost)
                } else if gapIdx < (ruhens + alg1Eligible) {
                    advantage += (alg1MoNet - oldNetM)
                } else {
                    advantage -= (oldNetM + postAlg1Gkv)
                }
            } else {
                if m == jobStartM {
                    cushionAtStart = advantage + (ref28Done ? 0 : faRefundOct2028)
                }
                let deficitM = max(0, oldNetM - newNetM)
                advantage -= deficitM
            }

            if advantage > 0 && monthlyRealRate != 0 {
                advantage *= (1.0 + monthlyRealRate)
            }

            series.append(max(0, advantage))

            if payoutDone && ref28Done && breakevenIdx == nil && advantage <= 0 {
                breakevenIdx = m
            }
            if let be = breakevenIdx, m >= min(259, max(48, be + 12)) {
                break
            }
        }

        return (jobStartM, cushionAtStart, breakevenIdx, series)
    }
}

// MARK: - Formatting Helpers

private func eur(_ val: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "EUR"
    formatter.maximumFractionDigits = 0
    formatter.locale = Locale(identifier: "de_DE")
    return formatter.string(from: NSNumber(value: val)) ?? "\(Int(val)) €"
}

private func monthLabel(_ index: Int) -> String {
    let months = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
    let yr = 2027 + (index / 12)
    return "\(months[index % 12]) \(yr)"
}

private func shortMonthLabel(_ index: Int) -> String {
    let months = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
    let yr = 27 + (index / 12)
    return "\(months[index % 12]) \(yr)"
}

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

// MARK: - Root 4-Tab Navigation Container

struct MainTabContainerView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @AppStorage("abfindungs_theme") private var themeMode: String = "dark"
    @State private var selectedTab: Int = 0
    @State private var activeTopic: StatutoryTopic?
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
                InputsTabView(activeTopic: $activeTopic)
                    .navigationTitle("AbfindungsPilot")
                    .toolbar { sharedToolbar }
            }
            .tabItem {
                Label("Eingaben", systemImage: "slider.horizontal.3")
            }
            .tag(0)

            NavigationStack {
                ResultsTabView(activeTopic: $activeTopic, onExportPDF: generatePDFReport)
                    .navigationTitle("Ergebnis")
                    .toolbar { sharedToolbar }
            }
            .tabItem {
                Label("Ergebnis", systemImage: "chart.pie.fill")
            }
            .tag(1)

            NavigationStack {
                ReichweiteTabView(activeTopic: $activeTopic)
                    .navigationTitle("Reichweite")
                    .toolbar { sharedToolbar }
            }
            .tabItem {
                Label("Reichweite", systemImage: "hourglass")
            }
            .tag(2)

            NavigationStack {
                JobSwitchTabView(activeTopic: $activeTopic)
                    .navigationTitle("Switch")
                    .toolbar { sharedToolbar }
            }
            .tabItem {
                Label("Switch", systemImage: "arrow.left.arrow.right")
            }
            .tag(3)
        }
        .preferredColorScheme(resolvedColorScheme)
        .sheet(item: $activeTopic) { topic in
            StatutoryInfoSheet(topic: topic)
                .preferredColorScheme(resolvedColorScheme)
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
                activeTopic = .recht2027Overview
            } label: {
                Image(systemName: "bolt.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Recht 2027")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                themeMode = (themeMode == "dark") ? "light" : "dark"
            } label: {
                Image(systemName: themeMode == "dark" ? "sun.max.fill" : "moon.fill")
                    .foregroundStyle(themeMode == "dark" ? .yellow : .indigo)
            }
            .accessibilityLabel(themeMode == "dark" ? "Heller Modus" : "Dunkler Modus")

            Button {
                generatePDFReport()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("PDF-Report exportieren")
        }
    }

    private func generatePDFReport() {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AbfindungsPilot_2027_Report.pdf")
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.label
                ]
                "AbfindungsPilot 2027 – Analyse & Steuer-Report".draw(at: CGPoint(x: 40, y: 40), withAttributes: titleAttrs)

                let bodyAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.darkGray
                ]
                let summary = """
                Basis-Abfindung Brutto: \(eur(engine.input.bruttoAbfindung))
                Effektive Abfindung (inkl. Sprinter): \(eur(engine.result.effectiveAbfindung))
                Sofort-Netto 2027 (nach AG-Einbehalt): \(eur(engine.result.sofortNetto2027))
                Finanzamt-Erstattung (Okt. 2028, § 34 EStG): +\(eur(engine.result.finanzamtRefundOct2028))
                Optimal-Netto Gesamt: \(eur(engine.result.optimalNettoTotal))
                End-Liquidität (Ende 2028): \(eur(engine.result.liquidityEnd2028))

                Reichweite Standard vs. Sprinter: \(String(format: "%.1f", engine.result.standardRunwayMonths)) Mon. vs. \(String(format: "%.1f", engine.result.sprinterRunwayMonths)) Mon.
                """
                summary.draw(in: CGRect(x: 40, y: 80, width: 515, height: 700), withAttributes: bodyAttrs)
            }
            self.pdfURL = url
            self.showPdfSheet = true
        } catch {
            print("PDF export error: \(error)")
        }
    }
}

// MARK: - Shared Pinned Bottom KPI Strip

struct PinnedKpiFooter: View {
    @EnvironmentObject var engine: TaxEngineHost

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sofort 2027")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(eur(engine.result.sofortNetto2027))
                        .font(.subheadline.bold())
                }
                Spacer()
                VStack(alignment: .center, spacing: 2) {
                    Text("FA Okt. 2028")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("+\(eur(engine.result.finanzamtRefundOct2028))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Optimal-Netto")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(eur(engine.result.optimalNettoTotal))
                        .font(.subheadline.bold())
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - TAB 1: EINGABEN (Inputs, Sprinter & Auto-Solver)

struct InputsTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var activeTopic: StatutoryTopic?

    var body: some View {
        Form {
            Section("Schnell-Szenarien (1-Click Presets)") {
                HStack(spacing: 10) {
                    Button {
                        engine.applyPreset("standard")
                    } label: {
                        Text("Standard")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(!engine.input.turboEnabled ? Color.blue : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(!engine.input.turboEnabled ? .white : .primary)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        engine.applyPreset("sprinter")
                    } label: {
                        Text("Sprinter")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background((engine.input.turboEnabled && engine.selectedSolver == .optimal) ? Color.blue : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle((engine.input.turboEnabled && engine.selectedSolver == .optimal) ? .white : .primary)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        engine.applyPreset("privatier")
                    } label: {
                        Text("Privatier")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background((engine.input.turboEnabled && engine.selectedSolver == .liquidity) ? Color.blue : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle((engine.input.turboEnabled && engine.selectedSolver == .liquidity) ? .white : .primary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("A · Basisdaten & Sprinter 2027") {
                sliderRow("Abfindung Brutto", value: $engine.input.bruttoAbfindung, range: 10_000...600_000, step: 2_500)
                sliderRow("Altes Monatsgehalt", value: $engine.input.altesMonatsgehalt, range: 2_500...25_000, step: 250)
                Stepper("Kündigungsfrist: \(Int(engine.input.fristMonate)) Monate", value: $engine.input.fristMonate, in: 0...12, step: 1)
                    .onChange(of: engine.input.fristMonate) { _, _ in engine.recalculate() }
                sliderRow("AG-Fiktivgehalt", value: $engine.input.agFiktivGehalt, range: 0...250_000, step: 2_500, topic: .agFiktivgehalt)
                sliderRow("Neues Gehalt 2027", value: $engine.input.neuesGehalt2027, range: 0...200_000, step: 1_000)

                HStack {
                    Text("Vor-Austritt GKV")
                    Spacer()
                    Picker("", selection: $engine.input.preExitGkv) {
                        Text("Pflicht (§ 19 SGB V)").tag("Pflichtversichert (§ 19 Abs. 2 SGB V)")
                        Text("Freiwillig GKV").tag("Freiwillig versichert")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: engine.input.preExitGkv) { _, _ in engine.recalculate() }
                    InfoHelpButton(topic: .gkvGracePeriod19) { activeTopic = $0 }
                }

                HStack {
                    Toggle("Sprinter-Option (Vorzeitiger Austritt)", isOn: $engine.input.turboEnabled)
                        .onChange(of: engine.input.turboEnabled) { _, _ in engine.recalculate() }
                    InfoHelpButton(topic: .sprinterRuhenszeit158, isWarning: true) { activeTopic = $0 }
                }

                if engine.input.turboEnabled {
                    sliderRow("Sprinter-Faktor", value: $engine.input.turboFaktor, range: 0.5...2.5, step: 0.1, isCurrency: false, suffix: "x")
                    HStack {
                        Toggle("ALG-1 Kürzung (12 Wo. Sperrzeit)", isOn: $engine.input.includeAlg1Loss)
                            .onChange(of: engine.input.includeAlg1Loss) { _, _ in engine.recalculate() }
                        InfoHelpButton(topic: .sperrzeit159, isWarning: true) { activeTopic = $0 }
                    }
                    HStack {
                        Text("Sprinter Netto-Delta:")
                        Spacer()
                        Text(eur(engine.result.sprinterNetDelta))
                            .fontWeight(.bold)
                            .foregroundStyle(engine.result.sprinterNetDelta >= 0 ? .green : .red)
                    }
                }

                HStack {
                    Toggle("Splittingtarif (Verheiratet)", isOn: $engine.input.isSplitting)
                        .onChange(of: engine.input.isSplitting) { _, _ in engine.recalculate() }
                    InfoHelpButton(topic: .splittingFuenftelFalle, isWarning: true) { activeTopic = $0 }
                }

                if engine.input.isSplitting {
                    sliderRow("Gehalt Ehepartner 2027", value: $engine.input.partnerGehalt2027, range: 0...180_000, step: 1_000)
                    Text("Splitting-Vorteil bis ca. \(eur(engine.result.partnerSplittingBreakEvenMax)) Partner-Brutto")
                        .font(.caption).foregroundStyle(.blue)
                }
            }

            Section("B · Auto-Solver & Steuer-Hebel") {
                Picker("Optimierungs-Modus", selection: $engine.selectedSolver) {
                    ForEach(SolverMode.allCases) { Text($0.rawValue).tag($0) }
                }

                if engine.selectedSolver == .custom {
                    ForEach(Array(engine.input.customSolverOrder.enumerated()), id: \.element) { idx, key in
                        HStack {
                            Text("\(idx + 1). \(String(leverDisplayName(key).dropFirst(3)))")
                                .font(.subheadline)
                            Spacer()
                            if idx > 0 {
                                Button {
                                    engine.input.customSolverOrder.swapAt(idx, idx - 1)
                                    engine.recalculate()
                                } label: { Image(systemName: "arrow.up.circle") }
                                .buttonStyle(.borderless)
                            }
                            if idx < engine.input.customSolverOrder.count - 1 {
                                Button {
                                    engine.input.customSolverOrder.swapAt(idx, idx + 1)
                                    engine.recalculate()
                                } label: { Image(systemName: "arrow.down.circle") }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                sliderRow("bAV-Einzahlung (max. 50.976 €)", value: $engine.input.bavAmount, range: 0...50_976, step: 500, topic: .bav63)
                sliderRow("DRV V0210 Ausgleich (50% frei)", value: $engine.input.drvV0210Amount, range: 0...80_000, step: 500, topic: .drvV0210)
                sliderRow("Rürup / Basisrente (frei: \(eur(engine.result.ruerupCapRemaining)))", value: $engine.input.ruerupAmount, range: 0...64_616, step: 500, topic: .ruerup10)
                sliderRow("PV-Investition (50% IAB)", value: $engine.input.pvIabPurchase, range: 0...400_000, step: 2_500, topic: .pvIab7g)

                Button("🎯 IAB Sweet-Spot anwenden (zvE → 0 €)") {
                    engine.selectedSolver = .manual
                    engine.input.pvIabPurchase = min(400_000, engine.result.iabSweetSpotDeduction * 2)
                    engine.recalculate()
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
            }
        }
        .safeAreaInset(edge: .bottom) {
            PinnedKpiFooter()
                .allowsHitTesting(false)
        }
    }

    private func leverDisplayName(_ key: String) -> String {
        switch key {
        case "bav": return "1. bAV (§ 3 Nr. 63 EStG)"
        case "drv": return "2. DRV V0210 (§ 187a SGB VI)"
        case "ruerup": return "3. Rürup / Basisrente (§ 10 EStG)"
        case "iab": return "4. PV-IAB (§ 7g EStG)"
        default: return key
        }
    }

    @ViewBuilder
    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        isCurrency: Bool = true,
        suffix: String = "",
        topic: StatutoryTopic? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                if let topic {
                    InfoHelpButton(topic: topic) { activeTopic = $0 }
                }
                Spacer()
                Text(isCurrency ? eur(value.wrappedValue) : String(format: "%.1f%@", value.wrappedValue, suffix))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            Slider(value: value, in: range, step: step)
                .onChange(of: value.wrappedValue) { _, _ in
                    if engine.selectedSolver != .manual &&
                        (title.hasPrefix("bAV") || title.hasPrefix("DRV") || title.hasPrefix("Rürup") || title.hasPrefix("PV-")) {
                        engine.selectedSolver = .manual
                    }
                    engine.recalculate()
                }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - TAB 2: ERGEBNIS (Full KPI Value Cards, Lever Cards & Charts)

struct ResultsTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var activeTopic: StatutoryTopic?
    let onExportPDF: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    kpiCard(
                        title: "Sofort-Netto 2027",
                        value: eur(engine.result.sofortNetto2027),
                        sub: "AG-Steuer: \(String(format: "%.1f%%", engine.result.upfrontTaxRatePct))",
                        tint: .primary
                    )
                    kpiCard(
                        title: "FA-Erstattung Okt. 2028",
                        value: "+\(eur(engine.result.finanzamtRefundOct2028))",
                        sub: "§ 34 Abs. 1 EStG",
                        tint: .green
                    )
                    kpiCard(
                        title: "Optimal-Netto Gesamt",
                        value: eur(engine.result.optimalNettoTotal),
                        sub: "Effektiv-Steuer: \(String(format: "%.1f%%", engine.result.finalTaxRatePct))",
                        tint: .blue
                    )
                    kpiCard(
                        title: "End-Liquidität (Ende 2028)",
                        value: eur(engine.result.liquidityEnd2028),
                        sub: "Frei verfügbares Cash",
                        tint: engine.result.liquidityEnd2028 >= 0 ? .indigo : .red
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Steuer-Hebel & Ersparnis-Karten")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        leverValueCard(
                            title: "bAV (§ 3 Nr. 63)",
                            invested: engine.result.solvedBav,
                            saved: engine.result.bavSavings,
                            tint: .blue
                        )
                        leverValueCard(
                            title: "DRV V0210 (§ 187a)",
                            invested: engine.result.solvedDrv,
                            saved: engine.result.drvSavings,
                            tint: .cyan
                        )
                        leverValueCard(
                            title: "Rürup (§ 10 EStG)",
                            invested: engine.result.solvedRuerup,
                            saved: engine.result.ruerupSavings,
                            tint: .green
                        )
                        leverValueCard(
                            title: "PV-IAB (§ 7g EStG)",
                            invested: engine.result.solvedPvPurchase,
                            saved: engine.result.iabSavings,
                            tint: .purple
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("2027 → 2028 Cashflow & Steuer-Vergleich")
                            .font(.headline)
                        InfoHelpButton(topic: .fuenftelregelung34) { activeTopic = $0 }
                    }
                    Chart {
                        BarMark(x: .value("Kategorie", "Sofort 2027"), y: .value("Betrag", engine.result.sofortNetto2027))
                            .foregroundStyle(.blue.gradient)
                        BarMark(x: .value("Kategorie", "FA Okt. 2028"), y: .value("Betrag", engine.result.finanzamtRefundOct2028))
                            .foregroundStyle(.green.gradient)
                        BarMark(x: .value("Kategorie", "Optimal-Netto"), y: .value("Betrag", engine.result.optimalNettoTotal))
                            .foregroundStyle(.indigo.gradient)
                    }
                    .frame(height: 190)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                if engine.input.turboEnabled && !engine.result.waterfallSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Sprinter Wasserfall-Brücke")
                                .font(.headline)
                            InfoHelpButton(topic: .sprinterRuhenszeit158, isWarning: true) { activeTopic = $0 }
                        }
                        Chart(engine.result.waterfallSteps) { step in
                            BarMark(
                                x: .value("Betrag", step.value),
                                y: .value("Komponente", step.label)
                            )
                            .foregroundStyle(step.isTotal ? Color.blue.gradient : (step.isPositive ? Color.green.gradient : Color.orange.gradient))
                        }
                        .frame(height: 210)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("1 · Sofort-Abrechnung Arbeitgeber (2027)")
                        .font(.headline)
                    detailRow("Effektive Abfindung Brutto", eur(engine.result.effectiveAbfindung))
                    detailRow("AG-Steuereinbehalt (ohne § 34)", "–\(eur(engine.result.agWithheldTax))", color: .red)
                    detailRow("Auszahlung Sofort-Netto 2027", eur(engine.result.sofortNetto2027), color: .blue)
                    Divider()
                    Text("2 · Endabrechnung Finanzamt (Okt. 2028)")
                        .font(.headline)
                    detailRow("Erstattung via Fünftelregelung", "+\(eur(engine.result.finanzamtRefundOct2028))", color: .green)
                    detailRow("Gesamt-Netto aus Abfindung", eur(engine.result.optimalNettoTotal), color: .blue)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                Button {
                    onExportPDF()
                } label: {
                    Label("PDF-Report für Verhandlung exportieren", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func kpiCard(title: String, value: String, sub: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func leverValueCard(title: String, invested: Double, saved: Double, tint: Color) -> some View {
        let pct = invested > 0 ? (saved / invested) * 100.0 : 0
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text("+\(eur(saved))")
                .font(.headline.bold())
                .foregroundStyle(saved > 0 ? .green : .secondary)
            Text("Einsatz: \(eur(invested)) (\(String(format: "%.0f%%", pct)))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func detailRow(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(color)
        }
    }
}

// MARK: - TAB 3: REICHWEITE (Inputs First -> KPI Cards -> Stacked Phases & Konto-Verlauf Area Chart)

struct ReichweiteTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var activeTopic: StatutoryTopic?

    private let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Parameter · Überleben ohne Job")
                        .font(.headline)

                    HStack {
                        Text("Austrittsmonat 2027").font(.subheadline)
                        Spacer()
                        Picker("", selection: $engine.input.payoutMonth2027) {
                            ForEach(1...12, id: \.self) { m in
                                Text("\(monthNames[m - 1]) 2027").tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: engine.input.payoutMonth2027) { _, _ in engine.recalculate() }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Einmal-Abfluss 2027 (Kredit/Urlaub/Puffer)").font(.subheadline)
                            Spacer()
                            Text(eur(engine.input.upfrontSpend2027)).font(.subheadline.bold())
                        }
                        Slider(value: $engine.input.upfrontSpend2027, in: 0...100_000, step: 1_000)
                            .onChange(of: engine.input.upfrontSpend2027) { _, _ in engine.recalculate() }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Monatl. Netto-Ausgaben (ohne GKV)").font(.subheadline)
                            Spacer()
                            Text(eur(engine.input.monthlyExpenses)).font(.subheadline.bold())
                        }
                        Slider(value: $engine.input.monthlyExpenses, in: 1_500...10_000, step: 100)
                            .onChange(of: engine.input.monthlyExpenses) { _, _ in engine.recalculate() }
                    }

                    Stepper("ALG-1 Anspruch: \(Int(engine.input.alg1ClaimMonths)) Monate", value: $engine.input.alg1ClaimMonths, in: 0...24, step: 1)
                        .onChange(of: engine.input.alg1ClaimMonths) { _, _ in engine.recalculate() }

                    HStack {
                        Text("GKV nach ALG-1").font(.subheadline)
                        Spacer()
                        Picker("", selection: $engine.input.postAlg1GkvMode) {
                            Text("Mindestbeitrag (~285 €)").tag("Mindestbeitrag")
                            Text("Familienvers. (0 €)").tag("Familienversicherung")
                            Text("Individuell").tag("Individuell")
                        }
                        .pickerStyle(.menu)
                        .onChange(of: engine.input.postAlg1GkvMode) { _, _ in engine.recalculate() }
                        InfoHelpButton(topic: .postAlg1Gkv) { activeTopic = $0 }
                    }

                    if engine.input.postAlg1GkvMode == "Individuell" {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Individueller GKV-Beitrag / Monat").font(.subheadline)
                                Spacer()
                                Text(eur(engine.input.customPostAlg1Gkv)).font(.subheadline.bold())
                            }
                            Slider(value: $engine.input.customPostAlg1Gkv, in: 0...1_400, step: 25)
                                .onChange(of: engine.input.customPostAlg1Gkv) { _, _ in engine.recalculate() }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Real-Zins / Inflation p.a.").font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f%%", engine.input.realReturnPct)).font(.subheadline.bold())
                        }
                        Slider(value: $engine.input.realReturnPct, in: -5.0...6.0, step: 0.5)
                            .onChange(of: engine.input.realReturnPct) { _, _ in engine.recalculate() }
                    }

                    Toggle("Gehalts-Überschuss vor Austritt sparen", isOn: $engine.input.savePreExitSalarySurplus)
                        .font(.subheadline)
                        .onChange(of: engine.input.savePreExitSalarySurplus) { _, _ in engine.recalculate() }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reichweite Standard")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(String(format: "%.1f", engine.result.standardRunwayMonths)) Mon.")
                            .font(.title3.bold())
                            .foregroundStyle(.blue)
                        Text("Bis \(monthLabel(engine.result.standardDepletedIdx))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reichweite Sprinter")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(String(format: "%.1f", engine.result.sprinterRunwayMonths)) Mon.")
                            .font(.title3.bold())
                            .foregroundStyle(.green)
                        Text("Bis \(monthLabel(engine.result.sprinterDepletedIdx))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Lebensphasen-Zeitstrahl")
                        .font(.headline)

                    Chart(engine.result.phaseSegments) { seg in
                        BarMark(
                            xStart: .value("Start", seg.startMonth),
                            xEnd: .value("Ende", seg.endMonth),
                            y: .value("Strategie", seg.strategy)
                        )
                        .foregroundStyle(seg.color)
                    }
                    .chartXAxis {
                        AxisMarks(values: [0, 5, 10, 15, 20, 25, 30]) { val in
                            AxisGridLine()
                            AxisValueLabel {
                                if let m = val.as(Int.self) {
                                    Text(shortMonthLabel(m))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 110)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], spacing: 6) {
                        legendDot(.indigo, "1. Gehaltsphase")
                        legendDot(.orange, "2. Ruhenszeit (GKV)")
                        legendDot(.cyan, "3. ALG-1 Bezug")
                        legendDot(.green, "4. Privatiers-Phase")
                    }
                    .font(.caption2)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Konto-Verlauf (€)")
                        .font(.title3.bold())

                    Text("Blau: Stand, den beide haben. Grün: Sprinter liegt vorn. Orange: Standard liegt vorn. Ein Punkt zeigt, wo das Geld aufgebraucht ist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Chart {
                        ForEach(engine.result.comparisonCurve) { pt in
                            AreaMark(
                                x: .value("Monat", pt.month),
                                yStart: .value("Basis", 0),
                                yEnd: .value("Gemeinsam", pt.sharedMinBalance)
                            )
                            .foregroundStyle(Color.blue.opacity(0.35))
                        }

                        ForEach(engine.result.comparisonCurve) { pt in
                            AreaMark(
                                x: .value("Monat", pt.month),
                                yStart: .value("Start", pt.sprinterAheadStart),
                                yEnd: .value("Ende", pt.sprinterAheadEnd)
                            )
                            .foregroundStyle(Color.green.opacity(0.45))
                        }

                        ForEach(engine.result.comparisonCurve) { pt in
                            AreaMark(
                                x: .value("Monat", pt.month),
                                yStart: .value("Start", pt.standardAheadStart),
                                yEnd: .value("Ende", pt.standardAheadEnd)
                            )
                            .foregroundStyle(Color.orange.opacity(0.45))
                        }

                        ForEach(engine.result.comparisonCurve) { pt in
                            LineMark(
                                x: .value("Monat", pt.month),
                                y: .value("Sprinter", pt.sprinterBalance),
                                series: .value("Strategie", "Sprinter")
                            )
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                        }

                        ForEach(engine.result.comparisonCurve) { pt in
                            LineMark(
                                x: .value("Monat", pt.month),
                                y: .value("Standard", pt.standardBalance),
                                series: .value("Strategie", "Standard")
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                        }

                        RuleMark(y: .value("Null", 0))
                            .foregroundStyle(.gray.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1))

                        RuleMark(x: .value("FA Okt 2028", 21))
                            .foregroundStyle(.purple.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                        PointMark(
                            x: .value("Standard Ende", engine.result.standardDepletedIdx),
                            y: .value("Null", 0)
                        )
                        .foregroundStyle(.blue)
                        .symbolSize(65)

                        PointMark(
                            x: .value("Sprinter Ende", engine.result.sprinterDepletedIdx),
                            y: .value("Null", 0)
                        )
                        .foregroundStyle(.green)
                        .symbolSize(65)
                    }
                    .chartXAxis {
                        AxisMarks(values: [0, 10, 21, 30, 42]) { val in
                            AxisGridLine()
                            AxisValueLabel {
                                if let m = val.as(Int.self) {
                                    Text(m == 21 ? "Okt 2028" : monthLabel(m))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing) { val in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = val.as(Double.self) {
                                    Text(eur(v))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 230)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), alignment: .leading)], spacing: 6) {
                        legendSquare(.blue.opacity(0.6), "Gemeinsamer Stand")
                        legendSquare(.green.opacity(0.75), "Sprinter vorn")
                        legendSquare(.orange.opacity(0.75), "Standard vorn")
                        legendDash(.green, "Linie Sprinter")
                        legendDash(.blue, "Linie Standard")
                        legendDash(.purple, "FA Okt 2028")
                    }
                    .font(.caption2)
                    .padding(.top, 4)

                    Divider()

                    VStack(spacing: 8) {
                        HStack {
                            Text("")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Sprinter")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                                .frame(width: 90, alignment: .leading)
                            Text("Standard")
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)
                                .frame(width: 90, alignment: .leading)
                        }
                        milestoneRow("Auszahlung", monthLabel(engine.result.sprinterPayoutMonthIdx), monthLabel(engine.result.standardPayoutMonthIdx))
                        milestoneRow("ALG 1 endet", monthLabel(engine.result.sprinterAlg1EndIdx), monthLabel(engine.result.standardAlg1EndIdx))
                        milestoneRow("Geld aufgebraucht", monthLabel(engine.result.sprinterDepletedIdx), monthLabel(engine.result.standardDepletedIdx), isBold: true)
                    }
                    .padding(.top, 4)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            PinnedKpiFooter()
                .allowsHitTesting(false)
        }
    }

    private func milestoneRow(_ label: String, _ sprinterVal: String, _ standardVal: String, isBold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(isBold ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(sprinterVal)
                .font(isBold ? .subheadline.bold() : .subheadline)
                .frame(width: 90, alignment: .leading)
            Text(standardVal)
                .font(isBold ? .subheadline.bold() : .subheadline)
                .frame(width: 90, alignment: .leading)
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func legendSquare(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func legendDash(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 12, height: 3)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

// MARK: - TAB 4: JOB-SWITCH (Identical Monthly Multi-Layer Filled Area Chart to Reichweite)

struct JobSwitchTabView: View {
    @EnvironmentObject var engine: TaxEngineHost
    @Binding var activeTopic: StatutoryTopic?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Parameter · Gehalts-Switch")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Neues Jahresgehalt Brutto").font(.subheadline)
                            Spacer()
                            Text(eur(engine.input.newJobGrossAnnual)).font(.subheadline.bold())
                        }
                        Slider(value: $engine.input.newJobGrossAnnual, in: 25_000...180_000, step: 2_500)
                            .onChange(of: engine.input.newJobGrossAnnual) { _, _ in engine.recalculate() }
                    }

                    Stepper("Job-Start nach Austritt: \(Int(engine.input.jobStartDelayMonths)) Mon.", value: $engine.input.jobStartDelayMonths, in: 0...24, step: 1)
                        .onChange(of: engine.input.jobStartDelayMonths) { _, _ in engine.recalculate() }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Gehaltswachstum p.a. (symmetrisch)").font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f%%", engine.input.salaryGrowthPct)).font(.subheadline.bold())
                        }
                        Slider(value: $engine.input.salaryGrowthPct, in: 0.0...6.0, step: 0.5)
                            .onChange(of: engine.input.salaryGrowthPct) { _, _ in engine.recalculate() }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monatl. Netto-Einbuße")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("–\(eur(engine.result.monthlyNetLoss))/Mo")
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                        Text("Alt: \(eur(engine.result.oldMonthlyNet)) vs. \(eur(engine.result.newMonthlyNet))")
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Break-Even Sprinter")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(engine.result.sprinterBreakEvenMonthIdx.map { monthLabel($0) } ?? "> 20 Jahre")
                            .font(.title3.bold())
                            .foregroundStyle(.green)
                        Text("Std: \(engine.result.standardBreakEvenMonthIdx.map { monthLabel($0) } ?? "> 20 Jahre")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Vermögens-Vorsprung (€)")
                        .font(.title3.bold())

                    Text("Blau: Stand, den beide haben. Grün: Sprinter liegt vorn. Orange: Standard liegt vorn. Ein Punkt zeigt den Break-Even (0 €).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Chart {
                        ForEach(engine.result.switchComparisonCurve) { pt in
                            AreaMark(
                                x: .value("Monat", pt.month),
                                yStart: .value("Basis", 0),
                                yEnd: .value("Gemeinsam", pt.sharedMinBalance)
                            )
                            .foregroundStyle(Color.blue.opacity(0.35))
                        }

                        ForEach(engine.result.switchComparisonCurve) { pt in
                            AreaMark(
                                x: .value("Monat", pt.month),
                                yStart: .value("Start", pt.sprinterAheadStart),
                                yEnd: .value("Ende", pt.sprinterAheadEnd)
                            )
                            .foregroundStyle(Color.green.opacity(0.45))
                        }

                        ForEach(engine.result.switchComparisonCurve) { pt in
                            AreaMark(
                                x: .value("Monat", pt.month),
                                yStart: .value("Start", pt.standardAheadStart),
                                yEnd: .value("Ende", pt.standardAheadEnd)
                            )
                            .foregroundStyle(Color.orange.opacity(0.45))
                        }

                        ForEach(engine.result.switchComparisonCurve) { pt in
                            LineMark(
                                x: .value("Monat", pt.month),
                                y: .value("Sprinter", pt.sprinterBalance),
                                series: .value("Strategie", "Sprinter")
                            )
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                        }

                        ForEach(engine.result.switchComparisonCurve) { pt in
                            LineMark(
                                x: .value("Monat", pt.month),
                                y: .value("Standard", pt.standardBalance),
                                series: .value("Strategie", "Standard")
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                        }

                        RuleMark(y: .value("Null", 0))
                            .foregroundStyle(.gray.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1))

                        RuleMark(x: .value("FA Okt 2028", 21))
                            .foregroundStyle(.purple.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                        if let stdBe = engine.result.standardBreakEvenMonthIdx {
                            PointMark(
                                x: .value("Standard BE", stdBe),
                                y: .value("Null", 0)
                            )
                            .foregroundStyle(.blue)
                            .symbolSize(65)
                        }

                        if let sprBe = engine.result.sprinterBreakEvenMonthIdx {
                            PointMark(
                                x: .value("Sprinter BE", sprBe),
                                y: .value("Null", 0)
                            )
                            .foregroundStyle(.green)
                            .symbolSize(65)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: engine.result.switchAxisTicks) { val in
                            AxisGridLine()
                            AxisValueLabel {
                                if let m = val.as(Int.self) {
                                    Text(monthLabel(m))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing) { val in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = val.as(Double.self) {
                                    Text(eur(v))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 230)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), alignment: .leading)], spacing: 6) {
                        legendSquare(.blue.opacity(0.6), "Gemeinsamer Stand")
                        legendSquare(.green.opacity(0.75), "Sprinter vorn")
                        legendSquare(.orange.opacity(0.75), "Standard vorn")
                        legendDash(.green, "Linie Sprinter")
                        legendDash(.blue, "Linie Standard")
                        legendDash(.purple, "FA Okt 2028")
                    }
                    .font(.caption2)
                    .padding(.top, 4)

                    Divider()

                    VStack(spacing: 8) {
                        HStack {
                            Text("")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Sprinter")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                                .frame(width: 90, alignment: .leading)
                            Text("Standard")
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)
                                .frame(width: 90, alignment: .leading)
                        }
                        milestoneRow("Job-Start", monthLabel(engine.result.sprinterJobStartIdx), monthLabel(engine.result.standardJobStartIdx))
                        milestoneRow("Puffer bei Start", eur(engine.result.sprinterCushionAtStart), eur(engine.result.standardCushionAtStart))
                        milestoneRow(
                            "Break-Even",
                            engine.result.sprinterBreakEvenMonthIdx.map { monthLabel($0) } ?? "> 20 Jahre",
                            engine.result.standardBreakEvenMonthIdx.map { monthLabel($0) } ?? "> 20 Jahre",
                            isBold: true
                        )
                    }
                    .padding(.top, 4)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            PinnedKpiFooter()
                .allowsHitTesting(false)
        }
    }

    private func milestoneRow(_ label: String, _ sprinterVal: String, _ standardVal: String, isBold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(isBold ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(sprinterVal)
                .font(isBold ? .subheadline.bold() : .subheadline)
                .frame(width: 90, alignment: .leading)
            Text(standardVal)
                .font(isBold ? .subheadline.bold() : .subheadline)
                .frame(width: 90, alignment: .leading)
        }
    }

    private func legendSquare(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func legendDash(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 12, height: 3)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

// MARK: - UIKit Share Sheet Wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
