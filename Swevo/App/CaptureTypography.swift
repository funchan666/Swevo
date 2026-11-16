import SwiftUI

extension Font {
    static func capture(_ style: Font.TextStyle, weight: Font.Weight = .regular, display: Bool = false) -> Font {
        let emphasized = display || style == .headline
        return .system(style, weight: emphasized && weight == .regular ? .semibold : weight)
    }
}

struct SceneTitle: View {
    @Environment(\.locale) private var locale
    @ScaledMetric private var size: CGFloat
    let title: String

    init(_ title: String, size: CGFloat = 44) {
        self.title = title
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        LocalizedText(title)
            .font(face)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var face: Font {
        switch AppLanguage.from(locale) {
        case .en, .es, .pt, .id:
            .custom("BricolageGrotesque36pt-SemiBold", fixedSize: size)
        case .ja, .ko, .ar:
            .system(size: size, weight: .semibold)
        }
    }
}
