import SwiftUI

// System faces carry Korean, Japanese and Arabic without bundled fonts and follow Dynamic Type.
extension Font {
    static func capture(_ style: Font.TextStyle, weight: Font.Weight = .regular, display: Bool = false) -> Font {
        if display { return .system(style, design: .monospaced, weight: .bold) }
        return .system(style, design: .default, weight: style == .headline && weight == .regular ? .semibold : weight)
    }
}
