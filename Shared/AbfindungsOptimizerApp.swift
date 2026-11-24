import SwiftUI
import JavaScriptCore
import Charts

enum PreExitGkvStatus: String, CaseIterable, Identifiable, Codable {
    case pflicht = "Pflichtversichert (§ 19 Abs. 2 SGB V)"
    case freiwillig = "Freiwillig gesetzlich"
    case pkv = "Privat (PKV)"
    var id: String { rawValue }
}

enum SolverMode: String, CaseIterable, Identifiable, Codable {
    case manual = "Manuell"
    case optimal = "Optimal-Netto"
    case liquidity = "Liquiditäts-Fokus"
    case retirement = "Altersvorsorge"
    case custom = "Eigene Priorität"
    var id: String { rawValue }

    var engineKey: String {
        switch self {
        case .manual: return "manual"
        case .optimal: return "optimal"
        case .liquidity: return "liquidity"
        case .retirement: return "retirement"
        case .custom: return "custom"
        }
    }
}

struct SimulationInput: Codable, Equatable {
    var altesMonatsgehalt: Double = 8_333
    var fristMonate: Int = 5
    var bruttoAbfindung: Double = 120_000
    var agFiktivGehalt: Double = 100_000
    var neuesGehalt2027: Double = 25_000
    var kvZusatzbeitragPct: Double = 2.5
    var preExitGkv: PreExitGkvStatus = .pflicht
    var isSplitting: Bool = false
    var partnerGehalt2027: Double = 0
    var churchRate: Double = 0.0
    var turboEnabled: Bool = false
    var turboFaktor: Double = 1.5
    var alg1SatzPct: Double = 60.0
    var includeAlg1Loss: Bool = false
    var solverMode: String = "manual"
    var customSolverOrder: [String] = ["bav", "drv", "ruerup", "iab"]
    var bavAmount: Double = 0
    var drvV0210Amount: Double = 0
    var ruerupAmount: Double = 0
    var pvIabPurchase: Double = 0
    var monthlyExpenses: Double = 3_500
    var alg1ClaimMonths: Int = 12
    var postAlg1GkvMode: String = "Mindestbeitrag"
    var newJobGrossAnnual: Double = 65_000
    var salaryGrowthPct: Double = 2.0
}

struct WaterfallStep: Identifiable, Decodable {
    let id: String
    let label: String
    let delta: Double
    let isPositive: Bool
}

struct RunwayPhaseSegment: Identifiable, Decodable {
    let id: String
    let strategy: String
    let phaseName: String
    let startMonth: Double
    let durationMonths: Double
}

struct CrossoverPoint: Identifiable, Decodable {
    var id: Int { year }
    let year: Int
    let netDelta: Double
}

struct SimulationResult: Decodable {
    let sofortNetto2027: Double
    let finanzamtRefundOct2028: Double
    let optimalNettoTotal: Double
    let ruerupCapRemaining: Double
    let iabSweetSpotDeduction: Double
    let partnerSplittingBreakEvenMax: Double
    let ruhenszeitMonths: Int
    let waterfallSteps: [WaterfallStep]
    let standardRunwayMonths: Double
    let sprinterRunwayMonths: Double
    let runwaySegments: [RunwayPhaseSegment]
    let solvedBav: Double
    let solvedDrv: Double
    let solvedRuerup: Double
    let solvedPvPurchase: Double
    let crossoverPoints: [CrossoverPoint]
    let breakEvenYear: Int
}

@Observable
final class TaxEngineBridge {
    private let context = JSContext()
    var input = SimulationInput()
    var selectedSolver: SolverMode = .manual
    private(set) var result = SimulationResult(
        sofortNetto2027: 0, finanzamtRefundOct2028: 0, optimalNettoTotal: 0,
        ruerupCapRemaining: 0, iabSweetSpotDeduction: 0, partnerSplittingBreakEvenMax: 0,
        ruhenszeitMonths: 0, waterfallSteps: [], standardRunwayMonths: 0,
        sprinterRunwayMonths: 0, runwaySegments: [],
        solvedBav: 0, solvedDrv: 0, solvedRuerup: 0, solvedPvPurchase: 0,
        crossoverPoints: [], breakEvenYear: -1
    )

