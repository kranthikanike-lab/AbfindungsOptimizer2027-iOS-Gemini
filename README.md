# AbfindungsPilot (iPhone)

Native SwiftUI iOS port of the **Abfindungs-Optimizer 2027** (*Pro v27.0*). All German 2027 tax and social security logic (§ 32a Tarif, *Fünftelregelung* § 34 Abs. 1 EStG, R 34.2 EStR negative spillover, Soli, *Wachstumschancengesetz* upfront payroll vs. *Finanzamt* refund, bAV/DRV V0210/Rürup/PV-IAB, 4-Mode Auto-Solver, Sprinter-Bilanz, Cash-Burn Runway, and Gehalts-Switch/Break-Even) runs inside `Shared/TaxEngine2027.js` via Apple `JavaScriptCore`, with native **Swift Charts**, contextual statutory info sheets, and **A4 PDF** report export.

## Screens & Modules (iPhone, iOS 17+)

| Section | Content |
| :--- | :--- |
| **Schnell-Szenarien** | 1-Click presets (`Standard`, `Sprinter`, `Privatier`) |
| **A · Basisdaten & Sprinter** | Severance & salary inputs, pre-exit GKV status (§ 19 Abs. 2 SGB V), Sprinter multiplier & § 158 SGB III *Ruhenszeit*, Splittingtarif break-even |
| **B · Auto-Solver & Steuer-Hebel** | 5 solver modes (`Manuell`, `Optimal-Netto`, `Liquiditäts-Fokus`, `Altersvorsorge`, `Eigene Priorität` with reordering), bAV (§ 3 Nr. 63), DRV V0210, Rürup (§ 10), PV-IAB (§ 7g) + Sweet-Spot |
| **Sprinter Netto-Brücke** | Horizontal waterfall chart isolating net Sprinter premium & tax leverage from lost net salary & GKV |
| **C · Reichweite (Runway)** | Multi-phase survival timeline comparing Standard vs. Sprinter across salary, *Ruhenszeit*, and ALG 1 |
| **D · Gehalts-Switch / Break-Even** | 15-year cumulative net delta trajectory chart with automatic break-even year detection |
| **Sticky Bottom KPI Bar** | Live `Sofort 2027`, `FA Okt. 2028` refund, and `Optimal-Netto` totals |

**Top Toolbar:** `Recht 2027` statutory reference sheet, version badge (`v27.1`), and native A4 PDF `ShareLink` export.

## Repository Layout

```text
├── project.yml                              # XcodeGen spec (Display Name: AbfindungsPilot)
├── Shared/
│   ├── AbfindungsOptimizerApp.swift         # SwiftUI views, Swift Charts & A4 PDF ImageRenderer
│   ├── StatutoryInfoSheet.swift             # Contextual ? / ! statutory info modals (Recht 2027)
│   ├── TaxEngine2027.js                     # 2027 EStG/SGB calculation engine, solver & runway math
│   └── Assets.xcassets/AppIcon.appiconset/  # 1024x1024 automotive-to-Euro app icon
└── .github/workflows/
    ├── build-ios.yml                        # Ubuntu Node.js CI verifying TaxEngine2027.js on push
    └── testflight.yml                       # Manual Xcode 26 archive & App Store Connect upload
