// Holt die Vornamensliste aus den offenen Daten Berlins und schreibt
// Sources/TextschleuseCore/Vornamen.swift.
//
//     swift Werkzeug/VornamenHolen.swift
//
// Quelle: „Liste der häufigen Vornamen in Berlin", Standesämter der Berliner
// Bezirke, veröffentlicht über das Datenregister Berlin unter CC-BY 4.0,
// aufbereitet von der BerlinOnline GmbH (Repository unter MIT).
// https://datenregister.berlin.de/dataset?q=vornamen
//
// Warum ein Skript und keine mitgelieferte Datei: so ist nachvollziehbar,
// woher jeder Name kommt, und die Liste lässt sich mit einem Befehl
// auffrischen, wenn ein neuer Jahrgang erscheint.

import Foundation

let jahre = Array(2012...2023)
let bezirke = [
    "charlottenburg-wilmersdorf", "friedrichshain-kreuzberg", "lichtenberg",
    "marzahn-hellersdorf", "mitte", "neukoelln", "pankow", "reinickendorf",
    "spandau", "steglitz-zehlendorf", "tempelhof-schoeneberg", "treptow-koepenick",
]

/// Unter dieser Gesamtzahl fliegt ein Name raus. Fängt Tippfehler in den
/// Quelldaten ab, ohne seltene, aber echte Namen zu verlieren.
let mindestzahl = 3

struct Zaehlung {
    var gesamt = 0
    var maennlich = 0
    var weiblich = 0
}

var gezaehlt: [String: Zaehlung] = [:]
var geholt = 0
var fehlend = 0

for jahr in jahre {
    for bezirk in bezirke {
        let adresse = URL(
            string: "https://github.com/berlin/haeufige-vornamen-berlin/raw/main/data/\(jahr)/\(bezirk).csv"
        )!
        guard let roh = try? String(contentsOf: adresse, encoding: .utf8) else {
            fehlend += 1
            continue
        }
        geholt += 1

        for zeile in roh.split(separator: "\n").dropFirst() {
            let felder = zeile.split(separator: ",", omittingEmptySubsequences: false)
            guard felder.count >= 3 else { continue }
            let name = felder[0].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "")
            guard name.count >= 3, name.first?.isLetter == true else { continue }
            let anzahl = Int(felder[1].trimmingCharacters(in: .whitespaces)) ?? 0
            let geschlecht = felder[2].trimmingCharacters(in: .whitespaces).lowercased()

            var stand = gezaehlt[name, default: Zaehlung()]
            stand.gesamt += anzahl
            if geschlecht.hasPrefix("m") { stand.maennlich += anzahl }
            if geschlecht.hasPrefix("w") || geschlecht.hasPrefix("f") { stand.weiblich += anzahl }
            gezaehlt[name] = stand
        }
    }
}

guard geholt > 0 else {
    FileHandle.standardError.write(Data("Keine Datei erreichbar. Netz?\n".utf8))
    exit(1)
}

let brauchbar = gezaehlt
    .filter { $0.value.gesamt >= mindestzahl }
    .keys
    .sorted()

let maennlich = brauchbar.filter { (gezaehlt[$0]?.maennlich ?? 0) > (gezaehlt[$0]?.weiblich ?? 0) }.count
let weiblich = brauchbar.count - maennlich

// Namen, die auch gewöhnliche Wörter sind. Die Daten verraten das nicht,
// deshalb steht die Liste von Hand hier — ohne sie würde aus jedem „im Mai"
// eine Person.
let mehrdeutig = [
    "mai", "rose", "linde", "hanne", "sonne", "erde", "art", "ernst",
    "frank", "franz", "mark", "norbert", "wolf", "bruno", "kai", "jan",
    "jo", "ben", "max", "kurt", "wilde", "lang", "reich", "gut",
    "sturm", "berg", "stein", "adler", "falk", "flint", "hoch", "klein",
    "gross", "neu", "alt", "weiss", "schwarz", "braun", "rot", "gold",
    "silber", "sommer", "winter", "herbst", "morgen", "abend", "nacht",
]