    init() {
        if let url = Bundle.main.url(forResource: "TaxEngine2027", withExtension: "js"),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            context?.evaluateScript(script)
        }
        recalculate()
    }

    func recalculate() {
        input.solverMode = selectedSolver.engineKey
        guard let data = try? JSONEncoder().encode(input),
              let json = String(data: data, encoding: .utf8),
              let raw = context?.evaluateScript("JSON.stringify(runSimulation(\(json)))")?.toString(),
              let outData = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(SimulationResult.self, from: outData) else { return }
        result = decoded
        if selectedSolver != .manual {
            input.bavAmount = decoded.solvedBav
            input.drvV0210Amount = decoded.solvedDrv
            input.ruerupAmount = decoded.solvedRuerup
            input.pvIabPurchase = decoded.solvedPvPurchase
        }
    }

    func applyPreset(_ name: String) {
        selectedSolver = .manual
        switch name {
        case "Standard":
            input = SimulationInput(altesMonatsgehalt: 8_333, fristMonate: 5, bruttoAbfindung: 120_000, agFiktivGehalt: 100_000, neuesGehalt2027: 25_000, turboEnabled: false)
        case "Sprinter":
            input = SimulationInput(altesMonatsgehalt: 9_000, fristMonate: 6, bruttoAbfindung: 140_000, agFiktivGehalt: 108_000, neuesGehalt2027: 0, turboEnabled: true, turboFaktor: 1.5, bavAmount: 25_000)
        case "Privatier":
            input = SimulationInput(altesMonatsgehalt: 10_500, fristMonate: 6, bruttoAbfindung: 240_000, agFiktivGehalt: 126_000, neuesGehalt2027: 0, isSplitting: true, partnerGehalt2027: 15_000, turboEnabled: true, bavAmount: 50_976, ruerupAmount: 30_000, pvIabPurchase: 0)
        default: break
        }
        recalculate()
    }

    @MainActor
    func generatePdfURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AbfindungsPilot_2027_Report.pdf")
        let reportView = ExecutivePdfReportView(input: input, result: result)
        let renderer = ImageRenderer(content: reportView)
        renderer.proposedSize = .init(width: 595, height: 842)

        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        return url
    }
}

struct ExecutivePdfReportView: View {
    let input: SimulationInput
    let result: SimulationResult

    private func eur(_ v: Double) -> String {
        v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AbfindungsPilot 2027 · Pro v27.0")
                        .font(.title2.bold())
                    Text("Executive Simulation Summary (§ 34 Abs. 1 EStG Fünftelregelung)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.bold())
            }
            Divider()

            HStack(spacing: 12) {
                kpiBox(title: "Sofort-Netto 2027", value: eur(result.sofortNetto2027), color: .primary)
                kpiBox(title: "FA-Erstattung Okt. 2028", value: "+" + eur(result.finanzamtRefundOct2028), color: .green)
                kpiBox(title: "Optimal-Netto Gesamt", value: eur(result.optimalNettoTotal), color: .blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Parameter & Rahmenbedingungen 2027").font(.headline)
                row("Abfindung Brutto", eur(input.bruttoAbfindung))
                row("Altes Monatsgehalt / Frist", "\(eur(input.altesMonatsgehalt)) / \(input.fristMonate) Monate")
                row("Neues Gehalt 2027", eur(input.neuesGehalt2027))
                row("Sprinter-Option", input.turboEnabled ? "Aktiv (\(String(format: "%.1fx", input.turboFaktor)), \(result.ruhenszeitMonths) Mo Ruhenszeit)" : "Inaktiv")
                row("Veranlagung", input.isSplitting ? "Zusammenveranlagung (Splitting)" : "Einzelveranlagung")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("2. Steuer-Optimierung (\(input.solverMode.capitalized))").font(.headline)
                row("bAV-Einzahlung (§ 3 Nr. 63 EStG)", eur(input.bavAmount))
                row("DRV V0210 Ausgleich (50% steuerfrei)", eur(input.drvV0210Amount))
                row("Rürup / Basisrente (§ 10 EStG)", eur(input.ruerupAmount))
                row("PV-IAB Investition (50% Abzug)", eur(input.pvIabPurchase))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("3. Reichweite & Gehalts-Switch Break-Even").font(.headline)
                row("Reichweite Standard / Sprinter", String(format: "%.1f Mo / %.1f Mo", result.standardRunwayMonths, result.sprinterRunwayMonths))
                row("Neues Zielgehalt / Break-Even", result.breakEvenYear > 0 ? "\(eur(input.newJobGrossAnnual)) p.a. (Jahr \(result.breakEvenYear))" : "\(eur(input.newJobGrossAnnual)) p.a. (> 15 Jahre)")
            }

            Spacer()
            Divider()
            Text("Hinweis: Mathematisches Simulations- und Rechenprogramm auf Basis der Steuer- und Sozialversicherungs-Rechengrößen 2027. Ersetzt keine individuelle Steuer- oder Rechtsberatung (StBerG).")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 595, height: 842)
        .background(Color.white)
    }

