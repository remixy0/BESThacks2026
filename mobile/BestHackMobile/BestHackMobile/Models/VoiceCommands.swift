import Foundation

/// Understands short spoken commands in Polish or English. Pure text matching, no AI: it looks for known words.
///
///     "lewy górny" / "żółty" / "jedynka" / "top left" / "yellow" / "one"   → corner 0 (top left)
///     "słonie" / "dinozaur" / "lions"                                      → that exhibit
///     "tak" / "yes", "nie" / "no"
///     "opowiedz" / "tell me", "dalej" / "next", "powtórz" / "repeat", "stop", "gdzie jestem", "którędy"
nonisolated enum VoiceCommands {
    struct Heard: Sendable, Equatable {
        /// 0 = top left, 1 = top right, 2 = bottom left, 3 = bottom right (from a position, colour or number).
        var corner: Int?
        /// Exhibit keys mentioned, in the order of the exhibit list.
        var exhibits: [String] = []
        var yes = false
        var no = false
        var story = false
        var next = false
        var repeatIt = false
        var stop = false
        var whereAmI = false
        var directions = false

        var isEmpty: Bool {
            corner == nil && exhibits.isEmpty && !yes && !no && !story && !next && !repeatIt && !stop && !whereAmI && !directions
        }
    }

    // Patterns: words separated by spaces must appear one after another; "word*" matches any word starting so.
    private static let cornerPhrases: [[String]] = [
        ["lew* gor*", "gor* lew*", "top left", "upper left", "left top"],
        ["praw* gor*", "gor* praw*", "top right", "upper right", "right top"],
        ["lew* dol*", "dol* lew*", "bottom left", "lower left", "left bottom"],
        ["praw* dol*", "dol* praw*", "bottom right", "lower right", "right bottom"],
    ]
    private static let colours: [[String]] = [
        ["zolt*", "yellow"],
        ["niebiesk*", "blekit*", "blue"],
        ["rozow*", "pink", "magenta"],
        ["zielon*", "green"],
    ]
    private static let numbers: [[String]] = [
        ["jeden", "jedna", "jedynk*", "pierwsz*", "one", "first", "1"],
        ["dwa", "dwie", "dwojk*", "drug*", "two", "second", "2"],
        ["trzy", "trojk*", "trzec*", "three", "third", "3"],
        ["cztery", "czwork*", "czwart*", "four", "fourth", "4"],
    ]
    private static let exhibitWords: [(key: String, patterns: [String])] = [
        ("maximo", ["maximo", "maksimo", "maksymo", "tytanozaur*", "titanosaur*", "dinozaur*", "dinosaur*", "patagotitan"]),
        ("elephants", ["slon*", "elephant*"]),
        ("totems", ["totem*", "pal", "pale", "pali"]),
        ("tsavo_lions", ["lew", "lwy", "lwow", "lwami", "lion*", "tsavo"]),
        ("seabirds", ["ptak*", "gluptak*", "bird*", "seabird*", "gannet*", "nurkuj*"]),
        ("mask", ["mask*", "teotihuacan"]),
        ("pawnee_lodge", ["pawnee", "paunis*", "ziemiank*", "lodge", "chat*"]),
        ("mastaba", ["mastab*", "grobow*", "tomb*", "egip*", "egypt*"]),
    ]
    private static let yesWords = ["tak", "yes", "yeah", "jasne", "dobrze", "ok", "okej", "okay", "potwierdzam", "idziemy",
                                   "ruszamy", "chodzmy", "prowadz", "zgoda", "sure"]
    private static let noWords = ["nie", "no", "anuluj", "cancel", "nope"]
    private static let storyWords = ["opowiedz*", "opowiadaj", "histori*", "wiecej", "story", "tell", "opisz", "co to", "informacj*", "info"]
    private static let nextWords = ["dalej", "nastepn*", "next", "kolejn*", "another", "wybierz", "nowy", "nowe"]
    private static let repeatWords = ["powtorz*", "repeat", "jeszcze raz", "again"]
    private static let stopWords = ["stop", "cisza", "przestan", "zatrzymaj*", "quiet", "silence", "koniec"]
    private static let whereWords = ["gdzie jestem", "gdzie ja jestem", "where am i"]
    private static let directionWords = ["ktoredy", "gdzie isc", "ktora strone", "w ktora strone", "which way", "direction*", "kierunek", "jak dojsc"]

    static func parse(_ text: String) -> Heard {
        let words = normalize(text)
        var heard = Heard()
        if let index = firstMatch(cornerPhrases, in: words) ?? firstMatch(colours, in: words) ?? firstMatch(numbers, in: words) {
            heard.corner = index
        }
        heard.exhibits = exhibitWords.filter { matchesAny($0.patterns, in: words) }.map(\.key)
        heard.yes = matchesAny(yesWords, in: words)
        heard.no = matchesAny(noWords, in: words)
        heard.story = matchesAny(storyWords, in: words)
        heard.next = matchesAny(nextWords, in: words)
        heard.repeatIt = matchesAny(repeatWords, in: words)
        heard.stop = matchesAny(stopWords, in: words)
        heard.whereAmI = matchesAny(whereWords, in: words)
        heard.directions = matchesAny(directionWords, in: words)
        return heard
    }

    /// Lowercase words without accents or punctuation ("Żółty!" → ["zolty"]).
    static func normalize(_ text: String) -> [String] {
        let folded = text.lowercased()
            .replacingOccurrences(of: "ł", with: "l")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ").map(String.init)
    }

    private static func firstMatch(_ groups: [[String]], in words: [String]) -> Int? {
        groups.firstIndex { matchesAny($0, in: words) }
    }

    private static func matchesAny(_ patterns: [String], in words: [String]) -> Bool {
        patterns.contains { matches($0, in: words) }
    }

    private static func matches(_ pattern: String, in words: [String]) -> Bool {
        let parts = pattern.split(separator: " ").map(String.init)
        guard !parts.isEmpty, words.count >= parts.count else { return false }
        for start in 0...(words.count - parts.count) {
            var all = true
            for (offset, part) in parts.enumerated() {
                let word = words[start + offset]
                let ok = part.hasSuffix("*") ? word.hasPrefix(String(part.dropLast())) : word == part
                if !ok { all = false; break }
            }
            if all { return true }
        }
        return false
    }
}