/// Die von Hand gepflegte Liste, mit der die App angefangen hat.
///
/// Sie bleibt drin, weil die Berliner Daten Neugeborene erfassen: Namen wie
/// Almut, Hildegard oder Waltraud kommen dort seit Jahren nicht mehr vor —
/// unter Bankkunden aber sehr wohl.
let klassiker = [
    "Achim",
    "Adam",
    "Adelheid",
    "Adrian",
    "Agnes",
    "Ahmet",
    "Albert",
    "Albrecht",
    "Aleksandra",
    "Alexander",
    "Alexandra",
    "Alfons",
    "Alfred",
    "Ali",
    "Alice",
    "Alina",
    "Almut",
    "Alois",
    "Amelie",
    "Amir",
    "Anastasia",
    "Anders",
    "Andrea",
    "Andreas",
    "Andrzej",
    "Angela",
    "Angelika",
    "Anja",
    "Anke",
    "Anna",
    "Annalena",
    "Anne",
    "Annegret",
    "Annelie",
    "Annette",
    "Annika",
    "Ansgar",
    "Antje",
    "Anton",
    "Armin",
    "Arne",
    "Arnold",
    "Arthur",
    "Astrid",
    "August",
    "Aylin",
    "Ayse",
    "Aysel",
    "Bahar",
    "Barbara",
    "Bastian",
    "Beate",
    "Benedikt",
    "Benjamin",
    "Berivan",
    "Bernd",
    "Bernhard",
    "Bert",
    "Bertram",
    "Bettina",
    "Bianca",
    "Birgit",
    "Bjarne",
    "Björn",
    "Bo",
    "Bodo",
    "Brigitte",
    "Britta",
    "Burak",
    "Burkhard",
    "Can",
    "Carla",
    "Carmen",
    "Carola",
    "Caroline",
    "Carsten",
    "Cathrin",
    "Cecilia",
    "Cem",
    "Cengiz",
    "Charlotte",
    "Christa",
    "Christian",
    "Christiane",
    "Christina",
    "Christine",
    "Christoph",
    "Clara",
    "Claudia",
    "Clemens",
    "Conny",
    "Constanze",
    "Cordula",
    "Cornelia",
    "Dagmar",
    "Daniel",
    "Daniela",
    "Danny",
    "Dario",
    "David",
    "Deniz",
    "Dennis",
    "Detlef",
    "Diana",
    "Dieter",
    "Dietmar",
    "Dimitri",
    "Dirk",
    "Dmitri",
    "Dominik",
    "Dominique",
    "Doris",
    "Dorothea",
    "Eberhard",
    "Ebru",
    "Eckhard",
    "Edeltraud",
    "Edgar",
    "Edith",
    "Eduard",
    "Eelke",
    "Efe",
    "Egon",
    "Elena",
    "Elfriede",
    "Elias",
    "Elif",
    "Elin",
    "Elisabeth",
    "Elke",
    "Ella",
    "Emil",
    "Emilia",
    "Emine",
    "Emma",
    "Emre",
    "Enes",
    "Erhard",
    "Erich",
    "Erik",
    "Erika",
    "Erwin",
    "Esther",
    "Eva",
    "Fabian",
    "Falk",
    "Fatima",
    "Fatma",
    "Felix",
    "Ferdinand",
    "Filip",
    "Finn",
    "Florian",
    "Francesco",
    "Frauke",
    "Frederik",
    "Freya",
    "Frieda",
    "Friedrich",
    "Fritz",
    "Gabriel",
    "Gabriele",
    "Georg",
    "Gerald",
    "Gerd",
    "Gerhard",
    "Gerlinde",
    "Gernot",
    "Gerrit",
    "Gertrud",
    "Giovanni",
    "Gisela",
    "Giulia",
    "Gottfried",
    "Gregor",
    "Greta",
    "Guido",
    "Gunnar",
    "Gustav",
    "Gökhan",
    "Günter",
    "Günther",
    "Hakan",
    "Hanna",
    "Hannah",
    "Hannes",
    "Hans",
    "Harald",
    "Hartmut",
    "Hasan",
    "Hatice",
    "Hedwig",
    "Heide",
    "Heidi",
    "Heike",
    "Heiko",
    "Heinrich",
    "Heinz",
    "Helena",
    "Helga",
    "Helmut",
    "Hendrik",
    "Henning",
    "Henriette",
    "Henrik",
    "Herbert",
    "Hermann",
    "Hilde",
    "Hildegard",
    "Holger",
    "Horst",
    "Hubert",
    "Hugo",
    "Hussein",
    "Ibrahim",
    "Ida",
    "Ilker",
    "Ilona",
    "Ilse",
    "Ines",
    "Inga",
    "Inge",
    "Ingeborg",
    "Ingo",
    "Ingrid",
    "Ingvar",
    "Irene",
    "Irina",
    "Iris",
    "Irmgard",
    "Isabel",
    "Isabelle",
    "Ivan",
    "Jakob",
    "Jana",
    "Janina",
    "Jasmin",
    "Jelena",
    "Jens",
    "Jesper",
    "Jessica",
    "Joachim",
    "Jochen",
    "Johann",
    "Johanna",
    "Johannes",
    "Jonas",
    "Jonathan",
    "Joost",
    "Josef",
    "Josefine",
    "Judith",
    "Julia",
    "Julian",
    "Juliane",
    "Justus",
    "Jusuf",
    "Jörg",
    "Jürgen",
    "Kadir",
    "Karim",
    "Karin",
    "Karl",
    "Karla",
    "Karsten",
    "Katarzyna",
    "Katharina",
    "Kathrin",
    "Katja",
    "Katrin",
    "Kemal",
    "Kerstin",
    "Kilian",
    "Kirsten",
    "Klara",
    "Klaus",
    "Konrad",
    "Konstantin",
    "Kristin",
    "Krzysztof",
    "Lara",
    "Lars",
    "Lasse",
    "Laura",
    "Lea",
    "Lena",
    "Lennart",
    "Leon",
    "Leonie",
    "Lieke",
    "Liesel",
    "Lilly",
    "Linda",
    "Lisa",
    "Lothar",
    "Lotte",
    "Luca",
    "Lucas",
    "Ludmila",
    "Ludwig",
    "Luigi",
    "Luise",
    "Lukas",
    "Luna",
    "Lutz",
    "Maarten",
    "Mads",
    "Magdalena",
    "Mahmut",
    "Maik",
    "Maike",
    "Malte",
    "Manfred",
    "Manuel",
    "Manuela",
    "Marc",
    "Marcel",
    "Marco",
    "Marek",
    "Margarete",
    "Margit",
    "Maria",
    "Marianne",
    "Marie",
    "Marina",
    "Marion",
    "Marius",
    "Markus",
    "Marlene",
    "Marta",
    "Martha",
    "Martin",
    "Martina",
    "Mathias",
    "Mathilde",
    "Matthias",
    "Maximilian",
    "Mehmet",
    "Melanie",
    "Merle",
    "Mert",
    "Mette",
    "Mia",
    "Micha",
    "Michael",
    "Michaela",
    "Milan",
    "Miriam",
    "Mohamed",
    "Mohammed",
    "Monika",
    "Moritz",
    "Murat",
    "Mustafa",
    "Nadine",
    "Natalia",
    "Natalie",
    "Nazan",
    "Nele",
    "Nicolas",
    "Nicole",
    "Niels",
    "Nikola",
    "Nikolaus",
    "Nils",
    "Nina",
    "Noah",
    "Norman",
    "Nurten",
    "Nynke",
    "Olaf",
    "Ole",
    "Olga",
    "Oliver",
    "Omar",
    "Ortrud",
    "Oskar",
    "Osman",
    "Otto",
    "Patricia",
    "Patrick",
    "Paul",
    "Paula",
    "Pavel",
    "Pelle",
    "Peter",
    "Petra",
    "Philipp",
    "Pia",
    "Piet",
    "Piotr",
    "Rafal",
    "Rainer",
    "Ralf",
    "Ralph",
    "Ramona",
    "Raphael",
    "Rasim",
    "Recep",
    "Regina",
    "Reiner",
    "Reinhard",
    "Reinhold",
    "Renate",
    "René",
    "Ricarda",
    "Richard",
    "Rita",
    "Robert",
    "Roland",
    "Rolf",
    "Romy",
    "Ronald",
    "Rosemarie",
    "Rudolf",
    "Ruth",
    "Sabine",
    "Sabrina",
    "Salih",
    "Sandra",
    "Sanne",
    "Sarah",
    "Sascha",
    "Sebastian",
    "Selin",
    "Sergej",
    "Serkan",
    "Sevim",
    "Siegfried",
    "Sigrid",
    "Sigrun",
    "Silke",
    "Silvia",
    "Simon",
    "Simone",
    "Sinan",
    "Slavko",
    "Sonja",
    "Sophia",
    "Sophie",
    "Stanislaw",
    "Stefan",
    "Stefanie",
    "Steffen",
    "Sten",
    "Stephan",
    "Stephanie",
    "Susanne",
    "Sven",
    "Svenja",
    "Svetlana",
    "Sylvia",
    "Tamara",
    "Tanja",
    "Tarik",
    "Tatjana",
    "Theo",
    "Theodor",
    "Therese",
    "Thies",
    "Thomas",
    "Thorben",
    "Thorsten",
    "Tilman",
    "Tim",
    "Timo",
    "Tina",
    "Tjark",
    "Tobias",
    "Tom",
    "Tomasz",
    "Torben",
    "Torsten",
    "Traudel",
    "Ulf",
    "Ulrich",
    "Ulrike",
    "Umut",
    "Ursula",
    "Ute",
    "Uwe",
    "Valentin",
    "Vanessa",
    "Vera",
    "Verena",
    "Veronika",
    "Viktor",
    "Viktoria",
    "Vincent",
    "Vladimir",
    "Volker",
    "Waldemar",
    "Walter",
    "Waltraud",
    "Werner",
    "Wilfried",
    "Wilhelm",
    "Willem",
    "Willi",
    "Wojciech",
    "Wolfgang",
    "Wolfram",
    "Yasemin",
    "Yasin",
    "Yusuf",
    "Yvonne",
    "Zeynep",
    "Zoran",
    "Özlem",
]

