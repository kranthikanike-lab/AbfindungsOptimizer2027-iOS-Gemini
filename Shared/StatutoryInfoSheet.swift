import SwiftUI

enum StatutoryTopic: String, Identifiable {
    case recht2027
    case agFiktiv
    case preExitGkv
    case postAlg1Gkv
    case tarifSplitting
    case sprinterLegal
    case alg1Rules
    case bav63
    case ruerup10
    case drvV0210
    case pvIab7g
    case liquidityTimeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recht2027:         return "Rechengrößen & Recht 2027"
        case .agFiktiv:          return "AG-Fiktivgehalt & Lohnsteuerabzug"
        case .preExitGkv:        return "GKV-Status vor Austritt (§ 19 SGB V)"
        case .postAlg1Gkv:       return "Freiwillige GKV nach ALG 1"
        case .tarifSplitting:    return "Grund- vs. Splittingtarif"
        case .sprinterLegal:     return "Sprinterprämie (§ 34 EStG)"
        case .alg1Rules:         return "ALG 1: Ruhenszeit vs. Sperrzeit"
        case .bav63:             return "bAV-Umwandlung (§ 3 Nr. 63 EStG)"
        case .ruerup10:          return "Rürup-Rente / Basisrente"
        case .drvV0210:          return "DRV-Ausgleich (§ 187a SGB VI / V0210)"
        case .pvIab7g:           return "PV-IAB (§ 7g EStG)"
        case .liquidityTimeline: return "Konto-Cash vs. Buch-Effekte"
        }
    }

    var badge: String {
        switch self {
        case .recht2027:         return "Rechtsstand 2027"
        case .agFiktiv:          return "Wachstumschancengesetz"
        case .preExitGkv:        return "§ 19 Abs. 2 SGB V"
        case .postAlg1Gkv:       return "§ 240 SGB V (Privatier)"
        case .tarifSplitting:    return "§ 32a / § 34 EStG"
        case .sprinterLegal:     return "§ 24 Nr. 1a & § 34 EStG"
        case .alg1Rules:         return "§§ 148, 158, 159 SGB III"
        case .bav63:             return "§ 3 Nr. 63 S. 1 & S. 3 EStG"
        case .ruerup10:          return "§ 10 Abs. 1 Nr. 2 & Abs. 3 EStG"
        case .drvV0210:          return "§ 3 Nr. 28 EStG & V0210"
        case .pvIab7g:           return "§ 7g EStG (50 % Abzug)"
        case .liquidityTimeline: return "Cash-Flow-Logik 2027/2028"
        }
    }

    var icon: String {
        switch self {
        case .sprinterLegal, .tarifSplitting:
            return "exclamationmark.triangle.fill"
        case .recht2027:
            return "scale.3d"
        default:
            return "info.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .sprinterLegal, .tarifSplitting:
            return .orange
        case .bav63, .ruerup10, .drvV0210, .pvIab7g:
            return .green
        default:
            return .blue
        }
    }

    var summary: String {
        switch self {
        case .recht2027:
            return "Alle Berechnungen basieren auf den gesetzlichen Rechengrößen und Steuertarifen für das Veranlagungsjahr 2027."
        case .agFiktiv:
            return "Seit dem Wachstumschancengesetz wendet der Arbeitgeber beim Lohnsteuerabzug keine Fünftelregelung mehr an."
        case .preExitGkv:
            return "Ihr Versicherungsstatus vor dem Austritt bestimmt, ob während einer Ruhenszeit im 1. Monat kostenfreier Schutz greift."
        case .postAlg1Gkv:
            return "Nach Ablauf von ALG 1 wechseln Sie ohne neuen Job i. d. R. in die freiwillige GKV oder die kostenfreie Familienversicherung."
        case .tarifSplitting:
            return "Bei Zusammenveranlagung kann eine hohe Abfindung die Progression so anheben, dass Einzelveranlagung günstiger ist (Fünftel-Falle)."
        case .sprinterLegal:
            return "Damit die Sprinterprämie ebenfalls nach der Fünftelregelung (§ 34 EStG) ermäßigt besteuert wird, gelten zwei strenge Voraussetzungen."
        case .alg1Rules:
            return "Beim Aufhebungsvertrag unterscheiden sich Ruhenszeit (Verschiebung) und Sperrzeit (echte Anspruchskürzung) grundlegend."
        case .bav63:
            return "Direktumwandlung aus der Abfindung in eine betriebliche Altersversorgung spart sofort 2027 Lohnsteuer."
        case .ruerup10:
            return "Beiträge zur Basisrente senken das Basiseinkommen vor der Fünftelung und lösen dadurch einen überproportionalen Steuerhebel aus."
        case .drvV0210:
            return "Direktzahlung des Arbeitgebers in die gesetzliche Rentenversicherung zum Ausgleich von Rentenabschlägen."
        case .pvIab7g:
            return "Für eine geplante gewerbliche Photovoltaik-Anlage können 50 % der geplanten Anschaffungskosten bereits 2027 abgezogen werden."
        case .liquidityTimeline:
            return "Der Liquiditäts-Zeitstrahl trennt echten Kontostand (31.12.2027 & Ende 2028) von reinen Buch- oder Opportunitätseffekten."
        }
    }

    var bullets: [String] {
        switch self {
        case .recht2027:
            return [
                "Einkommensteuer 2027 (§ 32a EStG): Grundfreibetrag 12.564 € (Splitting 25.128 €), 42 %-Spitzensteuersatz ab 70.600 € (Splitting 141.200 €), Reichensteuer 45 % ab 285.000 €.",
                "Kinderfreibetrag 2027 (§§ 31–32 EStG): 10.056 € pro Kind (7.128 € KFB + 2.928 € BEA) vs. 3.204 € Kindergeld (0,5-Schritte unterstützt).",
                "Solidaritätszuschlag & Kirchensteuer: Soli-Freigrenze 19.450 € ESt (Einzel) bzw. 38.900 € (Splitting); Kirchensteuer 8 % (BY/BW) oder 9 % (§ 51a EStG).",
                "Beitragsbemessungsgrenzen 2027: BBG-RV/ALV 106.200 €/Jahr (8.850 €/Mo); BBG-KV/PV 76.500 €/Jahr (6.375 €/Mo).",
                "R 34.2 Abs. 1 EStR (Negativer Überlauf): Übersteigen Sonderausgaben das Basiseinkommen, mindert der Überhang direkt die Abfindung vor der Fünftelung."
            ]
        case .agFiktiv:
            return [
                "Der Arbeitgeber versteuert die Abfindung bei Auszahlung anhand Ihres hochgerechneten Jahresgehalts zum vollen progressiven Tarif.",
                "Dadurch fällt das Sofort-Netto zunächst niedriger aus als die endgültige Steuerlast.",
                "Die Steuerersparnis aus der Fünftelregelung holen Sie sich über die Einkommensteuererklärung 2028 vom Finanzamt zurück."
            ]
        case .preExitGkv:
            return [
                "Pflichtversichert vor Austritt: Nach § 19 Abs. 2 SGB V besteht nach Ende der Beschäftigung für bis zu 1 Monat ein kostenfreier nachgehender Leistungsanspruch (0 € GKV/PV im 1. Ruhens-Monat).",
                "Freiwillig versichert vor Austritt: Der nachgehende Leistungsanspruch greift nicht — der freiwillige GKV/PV-Höchstsatz (~1.320 €/Mo bei 2,5 % Zusatzbeitrag) fällt ab Tag 1 der Ruhenszeit an.",
                "Freiwillige GKV/PV-Beiträge sind nach § 10 EStG voll als Sonderausgaben absetzbar."
            ]
        case .postAlg1Gkv:
            return [
                "Mindestbeitrag (~280 €/Mo): Gilt für freiwillig Versicherte ohne laufende steuerpflichtige Einkünfte (reiner Vermögensverzehr aus der Abfindung ist beitragsfrei).",
                "Kapitalerträge & Mieten: Zinsen, Dividenden und Mieteinnahmen werden ab dem ersten Euro (ohne Sparer-Pauschbetrag) bis zur BBG verbeitragt — wählen Sie dafür 'Individuell'.",
                "Familienversicherung (0 €/Mo): Möglich, wenn der Ehepartner gesetzlich versichert ist und das eigene Gesamteinkommen unter der monatlichen Einkommensgrenze bleibt."
            ]
        case .tarifSplitting:
            return [
                "Dauernd getrennt lebende Ehegatten müssen zwingend den Grundtarif (Einzel-Rürup-Limit 32.308 €) wählen.",
                "Bei Zusammenveranlagung (Splitting-Rürup-Limit 64.616 €) zeigt der Solver die exakte Partner-Gehaltsgrenze, bis zu der Splitting günstiger ist."
            ]
        case .sprinterLegal:
            return [
                "Einheitliche Entschädigung (§ 24 Nr. 1a EStG): Die Sprinterprämie muss im selben Aufhebungsvertrag als Ausgleich für den vorzeitigen Arbeitsplatzverlust vereinbart sein.",
                "Zusammenballung von Einkünften: Basis-Abfindung und Sprinterprämie müssen vollständig im selben Kalenderjahr (2027) zufließen.",
                "Eine Verteilung der Auszahlung auf zwei Kalenderjahre (z. B. 2026 und 2027) zerstört die Fünftelregelung für die gesamte Abfindung."
            ]
        case .alg1Rules:
            return [
                "Ruhenszeit (§ 158 SGB III): Bei Verkürzung der Kündigungsfrist ruht die Auszahlung höchstens für die Dauer der abgekauften Frist — es gehen 0 Anspruchstage verloren.",
                "Sperrzeit (§§ 148, 159 SGB III): Ein Aufhebungsvertrag ohne wichtigen Grund führt i. d. R. zu 12 Wochen Sperrzeit (läuft zeitgleich zur Ruhenszeit und kürzt den Gesamtanspruch um max. 12 Wochen).",
                "Wenn Sie Ihren vollen ALG-1-Anspruch nicht bis zum letzten Tag ausschöpfen, entsteht durch die Kürzung 0 € realer Geldverlust."
            ]
        case .bav63:
            return [
                "Setzt sich 2027 aus zwei steuerfreien Töpfen zusammen: 42.480 € Vervielfältigungsregel (§ 3 Nr. 63 S. 3 EStG: 4 % × 106.200 € × max. 10 Dienstjahre) plus 8.496 € regulärer 8 %-Jahresrahmen (§ 3 Nr. 63 S. 1 EStG).",
                "Die Steuerersparnis erfolgt sofort 2027 (weniger AG-Lohnsteuereinbehalt), nicht als FA-Erstattung 2028.",
                "Kürzt die Abfindung direkt vor der Fünftelung und schmälert Ihren Rürup-Höchstbetrag nicht."
            ]
        case .ruerup10:
            return [
                "Beiträge zur Basisrente sind 2027 bis 32.308 € (Einzel) bzw. 64.616 € (Splitting) abzgl. laufender gesetzlicher RV-Beiträge (18,6 % AN+AG) absetzbar.",
                "Fünftel-Hebel: Da Rürup das reguläre Basiseinkommen senkt, rutscht der 1/5-Abfindungsblock in niedrigere Progressionszonen.",
                "Achtung Liquidität: Das eingezahlte Kapital ist dauerhaft bis zum Rentenbeginn gebunden (lebenslange Verrentung)."
            ]
        case .drvV0210:
            return [
                "Steuer-Split: 50 % der Arbeitgeber-Direktzahlung sind nach § 3 Nr. 28 EStG komplett steuerfrei (ohne Kürzung Ihres Rürup-Limits); die anderen 50 % unterliegen der Fünftelregelung (§ 34 EStG).",
                "Voraussetzung unter 50 Jahren: Ein konkretes, personalisiertes Abfindungsangebot bzw. ein Aufhebungsvertrags-Entwurf des Arbeitgebers.",
                "Ablauf in 4 Schritten: (1) Kontenklärung via Formular V0100, (2) Antrag via Formular V0210, (3) Bescheid der DRV abwarten, (4) Direktüberweisung durch den Arbeitgeber vor Auszahlung der Abfindung."
            ]
        case .pvIab7g:
            return [
                "Für eine geplante gewerbliche Photovoltaik-Anlage (bis 400.000 €) können 50 % (max. 200.000 €) bereits 2027 als Investitionsabzugsbetrag (IAB) abgezogen werden.",
                "Liquiditätsvorteil: Im Jahr 2027 sind 0 € sofortiger Kapitaleinsatz erforderlich — die Anschaffung muss erst innerhalb der folgenden 3 Kalenderjahre erfolgen."
            ]
        case .liquidityTimeline:
            return [
                "Konto-Cash 31.12.2027 zeigt Ihren tatsächlichen Bankkontostand am Jahresende nach Lohnsteuerabzug, Netto-Gehalt 2027, Rürup/PV-Abfluss und eventueller freiwilliger GKV.",
                "Im Oktober 2028 fließt die Steuererstattung vom Finanzamt aus der Fünftelregelung und den Vorsorge-Hebeln auf Ihr Konto."
            ]
        }
    }
}

struct InfoIconButton: View {
    let topic: StatutoryTopic
    @Binding var selectedTopic: StatutoryTopic?

    var body: some View {
        Button {
            selectedTopic = topic
        } label: {
            Image(systemName: topic.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(topic.accentColor)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Info zu \(topic.title)")
    }
}

struct StatutoryInfoSheetView: View {
    let topic: StatutoryTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: topic.icon)
                            .font(.title2)
                            .foregroundStyle(topic.accentColor)
                        Text(topic.badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(topic.accentColor.opacity(0.14))
                            .foregroundStyle(topic.accentColor)
                            .clipShape(Capsule())
                    }

                    Text(topic.summary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(topic.bullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(topic.accentColor)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(bullet)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
