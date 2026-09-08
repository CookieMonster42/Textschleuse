import Foundation
import TextschleuseCore

// Reihenfolge: erst die Regeln einzeln, dann die Heuristik, dann das
// Zusammenspiel in Schleuse und Rückweg, zuletzt der Speicher.

// MARK: Regeln

Pruefstand.pruefe("E-Mail") {
    let funde = Regelwerk.finde(in: Beispieltexte.bankmail)
    let mails = funde.filter { $0.kategorie == .email }
    Pruefstand.gleich(mails.count, 1, "genau eine Adresse in der Bankmail")
    Pruefstand.gleich(mails.first?.text, "almut.weidenbach@beispielbank-nord.de", "Adresse vollständig")

    let mitPunkt = Regelwerk.finde(in: "Schreib an a.b-c@x.co.uk.")
        .filter { $0.kategorie == .email }
    Pruefstand.gleich(mitPunkt.first?.text, "a.b-c@x.co.uk", "Satzpunkt gehört nicht zur Adresse")
}

Pruefstand.pruefe("IBAN") {
    let funde = Regelwerk.finde(in: Beispieltexte.bankmail).filter { $0.kategorie == .iban }
    Pruefstand.gleich(funde.count, 1, "IBAN mit Leerzeichen erkannt")
    Pruefstand.gleich(funde.first?.text, "DE89 3704 0044 0532 0130 00", "IBAN samt Gruppierung")

    Pruefstand.wahr(IbanRegel.pruefsummeStimmt("DE89370400440532013000"), "gültige Prüfsumme")
    Pruefstand.falsch(IbanRegel.pruefsummeStimmt("DE89370400440532013001"), "verfälschte Ziffer fällt durch")
    Pruefstand.falsch(IbanRegel.pruefsummeStimmt("DE00370400440532013000"), "falsche Prüfziffern fallen durch")

    let unecht = Regelwerk.finde(in: "Aktenzeichen DE12 3456 7890 1234 5678 90 im Vorgang")
        .filter { $0.kategorie == .iban }
    Pruefstand.gleich(unecht.count, 0, "Zeichenfolge ohne gültige Prüfsumme ist keine IBAN")
}

Pruefstand.pruefe("BIC") {
    let funde = Regelwerk.finde(in: "Bankverbindung GENODE61MA1, bitte prüfen.")
        .filter { $0.kategorie == .bic }
    Pruefstand.gleich(funde.count, 1, "BIC mit Filialkennung")

    let falschPositiv = Regelwerk.finde(in: "Das Kürzel MARISK steht für nichts Bankfachliches.")
        .filter { $0.kategorie == .bic }
    Pruefstand.gleich(falschPositiv.count, 0, "gewöhnliche Großbuchstabenwörter sind kein BIC")
}

Pruefstand.pruefe("Kartennummer") {
    let funde = Regelwerk.finde(in: Beispieltexte.aktenvermerk).filter { $0.kategorie == .karte }
    Pruefstand.gleich(funde.count, 1, "Testkarte im Aktenvermerk erkannt")

    Pruefstand.wahr(KartenRegel.luhnStimmt("4111111111111111"), "Luhn: gültige Testnummer")
    Pruefstand.falsch(KartenRegel.luhnStimmt("4111111111111112"), "Luhn: letzte Ziffer verdreht")
    Pruefstand.falsch(KartenRegel.luhnStimmt("1234567812345678"), "Luhn: erfundene Nummer")
}

Pruefstand.pruefe("Telefon") {
    let mail = Regelwerk.finde(in: Beispieltexte.bankmail).filter { $0.kategorie == .telefon }
    Pruefstand.gleich(mail.count, 1, "Nummer hinter „Tel.\" erkannt")

    let vermerk = Regelwerk.finde(in: Beispieltexte.aktenvermerk).filter { $0.kategorie == .telefon }
    Pruefstand.gleich(vermerk.count, 1, "Nummer mit Ländervorwahl erkannt")
    Pruefstand.gleich(vermerk.first?.text, "+49 621 9876543", "Ländervorwahl gehört dazu")

    for schreibweise in ["0621/123456", "0621-123456", "(0621) 123456", "+49 (0)621 123456"] {
        let treffer = Regelwerk.finde(in: "Rückruf unter \(schreibweise) erbeten")
            .filter { $0.kategorie == .telefon }
        Pruefstand.gleich(treffer.count, 1, "Schreibweise \(schreibweise)")
    }
}

Pruefstand.pruefe("Telefon: keine Falschtreffer") {
    // Die Vorgangsnummer sieht wie eine Nummer aus, hat aber keinen
    // Telefonkontext und keine Trennzeichen. Sie darf nicht anspringen.
    let funde = Regelwerk.finde(in: Beispieltexte.beschwerde).filter { $0.kategorie == .telefon }
    Pruefstand.gleich(funde.count, 0, "Vorgangsnummer 4711000815 ist keine Telefonnummer")

    let betrag = Regelwerk.finde(in: "Der Saldo betrug 1.234.567,89 EUR im Jahr 2024.")
        .filter { $0.kategorie == .telefon }
    Pruefstand.gleich(betrag.count, 0, "Geldbetrag ist keine Telefonnummer")
}

Pruefstand.pruefe("Geburtsdatum") {
    let vermerk = Regelwerk.finde(in: Beispieltexte.aktenvermerk).filter { $0.kategorie == .datum }
    Pruefstand.gleich(vermerk.count, 1, "Datum hinter „geboren am\" erkannt")
    Pruefstand.gleich(vermerk.first?.text, "04.07.1968", "nur das Datum, nicht der Kontext")

    // Ein Datum ohne Geburtskontext ist Fachinhalt und bleibt stehen.
    let mail = Regelwerk.finde(in: Beispieltexte.bankmail).filter { $0.kategorie == .datum }
    Pruefstand.gleich(mail.count, 0, "„Ihre Nachricht vom 12.03.2024\" ist kein Geburtsdatum")

    for form in ["geb. 04.07.1968", "*04.07.1968", "Geburtsdatum: 04.07.1968", "geboren 4.7.1968"] {
        let treffer = Regelwerk.finde(in: "Kunde \(form) laut Ausweis")
            .filter { $0.kategorie == .datum }
        Pruefstand.gleich(treffer.count, 1, "Schreibweise \(form)")
    }
}

