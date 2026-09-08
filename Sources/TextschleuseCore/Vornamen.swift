import Foundation

/// Vornamensliste für die Personenvermutung. Bewusst breit gehalten: ein
/// falscher Treffer kostet dich einen Tastendruck im Popup, ein übersehener
/// Name kostet dich einen echten Namen im Prompt.
public enum Vornamen {

    /// Namen, die im Deutschen auch als gewöhnliches Wort vorkommen. Sie
    /// zählen nur, wenn ein zweites Indiz dazukommt: eine Anrede davor oder
    /// ein großgeschriebenes Wort dahinter.
    public static let mehrdeutig: Set<String> = [
        "mai", "rose", "linde", "hanne", "sonne", "erde", "art", "ernst",
        "frank", "franz", "mark", "norbert", "wolf", "bruno", "kai", "jan",
        "jo", "ben", "max", "kurt", "wilde", "lang", "reich", "gut",
    ]

    public static let alle: Set<String> = Set(liste.map { $0.lowercased() })

    public static func kenntVorname(_ wort: String) -> Bool {
        alle.contains(wort.lowercased())
    }

    public static func istMehrdeutig(_ wort: String) -> Bool {
        mehrdeutig.contains(wort.lowercased())
    }

    static let liste: [String] = [
        // Deutsch, klassisch
        "Achim", "Adam", "Adelheid", "Adrian", "Agnes", "Albert", "Albrecht", "Alexander",
        "Alexandra", "Alfons", "Alfred", "Alice", "Alina", "Almut", "Alois", "Amelie",
        "Andrea", "Andreas", "Angela", "Angelika", "Anja", "Anke", "Anna", "Annalena",
        "Anne", "Annegret", "Annelie", "Annette", "Ansgar", "Anton", "Antje", "Armin",
        "Arne", "Arnold", "Arthur", "Astrid", "August", "Aylin", "Barbara", "Bastian",
        "Beate", "Benedikt", "Benjamin", "Bernd", "Bernhard", "Bert", "Bertram", "Bettina",
        "Bianca", "Birgit", "Björn", "Bodo", "Brigitte", "Britta", "Burkhard", "Carla",
        "Carmen", "Carola", "Carsten", "Caroline", "Cathrin", "Cecilia", "Charlotte", "Christa",
        "Christian", "Christiane", "Christina", "Christine", "Christoph", "Clara", "Claudia", "Clemens",
        "Conny", "Constanze", "Cordula", "Cornelia", "Dagmar", "Daniel", "Daniela", "Danny",
        "David", "Detlef", "Diana", "Dieter", "Dietmar", "Dirk", "Dominik", "Dominique",
        "Doris", "Dorothea", "Edeltraud", "Eberhard", "Eckhard", "Edgar", "Edith", "Eduard",
        "Egon", "Elena", "Elfriede", "Elias", "Elisabeth", "Elke", "Ella", "Emil",
        "Emilia", "Emma", "Erhard", "Erich", "Erika", "Erwin", "Esther", "Eva",
        "Fabian", "Falk", "Felix", "Ferdinand", "Finn", "Florian", "Frauke", "Frederik",
        "Frieda", "Friedrich", "Fritz", "Gabriel", "Gabriele", "Georg", "Gerald", "Gerd",
        "Gerhard", "Gerlinde", "Gernot", "Gertrud", "Gisela", "Gottfried", "Greta", "Gregor",
        "Guido", "Gunnar", "Günter", "Günther", "Gustav", "Hannah", "Hanna", "Hannes",
        "Hans", "Harald", "Hartmut", "Hedwig", "Heide", "Heidi", "Heike", "Heiko",
        "Heinrich", "Heinz", "Helena", "Helga", "Helmut", "Henning", "Henrik", "Henriette",
        "Herbert", "Hermann", "Hilde", "Hildegard", "Holger", "Horst", "Hubert", "Hugo",
        "Ida", "Ilona", "Ilse", "Ines", "Inga", "Inge", "Ingeborg", "Ingo",
        "Ingrid", "Irene", "Iris", "Irmgard", "Isabel", "Isabelle", "Jakob", "Jana",
        "Janina", "Jasmin", "Jens", "Jessica", "Joachim", "Jochen", "Johann", "Johanna",
        "Johannes", "Jonas", "Jonathan", "Jörg", "Josef", "Josefine", "Judith", "Julia",
        "Julian", "Juliane", "Jürgen", "Justus", "Karin", "Karl", "Karla", "Karsten",
        "Katharina", "Kathrin", "Katja", "Katrin", "Kerstin", "Kilian", "Kirsten", "Klara",
        "Klaus", "Konrad", "Konstantin", "Kristin", "Lara", "Lars", "Laura", "Lea",
        "Lena", "Lennart", "Leon", "Leonie", "Liesel", "Lilly", "Linda", "Lisa",
        "Lotte", "Lothar", "Luca", "Lucas", "Ludwig", "Luise", "Lukas", "Luna",
        "Lutz", "Magdalena", "Maik", "Maike", "Malte", "Manfred", "Manuel", "Manuela",
        "Marc", "Marcel", "Marco", "Margarete", "Margit", "Maria", "Marianne", "Marie",
        "Marina", "Marion", "Marius", "Markus", "Marlene", "Marta", "Martha", "Martin",
        "Martina", "Mathias", "Mathilde", "Matthias", "Maximilian", "Melanie", "Merle", "Micha",
        "Michael", "Michaela", "Mia", "Miriam", "Monika", "Moritz", "Nadine", "Natalie",
        "Nele", "Nicolas", "Nicole", "Niels", "Nikolaus", "Nils", "Nina", "Noah",
        "Norman", "Olaf", "Oliver", "Ortrud", "Oskar", "Otto", "Patrick", "Patricia",
        "Paul", "Paula", "Peter", "Petra", "Philipp", "Pia", "Rainer", "Ralf",
        "Ralph", "Ramona", "Raphael", "Regina", "Reiner", "Reinhard", "Reinhold", "Renate",
        "René", "Ricarda", "Richard", "Rita", "Robert", "Rolf", "Roland", "Romy",
        "Ronald", "Rosemarie", "Rudolf", "Ruth", "Sabine", "Sabrina", "Sandra", "Sarah",
        "Sascha", "Sebastian", "Siegfried", "Sigrid", "Silke", "Silvia", "Simon", "Simone",
        "Sonja", "Sophia", "Sophie", "Stefan", "Stefanie", "Steffen", "Stephan", "Stephanie",
        "Susanne", "Sven", "Svenja", "Sylvia", "Tanja", "Tatjana", "Theo", "Theodor",
        "Therese", "Thomas", "Thorben", "Thorsten", "Tilman", "Tim", "Timo", "Tina",
        "Tobias", "Tom", "Torben", "Torsten", "Traudel", "Ulf", "Ulrich", "Ulrike",
        "Ursula", "Ute", "Uwe", "Valentin", "Vanessa", "Vera", "Verena", "Veronika",
        "Viktor", "Viktoria", "Vincent", "Volker", "Waldemar", "Walter", "Waltraud", "Werner",
        "Wilhelm", "Wilfried", "Willi", "Wolfgang", "Wolfram", "Yvonne",

        // Häufig in Deutschland, andere Sprachräume
        "Ahmet", "Ali", "Amir", "Anastasia", "Andrzej", "Aleksandra", "Ayse", "Aysel",
        "Bahar", "Berivan", "Burak", "Can", "Cem", "Cengiz", "Dario", "Deniz",
        "Dimitri", "Dmitri", "Ebru", "Efe", "Elif", "Emine", "Emre", "Enes",
        "Fatima", "Fatma", "Filip", "Francesco", "Giovanni", "Giulia", "Gökhan", "Hakan",
        "Hasan", "Hatice", "Hussein", "Ibrahim", "Ilker", "Irina", "Ivan", "Jelena",
        "Jusuf", "Kadir", "Karim", "Katarzyna", "Kemal", "Krzysztof", "Ludmila", "Luigi",
        "Magdalena", "Mahmut", "Maria", "Marek", "Mehmet", "Mert", "Milan", "Mohamed",
        "Mohammed", "Murat", "Mustafa", "Natalia", "Nazan", "Nikola", "Nurten", "Olga",
        "Omar", "Osman", "Özlem", "Pavel", "Piotr", "Rafal", "Rasim", "Recep",
        "Salih", "Selin", "Sergej", "Serkan", "Sevim", "Sinan", "Slavko", "Stanislaw",
        "Svetlana", "Tamara", "Tarik", "Tomasz", "Umut", "Vladimir", "Wojciech", "Yasemin",
        "Yasin", "Yusuf", "Zeynep", "Zoran",

        // Skandinavisch und niederländisch, im Norden verbreitet
        "Anders", "Annika", "Bjarne", "Bo", "Dennis", "Eelke", "Elin", "Erik",
        "Freya", "Gerrit", "Hendrik", "Ida", "Ingvar", "Jesper", "Joost", "Karsten",
        "Kirsten", "Lasse", "Lieke", "Maarten", "Mads", "Mette", "Nynke", "Ole",
        "Pelle", "Piet", "Sanne", "Sigrun", "Sten", "Thies", "Tjark", "Willem",
    ]
}
