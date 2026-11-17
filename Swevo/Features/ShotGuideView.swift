import SwiftUI

// Bundled, original editorial content. Reading never calls video, quota or advertising APIs.
struct ShotNote: Identifiable {
    struct Section {
        let title: String
        let body: String
        init(_ title: String, _ body: String) { self.title = title; self.body = body }
    }
    enum Cover: String {
        case steady = "SceneShot"
        case track = "SceneTrack"
        case reveal = "SceneReveal"
        case parallax = "SceneParallax"
        case focus = "GuideFocus"
        case setup = "SceneSetup"
    }
    let id: String
    let category: String
    let title: String
    let shortTitle: String
    let summary: String
    let cover: Cover
    let practiceMovement: ShotMovement?
    let sections: [Section]
    let takeaway: String
    var artwork: String { cover.rawValue }

    static let all: [ShotNote] = [
        ShotNote(
            id: "steady", category: "Framing", title: "Build a steady frame", shortTitle: "Build a steady frame",
            summary: "Choose a start and an end frame before you move.", cover: .steady, practiceMovement: nil,
            sections: [.init("Set your anchor", "Hold the phone with both hands and tuck your elbows comfortably. Pick a line in the scene to check the horizon."),
                       .init("Leave room", "Start still for a beat, then make the move and hold the end frame. Those two pauses give you clean cut points.")],
            takeaway: "Start and end on a frame you would keep as a photo."),
        ShotNote(
            id: "track", category: "Movement", title: "Follow at walking pace", shortTitle: "Follow",
            summary: "Keep a steady distance from a moving subject.", cover: .track, practiceMovement: .track,
            sections: [.init("Rehearse the path", "Agree on a short route with your subject and walk it together. Choose a clear path and look where you are going."),
                       .init("Match their rhythm", "Walk at the same speed and hold the subject at the same point in the frame. Leave room in the direction they are moving.")],
            takeaway: "If your distance changes, reset before the next take."),
        ShotNote(
            id: "reveal", category: "Movement", title: "Reveal from behind an edge", shortTitle: "Reveal",
            summary: "Start with the subject hidden behind the foreground.", cover: .reveal, practiceMovement: .reveal,
            sections: [.init("Choose a foreground", "Start with a wall or doorframe close to the lens. Keep the subject visible at your planned end position."),
                       .init("Move across the edge", "Slide sideways until the subject appears. Stop before you add a second move, so the reveal reads clearly.")],
            takeaway: "Look at the final frame first. Plan the reveal backward from it."),
        ShotNote(
            id: "parallax", category: "Movement", title: "Use layers for parallax", shortTitle: "Parallax",
            summary: "Show depth with a close foreground and a distant subject.", cover: .parallax, practiceMovement: .parallax,
            sections: [.init("Space the layers", "Find a nearby plant or post and place the subject farther away. Check that both are legible in the same frame."),
                       .init("Take a short side step", "Move parallel to the subject. The foreground will cross the frame faster than the background, giving the shot depth.")],
            takeaway: "A small, even move is enough when your foreground is close."),
        ShotNote(
            id: "focus", category: "Setup", title: "Keep focus where you want it", shortTitle: "Keep focus where you want it",
            summary: "Plan which subject should be sharp through the move.", cover: .focus, practiceMovement: nil,
            sections: [.init("Watch the preview", "Rehearse the move and check when the phone changes focus or exposure. Try it once without recording."),
                       .init("Use your camera controls", "If your camera app supports it, lock focus and exposure on the subject before the take. Recheck when the distance or light changes.")],
            takeaway: "Review the end frame before you record another take."),
        ShotNote(
            id: "setup", category: "Setup", title: "Build a three-shot sequence", shortTitle: "Build a three-shot sequence",
            summary: "A wide view, a medium action and a detail can tell one story.", cover: .setup, practiceMovement: nil,
            sections: [.init("List the three frames", "Show where you are, show the action and finish with a detail. Keep the subject moving in a consistent screen direction."),
                       .init("Review in order", "Play the three clips back together. Note the frame that is hard to cut and repeat that one with a longer hold.")],
            takeaway: "Write one purpose for each shot before you press record.")
    ]
}

private enum ShotGuideRoute: Hashable {
    case note(String)
    case practice(ShotMovement)
}

