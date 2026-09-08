import AppKit
import TextschleuseCore

/// Fragt, zu welchem bekannten Eintrag eine Nennung gehört.
///
/// Der Fall: „Jan Maia" steht im Wörterbuch, im Text steht „Jan  Maia" mit
/// zwei Leerzeichen oder „J. Maia". Die Automatik hält das für jemand anderen.
/// Hier sagst du, dass es dieselbe Person ist — sie bekommt dann `PERSON_3B`
/// statt eines eigenen Eintrags, und beim Lesen der KI-Antwort bleibt klar,
/// dass beides zusammengehört.
enum EintragWaehler {

    /// Zeigt die Auswahl und liefert den gewählten Eintrag, oder `nil` bei
    /// Abbruch.
    static func frage(
        woerterbuch: Woerterbuch,
        fuer nennung: String,
        vorschlag: UUID?
    ) -> Eintrag? {
        let kandidaten = woerterbuch.eintraege
            .sorted { ($0.kategorie.praefix, $0.nummer) < ($1.kategorie.praefix, $1.nummer) }
        guard !kandidaten.isEmpty else {
            let leer = NSAlert()
            leer.messageText = "Das Wörterbuch ist noch leer"
            leer.informativeText = "Merke zuerst einen Eintrag, dann kannst du weitere "
                + "Schreibweisen daran hängen."
            leer.runModal()
            return nil
        }

        let auswahl = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 25))
        for eintrag in kandidaten {
            auswahl.addItem(withTitle: beschriftung(fuer: eintrag))
            auswahl.lastItem?.representedObject = eintrag.id
        }
        if let vorschlag, let index = kandidaten.firstIndex(where: { $0.id == vorschlag }) {
            auswahl.selectItem(at: index)
        }

        let meldung = NSAlert()
        meldung.messageText = "„\(nennung)" + "\" gehört zu welchem Eintrag?"
        meldung.informativeText = """
            Die Nennung wird eine weitere Schreibweise des gewählten Eintrags und \
            bekommt dessen Decknamen mit einem Buchstaben dahinter. Ein eigener \
            Eintrag entsteht nicht.
            """
        meldung.accessoryView = auswahl
        meldung.addButton(withTitle: "Zuordnen")
        meldung.addButton(withTitle: "Abbrechen")

        guard meldung.runModal() == .alertFirstButtonReturn,
              let kennung = auswahl.selectedItem?.representedObject as? UUID
        else { return nil }
        return woerterbuch.eintrag(mitId: kennung)
    }

    private static func beschriftung(fuer eintrag: Eintrag) -> String {
        var text = "\(eintrag.text)  ·  \(eintrag.platzhalter)  ·  \(eintrag.kategorie.anzeigename)"
        if !eintrag.aliase.isEmpty {
            let weitere = eintrag.aliase.map(\.text).joined(separator: ", ")
            text += "  (auch: \(weitere))"
        }
        return text
    }
}