Pruefstand.pruefe("Steuer-ID") {
    let funde = Regelwerk.finde(in: Beispieltexte.aktenvermerk).filter { $0.kategorie == .steuerId }
    Pruefstand.gleich(funde.count, 1, "elfstellige Steuer-ID mit Gruppierung erkannt")
}

// MARK: Heuristik

Pruefstand.pruefe("Heuristik: Personen") {
    let funde = Heuristik.finde(in: Beispieltexte.bankmail, woerterbuch: Woerterbuch())
    let namen = Set(funde.filter { $0.kategorie == .person }.map(\.text))
    Pruefstand.wahr(namen.contains("Almut Weidenbach"), "Vor- und Nachname als Paar")
    Pruefstand.wahr(namen.contains("Ilse Bergkamp"), "Grußformel-Name erkannt")
    Pruefstand.wahr(
        funde.allSatisfy { $0.sicherheit == .vermutung },
        "Heuristiktreffer sind immer Vermutungen, nie sicher"
    )
}

Pruefstand.pruefe("Heuristik: Firmen") {
    let funde = Heuristik.finde(in: Beispieltexte.bankmail, woerterbuch: Woerterbuch())
    let firmen = funde.filter { $0.kategorie == .firma }.map(\.text)
    Pruefstand.wahr(
        firmen.contains(where: { $0.contains("Beispielbank Nord") }),
        "Rechtsform eG zieht den Firmennamen mit"
    )
}

Pruefstand.pruefe("Heuristik: Satzanfänge") {
    // Jedes deutsche Substantiv ist großgeschrieben. Ohne Gegenmaßnahme
    // würde die Heuristik den halben Text als Namen markieren.
    let funde = Heuristik.finde(
        in: "Die Prüfung ergab keine Beanstandung. Der Bericht liegt vor.",
        woerterbuch: Woerterbuch()
    )
    Pruefstand.gleich(funde.count, 0, "gewöhnlicher Fließtext ergibt keine Namensvermutung")
}

// MARK: Varianten und Beugung

Pruefstand.pruefe("Varianten: ganze Wörter") {
    guard let regex = Varianten.regex(fuer: "Berg") else {
        Pruefstand.wahr(false, "Regex ließ sich bauen")
        return
    }
    let text = "Berg, Bergkamp und Heidelberg" as NSString
    let treffer = regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
    Pruefstand.gleich(treffer.count, 1, "nur das eigenständige Wort trifft")
    Pruefstand.gleich(text.substring(with: treffer[0].range), "Berg", "Treffer ist „Berg\"")
}

Pruefstand.pruefe("Varianten: Beugung") {
    guard let regex = Varianten.regex(fuer: "Nyström") else {
        Pruefstand.wahr(false, "Regex ließ sich bauen")
        return
    }
    for form in ["Nyström", "Nyströms", "Nyströme", "Nyströmen"] {
        let text = "Vorgang \(form) heute" as NSString
        let treffer = regex.numberOfMatches(
            in: text as String,
            range: NSRange(location: 0, length: text.length)
        )
        Pruefstand.gleich(treffer, 1, "gebeugte Form \(form)")
    }
}

Pruefstand.pruefe("Varianten: Schreibweisen") {
    guard let regex = Varianten.regex(fuer: "Müller-Lüdenscheidt") else {
        Pruefstand.wahr(false, "Regex ließ sich bauen")
        return
    }
    for form in ["Müller-Lüdenscheidt", "müller-lüdenscheidt", "MÜLLER-LÜDENSCHEIDT"] {
        let text = "Herr \(form) rief an" as NSString
        let treffer = regex.numberOfMatches(
            in: text as String,
            range: NSRange(location: 0, length: text.length)
        )
        Pruefstand.gleich(treffer, 1, "Groß- und Kleinschreibung: \(form)")
    }
}

// MARK: Schleuse

Pruefstand.pruefe("Schleuse: Regeltreffer werden hart ersetzt") {
    let analyse = Schleuse.analysiere(Beispieltexte.bankmail, woerterbuch: Woerterbuch())
    let geschuetzt = Schleuse.geschuetzterText(analyse)

    Pruefstand.enthaeltNicht(geschuetzt, "almut.weidenbach@beispielbank-nord.de", "Adresse ersetzt")
    Pruefstand.enthaeltNicht(geschuetzt, "DE89 3704 0044 0532 0130 00", "IBAN ersetzt")
    Pruefstand.enthaeltNicht(geschuetzt, "0621 1234567", "Telefonnummer ersetzt")
    Pruefstand.enthaelt(geschuetzt, "EMAIL_1", "Platzhalter steht im Text")
    Pruefstand.enthaelt(geschuetzt, "vielen Dank für Ihre Nachricht", "Fachinhalt bleibt unverändert")
}

Pruefstand.pruefe("Schleuse: Vermutungen bleiben unbestätigt") {
    let analyse = Schleuse.analysiere(Beispieltexte.bankmail, woerterbuch: Woerterbuch())
    Pruefstand.wahr(!analyse.ungeprueft.isEmpty, "es gibt etwas zu prüfen")
    Pruefstand.wahr(
        analyse.ungeprueft.allSatisfy { $0.platzhalter.hasPrefix("UNBEKANNT_") },
        "unbestätigte Vermutungen werden zu UNBEKANNT_n"
    )
    Pruefstand.wahr(
        analyse.regeltreffer.allSatisfy { !$0.platzhalter.hasPrefix("UNBEKANNT_") },
        "Regeltreffer sind nie unbekannt"
    )
}

