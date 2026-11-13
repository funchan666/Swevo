import SwiftUI
import UIKit

enum SwevoStyle {
    static let background = Color(red: 0.071, green: 0.106, blue: 0.082)
    static let surface = Color(red: 0.106, green: 0.165, blue: 0.129)
    static let raised = Color(red: 0.161, green: 0.235, blue: 0.173)
    static let accent = Color(red: 0.831, green: 0.918, blue: 0.439)
    static let ink = Color(red: 0.098, green: 0.145, blue: 0.082)
    static let secondary = Color(red: 0.737, green: 0.784, blue: 0.686)
    static let paper = Color(red: 0.945, green: 0.941, blue: 0.867)
    static let paperSecondary = Color(red: 0.275, green: 0.341, blue: 0.227)
    static let mist = Color(red: 0.851, green: 0.890, blue: 0.710)
    static let line = Color.white.opacity(0.10)
    static let danger = Color(red: 1.000, green: 0.659, blue: 0.565)
}

// MARK: - Original raster artwork (Asset Catalog). Missing art never blocks layout or touch.

enum ArtworkCatalog {
    private static var cache: [String: Bool] = [:]
    static func has(_ name: String) -> Bool {
        if let known = cache[name] { return known }
        let found = UIImage(named: name) != nil
        cache[name] = found
        return found
    }
}

