import SwiftUI

// MARK: - Statutory Info Topics & Sheet

enum StatutoryTopic: String, Identifiable {
    case recht2027
    case tarifSplitting
    case preExitGkv
    case agFiktiv
    case sprinterLegal
    case alg1Rules
    case sprinterWaterfall
    case reichweiteOverview
    case reichweiteLogic
    case jobSwitchOverview
    case solverModes
    case bav63
    case ruerup10
    case drvV0210
    case pvIab7g
    case postAlg1Gkv
    case realReturnInflation
    case liquidityTimeline

    var id: String { rawValue }
}

private struct StatutoryInfoContent {
    let title: String
    let subtitle: String
    let sections: [(heading: String, body: String)]
}

private func infoContent(for topic: StatutoryTopic) -> StatutoryInfoContent {
    switch topic {
    case .recht2027:
        return StatutoryInfoContent(
            title: "Gesetzliche Parameter 2027",
            subtitle: "EStG §§ 32a, 32b, 34, 10, 7g · SGB III & SGB V",
            sections: [
                ("Einkommensteuer 2027 (§ 32a EStG)",
                 "Grundfreibetrag 12.564 € (Splitting: 25.128 €), Spitzensteuersatz 42 % ab 70.600 € und 45 % ab 285.000 € (Einzelveranlagung)."),
                ("Fünftelregelung (§ 34 EStG) & § 32b EStG",
                 "Tarifermäßigung für außerordentliche Einkünfte (Abfindung). Lohnersatzleistungen wie ALG 1 in 2027 fließen über den besonderen Steuersatz (§ 32b Abs. 2 EStG) in die Progression ein."),
                ("Hinweis (§ 2 StBerG)",
                 "Unverbindliche Modellrechnung auf Basis der Rechengrößen 2027. Keine Steuer- oder Rechtsberatung.")
            ]
        )
    case .tarifSplitting:
        return StatutoryInfoContent(
            title: "Grundtarif vs. Ehegattensplitting",
            subtitle: "§ 32a Abs. 5 EStG · Partnergehalt & § 34",
            sections: [
                ("Wirkung auf die Abfindung",
                 "Beim Splittingtarif wird das gemeinsame zvE halbiert und der Tarif verdoppelt. Je nach Partnergehalt und Fünftelregelung kann der Abfindungsvorteil gegenüber dem Grundtarif höher oder geringer ausfallen.")
            ]
        )
    case .preExitGkv:
        return StatutoryInfoContent(
            title: "GKV / PKV vor Austritt & Ruhenszeit",
            subtitle: "SGB V · Nachlauf & freiwillige Beiträge",
            sections: [
                ("Pflicht-GKV vs. Freiwillig / PKV",
                 "Bei Pflichtversicherten greift im ersten Monat nach Beschäftigungsende häufig der gesetzliche Nachlauf (§ 19 Abs. 2 SGB V), bevor ggf. freiwillige Beiträge anfallen.")
            ]
        )
    case .agFiktiv:
        return StatutoryInfoContent(
            title: "AG-Fiktivgehalt (Lohnsteuer-Einbehalt 2027)",
            subtitle: "Vorläufiger Lohnsteuerabzug beim Arbeitgeber",
            sections: [
                ("Auto-Default vs. Manuell",
                 "Ohne eigenen Eingabewert wird ein sinnvoller Richtwert aus dem Gehalt 2027 abgeleitet. Der endgültige Ausgleich erfolgt über die Einkommensteuerveranlagung 2028.")
            ]
        )
    case .sprinterLegal:
        return StatutoryInfoContent(
            title: "Sprinter-Option (Vorzeitiger Austritt)",
            subtitle: "Sprinter-Prämie & frühere Beendigung",
            sections: [
                ("Funktionsweise",
                 "Bei vorzeitigem Ausscheiden vor Ablauf der Kündigungsfrist wird eine zusätzliche Prämie (Faktor × Monatsbrutto × Fristmonate) angesetzt; gleichzeitig entfallen reguläre Gehaltsmonate und es können Ruhens- bzw. Sperrzeiten greifen.")
            ]
        )
    case .alg1Rules:
        return StatutoryInfoContent(
            title: "Sprinter-Option, Faktor & ALG-1-Regeln",
            subtitle: "Sofort-Austritt, Sprinter-Prämie · §§ 143a, 159 SGB III",
            sections: [
                ("1. Was bedeutet Sprinter-Option & Sprinter-Faktor?",
                 "• Sofort-Austritt ohne Kündigungsfrist: Mit der Sprinter-Option (Turboklausel) verzichten Sie darauf, Ihre reguläre Kündigungsfrist abzusitzen, und scheiden sofort bzw. früher aus dem Unternehmen aus.\n• Sprinter-Faktor (z. B. 1,5x): Für jeden eingesparten Monat der Kündigungsfrist zahlt der Arbeitgeber eine zusätzliche Prämie als Vielfaches Ihres Monatsbruttos (bei Faktor 1,5x also 1,5 Monatsgehälter pro eingespartem Fristmonat). Dafür entfallen die regulären Gehaltszahlungen während der Kündigungsfrist."),
                ("2. Ruhenszeit (§ 143a SGB III)",
                 "Greift bei vorzeitigem Austritt (Sprinter) mit Abfindung, wenn das Arbeitsverhältnis ohne Abfindung erst nach Ablauf der regulären Kündigungsfrist (fristMonate, z. B. 5 Monate) geendet hätte. Während der Ruhenszeit ruht der ALG-1-Anspruch (0 € ALG 1), da eine Doppelzahlung parallel zur fiktiven Kündigungsfrist vermieden werden soll. Bei freiwilliger GKV/PKV fallen laufende Beiträge an (bei Pflicht-GKV greift i. d. R. der 1-Monats-Nachlauf nach § 19 Abs. 2 SGB V)."),
                ("3. Sperrzeit (§ 159 SGB III) & Zusammenspiel mit der Ruhenszeit",
                 "Bei freiwilligem Ausscheiden oder Aufhebungsvertrag ohne wichtigen Grund kann eine Sperrzeit von regelmäßig 12 Wochen (ca. 3 Monaten) eintreten.\n• Gleichzeitiger Ablauf statt einfacher Addition: Die Sperrzeit beginnt ab dem Austritt und läuft bei einer längeren Ruhenszeit (z. B. 5 Monate Kündigungsfrist) parallel / überlappend innerhalb der ersten Monate ab — sie wird also nicht pauschal als weitere 3 Monate oben auf die 5 Monate addiert.\n• Anspruchskürzung (z. B. 12M → 9M): Durch die Sperrzeit verkürzt sich jedoch die gesamte ALG-1-Bezugsdauer entsprechend (aus einem 12-monatigen Anspruch werden 9 Monate ALG 1 nach Ablauf der Start-/Ruhensphase)."),
                ("4. Abfindungs-Anteil nach Alter & Jahren im Job",
                 "Je nach Lebensalter und Dauer der Betriebszugehörigkeit (Jahre im Job) wird im Modell nur ein bestimmter Prozentsatz der Abfindung für die Sprinter-Überbrückung angesetzt — nicht zwingend 100 %:\n• < 5 Jahre im Job: < 50 J. ~50 % · 50–54 J. ~60 % · 55+ J. ~70 %\n• 5–14 Jahre im Job: < 50 J. ~65 % · 50–54 J. ~75 % · 55+ J. ~85 %\n• 15+ Jahre im Job: < 50 J. ~80 % · 50–54 J. ~90 % · 55+ J. 100 %"),
                ("Hinweis (§ 2 StBerG)",
                 "Unverbindliche Orientierungstabelle und Modellrechnung (keine Rechts- oder Steuerberatung). Maßgeblich im Einzelfall sind Vereinbarung/Sozialplan sowie der Bescheid der Agentur für Arbeit.")
            ]
        )
    case .sprinterWaterfall:
        return StatutoryInfoContent(
            title: "Sprinter Netto-Brücke (Wasserfall)",
            subtitle: "Schritt-für-Schritt-Vergleich: Sofort-Austritt vs. Kündigungsfrist",
            sections: [
                ("1. + Netto-Prämie",
                 "Ihre zusätzliche Sprinter-Prämie (Faktor × Monatsbrutto × eingesparte Fristmonate) abzüglich der zusätzlichen Einkommensteuer, die durch diese Prämie entsteht."),
                ("2. + Fünftel-Hebel (§ 34 EStG)",
                 "Durch den Wegfall des regulären Gehalts während der Kündigungsfrist sinkt Ihr Basiseinkommen 2027. Dadurch greift die Fünftelregelung auf die Basis-Abfindung günstiger und erzeugt eine zusätzliche Steuerersparnis."),
                ("3. − Netto-Gehalt",
                 "Das reguläre Netto-Gehalt (inkl. ggf. abweichendem ALG 1 in 2027), auf das Sie durch den vorzeitigen Austritt während der Kündigungsfrist verzichten."),
                ("4. − GKV Ruhenszeit",
                 "Freiwillige GKV- oder PKV-Beiträge während der Ruhenszeit ohne Arbeitgeberzuschuss. Bei Pflicht-GKV greift im ersten Monat in der Regel der beitragsfreie Nachlauf (§ 19 Abs. 2 SGB V)."),
                ("5. − RV-Punkte",
                 "Rechnerischer Wert der entgangenen gesetzlichen Rentenversicherungsbeiträge (AN + AG = 18,6 % bis zur BBG) für die nicht gearbeiteten Fristmonate — ein Vermögens-, kein sofortiger Konto-Abfluss."),
                ("6. − ALG-1 Sperrzeit (falls aktiv)",
                 "Entgangenes ALG 1 durch eine mögliche Sperrzeit von bis zu 12 Wochen (§ 159 SGB III), sofern die Option in den Eingaben aktiviert ist."),
                ("7. = Sprinter-Bilanz",
                 "Das gesamte finanzielle Netto-Ergebnis (Plus oder Minus) des sofortigen Sprinter-Austritts im Vergleich zum regulären Absitzen der Kündigungsfrist.")
            ]
        )
    case .reichweiteOverview:
        return StatutoryInfoContent(
            title: "Reichweite (Überleben ohne Job)",
            subtitle: "Cash-Burn-Simulation · Standard (Frist) vs. Sprinter (Sofort)",
            sections: [
                ("1. Worum geht es hier?",
                 "Zeigt, wie viele Monate Ihr Netto-Kapital aus Abfindung, Gehalt und Steuererstattung Ihre laufenden Lebenshaltungskosten deckt — im direkten Vergleich zwischen regulärer Kündigungsfrist (Standard 🐢) und sofortigem Austritt (Sprinter 🏃)."),
                ("2. Startkapital & Day-0 Abfluss",
                 "Basis ist Ihr Sofort-Netto 2027 abzüglich einer eventuellen Rürup-Einzahlung und Ihrem Einmal-Abfluss 2027 (Day-0, z. B. Kreditablösung oder fester Notgroschen)."),
                ("3. Die 3 Lebensphasen im Zeitstrahl",
                 "• Frist / Ruhenszeit: Bei Standard läuft Ihr Gehalt weiter (optional inkl. gespartem Überschuss). Bei Sprinter überbrückt das Kapital die Ruhens-/Sperrzeit inkl. freiwilliger GKV/PKV.\n• ALG-1-Phase: Monatliche Entnahme = (Monatsausgaben − ALG 1 Netto). Bei aktiver Sperrzeit verkürzt sich Sprinter z. B. von 12M auf 9M.\n• Privatier-Phase: Nach ALG 1 fallen volle (Monatsausgaben + GKV nach ALG 1) an, bis das Guthaben aufgebraucht ist."),
                ("4. FA-Erstattung Okt. 2028 & Brücke",
                 "Im Oktober 2028 fließt die Einkommensteuer-Erstattung auf das Konto. Der Meilenstein „Okt. 2028 Brücke“ warnt, falls das Guthaben schon vor dieser Erstattung ins Minus laufen würde."),
                ("5. Real-Zins / Inflation p.a.",
                 "Verzinst oder entwertet das laufende Restkapital monatlich nach Inflation: Ein positiver Wert (+) verlängert die Reichweite, ein negativer Wert (−) verkürzt sie.")
            ]
        )
    case .reichweiteLogic:
        return StatutoryInfoContent(
            title: "Reichweite: Abfindungs-Puffer & Mindestzeit-Logik",
            subtitle: "Cash-Burn-Phasen, 3-Monats-Minimum & 9M ALG 1",
            sections: [
                ("1. Day-0 Einmalabfluss",
                 "Einmalabflüsse (Day-0, z. B. Kredit/Puffer oder Rürup) werden sofort zu Beginn abgezogen."),
                ("2. Sprinter-/Sperrphase & Vergleich mit Kündigungsfrist / 3-Monats-Sperrzeit",
                 "Der verbleibende Netto-Puffer überbrückt die anfängliche Sprinter-/Sperrphase anhand Ihres monatlichen Netto-Vergleichsgehalts (dem Netto, das Sie anstelle einer regulären Beschäftigung in der Kündigungsfrist erhalten).\n• Weniger als 3 Monate Puffer (< 3 Mon.): Reicht der rechnerische Puffer aus dem Abfindungs-/Sprinter-Betrag für weniger als die 3-monatige Sperrzeit, wird das Minimum aus beiden Zeiträumen angesetzt.\n• Mehr als Kündigungsfrist (> fristMonate): Deckt der rechnerische Puffer mehr Monate ab als Ihre Kündigungsfrist (z. B. > 5 Monate), bleibt der volle Überschuss im Konto-Cash erhalten und verlängert die spätere Reichweite — die Startphase wird nicht künstlich verkürzt."),
                ("3. ALG-1-Phase (z. B. 9M) & Privatier-Phase",
                 "Nach der anfänglichen Sprinter-/Ruhensphase starten die verbleibenden ALG-1-Monate (bei 12 Monaten Anspruch abzüglich 3 Monaten Sperrzeit: 9 Monate ALG 1) mit einer monatlichen Netto-Entnahme von (Monatsausgaben − ALG 1 Netto). Nach Ablauf von ALG 1 folgt die reine Privatier-Phase mit einer monatlichen Entnahme von (Monatsausgaben + GKV nach ALG 1) bis das Kapital aufgebraucht ist (zuzüglich FA-Erstattung Okt. 2028 und Real-Zins)."),
                ("Hinweis (§ 2 StBerG)",
                 "Unverbindliche Modellrechnung auf Basis der Rechengrößen 2027. Keine Steuer- oder Rechtsberatung.")
            ]
        )
    case .jobSwitchOverview:
        return StatutoryInfoContent(
            title: "Job-Switch & Break-Even",
            subtitle: "Gehaltswechsel mit Abfindung · Vermögens-Vorsprung",
            sections: [
                ("1. Worum geht es hier?",
                 "Beantwortet die Frage: „Wie lange bin ich finanziell im Plus, wenn ich die Abfindung mitnehme und dafür in einen neuen Job mit anderem Gehalt wechsle?“"),
                ("2. Abfindungs-Vorsprung (Start & Jahr 2)",
                 "Sie starten mit dem Netto-Puffer der Abfindung (abzüglich Rürup und eventueller Ruhens-GKV). In Jahr 2 kommt die Finanzamt-Erstattung (Okt. 2028) als zusätzlicher Schub hinzu."),
                ("3. Jährlicher Netto-Vergleich (Alt vs. Neu)",
                 "Vergleicht jedes Jahr das Netto im neuen Job (inklusive einer optionalen Pause bis zum Neustart in Jahr 1) mit dem Netto, das Sie im alten Job weiterverdient hätten — bei gleichem prozentualen Gehaltswachstum."),
                ("4. Break-Even-Punkt (0 € Schwelle)",
                 "Solange die Kurve über 0 € bleibt, überwiegt Ihr Abfindungs-Vorsprung. Der Break-Even (Jahre + Monat/Jahr) zeigt genau, ab wann das höhere alte Gehalt den Vorsprung aufgeholt hat. Ist das neue Gehalt gleich hoch oder höher, bleiben Sie dauerhaft im Plus (> 15 Jahre)."),
                ("5. Standard vs. Sprinter",
                 "Vergleicht beide Ausstiegswege inklusive Startpause: Bei Standard federt ggf. ALG 1 die Pause ab, bei Sprinter wirkt die höhere Sprinter-Prämie.")
            ]
        )
    case .solverModes:
        return StatutoryInfoContent(
            title: "Optimierungs-Modi",
            subtitle: "Manuell, Liquidität, Optimal-Netto & Altersvorsorge",
            sections: [
                ("Modi im Überblick",
                 "Wählt eine Zielgewichtung für bAV (§ 3 Nr. 63), Rürup (§ 10), DRV V0210 und PV-IAB (§ 7g) oder erlaubt die freie manuelle Einstellung.")
            ]
        )
    case .bav63:
        return StatutoryInfoContent(
            title: "Betriebliche Altersversorgung (§ 3 Nr. 63 EStG)",
            subtitle: "Steuer- und sozialabgabenbegünstigte Entgeltumwandlung",
            sections: [
                ("Wirkung",
                 "Reduziert das steuer- und beitragspflichtige Einkommen im Rahmen der gesetzlichen Höchstgrenzen und senkt den Sofort-Abzug.")
            ]
        )
    case .ruerup10:
        return StatutoryInfoContent(
            title: "Rürup / Basisrente (§ 10 Abs. 3 EStG)",
            subtitle: "Sonderausgabenabzug & Kapitalbindung",
            sections: [
                ("Wirkung & Bindung",
                 "Senkt das zu versteuernde Einkommen bis zum gemeinsamen/individuellen Höchstbetrag (abzüglich RV-Beiträge). Das eingezahlte Kapital ist lebenslang als Rente gebunden.")
            ]
        )
    case .drvV0210:
        return StatutoryInfoContent(
            title: "DRV-Ausgleichszahlung (V0210)",
            subtitle: "§ 187a SGB VI & § 3 Nr. 28 EStG · AG-Direktzahlung",
            sections: [
                ("1. Ziel: Rentenabschläge ausgleichen",
                 "Bei vorzeitigem Renteneintritt (z. B. mit 63 statt 67) kürzt die Deutsche Rentenversicherung die Rente dauerhaft um 0,3 % pro Monat (bis 14,4 %). Mit einer Ausgleichszahlung kaufen Sie diese Rentenpunkte vorab zurück."),
                ("2. Steuer-Regel (50/50-Split)",
                 "Zahlt der Arbeitgeber den Betrag direkt aus der Abfindung an die DRV:\n• 50 % sind komplett steuerfrei (§ 3 Nr. 28 EStG) — und kürzen Ihren separaten Rürup-Höchstbetrag nicht.\n• 50 % bleiben Teil der Abfindung und profitieren von der Fünftelregelung (§ 34 EStG).\n• 100 % werden vor Auszahlung direkt vom Sofort-Netto abgezogen."),
                ("3. Voraussetzungen & Ablauf (auch unter 50 Jahren)",
                 "• Kontenklärung (Formular V0100): Zuerst muss Ihr DRV-Versicherungskonto vollständig geklärt sein.\n• Antrag (Formular V0210): Antrag auf Auskunft über die mögliche Ausgleichszahlung (auch online per eID/AusweisApp). Regulär ab 50 Jahren — unter 50 Jahren nur mit Ausnahme und konkretem Abfindungsangebot / Aufhebungsvertragsentwurf.\n• Direkte Überweisung durch Arbeitgeber: Der Betrag darf nicht erst an Sie ausgezahlt werden, sondern muss direkt vom Arbeitgeber an die DRV überwiesen werden.")
            ]
        )
    case .pvIab7g:
        return StatutoryInfoContent(
            title: "Investitionsabzugsbetrag (§ 7g EStG)",
            subtitle: "50 % Sofort-Abzug · 3-Jahres-Investitionsfrist",
            sections: [
                ("1. Sofort-Effekt 2027 (0 € Cash-Abfluss)",
                 "Bis zu 50 % der geplanten Anschaffungskosten (max. 200.000 € Abzug bei 400.000 € Kaufpreis) mindern sofort Ihr zu versteuerndes Einkommen 2027. Sie müssen 2027 noch nichts kaufen und haben keinen sofortigen Cash-Abfluss."),
                ("2. 3-Jahres-Investitionsfrist",
                 "Der Abzug gilt gegen das Versprechen, die geplante Investition innerhalb der nächsten 3 Kalenderjahre (bis Ende 2030) tatsächlich umzusetzen."),
                ("3. Wichtige Regeln",
                 "• Gewerblich & beweglich: Gilt nur für abnutzbare, bewegliche Wirtschaftsgüter in einem Gewerbebetrieb mit Gewinnerzielungsabsicht und mind. 90 % betrieblicher Nutzung (z. B. gewerbliches PV-Direktinvestment — nicht für steuerbefreite Privat-Dachanlagen nach § 3 Nr. 72 EStG).\n• Bei Nicht-Investition: Wird nicht innerhalb von 3 Jahren gekauft, löst das Finanzamt den IAB rückwirkend für 2027 auf — die gesparte Steuer wird inkl. Nachzahlungszinsen zurückgefordert.\n• Steuer-Verschiebung: Der IAB mindert später die Abschreibungsbasis (AfA). Der echte Vorteil entsteht dadurch, dass Sie Steuern aus dem hohen Abfindungsjahr 2027 in Jahre mit niedrigerem Steuersatz verlagern.")
            ]
        )
    case .postAlg1Gkv:
        return StatutoryInfoContent(
            title: "Krankenversicherung nach ALG 1",
            subtitle: "Mindestbeitrag, Familienversicherung oder individuell",
            sections: [
                ("Monatliche Kosten",
                 "Nach Ende des ALG-1-Bezugs fallen laufende Kranken- und Pflegeversicherungsbeiträge an, sofern keine Familienversicherung greift.")
            ]
        )
    case .realReturnInflation:
        return StatutoryInfoContent(
            title: "Real-Zins / Inflation p.a.",
            subtitle: "Rendite nach Inflation · Wirkung auf die Reichweite",
            sections: [
                ("Was bedeutet der Wert?",
                 "Der Real-Zins entspricht der jährlichen Kapitalrendite abzüglich der Inflation (reale Kaufkraft-Veränderung Ihres Guthabens pro Jahr)."),
                ("Positiver Wert (+, z. B. +2,0 %)",
                 "Ihr Guthaben wächst real stärker als die Inflation (Kapitalertrag > Inflation). Das verlängert Ihre Reichweite."),
                ("Negativer Wert (−, z. B. −2,0 %)",
                 "Die Inflation übersteigt den Zins (Kaufkraftverlust > Rendite). Das verkürzt Ihre Reichweite."),
                ("Neutral (0,0 %)",
                 "Zinsen gleichen die Inflation exakt aus — die Kaufkraft Ihres Guthabens bleibt konstant.")
            ]
        )
    case .liquidityTimeline:
        return StatutoryInfoContent(
            title: "Liquiditäts-Zeitstrahl 2027 / 2028",
            subtitle: "Sofort-Netto 2027, Einkommen 2027 & FA-Erstattung 2028",
            sections: [
                ("Zeitlicher Ablauf",
                 "Trennt den unmittelbaren Netto-Zufluss 2027 von der Einkommensteuerveranlagung (Erstattung/Nachzahlung) im Folgejahr.")
            ]
        )
    }
}

struct InfoIconButton: View {
    let topic: StatutoryTopic
    @Binding var selectedTopic: StatutoryTopic?

    var body: some View {
        Button {
            selectedTopic = topic
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Weitere Informationen")
    }
}

struct StatutoryInfoSheetView: View {
    let topic: StatutoryTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let content = infoContent(for: topic)
        NavigationStack {
            List {
                Section {
                    Text(content.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(content.sections.enumerated()), id: \.offset) { _, sec in
                    Section(sec.heading) {
                        Text(sec.body)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