Pruefstand.pruefe("Schleuse: Platzhalter bleiben über Texte hinweg gleich") {
    var buch = Woerterbuch()
    let erste = Schleuse.analysiere(Beispieltexte.bankmail, woerterbuch: buch)
    buch = erste.woerterbuch
    guard let mail = erste.regeltreffer.first(where: { $0.kategorie == .email }) else {
        Pruefstand.wahr(false, "Adresse im ersten Text gefunden")
        return
    }

    let zweite = Schleuse.analysiere(
        "Nachfrage an almut.weidenbach@beispielbank-nord.de wegen des Termins.",
        woerterbuch: buch
    )
    // Beim zweiten Mal kommt der Treffer aus dem Wörterbuch, nicht mehr aus
    // der Regel. Der Platzhalter muss trotzdem derselbe sein.
    let wieder = zweite.aktiveFunde.first { $0.kategorie == .email }
    Pruefstand.gleich(wieder?.platzhalter, mail.platzhalter, "dieselbe Adresse, derselbe Platzhalter")
    Pruefstand.gleich(wieder?.quelle, .woerterbuch, "der Treffer kommt jetzt aus dem Wörterbuch")
}

Pruefstand.pruefe("Schleuse: bestätigte Vermutung wird gemerkt") {
    var analyse = Schleuse.analysiere(Beispieltexte.aktenvermerk, woerterbuch: Woerterbuch())
    guard let vermutung = analyse.ungeprueft.first(where: { $0.text == "Thorben Nyström" }) else {
        Pruefstand.wahr(false, "„Thorben Nyström\" als Vermutung vorhanden")
        return
    }

    Schleuse.bestaetige(fundId: vermutung.id, als: .person, in: &analyse)
    let geschuetzt = Schleuse.geschuetzterText(analyse)
    Pruefstand.enthaelt(geschuetzt, "PERSON_1", "bestätigter Name bekommt PERSON_1")
    Pruefstand.enthaeltNicht(geschuetzt, "Thorben Nyström", "Klartext ist raus")
    Pruefstand.gleich(analyse.woerterbuch.eintraege.count > 0, true, "Eintrag liegt im Wörterbuch")

    // Zweiter Text, diesmal nur der Nachname. Der ist keine sichere Sache —
    // es könnte der Bruder sein — kommt aber mit dem Hinweis, zu wem er
    // vermutlich gehört.
    let spaeter = Schleuse.analysiere(
        "Herr Nyström hat zugestimmt.",
        woerterbuch: analyse.woerterbuch
    )
    guard let nachname = spaeter.aktiveFunde.first(where: { $0.text == "Nyström" }) else {
        Pruefstand.wahr(false, "der einzelne Nachname wird gefunden")
        return
    }
    Pruefstand.gleich(nachname.sicherheit, .vermutung, "und bleibt eine Vermutung")
    Pruefstand.gleich(
        nachname.gruppenVorschlag,
        analyse.woerterbuch.eintrag(fuerText: "Thorben Nyström")?.id,
        "mit Verweis auf die Hauptnennung"
    )

    // Volle Nennung dagegen greift ohne Nachfrage.
    let voll = Schleuse.analysiere(
        "Thorben Nyström hat zugestimmt.",
        woerterbuch: analyse.woerterbuch
    )
    Pruefstand.wahr(
        voll.aktiveFunde.contains { $0.quelle == .woerterbuch && $0.platzhalter == "PERSON_1" },
        "der gemerkte Name greift beim nächsten Mal von selbst"
    )
}

Pruefstand.pruefe("Schleuse: Alias hängt an der Hauptnennung") {
    var analyse = Schleuse.analysiere(Beispieltexte.beschwerde, woerterbuch: Woerterbuch())
    guard let voll = analyse.ungeprueft.first(where: { $0.text == "Ilse Bergkamp" }) else {
        Pruefstand.wahr(false, "„Ilse Bergkamp\" als Vermutung vorhanden")
        return
    }
    Schleuse.bestaetige(fundId: voll.id, als: .person, in: &analyse)

    guard let eintrag = analyse.woerterbuch.eintrag(fuerText: "Ilse Bergkamp") else {
        Pruefstand.wahr(false, "Eintrag angelegt")
        return
    }
    guard let kurz = analyse.funde.first(where: { $0.text == "Bergkamp" && $0.eintragId == nil }) else {
        Pruefstand.wahr(false, "„Bergkamp\" separat gefunden")
        return
    }

    Schleuse.alsAliasZuordnen(fundId: kurz.id, zu: eintrag.id, in: &analyse)
    let geschuetzt = Schleuse.geschuetzterText(analyse)
    Pruefstand.enthaelt(geschuetzt, "PERSON_1", "Hauptnennung")
    Pruefstand.enthaelt(geschuetzt, "PERSON_1B", "Kurzform als Unter-Platzhalter")
    Pruefstand.enthaeltNicht(geschuetzt, "Bergkamp", "kein Klartext mehr übrig")
}

Pruefstand.pruefe("Schleuse: verworfener Fund bleibt Klartext") {
    var analyse = Schleuse.analysiere(Beispieltexte.bankmail, woerterbuch: Woerterbuch())
    guard let fund = analyse.ungeprueft.first else {
        Pruefstand.wahr(false, "Vermutung vorhanden")
        return
    }
    let text = fund.text
    Schleuse.verwerfe(fundId: fund.id, in: &analyse)
    Pruefstand.enthaelt(Schleuse.geschuetzterText(analyse), text, "„\(text)\" steht weiterhin im Text")
}

// MARK: Hinweise

Pruefstand.pruefe("Hinweise") {
    let analyse = Schleuse.analysiere(Beispieltexte.bankmail, woerterbuch: Woerterbuch())
    let fuerKi = Schleuse.fuerZwischenablage(analyse, mitHinweisen: true)
    Pruefstand.enthaelt(fuerKi, "Platzhalter", "der Vorspann erklärt die Platzhalter")
    Pruefstand.enthaelt(fuerKi, "UNBEKANNT", "der Vorspann warnt vor den Unbekannten")

    let ohne = Schleuse.fuerZwischenablage(analyse, mitHinweisen: false)
    Pruefstand.gleich(ohne, Schleuse.geschuetzterText(analyse), "ohne Hinweise nur der nackte Text")
}