    private func kpiBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline.bold()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.bold())
        }
    }
}

@main
struct AbfindungsOptimizerApp: App {
    @State private var engine = TaxEngineBridge()
    var body: some Scene {
        WindowGroup { MainView(engine: engine) }
    }
}

struct MainView: View {
    @Bindable var engine: TaxEngineBridge
    @State private var selectedInfoTopic: StatutoryTopic?

    private func eur(_ v: Double) -> String {
        v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))
    }

    private func leverDisplayName(_ key: String) -> String {
        switch key {
        case "bav": return "1. bAV (§ 3 Nr. 63 EStG)"
        case "drv": return "2. DRV V0210 (§ 187a SGB VI)"
        case "ruerup": return "3. Rürup / Basisrente (§ 10)"
        case "iab": return "4. PV-IAB (§ 7g EStG)"
        default: return key
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Schnell-Szenarien (1-Click Presets)") {
                    HStack {
                        ForEach(["Standard", "Sprinter", "Privatier"], id: \.self) { preset in
                            Button(preset) { engine.applyPreset(preset) }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                Section("A · Basisdaten & Sprinter 2027") {
                    sliderRow("Abfindung Brutto", value: $engine.input.bruttoAbfindung, range: 10_000...500_000, step: 2_500)
                    sliderRow("Altes Monatsgehalt", value: $engine.input.altesMonatsgehalt, range: 2_500...25_000, step: 250)
                    Stepper("Kündigungsfrist: \(engine.input.fristMonate) Monate", value: $engine.input.fristMonate, in: 1...12)
                    sliderRow("AG-Fiktivgehalt", value: $engine.input.agFiktivGehalt, range: 20_000...250_000, step: 2_500, topic: .agFiktiv)
                    sliderRow("Neues Gehalt 2027", value: $engine.input.neuesGehalt2027, range: 0...150_000, step: 1_000)

                    HStack(spacing: 4) {
                        Picker("Vor-Austritt GKV", selection: $engine.input.preExitGkv) {
                            ForEach(PreExitGkvStatus.allCases) { Text($0.rawValue).tag($0) }
                        }
                        InfoIconButton(topic: .preExitGkv, selectedTopic: $selectedInfoTopic)
                    }

                    HStack {
                        Toggle("Sprinter-Option (Vorzeitiger Austritt)", isOn: $engine.input.turboEnabled)
                        InfoIconButton(topic: .sprinterLegal, selectedTopic: $selectedInfoTopic)
                    }

                    if engine.input.turboEnabled {
                        sliderRow("Sprinter-Faktor (\(String(format: "%.1fx", engine.input.turboFaktor)))", value: $engine.input.turboFaktor, range: 0.5...2.5, step: 0.1, isCurrency: false)
                        HStack(spacing: 4) {
                            Text("ALG-1 Ruhenszeit (§ 158 SGB III): \(engine.result.ruhenszeitMonths) Monate")
                                .font(.caption).foregroundStyle(.secondary)
                            InfoIconButton(topic: .alg1Rules, selectedTopic: $selectedInfoTopic)
                        }
                    }

                    HStack {
                        Toggle("Zusammenveranlagung (Splitting)", isOn: $engine.input.isSplitting)
                        InfoIconButton(topic: .tarifSplitting, selectedTopic: $selectedInfoTopic)
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
                                Text("\(idx + 1). \(leverDisplayName(key).dropFirst(3))")
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
                    sliderRow("Rürup / Basisrente (frei: \(eur(engine.result.ruerupCapRemaining)))", value: $engine.input.ruerupAmount, range: 0...64_000, step: 500, topic: .ruerup10)
                    sliderRow("PV-Investition (50% IAB)", value: $engine.input.pvIabPurchase, range: 0...400_000, step: 2_500, topic: .pvIab7g)
                    Button("🎯 IAB Sweet-Spot anwenden (zvE → 0 €)") {
                        engine.selectedSolver = .manual
                        engine.input.pvIabPurchase = min(400_000, engine.result.iabSweetSpotDeduction * 2)
                        engine.recalculate()
                    }
                    .foregroundStyle(.blue)
                }

                if engine.input.turboEnabled {
                    Section("Sprinter Netto-Brücke") {
                        Chart(engine.result.waterfallSteps) { step in
                            BarMark(x: .value("Betrag", step.delta), y: .value("Faktor", step.label))
                                .foregroundStyle(step.isPositive ? Color.green : Color.red)
                        }
                        .frame(height: 190)
                    }
                }

                Section {
                    sliderRow("Monatliche Ausgaben", value: $engine.input.monthlyExpenses, range: 1_500...12_000, step: 250)
                    Chart(engine.result.runwaySegments) { seg in
                        BarMark(
                            xStart: .value("Start", seg.startMonth),
                            xEnd: .value("Ende", seg.startMonth + seg.durationMonths),
                            y: .value("Strategie", seg.strategy)
                        )
                        .foregroundStyle(by: .value("Phase", seg.phaseName))
                    }
                    .frame(height: 120)
                    Text("Reichweite: Standard \(engine.result.standardRunwayMonths, specifier: "%.1f") Mo · Sprinter \(engine.result.sprinterRunwayMonths, specifier: "%.1f") Mo")
                        .font(.caption.bold())
                } header: {
                    HStack(spacing: 4) {
                        Text("C · Finanzielle Reichweite (Runway)")
                        InfoIconButton(topic: .liquidityTimeline, selectedTopic: $selectedInfoTopic)
                    }
                }

                Section("D · Gehalts-Switch / Break-Even") {
                    sliderRow("Neues Zielgehalt (Brutto/Jahr)", value: $engine.input.newJobGrossAnnual, range: 20_000...180_000, step: 2_500)
                    sliderRow("Gehaltswachstum p.a. (\(String(format: "%.1f%%", engine.input.salaryGrowthPct)))", value: $engine.input.salaryGrowthPct, range: 0...6.0, step: 0.5, isCurrency: false)
                    Chart(engine.result.crossoverPoints) { pt in
                        AreaMark(x: .value("Jahr", pt.year), y: .value("Kumulierter Vorteil", pt.netDelta))
                            .foregroundStyle(Color.blue.opacity(0.18))
                        LineMark(x: .value("Jahr", pt.year), y: .value("Kumulierter Vorteil", pt.netDelta))
                            .foregroundStyle(Color.blue)
                        RuleMark(y: .value("Break-Even", 0))
                            .foregroundStyle(Color.red.opacity(0.6))
                    }
                    .frame(height: 160)
                    Text(engine.result.breakEvenYear > 0
                         ? "Break-Even erreicht in Jahr \(engine.result.breakEvenYear) nach Austritt"
                         : "Kein Break-Even innerhalb von 15 Jahren (Abfindung überwiegt)")
                        .font(.caption.bold())
                        .foregroundStyle(engine.result.breakEvenYear > 0 ? .orange : .green)
                }
            }
            .navigationTitle("AbfindungsPilot 2027")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selectedInfoTopic = .recht2027
                    } label: {
                        Label("Recht 2027", systemImage: "scale.3d")
                            .font(.caption.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Text("v27.1")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())

                        ShareLink(item: engine.generatePdfURL()) {
                            Label("PDF", systemImage: "doc.richtext")
                        }
                    }
                }
            }
            .sheet(item: $selectedInfoTopic) { topic in
                StatutoryInfoSheetView(topic: topic)
            }
            .onChange(of: engine.input) { _, _ in engine.recalculate() }
            .onChange(of: engine.selectedSolver) { _, _ in engine.recalculate() }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Sofort 2027").font(.caption2).foregroundStyle(.secondary)
                        Text(eur(engine.result.sofortNetto2027)).font(.subheadline.bold())
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("FA Okt. 2028").font(.caption2).foregroundStyle(.secondary)
                        Text("+" + eur(engine.result.finanzamtRefundOct2028)).font(.subheadline.bold()).foregroundStyle(.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Optimal-Netto").font(.caption2).foregroundStyle(.secondary)
                        Text(eur(engine.result.optimalNettoTotal)).font(.headline.bold()).foregroundStyle(.blue)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .overlay(Divider(), alignment: .top)
            }
        }
    }

    @ViewBuilder
    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, isCurrency: Bool = true, topic: StatutoryTopic? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.subheadline)
                if let topic {
                    InfoIconButton(topic: topic, selectedTopic: $selectedInfoTopic)
                }
                Spacer()
                Text(isCurrency ? eur(value.wrappedValue) : String(format: "%.1f", value.wrappedValue)).bold()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
