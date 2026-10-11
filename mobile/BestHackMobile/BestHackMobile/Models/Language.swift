import Foundation
import Observation

/// The app's language: Polish (default) or English. Everything the app shows or says follows it,
/// including the exhibit stories, place names and the speech recognizer.
enum AppLanguage: String, CaseIterable, Identifiable {
    case polish = "pl"
    case english = "en"

    var id: Self { self }

    /// Shown in the switcher, always in its own language.
    var title: String {
        switch self {
        case .polish: "Polski"
        case .english: "English"
        }
    }

    var short: String { rawValue.uppercased() }

    /// The country flag shown next to the language.
    var flag: String {
        switch self {
        case .polish: "🇵🇱"
        case .english: "🇬🇧"
        }
    }

    /// ISO 639-3 code for ElevenLabs speech-to-text.
    var speechCode: String {
        switch self {
        case .polish: "pol"
        case .english: "eng"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

/// The current language. Views that call `tr(_:_:)` redraw when it changes.
@Observable
final class LanguageSettings {
    static let shared = LanguageSettings()
    static let key = "app.language"

    var current: AppLanguage {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: Self.key) }
    }

    private init() {
        current = UserDefaults.standard.string(forKey: Self.key).flatMap(AppLanguage.init) ?? .polish
    }
}

/// The English or Polish text, for the current language.
func tr(_ english: String, _ polish: String) -> String {
    LanguageSettings.shared.current == .polish ? polish : english
}

/// Same, for code that isn't on the main actor (error messages from network code).
nonisolated func trNow(_ english: String, _ polish: String) -> String {
    UserDefaults.standard.string(forKey: "app.language") == "en" ? english : polish
}

/// "1 metr", "3 metry", "12 metrów" / "1 meter", "12 meters".
func metersText(_ value: Int) -> String {
    guard LanguageSettings.shared.current == .polish else { return value == 1 ? "1 meter" : "\(value) meters" }
    let lastTwo = value % 100, last = value % 10
    if value == 1 { return "1 metr" }
    if (2...4).contains(last), !(12...14).contains(lastTwo) { return "\(value) metry" }
    return "\(value) metrów"
}

// MARK: - Museum texts

/// Polish names and stories for the museum data (the info JSON is in English).
nonisolated enum MuseumText {
    struct ExhibitText: Sendable {
        let title: String
        let gallery: String
        let story: String
    }

    static let polishExhibits: [String: ExhibitText] = [
        "maximo": ExhibitText(
            title: "Máximo – tytanozaur",
            gallery: "Hala Stanleya Fielda",
            story: "Odlew tytanozaura Patagotitan mayorum, jednego z największych zwierząt, jakie kiedykolwiek chodziły po lądzie. Miał około trzydziestu siedmiu metrów długości i żył około stu milionów lat temu na terenie dzisiejszej Patagonii w Argentynie."),
        "elephants": ExhibitText(
            title: "Walczące słonie afrykańskie",
            gallery: "Hala Stanleya Fielda",
            story: "Dwa samce słonia afrykańskiego sczepione w walce, przygotowane przez przyrodnika i preparatora Carla Akeleya. Można je oglądać w Field Museum od 1909 roku."),
        "totems": ExhibitText(
            title: "Pale totemiczne",
            gallery: "Hala Stanleya Fielda",
            story: "Rzeźbione pale z czerwonego cedru z północno-zachodniego wybrzeża Ameryki Północnej. Postacie ułożone jedna nad drugą – niedźwiedź, kruk, ptak gromu, bóbr i inne – to herby, które opowiadają historie rodów, które je wzniosły."),
        "tsavo_lions": ExhibitText(
            title: "Lwy z Tsavo",
            gallery: "Ssaki Afryki",
            story: "W 1898 roku dwa lwy bez grzyw atakowały robotników budujących most kolejowy nad rzeką Tsavo w Kenii. Zastrzelił je John Henry Patterson, a od 1925 roku są w Field Museum."),
        "seabirds": ExhibitText(
            title: "Nurkujące ptaki morskie",
            gallery: "Ptaki",
            story: "Głuptaki białe i głuptaki niebieskonogie składają skrzydła i z dużą prędkością nurkują w morzu, żeby łowić ryby. Gniazdują w hałaśliwych koloniach na skalistych wybrzeżach i wyspach."),
        "mask": ExhibitText(
            title: "Maska z zielonego kamienia",
            gallery: "Starożytne Ameryki",
            story: "Kamienne maski wykonywano w całej starożytnej Mezoameryce, zwłaszcza w Teotihuacán w środkowym Meksyku. Ich oczy często inkrustowano muszlami i obsydianem."),
        "pawnee_lodge": ExhibitText(
            title: "Ziemianka Paunisów",
            gallery: "Starożytne Ameryki",
            story: "Rekonstrukcja w pełnej skali ziemianki, tradycyjnego domu ludu Paunisów z Wielkich Równin. Wejdź do środka, żeby zobaczyć cztery centralne słupy, palenisko i rodzinne posłania."),
        "mastaba": ExhibitText(
            title: "Kaplica grobowca mastaby",
            gallery: "Wnętrze starożytnego Egiptu",
            story: "Mastaba to starożytny egipski grobowiec z płaskim dachem. Przejdź przez wejście do korytarza kaplicy, gdzie zostawiano dary dla osoby pochowanej poniżej. Płaskorzeźby na ścianach mają tu charakter dekoracyjny."),
    ]

    static let polishPlaces: [String: String] = [
        "Africa": "Afryka",
        "Ancient Americas": "Starożytne Ameryki",
        "Apsáalooke Women and Warriors": "Kobiety i wojownicy Apsáalooke",
        "Bird Habitats": "Siedliska ptaków",
        "Birds": "Ptaki",
        "Coat Check": "Szatnia",
        "Field Bistro": "Field Bistro",
        "Founders' Room": "Sala Założycieli",
        "Inside Ancient Egypt": "Wnętrze starożytnego Egiptu",
        "Mammals of Africa": "Ssaki Afryki",
        "Museum Store": "Sklep muzealny",
        "Nature Walk": "Ścieżka przyrody",
        "Pawnee Earth Lodge": "Ziemianka Paunisów",
        "Plant Medicine": "Rośliny lecznicze",
        "Reptiles": "Gady",
        "Science Hub": "Centrum nauki",
        "What Is an Animal?": "Czym jest zwierzę?",
        "Stanley Field Hall": "Hala Stanleya Fielda",
        "South Entrance": "Wejście południowe",
        "North Entrance": "Wejście północne",
        "Corridor": "Korytarz",
        "Field Museum": "Field Museum",
    ]
}

extension MuseumInfo.Exhibit {
    /// The title in the app's language.
    var name: String {
        LanguageSettings.shared.current == .polish ? (MuseumText.polishExhibits[key]?.title ?? title) : title
    }

    /// The gallery in the app's language.
    var galleryName: String {
        LanguageSettings.shared.current == .polish ? (MuseumText.polishExhibits[key]?.gallery ?? gallery) : gallery
    }

    /// The story in the app's language.
    var story: String {
        LanguageSettings.shared.current == .polish ? (MuseumText.polishExhibits[key]?.story ?? text) : text
    }
}

/// A place name from the museum data ("Birds", "Stanley Field Hall"…) in the app's language.
func placeText(_ english: String) -> String {
    guard LanguageSettings.shared.current == .polish else { return english }
    return MuseumText.polishPlaces[english] ?? english
}