struct ShotGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var category = "All"
    @State private var path: [ShotGuideRoute]
    private let categories = ["All", "Framing", "Movement", "Setup"]
    private var notes: [ShotNote] {
        ShotNote.all.filter { category == "All" || $0.category == category }
    }

    init(initialNoteID: String? = nil) {
        _path = State(initialValue: initialNoteID.map { [.note($0)] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScenePage(artwork: notes.first?.artwork, depth: 210, openingGap: 0, artworkOpacity: 0.68) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    if let first = notes.first {
                        NavigationLink(value: ShotGuideRoute.note(first.id)) {
                            HStack(spacing: 10) {
                                LocalizedText(first.title).font(.capture(.subheadline, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Glyph(symbol: .back, size: 12, tint: SwevoStyle.accent).rotationEffect(.degrees(180))
                            }.padding(.horizontal, 14).padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .swevoGlass(cornerRadius: 16)
                                .foregroundStyle(SwevoStyle.paper)
                                .contentShape(Rectangle())
                        }.buttonStyle(PressStyle()).accessibilityIdentifier("shotGuide.\(first.id)")
                    }
                }.padding(.trailing, 50)
            } content: { _ in
                VStack(alignment: .leading, spacing: 20) {
                    ChoiceStrip(values: categories, selected: category) { category = $0 }
                    if let first = notes.first {
                        LocalizedText(first.summary).font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 140), spacing: 16)], alignment: .leading, spacing: 22) {
                        ForEach(Array(notes.dropFirst())) { note in
                            NavigationLink(value: ShotGuideRoute.note(note.id)) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Color.clear.aspectRatio(1.3, contentMode: .fit)
                                        .background { SceneImage(name: note.artwork) }
                                    LocalizedText(note.shortTitle).font(.capture(.headline))
                                        .fixedSize(horizontal: false, vertical: true)
                                    LocalizedText(note.summary).font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }.foregroundStyle(SwevoStyle.paper)
                                    .contentShape(Rectangle())
                            }.buttonStyle(PressStyle()).accessibilityIdentifier("shotGuide.\(note.id)")
                        }
                    }
                }
            }
                .sceneDismiss { dismiss() }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ShotGuideRoute.self) { route in
                    switch route {
                    case .note(let id):
                        if let note = ShotNote.all.first(where: { $0.id == id }) {
                            ShotNoteReader(note: note)
                        }
                    case .practice(let movement):
                        ShotPracticeView(initialMovement: movement, showsBackButton: true)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
        }
    }
}

private struct ShotNoteReader: View {
    let note: ShotNote
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { viewport in
            let docked = note.practiceMovement != nil && canDockPractice(in: viewport)
            ScenePage(artwork: note.artwork, depth: 264, openingGap: 0) { _ in
                SceneTitle(note.title, size: 36)
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(.top, 52)
            } content: { _ in
                VStack(alignment: .leading, spacing: 24) {
                    LocalizedText(note.summary).font(.capture(.body))
                        .foregroundStyle(SwevoStyle.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    shootingSteps
                    takeaway
                    if !docked, let movement = note.practiceMovement {
                        practiceLink(movement)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if docked, let movement = note.practiceMovement {
                    practiceLink(movement)
                        .pageHorizontalMargins()
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(SwevoStyle.background)
                }
            }
        }
        .sceneDismiss(symbol: .back, label: "Back to shot field notes", edge: .leading) { dismiss() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var shootingSteps: some View {
        VStack(alignment: .leading, spacing: 0) {
            LocalizedText("How to shoot").font(.capture(.footnote, weight: .semibold))
                .foregroundStyle(SwevoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 10)
            ForEach(note.sections.indices, id: \.self) { index in
                Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
                shootingStep(note.sections[index], number: index + 1)
            }
        }
    }

    private func shootingStep(_ section: ShotNote.Section, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(number, format: .number).monospacedDigit()
                    .font(.capture(.headline))
                    .foregroundStyle(SwevoStyle.accent)
                LocalizedText(section.title).font(.capture(.title3, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            LocalizedText(section.body).font(.capture(.body)).lineSpacing(5)
                .foregroundStyle(SwevoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 14)
    }

    private var takeaway: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("One thing to remember").font(.capture(.footnote, weight: .semibold))
                .foregroundStyle(SwevoStyle.accent)
                .accessibilityAddTraits(.isHeader)
            LocalizedText(note.takeaway).font(.capture(.body, weight: .medium)).lineSpacing(4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .swevoGlass(cornerRadius: 16)
    }

    private func practiceLink(_ movement: ShotMovement) -> some View {
        NavigationLink(value: ShotGuideRoute.practice(movement)) {
            HStack(spacing: 12) {
                LocalizedText("Try this camera move").font(.capture(.subheadline, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .back, size: 15, tint: SwevoStyle.ink)
                    .rotationEffect(.degrees(180))
            }
            .foregroundStyle(SwevoStyle.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .background { CaptureSurface(tone: .accent) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("shotGuide.try.\(movement.id)")
    }

    private func canDockPractice(in viewport: GeometryProxy) -> Bool {
        guard typeSize <= .xLarge, SwevoStyle.pageContentWidth(in: viewport) >= 300,
              viewport.size.height >= 440 else { return false }
        let width = min(680, viewport.size.width)
        let dock = CGRect(x: (viewport.size.width - width) / 2, y: viewport.size.height - 96,
                          width: width, height: 96)
        return !SwevoStyle.intersectsReservedRegion(dock, in: viewport)
    }
}