// MARK: Rückweg

Pruefstand.pruefe("Rückweg: Hin und zurück") {
    var analyse = Schleuse.analysiere(Beispieltexte.bankmail, woerterbuch: Woerterbuch())
    for fund in analyse.ungeprueft {
        Schleuse.bestaetige(fundId: fund.id, als: fund.kategorie, in: &analyse)
    }
    let geschuetzt = Schleuse.geschuetzterText(analyse)

    let zurueck = Rueckweg.analysiere(
        geschuetzt,
        woerterbuch: analyse.woerterbuch,
        unbekannte: analyse.unbekannte
    )
    Pruefstand.gleich(zurueck.offen.count, 0, "nichts bleibt offen")
    Pruefstand.gleich(zurueck.ergebnis, Beispieltexte.bankmail, "Wort für Wort derselbe Text")
}

Pruefstand.pruefe("Rückweg: Schreibvarianten der KI") {
    var buch = Woerterbuch()
    _ = buch.anlegen(text: "Thorben Nyström", kategorie: .person)

    for variante in ["PERSON_1", "**PERSON_1**", "<PERSON_1>", "[PERSON_1]", "PERSON 1", "Person_1", "person_1"] {
        let ergebnis = Rueckweg.analysiere(
            "Bitte melde dich bei \(variante) wegen des Termins.",
            woerterbuch: buch,
            unbekannte: [:]
        )
        Pruefstand.gleich(ergebnis.aufgeloest.count, 1, "Variante \(variante) erkannt")
        Pruefstand.enthaelt(ergebnis.ergebnis, "Thorben Nyström", "Variante \(variante) aufgelöst")
    }
}

Pruefstand.pruefe("Rückweg: Alias getrennt vom Hauptnamen") {
    var buch = Woerterbuch()
    let eintrag = buch.anlegen(text: "Ilse Bergkamp", kategorie: .person)
    guard let alias = buch.aliasHinzufuegen("Bergkamp", zu: eintrag.id) else {
        Pruefstand.wahr(false, "Alias ließ sich anlegen")
        return
    }
    let aliasPlatzhalter = buch.eintrag(mitId: eintrag.id)?.platzhalter(fuer: alias) ?? ""

    let ergebnis = Rueckweg.analysiere(
        "Frau PERSON_1 hat unterschrieben, \(aliasPlatzhalter) bestätigt den Eingang.",
        woerterbuch: buch,
        unbekannte: [:]
    )
    Pruefstand.enthaelt(ergebnis.ergebnis, "Frau Ilse Bergkamp", "Hauptnennung")
    Pruefstand.enthaelt(ergebnis.ergebnis, "Bergkamp bestätigt", "Kurzform bleibt Kurzform")
}

Pruefstand.pruefe("Rückweg: Unbekanntes bleibt stehen") {
    let ergebnis = Rueckweg.analysiere(
        "Bitte an UNBEKANNT_3 weiterleiten.",
        woerterbuch: Woerterbuch(),
        unbekannte: [:]
    )
    Pruefstand.gleich(ergebnis.offen.count, 1, "der Platzhalter wird als offen gemeldet")
    Pruefstand.enthaelt(ergebnis.ergebnis, "UNBEKANNT_3", "und bleibt im Text stehen")
}

// MARK: Speicher

