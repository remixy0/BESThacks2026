import SwiftUI

/// Map colours shared by the 2D map (the 3D model, MuseumMap.usdz, bakes in the same floor tints).
enum MapPalette {
    /// Soft floor tint per gallery theme, like Apple's indoor maps.
    static func floor(theme: String, dark: Bool) -> Color {
        let rgb: (Double, Double, Double) = switch theme {
        case "birds": (0.86, 0.92, 0.95)
        case "animals": (0.90, 0.91, 0.93)
        case "mammals": (0.95, 0.91, 0.84)
        case "africa": (0.87, 0.93, 0.87)
        case "nature": (0.88, 0.94, 0.86)
        case "americas": (0.87, 0.90, 0.96)
        case "apsaalooke": (0.93, 0.94, 0.88)
        case "egypt": (0.96, 0.92, 0.84)
        case "white": (0.96, 0.93, 0.86)
        case "warm": (0.95, 0.91, 0.87)
        default: (0.85, 0.85, 0.86)
        }
        return dark ? Color(red: rgb.0 * 0.40, green: rgb.1 * 0.41, blue: rgb.2 * 0.45) : Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    static func building(dark: Bool) -> Color { dark ? Color(red: 0.17, green: 0.19, blue: 0.23) : Color(white: 0.965) }
    static func hall(dark: Bool) -> Color { dark ? Color(red: 0.24, green: 0.26, blue: 0.31) : Color(white: 0.985) }
    static func wall(dark: Bool) -> Color { dark ? Color(red: 0.5, green: 0.53, blue: 0.6) : Color(white: 0.72) }
    static func outside(dark: Bool) -> Color { dark ? Color(red: 0.09, green: 0.1, blue: 0.13) : Color(red: 0.93, green: 0.93, blue: 0.91) }
    static let exhibit = Theme.coral
    static let selected = Theme.accent
    static let route = Theme.coral
    static let user = Theme.accent
    static let visited = Theme.mint
}