/// Square spot illustrations for empty states, sheets and cards.
struct CaptureArtwork: View {
    enum Kind: String { case studio = "ArtStudio", lesson = "ArtLesson", pass = "ArtPass", notebook = "ArtNotebook" }
    let kind: Kind
    var height: CGFloat = 160
    var body: some View {
        Group {
            if ArtworkCatalog.has(kind.rawValue) {
                Image(kind.rawValue).renderingMode(.original).resizable().interpolation(.high).scaledToFit()
            } else { Color.clear }
        }
        .frame(width: height, height: height)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Editorial covers for the guide and practice tools.
struct GuideArtwork: View {
    enum Subject: String {
        case steady = "GuideSteady"
        case track = "GuideTrack"
        case reveal = "GuideReveal"
        case parallax = "GuideParallax"
        case focus = "GuideFocus"
        case setup = "GuideSetup"
        case review = "ToolReview", speed = "ToolSpeed", frame = "ToolFrame", audio = "ToolAudio"
    }
    let subject: Subject
    var body: some View {
        SwevoStyle.raised.overlay {
            if ArtworkCatalog.has(subject.rawValue) {
                Image(subject.rawValue).renderingMode(.original).resizable().interpolation(.high).scaledToFill()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CaptureBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.clear.aspectRatio(1.9, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        Image("HeroCapture").resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                }
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)
            LocalizedText("Make the move count.")
                .font(.capture(.largeTitle, display: true)).foregroundStyle(SwevoStyle.paper)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            LocalizedText("Learn to reveal, follow and reframe with the phone in your hand.")
                .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Glyphs

enum SwevoGlyph: String, CaseIterable {
    case home, feed, edit, library, link, search, bookmark, download
    case play, pause, close, back, sound, mute, folder, settings
    var assetName: String { "Glyph" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    // Shown only while the original glyph artwork is missing, so every control stays usable.
    var fallbackTitle: String {
        switch self {
        case .home: "Home"; case .feed: "Watch"; case .edit: "Edit"; case .library: "Library"
        case .link: "Link"; case .search: "Search"; case .bookmark: "Saved"; case .download: "Download"
        case .play: "Play"; case .pause: "Pause"; case .close: "Close"; case .back: "Back"
        case .sound: "Sound"; case .mute: "Mute"; case .folder: "Folder"; case .settings: "Me"
        }
    }
}

/// Single-colour original glyph artwork, tinted at display time.
struct Glyph: View {
    @Environment(\.layoutDirection) private var direction
    let symbol: SwevoGlyph
    var size: CGFloat = 25
    var tint: Color = .white
    var body: some View {
        Group {
            if ArtworkCatalog.has(symbol.assetName) {
                Image(symbol.assetName).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                    .foregroundStyle(tint)
                    .scaleEffect(x: symbol == .back && direction == .rightToLeft ? -1 : 1, y: 1)
            } else { Color.clear }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Template artwork by asset name (player rail, tab-like controls).
struct TintedArtwork: View {
    let name: String
    var tint: Color = .white
    var body: some View {
        if ArtworkCatalog.has(name) {
            Image(name).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                .foregroundStyle(tint).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

struct IconButton: View {
    let symbol: SwevoGlyph
    let label: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if ArtworkCatalog.has(symbol.assetName) {
                    Glyph(symbol: symbol, size: 21, tint: selected ? SwevoStyle.accent : .white)
                } else {
                    LocalizedText(symbol.fallbackTitle).font(.capture(.caption2, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 4)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .background { if selected { CaptureSurface(tone: .plum) } }
            .contentShape(.interaction, Rectangle())
        }.buttonStyle(PressStyle()).accessibilityLabel(LocalizedStringKey(label))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Controls

struct PressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(!isEnabled ? 0.55 : (configuration.isPressed ? 0.7 : 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
// Compact controls keep their full localized label; enclosing layouts scroll or use ViewThatFits.
struct CompactActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.capture(.footnote, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .foregroundStyle(SwevoStyle.paper)
            .background { CaptureSurface(tone: .plum) }
            .contentShape(.interaction, Rectangle())
            .opacity(!isEnabled ? 0.55 : (configuration.isPressed ? 0.7 : 1))
    }
}
struct ActionButton: View {
    let title: String
    var primary = true
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            LocalizedText(busy ? "Please wait…" : title).font(.capture(.subheadline, display: true))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading).padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(primary ? SwevoStyle.ink : SwevoStyle.paper)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background { CaptureSurface(tone: primary ? .accent : .plum) }
                .contentShape(.interaction, Rectangle())
        }.buttonStyle(PressStyle()).disabled(busy)
    }
}
struct MessagePanel: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LocalizedText(title).font(.capture(.headline)).foregroundStyle(SwevoStyle.paper)
            LocalizedText(message).font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action { ActionButton(title: actionTitle, primary: false, action: action) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
struct ErrorNote: View {
    @Environment(\.locale) private var locale
    let message: String
    var body: some View {
        LocalizedText(message).font(.capture(.subheadline)).foregroundStyle(SwevoStyle.danger)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            .accessibilityLabel(Text(verbatim: L10n.display("Error: \(message)", language: AppLanguage.from(locale))))
    }
}
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.capture(.subheadline)).foregroundStyle(SwevoStyle.paper).padding(14)
            .background(SwevoStyle.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .tint(SwevoStyle.accent)
    }
}
// Measure in the owning screen, so scrolling, keyboard avoidance and resizing
// keep the input exclusion region aligned. No global window or focus broadcast.
private struct KeyboardInputBounds: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $0.union($1) })
    }
}
private struct OutsideInputTap: ViewModifier {
    let focus: FocusState<Bool>.Binding
    let scope: String
    @State private var inputBounds: CGRect?
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle()) // Hit area only.
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named(scope)).onEnded { tap in
                guard focus.wrappedValue, let inputBounds, !inputBounds.contains(tap.location) else { return }
                focus.wrappedValue = false
            })
            .onPreferenceChange(KeyboardInputBounds.self) { inputBounds = $0[scope] }
            .coordinateSpace(name: scope)
    }
}

extension View {
    func keyboardInputRegion(_ scope: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: KeyboardInputBounds.self,
                                       value: [scope: geometry.frame(in: .named(scope))])
            }.allowsHitTesting(false)
        }
    }
    func dismissKeyboardOnOutsideTap(_ focus: FocusState<Bool>.Binding, scope: String) -> some View {
        modifier(OutsideInputTap(focus: focus, scope: scope))
    }
    func swevoField() -> some View { modifier(FieldStyle()) }
    // Extend visual surfaces to every container edge, while preserving keyboard avoidance
    // and the foreground's safe area for interactive controls.
    func swevoScreenBackground(_ color: Color = SwevoStyle.background) -> some View {
        background { color.ignoresSafeArea(.container, edges: .all) }
    }
    // A readable column follows the available container (outer or inner display) without resetting state.
    func swevoPage() -> some View {
        pageHorizontalMargins().padding(.top, 16).padding(.bottom, 24)
            .frame(maxWidth: 680).frame(maxWidth: .infinity, alignment: .top)
    }
    @ViewBuilder
    fileprivate func pageHorizontalMargins() -> some View {
        if #available(iOS 27.1, *) {
            contentMargins(for: .container, edges: .horizontal)
        } else {
            padding(.horizontal, 20)
        }
    }
}
struct MediaCover: View {
    let url: URL?
    var folder = false
    var body: some View {
        SwevoStyle.raised.overlay {
            GeometryReader { geometry in
                Group {
                    if folder { Glyph(symbol: .folder, size: 30) }
                    else if let url {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Glyph(symbol: .feed, size: 30) }
                        }
                    } else { Glyph(symbol: .feed, size: 30) }
                }.frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        }.clipped()
    }
}
struct SheetHeading: View {
    let title: String
    var close: () -> Void
    var body: some View {
        HStack {
            LocalizedText(title).font(.capture(.headline)).lineLimit(2)
            Spacer()
            IconButton(symbol: .close, label: "Close", action: close)
        }.pageHorizontalMargins().padding(.top, 8)
    }
}