Pruefstand.pruefe("Speicher: verschlüsselt sichern und laden") {
    let ordner = FileManager.default.temporaryDirectory
        .appendingPathComponent("textschleuse-pruefung-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: ordner) }

    // Fester Schlüssel statt Keychain: ein unsigniertes Programm bekommt vom
    // Anmeldeschlüsselbund keinen Zugriff. Der Keychain-Weg wird in der
    // gebauten App geprüft, nicht hier.
    let quelle = FesterSchluessel()
    let speicher = Speicher(ordner: ordner, schluesselquelle: quelle)
    var buch = Woerterbuch()
    let eintrag = buch.anlegen(text: "Thorben Nyström", kategorie: .person)
    _ = buch.aliasHinzufuegen("Nyström", zu: eintrag.id)

    do {
        try speicher.sichern(buch)
        let roh = try Data(contentsOf: speicher.datei)
        let alsText = String(decoding: roh, as: UTF8.self)
        Pruefstand.enthaeltNicht(alsText, "Nyström", "der Name steht nicht lesbar in der Datei")

        // Zweite Instanz, gleicher Schlüssel: so läuft es nach einem Neustart.
        let geladen = try Speicher(ordner: ordner, schluesselquelle: quelle).laden()
        Pruefstand.gleich(geladen.eintraege.count, 1, "Eintrag wieder da")
        Pruefstand.gleich(geladen.eintraege.first?.text, "Thorben Nyström", "Text unverändert")
        Pruefstand.gleich(geladen.eintraege.first?.aliase.count, 1, "Alias unverändert")
    } catch {
        Pruefstand.wahr(false, "sichern und laden ohne Fehler (\(error))")
    }
}

Pruefstand.pruefe("Speicher: Klartext-Export und -Import") {
    let ordner = FileManager.default.temporaryDirectory
        .appendingPathComponent("textschleuse-pruefung-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: ordner) }
    try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)

    let speicher = Speicher(ordner: ordner, schluesselquelle: FesterSchluessel())
    var buch = Woerterbuch()
    _ = buch.anlegen(text: "Beispielbank Nord eG", kategorie: .firma)
    let ziel = ordner.appendingPathComponent("export.json")

    do {
        try speicher.exportiereKlartext(buch, nach: ziel)
        let alsText = try String(contentsOf: ziel, encoding: .utf8)
        Pruefstand.enthaelt(alsText, "Beispielbank Nord eG", "der Export ist absichtlich lesbar")

        let zurueck = try speicher.importiereKlartext(von: ziel)
        Pruefstand.gleich(zurueck.eintraege.count, 1, "Import bringt den Eintrag zurück")
    } catch {
        Pruefstand.wahr(false, "Export und Import ohne Fehler (\(error))")
    }
}

Pruefstand.pruefe("Wörterbuch: gelöschte Nummern werden nicht neu vergeben") {
    var buch = Woerterbuch()
    let erster = buch.anlegen(text: "Anna Beispiel", kategorie: .person)
    Pruefstand.gleich(erster.platzhalter, "PERSON_1", "erste Person")

    buch.loeschen(erster.id)
    let zweiter = buch.anlegen(text: "Bernd Beispiel", kategorie: .person)
    Pruefstand.gleich(zweiter.platzhalter, "PERSON_2", "die 1 bleibt verbrannt")
}

// MARK: Decknamen

Pruefstand.pruefe("Deckname: Prüfung der Eingabe") {
    var buch = Woerterbuch()
    let eintrag = buch.anlegen(text: "Beispielbank Nord eG", kategorie: .firma)

    Pruefstand.gleich(try? buch.pruefeDeckname("kunde_nord", fuer: eintrag.id), "KUNDE_NORD",
                      "Kleinschreibung wird hochgezogen")
    Pruefstand.gleich(try? buch.pruefeDeckname("  HAUSBANK  ", fuer: eintrag.id), "HAUSBANK",
                      "Leerraum am Rand fällt weg")

    for (eingabe, erwartet) in [
        ("", Woerterbuch.DecknamenFehler.leer),
        ("KUNDE NORD", .ungueltigeZeichen),
        ("KUNDE-NORD", .ungueltigeZeichen),
        ("MÜLLER", .ungueltigeZeichen),
        ("123", .ohneBuchstabe),
    ] {
        do {
            _ = try buch.pruefeDeckname(eingabe, fuer: eintrag.id)
            Pruefstand.wahr(false, "„\(eingabe)\" wird abgelehnt")
        } catch let fehler as Woerterbuch.DecknamenFehler {
            Pruefstand.gleich(fehler, erwartet, "„\(eingabe)\" wird abgelehnt")
        } catch {
            Pruefstand.wahr(false, "„\(eingabe)\": unerwarteter Fehler \(error)")
        }
    }
}

Pruefstand.pruefe("Deckname: schon vergeben") {
    var buch = Woerterbuch()
    let erster = buch.anlegen(text: "Anna Beispiel", kategorie: .person)
    let zweiter = buch.anlegen(text: "Bernd Beispiel", kategorie: .person)
    _ = try? buch.umbenennen(erster.id, auf: "VORSTAND")

    do {
        _ = try buch.pruefeDeckname("VORSTAND", fuer: zweiter.id)
        Pruefstand.wahr(false, "ein zweites Mal VORSTAND wird abgelehnt")
    } catch let fehler as Woerterbuch.DecknamenFehler {
        Pruefstand.gleich(fehler, .vergeben("VORSTAND"), "ein zweites Mal VORSTAND wird abgelehnt")
    } catch {
        Pruefstand.wahr(false, "unerwarteter Fehler \(error)")
    }

    // Der Eintrag darf seinen eigenen Namen behalten.
    Pruefstand.gleich(try? buch.pruefeDeckname("VORSTAND", fuer: erster.id), "VORSTAND",
                      "der Eintrag stößt sich nicht an sich selbst")
}

Pruefstand.pruefe("Deckname: alter Name bleibt auflösbar") {
    var buch = Woerterbuch()
    let eintrag = buch.anlegen(text: "Thorben Nyström", kategorie: .person)
    _ = buch.aliasHinzufuegen("Nyström", zu: eintrag.id)
    Pruefstand.gleich(buch.eintrag(mitId: eintrag.id)?.platzhalter, "PERSON_1", "vorher")

    _ = try? buch.umbenennen(eintrag.id, auf: "MANDANT_A")
    Pruefstand.gleich(buch.eintrag(mitId: eintrag.id)?.platzhalter, "MANDANT_A", "nachher")

    // Beide Namen lösen auf: eine Antwort auf die ältere Mail geht weiter auf.
    Pruefstand.gleich(buch.klartext(fuerPlatzhalter: "MANDANT_A"), "Thorben Nyström", "neuer Name")
    Pruefstand.gleich(buch.klartext(fuerPlatzhalter: "PERSON_1"), "Thorben Nyström", "alter Name")
    Pruefstand.gleich(buch.klartext(fuerPlatzhalter: "MANDANT_AB"), "Nyström", "Alias unter neuem Namen")
    Pruefstand.gleich(buch.klartext(fuerPlatzhalter: "PERSON_1B"), "Nyström", "Alias unter altem Namen")
}

Pruefstand.pruefe("Deckname: Rückweg findet freie Namen") {
    var buch = Woerterbuch()
    let eintrag = buch.anlegen(text: "Beispielbank Nord eG", kategorie: .firma)
    _ = try? buch.umbenennen(eintrag.id, auf: "HAUSBANK")

    for variante in ["HAUSBANK", "**HAUSBANK**", "Hausbank", "hausbank"] {
        let ergebnis = Rueckweg.analysiere(
            "Die \(variante) hat bestätigt.",
            woerterbuch: buch,
            unbekannte: [:]
        )
        Pruefstand.gleich(ergebnis.aufgeloest.count, 1, "Variante \(variante) erkannt")
        Pruefstand.enthaelt(ergebnis.ergebnis, "Beispielbank Nord eG", "Variante \(variante) aufgelöst")
    }

    // Mehrteiliger Name, vom Modell mit Leerzeichen geschrieben.
    let zweiter = buch.anlegen(text: "Sparkasse Süd", kategorie: .firma)
    _ = try? buch.umbenennen(zweiter.id, auf: "KUNDE_NORD")
    let ergebnis = Rueckweg.analysiere("Bitte KUNDE NORD anschreiben.", woerterbuch: buch)
    Pruefstand.enthaelt(ergebnis.ergebnis, "Sparkasse Süd", "KUNDE NORD mit Leerzeichen")
}

Pruefstand.pruefe("Deckname: zurücksetzen") {
    var buch = Woerterbuch()
    let eintrag = buch.anlegen(text: "Anna Beispiel", kategorie: .person)
    _ = try? buch.umbenennen(eintrag.id, auf: "CHEFIN")
    buch.decknameZuruecksetzen(eintrag.id)

    Pruefstand.gleich(buch.eintrag(mitId: eintrag.id)?.platzhalter, "PERSON_1", "wieder die Nummer")
    Pruefstand.gleich(buch.klartext(fuerPlatzhalter: "CHEFIN"), "Anna Beispiel", "der alte Name geht weiter auf")
}

// MARK: Freie Markierung

Pruefstand.pruefe("Markierung: merken") {
    let text = "Das Projekt Nordlicht läuft seit März."
    var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
    let bereich = (text as NSString).range(of: "Nordlicht")

    let kennung = Schleuse.markiere(bereich: bereich, als: .begriff, merken: true, in: &analyse)
    Pruefstand.wahr(kennung != nil, "die Markierung wird angenommen")
    Pruefstand.enthaelt(Schleuse.geschuetzterText(analyse), "BEGRIFF_1", "Platzhalter steht im Text")
    Pruefstand.enthaeltNicht(Schleuse.geschuetzterText(analyse), "Nordlicht", "Klartext ist raus")
    Pruefstand.gleich(analyse.woerterbuch.eintrag(fuerText: "Nordlicht")?.kategorie, .begriff,
                      "der Begriff liegt im Wörterbuch")

    // Beim nächsten Text greift er von selbst.
    let spaeter = Schleuse.analysiere("Nordlicht ist abgeschlossen.", woerterbuch: analyse.woerterbuch)
    Pruefstand.wahr(spaeter.aktiveFunde.contains { $0.quelle == .woerterbuch },
                    "gemerkt heißt: beim nächsten Mal ohne Nachfrage")
}

Pruefstand.pruefe("Markierung: nur dieser Text") {
    let text = "Das Projekt Nordlicht läuft."
    var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
    let bereich = (text as NSString).range(of: "Nordlicht")

    Schleuse.markiere(bereich: bereich, als: .begriff, merken: false, in: &analyse)
    Pruefstand.gleich(analyse.woerterbuch.eintraege.count, 0, "nichts im Wörterbuch")
    Pruefstand.enthaeltNicht(Schleuse.geschuetzterText(analyse), "Nordlicht", "trotzdem ersetzt")
    Pruefstand.wahr(analyse.unbekannte.values.contains("Nordlicht"),
                    "steht in der Sitzungszuordnung, damit der Rückweg ihn kennt")
}

Pruefstand.pruefe("Markierung: der ganze Text wird nachdurchsucht") {
    let text = """
        Das Projekt Nordlicht startet im Frühjahr. Die Leitung von Nordlicht \
        liegt bei der Abteilung Kredit. Nordlichts Budget ist bewilligt.
        """
    var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
    // Nur das erste Vorkommen markieren.
    let erstes = (text as NSString).range(of: "Nordlicht")

    Schleuse.markiere(bereich: erstes, als: .begriff, merken: true, in: &analyse)
    let treffer = analyse.aktiveFunde.filter { $0.eintragId != nil }
    Pruefstand.gleich(treffer.count, 3, "alle drei Vorkommen, auch die gebeugte Form")
    Pruefstand.wahr(
        treffer.allSatisfy { $0.platzhalter == "BEGRIFF_1" },
        "alle bekommen denselben Platzhalter"
    )

    let geschuetzt = Schleuse.geschuetzterText(analyse)
    Pruefstand.enthaeltNicht(geschuetzt, "Nordlicht", "kein Klartext mehr übrig")
    Pruefstand.gleich(
        geschuetzt.components(separatedBy: "BEGRIFF_1").count - 1, 3,
        "dreimal ersetzt"
    )
}

Pruefstand.pruefe("Markierung: Nachsuchen ohne Wörterbuch") {
    let text = "Nordlicht läuft. Nordlicht ist wichtig."
    var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())

    Schleuse.markiere(
        bereich: (text as NSString).range(of: "Nordlicht"),
        als: .begriff,
        merken: false,
        in: &analyse
    )
    Pruefstand.gleich(analyse.aktiveFunde.count, 2, "beide Vorkommen")
    Pruefstand.gleich(analyse.woerterbuch.eintraege.count, 0, "trotzdem nichts im Wörterbuch")
    Pruefstand.enthaeltNicht(Schleuse.geschuetzterText(analyse), "Nordlicht", "beide ersetzt")
}

