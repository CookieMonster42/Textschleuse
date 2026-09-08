import Foundation

/// Testkorpus. Alle Namen, Nummern und Adressen sind erfunden. Echte
/// Kundendaten gehören nicht in dieses Verzeichnis, auch nicht ausgedachte
/// Varianten echter Vorgänge.
///
/// Die IBAN ist die öffentlich dokumentierte Beispiel-IBAN, die Kartennummer
/// die bekannte Testnummer der Kartenhersteller. Beide sind rechnerisch
/// gültig, damit die Prüfsummen anspringen.
enum Beispieltexte {

    static let bankmail = """
        Sehr geehrter Herr Nyström,

        vielen Dank für Ihre Nachricht vom 12.03.2024. Anbei die Unterlagen zur
        Kontoverbindung DE89 3704 0044 0532 0130 00 bei der Beispielbank Nord eG.

        Ihre Ansprechpartnerin Frau Almut Weidenbach erreichen Sie unter
        almut.weidenbach@beispielbank-nord.de oder Tel. 0621 1234567.

        Mit freundlichen Grüßen
        Ilse Bergkamp
        68159 Mannheim
        """

    static let aktenvermerk = """
        Aktenvermerk zum Kundengespräch

        Teilnehmer: Thorben Nyström (geboren am 04.07.1968), Frau Weidenbach.
        Herr Nyström legte die Karte 4111 1111 1111 1111 vor.
        Steuer-ID 12 345 678 901 wurde geprüft.
        Rückruf zugesagt unter +49 621 9876543.
        """

    static let beschwerde = """
        Betreff: Beschwerde über die Abrechnung

        Ich, Ilse Bergkamp, habe am 12.03.2024 eine Gutschrift erwartet.
        Meine Vorgangsnummer lautet 4711000815 und hat mit dem Konto nichts zu tun.
        Bitte melden Sie sich bei mir, Bergkamp, unter ilse.bergkamp@example.org.
        """
}