struct SectionLabel: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                LocalizedText(title).font(.capture(.headline))
                Spacer(minLength: 12)
                if let detail { LocalizedText(detail).font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary) }
            }
            VStack(alignment: .leading, spacing: 6) {
                LocalizedText(title).font(.capture(.headline))
                if let detail { LocalizedText(detail).font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Original raster artwork. Its layout never participates in navigation hit testing.
struct SwevoIllustration: View {
    let name: String
    var height: CGFloat = 180
    var body: some View {
        Group {
            if ArtworkCatalog.has(name) {
                Image(name).renderingMode(.original).resizable().scaledToFit()
            } else { Color.clear }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct FeatureRow: View {
    let symbol: SwevoGlyph
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 16) {
            Glyph(symbol: symbol, size: 22)
                .frame(width: 48, height: 48)
                .background(SwevoStyle.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText(title).font(.capture(.subheadline, weight: .semibold)).foregroundStyle(SwevoStyle.paper)
                LocalizedText(detail).font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Surfaces (native fills; no drawn artwork)

struct CaptureSurface: View {
    enum Tone { case accent, plum, blush, mist }
    let tone: Tone
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        switch tone {
        case .accent: shape.fill(SwevoStyle.accent)
        case .plum: shape.fill(SwevoStyle.raised).overlay(shape.strokeBorder(SwevoStyle.line))
        case .blush: shape.fill(SwevoStyle.paper)
        case .mist: shape.fill(SwevoStyle.surface).overlay(shape.strokeBorder(SwevoStyle.line))
        }
    }
}

/// Surfaces for controls placed on the blush paper card.
struct PaperSurface: View {
    enum Tone { case accent, plum, inkOnPaper, mistOnPaper }
    let tone: Tone
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        switch tone {
        case .accent: shape.fill(SwevoStyle.accent)
        case .plum: shape.fill(SwevoStyle.raised)
        case .inkOnPaper: shape.fill(SwevoStyle.ink)
        case .mistOnPaper: shape.fill(SwevoStyle.mist)
        }
    }
}

struct MatteActionStyle: ButtonStyle {
    var onPaper = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.capture(.footnote, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
            .foregroundStyle(onPaper ? SwevoStyle.ink : SwevoStyle.paper)
            .background { PaperSurface(tone: onPaper ? .mistOnPaper : .plum) }
            .contentShape(Rectangle())
            .opacity(!isEnabled ? 0.55 : (configuration.isPressed ? 0.75 : 1))
    }
}

struct ChoiceStrip: View {
    let values: [String]
    let selected: String
    let select: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button { select(value) } label: {
                        LocalizedText(value).font(.capture(.footnote, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .foregroundStyle(selected == value ? SwevoStyle.ink : SwevoStyle.paper)
                            .background { CaptureSurface(tone: selected == value ? .accent : .plum) }
                            .contentShape(Rectangle())
                    }.buttonStyle(PressStyle())
                        .accessibilityAddTraits(selected == value ? .isSelected : [])
                }
            }
        }
    }
}