Pruefstand.pruefe("Markierung: Nachsuchen achtet Verworfenes") {
    let text = "Nordlicht läuft. Nordlicht ist wichtig. Nordlicht endet."
    var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
    let nsText = text as NSString

    // Am zweiten Vorkommen ausdrücklich Nein sagen …
    let zweites = nsText.range(of: "Nordlicht", options: [], range: NSRange(location: 17, length: nsText.length - 17))
    guard let vorher = Schleuse.markiere(bereich: zweites, als: .begriff, merken: false, in: &analyse) else {
        Pruefstand.wahr(false, "Markierung angelegt")
        return
    }
    Schleuse.verwerfe(fundId: vorher, in: &analyse)

    // … und dann das erste markieren.
    Schleuse.markiere(bereich: nsText.range(of: "Nordlicht"), als: .begriff, merken: true, in: &analyse)

    Pruefstand.gleich(analyse.aktiveFunde.count, 2, "erstes und drittes Vorkommen, nicht das verworfene")
    Pruefstand.enthaelt(
        Schleuse.geschuetzterText(analyse), "Nordlicht ist wichtig",
        "die verworfene Stelle bleibt Klartext"
    )
}

Pruefstand.pruefe("Bestätigen: der ganze Text wird nachdurchsucht") {
    let text = """
        Sehr geehrter Herr Nyström,

        wie mit Ihnen besprochen. Thorben Nyström wird die Unterlagen prüfen.
        Bitte wenden Sie sich an Nyström.
        """
    var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
    guard let voll = analyse.ungeprueft.first(where: { $0.text == "Thorben Nyström" }) else {
        Pruefstand.wahr(false, "„Thorben Nyström" + "\" als Vermutung vorhanden")
        return
    }

    Schleuse.bestaetige(fundId: voll.id, als: .person, in: &analyse)
    Pruefstand.enthaeltNicht(
        Schleuse.geschuetzterText(analyse), "Nyström",
        "keine Nennung bleibt im Klartext stehen"
    )
}

