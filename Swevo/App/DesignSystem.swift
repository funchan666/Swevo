import SwiftUI
import UIKit

enum SwevoStyle {
    static let background = Color("LaunchBackground")
    static let surface = Color(red: 25.0 / 255, green: 43.0 / 255, blue: 60.0 / 255)
    static let raised = Color(red: 34.0 / 255, green: 55.0 / 255, blue: 74.0 / 255)
    static let accent = Color(red: 143.0 / 255, green: 228.0 / 255, blue: 212.0 / 255)
    static let ink = Color(red: 15.0 / 255, green: 33.0 / 255, blue: 43.0 / 255)
    static let secondary = Color(red: 176.0 / 255, green: 197.0 / 255, blue: 214.0 / 255)
    static let paper = Color(red: 239.0 / 255, green: 247.0 / 255, blue: 252.0 / 255)
    static let paperSecondary = Color(red: 51.0 / 255, green: 75.0 / 255, blue: 94.0 / 255)
    static let mist = Color(red: 211.0 / 255, green: 232.0 / 255, blue: 241.0 / 255)
    static let line = paper.opacity(0.16)
    static let danger = Color(red: 255.0 / 255, green: 172.0 / 255, blue: 186.0 / 255)
    static let pageMargin: CGFloat = 20

    static func pageContentWidth(in container: GeometryProxy) -> CGFloat {
        if #available(iOS 27.1, *) {
            let margins = container.contentMargins(for: .container, edges: .horizontal)
            return max(0, container.size.width - margins.leading - margins.trailing)
        }
        return max(0, container.size.width - pageMargin * 2)
    }

    static func intersectsReservedRegion(_ frame: CGRect, in container: GeometryProxy) -> Bool {
        guard #available(iOS 27.1, *) else { return false }
        let regions = container.reservedRegions(kind: .division) + container.reservedRegions(kind: .occlusion)
        return regions.contains { $0.isActive && frame.intersects($0.frame) }
    }
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

struct SceneArtwork: View {
    let name: String