let alleNamen = Set(brauchbar.map { $0.lowercased() })
    .union(klassiker.map { $0.lowercased() })
    .filter { $0.count >= 3 }
    .sorted()
let nurAusKlassikern = alleNamen.count - brauchbar.count

let quelle = """
    import Foundation

    /// Vornamen für die Personenerkennung.
    ///
    /// Erzeugt von `Werkzeug/VornamenHolen.swift` — nicht von Hand ändern,
    /// sondern das Skript laufen lassen.
    ///
    /// Quelle: „Liste der häufigen Vornamen in Berlin", Standesämter der
    /// Berliner Bezirke, Jahrgänge \(jahre.first!) bis \(jahre.last!),
    /// veröffentlicht über das Datenregister Berlin unter CC-BY 4.0.
    /// Aufbereitung: BerlinOnline GmbH.
    /// https://datenregister.berlin.de/dataset?q=vornamen
    ///
    /// Stand dieser Fassung: \(alleNamen.count) Namen. \(brauchbar.count) davon
    /// aus \(geholt) Berliner Dateien (überwiegend männlich \(maennlich),
    /// überwiegend weiblich \(weiblich)), aufgenommen ab \(mindestzahl) Vorkommen.
    /// Dazu \(nurAusKlassikern) ältere deutsche Namen aus der von Hand
    /// gepflegten Liste — Berlin erfasst Neugeborene, und Almut oder Waltraud
    /// kommen dort seit Jahren nicht mehr vor. Unter Bankkunden schon.
    ///
    /// Berlin ist als Quelle bewusst gewählt: die Standesämter erfassen dort
    /// Namen aus aller Welt, nicht nur deutsche. Für Bankpost im
    /// deutschsprachigen Raum deckt das mehr ab als eine reine Namensliste.
    public enum Vornamen {

        /// Namen, die auch gewöhnliche Wörter sind. Sie zählen nur dann als
        /// Person, wenn ein Nachname folgt — sonst würde aus „im Mai" eine.
        public static let mehrdeutig: Set<String> = [
    \(mehrdeutig.map { "        \"\($0)\"," }.joined(separator: "\n"))
        ]

        public static let alle: Set<String> = Set(
            liste.split(separator: "\\n").map(String.init)
        )

        public static func kenntVorname(_ wort: String) -> Bool {
            alle.contains(wort.lowercased())
        }

        public static func istMehrdeutig(_ wort: String) -> Bool {
            mehrdeutig.contains(wort.lowercased())
        }

        /// Alles kleingeschrieben, durch Zeilenumbrüche getrennt. Als eine
        /// Zeichenkette statt als Feld, weil der Übersetzer bei \(alleNamen.count)
        /// einzelnen Literalen sehr langsam wird.
        static let liste = \"\"\"
    \(alleNamen.joined(separator: "\n"))
    \"\"\"
    }

    """

let ziel = "Sources/TextschleuseCore/Vornamen.swift"
try quelle.write(toFile: ziel, atomically: true, encoding: .utf8)

print("\(alleNamen.count) Namen geschrieben nach \(ziel)")
print("  \(brauchbar.count) aus \(geholt) Berliner Dateien, \(nurAusKlassikern) nur aus der alten Liste")
if fehlend > 0 { print("\(fehlend) Dateien waren nicht erreichbar (Bezirk in dem Jahr ohne Daten)") }
print("überwiegend männlich: \(maennlich), überwiegend weiblich: \(weiblich)")