Pruefstand.pruefe("Markierung: Ränder werden geputzt") {
    let text = "Ansprechpartner ist Nordlicht, bitte melden."
    var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
    // Mit der Maus erwischt man fast immer ein Leerzeichen und das Komma mit.
    let grob = (text as NSString).range(of: " Nordlicht, ")

    let kennung = Schleuse.markiere(bereich: grob, als: .begriff, merken: true, in: &analyse)
    let fund = analyse.funde.first { $0.id == kennung }
    Pruefstand.gleich(fund?.text, "Nordlicht", "Leerzeichen und Komma fallen weg")
}

Pruefstand.pruefe("Markierung: verdrängt was darunter liegt") {
    var analyse = Schleuse.analysiere(Beispieltexte.bankmail, woerterbuch: Woerterbuch())
    let vorher = analyse.aktiveFunde.count
    guard let mail = analyse.regeltreffer.first(where: { $0.kategorie == .email }) else {
        Pruefstand.wahr(false, "Adresse gefunden")
        return
    }

    // Ein größerer Bereich, der die Adresse einschließt.
    let umfassend = NSRange(location: mail.bereich.location, length: mail.bereich.length + 3)
    Schleuse.markiere(bereich: umfassend, als: .begriff, merken: false, in: &analyse)

    Pruefstand.gleich(analyse.aktiveFunde.count, vorher, "der alte Fund weicht, der neue tritt an seine Stelle")
    Pruefstand.falsch(analyse.funde.contains { $0.id == mail.id }, "der überdeckte Fund ist weg")
}

Pruefstand.pruefe("Markierung: leere Auswahl tut nichts") {
    let text = "Ein kurzer Text."
    var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
    let vorher = analyse.funde.count

    let leer = NSRange(location: 4, length: 0)
    let nurLeerzeichen = (text as NSString).range(of: " ")
    let nurSatzzeichen = (text as NSString).range(of: ".")

    for (bereich, was) in [(leer, "leere Auswahl"), (nurLeerzeichen, "nur ein Leerzeichen"), (nurSatzzeichen, "nur ein Punkt")] {
        Pruefstand.wahr(
            Schleuse.markiere(bereich: bereich, als: .person, merken: true, in: &analyse) == nil,
            "\(was) wird abgelehnt"
        )
    }
    Pruefstand.gleich(analyse.funde.count, vorher, "nichts hinzugekommen")
}

Pruefstand.pruefe("Umbenennen aus dem Popup heraus") {
    let text = "Das Projekt Nordlicht läuft."
    var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
    let bereich = (text as NSString).range(of: "Nordlicht")
    guard let kennung = Schleuse.markiere(bereich: bereich, als: .begriff, merken: true, in: &analyse) else {
        Pruefstand.wahr(false, "Markierung angelegt")
        return
    }

    try? Schleuse.benenneUm(fundId: kennung, auf: "projekt_n", in: &analyse)
    Pruefstand.enthaelt(Schleuse.geschuetzterText(analyse), "PROJEKT_N", "der neue Name steht im Text")

    let zurueck = Rueckweg.analysiere(
        Schleuse.geschuetzterText(analyse),
        woerterbuch: analyse.woerterbuch,
        unbekannte: analyse.unbekannte
    )
    Pruefstand.gleich(zurueck.ergebnis, text, "und der Rückweg geht auf")
}

Pruefstand.pruefe("Umbenennen ohne Wörterbucheintrag") {
    let text = "Das Projekt Nordlicht läuft."
    var analyse = Schleuse.analysiere(text, woerterbuch: Woerterbuch())
    let bereich = (text as NSString).range(of: "Nordlicht")
    guard let kennung = Schleuse.markiere(bereich: bereich, als: .begriff, merken: false, in: &analyse) else {
        Pruefstand.wahr(false, "Markierung angelegt")
        return
    }

    try? Schleuse.benenneUm(fundId: kennung, auf: "PROJEKT_N", in: &analyse)
    Pruefstand.enthaelt(Schleuse.geschuetzterText(analyse), "PROJEKT_N", "der Name gilt für diesen Text")
    Pruefstand.gleich(analyse.unbekannte["PROJEKT_N"], "Nordlicht", "und steht in der Sitzungszuordnung")
    Pruefstand.gleich(analyse.woerterbuch.eintraege.count, 0, "das Wörterbuch bleibt unberührt")
}

Pruefstand.pruefe("Alte Datei ohne die neuen Felder lädt") {
    // Eine Datei aus Version 1: eigenerDeckname und fruehereDecknamen fehlen.
    let alt = """
        {"version":1,"naechsteNummern":{"person":2},"eintraege":[
        {"id":"11111111-1111-1111-1111-111111111111","text":"Anna Beispiel",
         "kategorie":"person","nummer":1,"aliase":[],"automatischErkannt":false,
         "angelegt":"2026-01-01T00:00:00Z"}]}
        """
    do {
        let buch = try JSONDecoder.textschleusePruefung.decode(Woerterbuch.self, from: Data(alt.utf8))
        Pruefstand.gleich(buch.eintraege.count, 1, "Eintrag gelesen")
        Pruefstand.gleich(buch.eintraege.first?.platzhalter, "PERSON_1", "Deckname wie gehabt")
        Pruefstand.gleich(buch.eintraege.first?.fruehereDecknamen.count, 0, "keine früheren Namen")
    } catch {
        Pruefstand.wahr(false, "alte Datei lädt (\(error))")
    }
}

// MARK: Wörterbuch bearbeiten