    var body: some View {
        GeometryReader { geometry in
            let subjectWidth = geometry.size.height * 1.5
            if geometry.size.width > geometry.size.height * 1.85 {
                ZStack {
                    SceneImage(name: name).blur(radius: 22).opacity(0.55)
                    SceneImage(name: name).frame(width: subjectWidth)
                        .mask {
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.14),
                                .init(color: .black, location: 0.86),
                                .init(color: .clear, location: 1)
                            ], startPoint: .leading, endPoint: .trailing)
                        }
                }
            } else {
                SceneImage(name: name)
            }
        }
        .clipped()
        .overlay {
            LinearGradient(stops: [
                .init(color: SwevoStyle.background.opacity(0.82), location: 0),
                .init(color: .clear, location: 0.24),
                .init(color: .clear, location: 0.46),
                .init(color: SwevoStyle.background.opacity(0.82), location: 0.76),
                .init(color: SwevoStyle.background, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Aspect-fill display for bundled scenery and empty-state artwork.
struct SceneImage: View {
    let name: String

    var body: some View {
        GeometryReader { geometry in
            Image(name).resizable().interpolation(.high).scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .background(SwevoStyle.background)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ScenePage<Opening: View, PageContent: View>: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let artwork: String?
    let artworkOpacity: Double
    let depth: CGFloat
    let openingGap: CGFloat
    let opening: (CGFloat) -> Opening
    let content: (GeometryProxy) -> PageContent

    init(artwork: String?, depth: CGFloat, openingGap: CGFloat = 16, artworkOpacity: Double = 1,
         @ViewBuilder opening: @escaping (CGFloat) -> Opening,
         @ViewBuilder content: @escaping (GeometryProxy) -> PageContent) {
        self.artwork = artwork
        self.artworkOpacity = artworkOpacity
        self.depth = depth
        self.openingGap = openingGap
        self.opening = opening
        self.content = content
    }

    var body: some View {
        GeometryReader { container in
            let widthAdjustment = artwork == nil ? 0 : min(72, max(-32, (container.size.width - 390) * 0.22))
            let height = verticalSizeClass == .compact ? min(depth, 178) : max(44, depth + widthAdjustment)
            let openingTopPadding: CGFloat = 10
            ScrollView {
                VStack(spacing: 0) {
                    if depth > 0 || artwork != nil {
                        opening(height)
                            .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
                            .pageHorizontalMargins()
                            .frame(maxWidth: 680)
                            .frame(maxWidth: .infinity)
                            .padding(.top, openingTopPadding)
                            .padding(.bottom, openingGap)
                    }
                    content(container).swevoPage()
                        .background { SwevoStyle.background }
                }
            }
            .clipped()
            .background(alignment: .top) {
                // Let the artwork reach the screen edge while the scroll viewport respects the safe area.
                if let artwork {
                    SceneArtwork(name: artwork)
                        .opacity(artworkOpacity)
                        .ignoresSafeArea(.container, edges: .top)
                        .frame(height: height + openingTopPadding + openingGap)
                }
            }
        }
        .swevoScreenBackground()
        .foregroundStyle(SwevoStyle.paper)
    }
}

extension ScenePage where Opening == EmptyView {
    init(artwork: String? = nil, depth: CGFloat = 0, artworkOpacity: Double = 1,
         @ViewBuilder content: @escaping (GeometryProxy) -> PageContent) {
        self.init(artwork: artwork, depth: depth, openingGap: 0, artworkOpacity: artworkOpacity,
                  opening: { _ in EmptyView() }, content: content)
    }
}

// MARK: - Glyphs

enum SwevoGlyph: String, CaseIterable {
    case feed, edit, library, link, search, bookmark, download
    case play, pause, close, back, sound, mute, folder, settings
    var assetName: String { "Glyph" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    // Shown only while the original glyph artwork is missing, so every control stays usable.
    var fallbackTitle: String {
        switch self {
        case .feed: "Watch"; case .edit: "Edit"; case .library: "Library"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(!isEnabled ? 0.55 : (configuration.isPressed ? 0.7 : 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
            ActionLabel(title: busy ? "Please wait…" : title, primary: primary, busy: busy)
        }.buttonStyle(PressStyle()).disabled(busy)
    }
}

struct ActionLabel: View {
    let title: String
    var symbol: SwevoGlyph? = nil
    var primary = true
    var busy = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let iconTint = primary ? SwevoStyle.ink : SwevoStyle.accent

        HStack(spacing: 10) {
            LocalizedText(title).font(.capture(.subheadline, weight: .semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if busy {
                    ProgressView().tint(iconTint)
                } else if let symbol {
                    Glyph(symbol: symbol, size: 17, tint: iconTint)
                } else {
                    Glyph(symbol: .back, size: 13, tint: iconTint).rotationEffect(.degrees(180))
                }
            }
            .frame(width: 38, height: 36)
            .background(primary ? SwevoStyle.accent : SwevoStyle.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .frame(minHeight: 50)
        .foregroundStyle(SwevoStyle.paper)
        .background(primary ? SwevoStyle.raised : SwevoStyle.surface, in: shape)
        .overlay { shape.strokeBorder(primary ? SwevoStyle.accent.opacity(0.30) : SwevoStyle.line).allowsHitTesting(false) }
        .contentShape(.interaction, shape)
    }
}

struct EmptyStateScene: View {
    let artwork: String
    var title: String? = nil
    var message: String? = nil
    let container: GeometryProxy
    var columnWidth: CGFloat? = nil
    var maxArtworkHeight: CGFloat = 300

    var body: some View {
        let artworkWidth = columnWidth ?? min(container.size.width, 680)
        let artworkHeight = ArtworkCatalog.has(artwork)
            ? min(artworkWidth * 0.64, min(maxArtworkHeight, container.size.height * 0.36))
            : 0

        VStack(alignment: .leading, spacing: 6) {
            if let title {
                SceneTitle(title, size: 32)
                    .foregroundStyle(SwevoStyle.paper)
            }
            if let message {
                LocalizedText(message)
                    .font(.capture(.body))
                    .foregroundStyle(SwevoStyle.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, artworkHeight * 0.86)
        .background(alignment: .top) {
            SceneImage(name: artwork)
                .frame(width: columnWidth == nil ? artworkWidth : nil, height: artworkHeight)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.14),
                        .init(color: .black, location: 0.54),
                        .init(color: .black.opacity(0.08), location: 0.85),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .mask {
                    if columnWidth != nil || artworkWidth < container.size.width {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.08),
                            .init(color: .black, location: 0.92),
                            .init(color: .clear, location: 1)
                        ], startPoint: .leading, endPoint: .trailing)
                    } else {
                        Color.black
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

struct EmptyStateAction: View {
    let title: String
    let symbol: SwevoGlyph
    var primary = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionLabel(title: title, symbol: symbol, primary: primary)
        }
        .buttonStyle(PressStyle())
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
            .fixedSize(horizontal: false, vertical: true)
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
    func pageHorizontalMargins() -> some View {
        if #available(iOS 27.1, *) {
            contentMargins(for: .container, edges: .horizontal)
        } else {
            padding(.horizontal, SwevoStyle.pageMargin)
        }
    }

    func swevoGlass(cornerRadius: CGFloat = 16, tint: Color? = nil) -> some View {
        modifier(SwevoGlass(cornerRadius: cornerRadius, tint: tint))
    }

    func sceneDismiss(symbol: SwevoGlyph = .close, label: String = "Close", edge: HorizontalEdge = .trailing,
                      disabled: Bool = false, action: @escaping () -> Void) -> some View {
        overlay(alignment: .top) {
            IconButton(symbol: symbol, label: label, action: action)
                .swevoGlass(cornerRadius: 22)
                .disabled(disabled)
                .accessibilitySortPriority(1)
                .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
                .pageHorizontalMargins()
                .padding(.top, 8)
        }
    }
}

private struct SwevoGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content.background(tint ?? .clear, in: shape)
                .background(SwevoStyle.raised, in: shape)
                .overlay { shape.strokeBorder(SwevoStyle.line).allowsHitTesting(false) }
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(tint ?? SwevoStyle.raised.opacity(0.48)), in: shape)
        } else {
            content.background(tint ?? SwevoStyle.raised.opacity(0.52), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(SwevoStyle.paper.opacity(0.22)).allowsHitTesting(false) }
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
        HStack(alignment: .top, spacing: 12) {
            LocalizedText(title).font(.capture(.headline))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
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
            Glyph(symbol: symbol, size: 20, tint: SwevoStyle.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText(title).font(.capture(.subheadline, weight: .semibold)).foregroundStyle(SwevoStyle.paper)
                LocalizedText(detail).font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

// MARK: - Surfaces (native fills; no drawn artwork)

struct CaptureSurface: View {
    enum Tone { case accent, plum, blush, mist }
    let tone: Tone
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        switch tone {
        case .accent: shape.fill(SwevoStyle.accent)
        case .plum: shape.fill(SwevoStyle.raised).overlay(shape.strokeBorder(SwevoStyle.line))
        case .blush: shape.fill(SwevoStyle.paper)
        case .mist: shape.fill(SwevoStyle.surface).overlay(shape.strokeBorder(SwevoStyle.line))
        }
    }
}

/// Surfaces for controls placed on light cards.
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
                            .background(selected == value ? SwevoStyle.accent : SwevoStyle.surface, in: Capsule())
                            .contentShape(.interaction, Capsule())
                    }.buttonStyle(PressStyle())
                        .accessibilityAddTraits(selected == value ? .isSelected : [])
                }
            }
        }
    }
}
