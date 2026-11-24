import SwiftUI

enum StatutoryTopic: String, Identifiable {
    case recht2027Overview
    case agFiktivgehalt
    case gkvGracePeriod19
    case sprinterRuhenszeit158
    case sperrzeit159
    case splittingFuenftelFalle
    case bav63
    case drvV0210
    case ruerup10
    case pvIab7g
    case fuenftelregelung34
    case postAlg1Gkv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recht2027Overview: return "Rechengrößen & Recht 2027"
        case .agFiktivgehalt: return "AG-Fiktivgehalt & Wachstumschancengesetz"
        case .gkvGracePeriod19: return "§ 19 Abs. 2 SGB V · Nachgehender Anspruch"
        case .sprinterRuhenszeit158: return "Sprinterprämie & Ruhenszeit (§ 158 SGB III)"
        case .sperrzeit159: return "ALG-1 Sperrzeit (§ 159 SGB III)"
        case .splittingFuenftelFalle: return "Splittingtarif & Fünftel-Falle"
        case .bav63: return "bAV-Umwandlung (§ 3 Nr. 63 EStG)"
        case .drvV0210: return "DRV-Ausgleich V0210 (§ 187a SGB VI)"
        case .ruerup10: return "Rürup / Basisrente (§ 10 EStG)"
        case .pvIab7g: return "Gewerbliche PV-Anlage & IAB (§ 7g EStG)"
        case .fuenftelregelung34: return "Fünftelregelung (§ 34 EStG)"
        case .postAlg1Gkv: return "Freiwillige GKV nach ALG-1"
        }
    }

    var bodyText: String {
        switch self {
        case .recht2027Overview:
            return """
            • Grundfreibetrag 2027: 12.564 € (Single) / 25.128 € (Splitting)
            • 42%-Tarifzone ab 70.600 €; 45% ab 250.000 €; 47% ab 280.000 €
            • BBG RV/ALV 2027: 106.200 €/Jahr (8.850 €/Monat)
            • BBG KV/PV 2027: 76.500 €/Jahr (6.375 €/Monat)
            • Rürup-Höchstbetrag 2027: 32.308 € (Single) / 64.616 € (Splitting)
            • bAV-Höchstbetrag 2027: 50.976 € (42.480 € Vervielfältigung + 8.496 €)
            """
        case .agFiktivgehalt:
            return "Seit dem Wachstumschancengesetz wendet der Arbeitgeber die Fünftelregelung nicht mehr beim Lohnsteuerabzug an. Der Steuervorteil wird über die Einkommensteuererklärung 2027 (Erstattung ca. Okt. 2028) realisiert."
        case .gkvGracePeriod19:
            return "Waren Sie vor dem Austritt gesetzlich pflichtversichert, greift nach Ende der Beschäftigung 1 Monat lang der kostenlose nachgehende Leistungsanspruch (§ 19 Abs. 2 SGB V) – sofern keine Familienversicherung besteht."
        case .sprinterRuhenszeit158:
            return "Wird die Kündigungsfrist verkürzt und eine erhöhte Abfindung gezahlt, ruht der ALG-1-Anspruch bis zum regulären Fristende (§ 158 SGB III). In dieser Zeit fällt der freiwillige GKV/PV-Höchstsatz (~1.320 €/Mo) an (abzugsfähig nach § 10 EStG)."
        case .sperrzeit159:
            return "Ohne wichtigen Grund führt ein Aufhebungsvertrag zu einer 12-wöchigen Sperrzeit (§ 159 SGB III), die die Gesamtanspruchsdauer um mindestens ein Viertel mindert (§ 148 SGB III)."
        case .splittingFuenftelFalle:
            return "Bei Zusammenveranlagung wird die Fünftelregelung auf das gemeinsame zvE angewendet. Verdient der Ehepartner gut, kann das Partnereinkommen den Fünftel-Hebel abschwächen (Fünftel-Falle)."
        case .bav63:
            return "Bis zu 50.976 € (42.480 € Vervielfältigungsregel für 10 Dienstjahre + 8.496 € Jahresfreibetrag 2027) werden vor Lohnsteuerabzug direkt abgezogen. Die Steuerersparnis erfolgt sofort 2027."
        case .drvV0210:
            return "Direktzahlung des Arbeitgebers in die gesetzliche Rentenversicherung zum Ausgleich von Rentenabschlägen (§ 187a SGB VI, Formular V0210): 50 % sind nach § 3 Nr. 28 EStG komplett steuerfrei (ohne Kürzung des Rürup-Limits), 50 % unterliegen der Fünftelregelung."
        case .ruerup10:
            return "Beiträge zur Basisrente (§ 10 Abs. 1 Nr. 2 EStG) mindern das Basis-zvE und wirken über R 34.2 Abs. 1 EStR als negativer Überlauf direkt in die Fünftelregelung (oft >100 % Steuererstattung im Sweet-Spot)."
        case .pvIab7g:
            return "Über einen Investitionsabzugsbetrag (§ 7g EStG) können 50 % einer geplanten gewerblichen PV-Investition (bis 400.000 € → 200.000 € Abzug) bereits 2027 steuermindernd geltend gemacht werden."
        case .fuenftelregelung34:
            return "Nach § 34 Abs. 1 EStG wird die außerordentliche Abfindung rechnerisch auf 5 Jahre verteilt (1/5), wodurch die Steuerprogression deutlich gedämpft wird. Voraussetzung ist die Zusammenballung in einem Kalenderjahr."
        case .postAlg1Gkv:
            return "Nach Ende des ALG-1-Bezugs gilt der GKV-Mindestbeitrag (~280 €/Mo), solange keine nennenswerten Zins-, Dividenden- oder Mieteinnahmen anfallen. Kursgewinne aus privaten ETF-/Aktienverkäufen bleiben dabei beitragsfrei."
        }
    }
}

struct InfoHelpButton: View {
    let topic: StatutoryTopic
    var isWarning: Bool = false
    let onTap: (StatutoryTopic) -> Void

    var body: some View {
        Button {
            onTap(topic)
        } label: {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "questionmark.circle")
                .font(.caption)
                .foregroundStyle(isWarning ? .orange : .blue)
        }
        .buttonStyle(.borderless)
    }
}

struct StatutoryInfoSheet: View {
    let topic: StatutoryTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(topic.title)
                        .font(.title3.bold())
                    Text(topic.bodyText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Steuer- & Rechts-Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