Pruefstand.pruefe("Bearbeiten: Begriff ändern") {
    var buch = Woerterbuch()
    let eintrag = buch.anlegen(text: "Thorben Nystrom", kategorie: .person)

    try? buch.aendereText(eintrag.id, auf: "Thorben Nyström")
    Pruefstand.gleich(buch.eintrag(mitId: eintrag.id)?.text, "Thorben Nyström", "Tippfehler behoben")
    Pruefstand.gleich(buch.eintrag(mitId: eintrag.id)?.platzhalter, "PERSON_1",
                      "der Deckname bleibt, sonst stimmen verschickte Texte nicht mehr")

    do {
        try buch.aendereText(eintrag.id, auf: "   ")
        Pruefstand.wahr(false, "leerer Begriff wird abgelehnt")
    } catch let fehler as Woerterbuch.EintragFehler {
        Pruefstand.gleich(fehler, .leer, "leerer Begriff wird abgelehnt")
    } catch {
        Pruefstand.wahr(false, "unerwarteter Fehler \(error)")
    }
}

Pruefstand.pruefe("Bearbeiten: Begriff schon vergeben") {
    var buch = Woerterbuch()
    _ = buch.anlegen(text: "Anna Beispiel", kategorie: .person)
    let zweiter = buch.anlegen(text: "Bernd Beispiel", kategorie: .person)

    do {
        try buch.aendereText(zweiter.id, auf: "anna beispiel")
        Pruefstand.wahr(false, "doppelter Begriff wird abgelehnt")
    } catch let fehler as Woerterbuch.EintragFehler {
        Pruefstand.gleich(fehler, .schonVorhanden("anna beispiel"), "doppelter Begriff wird abgelehnt")
    } catch {
        Pruefstand.wahr(false, "unerwarteter Fehler \(error)")
    }
    Pruefstand.gleich(buch.eintrag(mitId: zweiter.id)?.text, "Bernd Beispiel", "und nichts wurde geändert")
}

Pruefstand.pruefe("Bearbeiten: Kategorie ändern") {
    var buch = Woerterbuch()
    let eintrag = buch.anlegen(text: "Beispielbank Nord", kategorie: .person)
    Pruefstand.gleich(buch.eintrag(mitId: eintrag.id)?.platzhalter, "PERSON_1", "vorher")

    buch.aendereKategorie(eintrag.id, auf: .firma)
    Pruefstand.gleich(buch.eintrag(mitId: eintrag.id)?.platzhalter, "FIRMA_1", "nachher")
    Pruefstand.gleich(buch.klartext(fuerPlatzhalter: "PERSON_1"), "Beispielbank Nord",
                      "der alte Deckname bleibt auflösbar")
}

Pruefstand.pruefe("Bearbeiten: Kategorie ändern kollidiert nicht") {
    var buch = Woerterbuch()
    _ = buch.anlegen(text: "Sparkasse Süd", kategorie: .firma)   // FIRMA_1
    let person = buch.anlegen(text: "Beispielbank Nord", kategorie: .person)

    buch.aendereKategorie(person.id, auf: .firma)
    Pruefstand.gleich(buch.eintrag(mitId: person.id)?.platzhalter, "FIRMA_2",
                      "es gibt eine frische Nummer, FIRMA_1 ist belegt")
    Pruefstand.gleich(buch.klartext(fuerPlatzhalter: "FIRMA_1"), "Sparkasse Süd", "der andere bleibt er selbst")
}

Pruefstand.pruefe("Bearbeiten: eigener Deckname überlebt den Kategoriewechsel") {
    var buch = Woerterbuch()
    let eintrag = buch.anlegen(text: "Beispielbank Nord", kategorie: .person)
    _ = try? buch.umbenennen(eintrag.id, auf: "HAUSBANK")

    buch.aendereKategorie(eintrag.id, auf: .firma)
    Pruefstand.gleich(buch.eintrag(mitId: eintrag.id)?.platzhalter, "HAUSBANK", "der eigene Name bleibt")
    Pruefstand.gleich(buch.eintrag(mitId: eintrag.id)?.kategorie, .firma, "die Kategorie stimmt")
}

Pruefstand.pruefe("Bearbeiten: Schreibweisen") {
    var buch = Woerterbuch()
    let eintrag = buch.anlegen(text: "Thorben Nyström", kategorie: .person)
    guard let alias = buch.aliasHinzufuegen("Nystrom", zu: eintrag.id) else {
        Pruefstand.wahr(false, "Alias angelegt")
        return
    }
    Pruefstand.gleich(buch.klartext(fuerPlatzhalter: "PERSON_1B"), "Nystrom", "vorher")

    try? buch.aendereAlias(alias.id, in: eintrag.id, auf: "Nyström")
    Pruefstand.gleich(buch.klartext(fuerPlatzhalter: "PERSON_1B"), "Nyström",
                      "geändert, der Buchstabe bleibt")

    buch.loescheAlias(alias.id, in: eintrag.id)
    Pruefstand.gleich(buch.eintrag(mitId: eintrag.id)?.aliase.count, 0, "gelöscht")

    // Der Buchstabe wird nicht neu vergeben.
    let neuer = buch.aliasHinzufuegen("Nyström", zu: eintrag.id)
    Pruefstand.gleich(neuer?.suffix, "B", "B ist wieder frei, weil er nicht mehr im Umlauf ist")
}

Pruefstand.pruefe("Bearbeiten: Schreibweise zur Hauptnennung machen") {
    var buch = Woerterbuch()
    let eintrag = buch.anlegen(text: "Nyström", kategorie: .person)
    guard let alias = buch.aliasHinzufuegen("Thorben Nyström", zu: eintrag.id) else {
        Pruefstand.wahr(false, "Alias angelegt")
        return
    }

    buch.machtZurHauptnennung(alias.id, in: eintrag.id)
    Pruefstand.gleich(buch.eintrag(mitId: eintrag.id)?.text, "Thorben Nyström", "die volle Form führt jetzt")
    Pruefstand.gleich(buch.klartext(fuerPlatzhalter: "PERSON_1"), "Thorben Nyström", "PERSON_1 ist die Hauptnennung")
    Pruefstand.gleich(buch.klartext(fuerPlatzhalter: "PERSON_1B"), "Nyström", "die Kurzform ist jetzt die Schreibweise")
}

Pruefstand.bilanzUndEnde()
