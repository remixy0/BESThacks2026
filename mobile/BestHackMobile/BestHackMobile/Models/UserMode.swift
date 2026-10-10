import Foundation

/// How you use the app, chosen in the intro (and in Settings).
enum UserMode: String, CaseIterable, Identifiable {
    /// No map: four big coloured choices, everything spoken, strong vibrations.
    case blind
    /// The 3D map, with the same sound guidance.
    case standard

    var id: Self { self }

    var title: String {
        switch self {
        case .blind: tr("Just listening", "Tylko słuchanie")
        case .standard: tr("With the map", "Z mapą")
        }
    }

    var shortTitle: String {
        switch self {
        case .blind: tr("Listen", "Słuchanie")
        case .standard: tr("Map", "Mapa")
        }
    }

    var detail: String {
        switch self {
        case .blind: tr("No map. Four big coloured buttons, everything is spoken, and you can talk back.",
                        "Bez mapy. Cztery duże kolorowe przyciski, wszystko jest czytane na głos i można mówić do przewodnika.")
        case .standard: tr("See the museum in 3D and follow the sound.", "Muzeum w 3D i prowadzenie dźwiękiem.")
        }
    }

    /// One short line for the big mode card in Settings.
    var cardDetail: String {
        switch self {
        case .blind: tr("No map: big buttons, everything read aloud.", "Bez mapy: duże przyciski, wszystko czytane na głos.")
        case .standard: tr("A 3D map, and the sound shows the way.", "Mapa 3D, a dźwięk wskazuje drogę.")
        }
    }

    var systemImage: String {
        switch self {
        case .blind: "ear.fill"
        case .standard: "map.fill"
        }
    }
}
