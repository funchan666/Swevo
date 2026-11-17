import SwiftUI
import AVFoundation
import ImageIO
import PhotosUI
import UniformTypeIdentifiers

enum VideoTool: String, Identifiable, CaseIterable {
    case audio, speed, frame, studio, ranges
    var id: String { rawValue }
    var title: String {
        switch self {
        case .audio: return "Extract audio"
        case .speed: return "Change speed"
        case .frame: return "Reframe video"
        case .studio: return "Edit video"
        case .ranges: return "Mark a range"
        }
    }
    var detail: String {
        switch self {
        case .audio: return "Save a video’s audio as an M4A file."
        case .speed: return "Slow down or speed up a clip."
        case .frame: return "Crop, rotate or mirror a video."
        case .studio: return "Trim a clip and adjust its framing, speed or audio."
        case .ranges: return "Loop a section or compare its frames."
        }
    }
    var editorTab: String {
        switch self {
        case .audio: return "Audio"
        case .speed: return "Speed"
        case .frame: return "Frame"
        case .studio, .ranges: return "Trim"
        }
    }
    var glyph: SwevoGlyph {
        switch self {
        case .audio: return .sound
        case .speed: return .play
        case .frame: return .feed
        case .studio: return .edit
        case .ranges: return .bookmark
        }
    }
}

struct ToolsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    let openPlus: () -> Void
    @State private var selection: WorkspaceSelection?

    private enum WorkspaceSelection: Identifiable {
        case editor(VideoTool, PracticeRecording?)
        case comparison(RangeFrameRequest)

        var id: String {
            switch self {
            case .editor(let tool, let movie): "\(tool.id)-\(movie?.id.uuidString ?? "choose")"
            case .comparison(let request): "comparison-\(request.id)"
            }
        }
    }

    var body: some View {
        let movie = library.movies.lazy.filter { !$0.isAudio }.max { first, second in
            (first.lastOpenedAt ?? .distantPast, first.date) < (second.lastOpenedAt ?? .distantPast, second.date)
        }
        ScenePage(artwork: movie == nil ? "SceneEdit" : nil, depth: movie == nil ? 168 : 44,
                  openingGap: 0, artworkOpacity: 0.84) { height in
            VStack(alignment: .leading, spacing: 12) {
                PlusEntryButton(action: openPlus)
                if movie == nil {
                    Spacer(minLength: 16)
                    chooseVideo
                }
            }
            .frame(minHeight: height, alignment: .top)
        } content: { container in
            let width = min(640, SwevoStyle.pageContentWidth(in: container))
            let bounds = CGRect(origin: .zero, size: container.size)
            let allowsColumns = typeSize <= .xLarge && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
            let sideBySide = movie != nil && allowsColumns && width >= 620
            let rangeWidth = sideBySide ? (width - 18) / 2 : width
            let stackedPreview = !allowsColumns || rangeWidth < 300
            let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 18))
                                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            VStack(alignment: .leading, spacing: 20) {
                layout {
                    if let movie { currentVideo(movie) }
                    rangePanel(movie: movie, stacked: stackedPreview)
                }
                quickTools(movie: movie, stacked: !allowsColumns || width < 320)
            }
        }
        .sheet(item: $selection) { selection in
            switch selection {
            case .editor(let tool, let movie):
                EditorSheet(initialMovie: movie, initialTool: tool)
            case .comparison(let request):
                RangeFrameComparison(request: request)
            }
        }
    }

    private var chooseVideo: some View {
        Button { selection = .editor(.studio, nil) } label: {
            ActionLabel(title: "Choose a video", symbol: .folder)
        }
        .buttonStyle(PressStyle())
        .accessibilityHint("Choose a video from Photos or Files to start editing.")
        .accessibilityIdentifier("tools.studio")
    }

    private func currentVideo(_ movie: PracticeRecording) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { selection = .editor(.studio, movie) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    VideoFileThumbnail(url: library.url(for: movie), maximumSize: 1080, contentMode: .fit)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 14))
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: movie.displayFilename).font(.capture(.headline))
                                .foregroundStyle(SwevoStyle.paper)
                            LocalizedText(VideoTool.studio.title).font(.capture(.footnote, weight: .semibold))
                                .foregroundStyle(SwevoStyle.accent)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Glyph(symbol: .back, size: 13, tint: SwevoStyle.accent)
                            .rotationEffect(.degrees(180))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Edit video")
            .accessibilityValue(Text(verbatim: movie.displayFilename))
            .accessibilityIdentifier("tools.studio")

            Button { selection = .editor(.studio, nil) } label: {
                commandLabel("Change video", symbol: .folder)
            }
            .buttonStyle(PressStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func rangePanel(movie: PracticeRecording?, stacked: Bool) -> some View {
        if let movie, let mark = movie.rangeMarks?.first(where: { $0.timeRange != nil }) {
            let request = RangeFrameRequest(source: library.url(for: movie), mark: mark)
            savedRange(request, movie: movie, stacked: stacked)
        } else {
            Button { selection = .editor(.ranges, movie) } label: {
                HStack(spacing: 12) {
                    Glyph(symbol: .bookmark, size: 20, tint: SwevoStyle.ink)
                        .frame(width: 38, height: 46)
                        .background(SwevoStyle.accent, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        LocalizedText(VideoTool.ranges.title).font(.capture(.title3, weight: .semibold))
                            .foregroundStyle(SwevoStyle.paper)
                        LocalizedText(VideoTool.ranges.detail).font(.capture(.footnote))
                            .foregroundStyle(SwevoStyle.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Glyph(symbol: .back, size: 13, tint: SwevoStyle.accent).rotationEffect(.degrees(180))
                }
                .padding(12)
                .frame(minHeight: 74)
                .swevoGlass(cornerRadius: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("tools.ranges")
        }
    }

    private func savedRange(_ request: RangeFrameRequest, movie: PracticeRecording, stacked: Bool) -> some View {
        let start = durationLabel(request.mark.start, fractional: true)
        let end = durationLabel(request.mark.end, fractional: true)
        let review = Button { selection = .editor(.ranges, movie) } label: {
            commandLabel("Review saved ranges", symbol: .bookmark, primary: true)
        }.buttonStyle(PressStyle()).accessibilityIdentifier("tools.ranges")
        let compare = Button { selection = .comparison(request) } label: {
            commandLabel("Compare 3 frames", symbol: .feed)
        }.buttonStyle(PressStyle()).accessibilityIdentifier("tools.compareFrames")

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText("Saved ranges").font(.capture(.caption, weight: .semibold))
                    .foregroundStyle(SwevoStyle.accent)
                Text(verbatim: request.title(in: AppLanguage.from(locale)))
                    .font(.capture(.title3, weight: .semibold))
                Text(verbatim: "\(start) – \(end)").font(.capture(.footnote)).monospacedDigit()
                    .foregroundStyle(SwevoStyle.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            RangePreview(request: request, stacked: stacked)
                .id(request.id)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    review.fixedSize(horizontal: true, vertical: false)
                    compare.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    review
                    compare
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .swevoGlass(cornerRadius: 16)
    }

    private func commandLabel(_ title: String, symbol: SwevoGlyph, primary: Bool = false) -> some View {
        HStack(spacing: 7) {
            Glyph(symbol: symbol, size: 15, tint: primary ? SwevoStyle.ink : SwevoStyle.accent)
            LocalizedText(title).font(.capture(.footnote, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(minWidth: 44, minHeight: 44)
        .foregroundStyle(primary ? SwevoStyle.ink : SwevoStyle.accent)
        .background(primary ? SwevoStyle.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private func quickTools(movie: PracticeRecording?, stacked: Bool) -> some View {
        let tools: [VideoTool] = [.frame, .speed, .audio]
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        let rule = Rectangle().fill(SwevoStyle.line)
            .frame(width: stacked ? nil : 1, height: stacked ? 1 : nil)
            .padding(stacked ? .horizontal : .vertical, 8)
            .allowsHitTesting(false).accessibilityHidden(true)
        return VStack(spacing: 0) {
            Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
            layout {
                ForEach(tools) { tool in
                    quickToolButton(tool, movie: movie, stacked: stacked)
                    if tool != .audio { rule }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
        }
    }

    private func quickToolButton(_ tool: VideoTool, movie: PracticeRecording?, stacked: Bool) -> some View {
        let label = stacked ? AnyLayout(HStackLayout(spacing: 12))
                            : AnyLayout(VStackLayout(alignment: .leading, spacing: 9))
        return Button { selection = .editor(tool, movie) } label: {
            label {
                Glyph(symbol: tool.glyph, size: 18, tint: SwevoStyle.accent)
                    .frame(width: 33, height: 33)
                    .background(SwevoStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                LocalizedText(tool.title).font(.capture(stacked ? .subheadline : .footnote, weight: .semibold))
                    .foregroundStyle(SwevoStyle.paper)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if stacked {
                    Spacer(minLength: 4)
                    Glyph(symbol: .back, size: 12, tint: SwevoStyle.secondary).rotationEffect(.degrees(180))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: stacked ? 54 : 78, alignment: stacked ? .leading : .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityHint(Text(LocalizedStringKey(tool.detail)))
        .accessibilityIdentifier("tools.\(tool.rawValue)")
    }
}

private struct RangePreview: View {
    let request: RangeFrameRequest
    let stacked: Bool
    @State private var frames: [RangeStill] = []
    @State private var error: String?

    var body: some View {
        Group {
            if frames.isEmpty {
                LocalizedText(error ?? "Reading video frames…")
                    .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                     : AnyLayout(HStackLayout(alignment: .top, spacing: 6))
                let cell = stacked ? AnyLayout(HStackLayout(spacing: 10))
                                   : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                layout {
                    ForEach(frames) { frame in
                        cell {
                            Image(decorative: frame.image, scale: 1)
                                .resizable().scaledToFit()
                                .frame(maxWidth: stacked ? 80 : .infinity)
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .background(SwevoStyle.ink)
                                .clipShape(.rect(cornerRadius: 6))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                LocalizedText(frame.position.title).font(.capture(.caption, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: durationLabel(frame.time, fractional: true))
                                    .font(.capture(.caption)).monospacedDigit().foregroundStyle(SwevoStyle.secondary)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .task {
            error = nil
            do {
                let result = try await request.readFrames(maximumSize: 360)
                guard !Task.isCancelled else { return }
                frames = result
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

struct EditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialMovie: PracticeRecording? = nil
    var initialTool: VideoTool = .studio
    var initialLoop: VideoRangeMark? = nil
    var onVideoOpened: ((PracticeRecording) -> Void)? = nil
    @StateObject private var departure = ExportDeparture()
    var body: some View {
        EditorWorkspace(initialMovie: initialMovie, initialTool: initialTool, initialLoop: initialLoop, onVideoOpened: onVideoOpened) {
            departure.request { dismiss() }
        }
            .environmentObject(departure)
            .modifier(ExportDepartureProtection(departure: departure))
    }
}
struct EditorWorkspace: View {
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingExportMembership = false
    @EnvironmentObject private var departure: ExportDeparture
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var editingRangeName: Bool
    let initialTool: VideoTool
    let onVideoOpened: ((PracticeRecording) -> Void)?
    let close: () -> Void
    @StateObject private var editor = VideoEditor()
    @State private var selected: PracticeRecording?
    @State private var pendingLoop: VideoRangeMark?
    @State private var activeLoop: VideoRangeMark?
    @State private var reviewStart: Double?
    @State private var reviewEnd: Double?
    @State private var frameComparison: RangeFrameRequest?
    @State private var importing = false
    @State private var error: String?
    @State private var shareURL: SharedFile?
    @State private var savedExport: PracticeRecording?
    @State private var sharingExport = false
    @State private var shareTask: Task<Void, Never>?
    @State private var playbackScrubbing = false
    @State private var resumePreview = false
    @State private var retryID = UUID()
    @State private var openedRequest: VideoOpenRequest?
    @State private var tool = "Trim"
    @State private var showingExportSettings = false
    @State private var exportTask: Task<Void, Never>?
    private let tools = ["Trim", "Frame", "Speed", "Audio"]

    private var audioOnly: Bool { initialTool == .audio }
    private var focusesRanges: Bool { initialTool == .ranges }
    private var rangeStart: Double { focusesRanges ? reviewStart ?? 0 : editor.recipe.start }
    private var rangeEnd: Double { focusesRanges ? reviewEnd ?? editor.duration : editor.recipe.end }
    private var previewRange: ClosedRange<Double> {
        if rangeStart <= rangeEnd { return rangeStart...rangeEnd }
        return 0...editor.duration
    }
    private var editingLocked: Bool {
        departure.running || editor.isExporting || editor.isPreparingPreview || sharingExport
    }
    private var canPlay: Bool {
        scenePhase == .active && !ads.isPresenting && shareURL == nil
            && !showingExportMembership && !showingExportSettings && frameComparison == nil
    }
    private var operationError: String? {
        guard !departure.running else { return nil }
        return error ?? (editor.duration > 0 ? editor.error : nil)
    }

    init(initialMovie: PracticeRecording? = nil, initialTool: VideoTool = .studio, initialLoop: VideoRangeMark? = nil,
         onVideoOpened: ((PracticeRecording) -> Void)? = nil, close: @escaping () -> Void) {
        self.initialTool = initialTool
        self.onVideoOpened = onVideoOpened
        self.close = close
        _selected = State(initialValue: initialMovie)
        _pendingLoop = State(initialValue: initialLoop)
        _reviewStart = State(initialValue: initialLoop?.start)
        _reviewEnd = State(initialValue: initialLoop?.end)
        _tool = State(initialValue: initialTool.editorTab)
    }
    var body: some View {
        ScrollViewReader { scroll in
            workspace(scroll)
                .onChange(of: savedExport?.id) { _, id in
                    if let id { scroll.scrollTo(id, anchor: .bottom) }
                }
                .onChange(of: operationError) { _, message in
                    if message != nil { scroll.scrollTo("editor-feedback", anchor: .bottom) }
                }
        }
    }

    private func workspace(_ scroll: ScrollViewProxy) -> some View {
        let openRequest = VideoOpenRequest(movieID: selected?.id, retryID: retryID)
        return GeometryReader { container in
            let width = SwevoStyle.pageContentWidth(in: container)
            let bounds = CGRect(origin: .zero, size: container.size)
            let besidePreview = width >= 1000 && typeSize <= .xLarge
                && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
            let stacked = width < 340 || typeSize > .xLarge
            let layout = besidePreview ? AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                                       : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            let height = focusesRanges
                ? min(420, max(112, container.size.height * 0.42))
                : min(580, max(120, container.size.height * 0.59))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header(stacked: stacked).pageHorizontalMargins().id("editor-top")
                    if let selected {
                        layout {
                            previewStage(height: height, stacked: stacked, scroll: scroll)
                            if editor.duration > 0 {
                                inspector(for: selected, stackedTrim: stacked || besidePreview, scroll: scroll)
                                    .frame(maxWidth: besidePreview ? 318 : .infinity, alignment: .leading)
                                    .pageHorizontalMargins()
                            }
                        }
                    } else {
                        importContent(in: container).pageHorizontalMargins()
                    }
                }
                .padding(.top, 8).padding(.bottom, 20)
                .frame(maxWidth: selected == nil ? 680 : (besidePreview ? 1140 : 820))
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let selected, editor.duration > 0, !editingRangeName, !focusesRanges {
                    exportDock(for: selected)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
            .swevoScreenBackground()
            .foregroundStyle(SwevoStyle.paper)
            .dismissKeyboardOnOutsideTap($editingRangeName, scope: "editor-range-name")
            .interactiveDismissDisabled(importing || departure.running)
            .sheet(item: $shareURL) { ShareSheet(items: [$0.url]) }
            .fullScreenCover(isPresented: $showingExportMembership) { MembershipView(exportRequired: true) }
            .sheet(isPresented: $showingExportSettings) { exportSettings }
            .sheet(item: $frameComparison) { request in RangeFrameComparison(request: request) }
            .onChange(of: selected?.id) { _, _ in
                activeLoop = nil
                reviewStart = nil
                reviewEnd = nil
                scroll.scrollTo("editor-top", anchor: .top)
            }
            .task(id: openRequest) {
                guard let selected, openedRequest != openRequest else { return }
                playbackScrubbing = false
                await editor.open(library.url(for: selected)) {
                    openedRequest = openRequest
                    library.markOpened(selected)
                    onVideoOpened?(selected)
                    playPendingLoop()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { interruptPreview() }
                else if phase == .active { resumePreviewIfPossible() }
            }
            .onChange(of: ads.isPresenting) { _, presenting in
                if presenting { interruptPreview() } else { resumePreviewIfPossible() }
            }
            .onChange(of: showingExportMembership) { _, presenting in if presenting { editor.preview.pause() } }
            .onDisappear {
                guard !showingExportMembership else { return }
                openedRequest = nil
                editor.close()
                exportTask?.cancel()
                shareTask?.cancel()
            }
    }

    private func header(stacked: Bool) -> some View {
        let fileLayout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                                 : AnyLayout(HStackLayout(spacing: 8))
        return HStack(alignment: .top, spacing: 8) {
            if let selected {
                fileLayout {
                    Text(verbatim: selected.displayFilename)
                        .font(.capture(.headline))
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    changeVideo
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    SceneTitle("Choose a video", size: 32)
                    if let pickerToolTitle {
                        LocalizedText(pickerToolTitle).font(.capture(.subheadline, weight: .medium))
                            .foregroundStyle(SwevoStyle.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            IconButton(symbol: .close, label: "Close", action: close)
                .swevoGlass(cornerRadius: 22).disabled(importing)
        }
    }

    private var pickerToolTitle: String? {
        if audioOnly || focusesRanges { return initialTool.title }
        return tool == VideoTool.studio.editorTab ? nil : tool
    }

    private func importContent(in container: GeometryProxy) -> some View {
        let recentImports = library.importedMovies.filter { !$0.isAudio }
        let width = min(640, SwevoStyle.pageContentWidth(in: container))
        let bounds = CGRect(origin: .zero, size: container.size)
        let allowsColumns = !SwevoStyle.intersectsReservedRegion(bounds, in: container)
        let stackedSources = width < 300 || !allowsColumns || typeSize > .xLarge
        let tiled = width >= 330 && allowsColumns && typeSize <= .large && recentImports.count > 1
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .topLeading), count: tiled ? 2 : 1)

        return VStack(alignment: .leading, spacing: 20) {
            VideoImportActions(onImported: choose, importing: $importing,
                               presentation: .sourcePair(stacked: stackedSources))
            if let error { ErrorNote(message: error).id("editor-feedback") }
            VStack(alignment: .leading, spacing: 12) {
                Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
                SectionLabel(title: "Recent imports")
                    .accessibilityAddTraits(.isHeader)
                if recentImports.isEmpty {
                    if let libraryError = library.error {
                        ErrorNote(message: libraryError)
                    } else {
                        EmptyStateScene(artwork: "SceneEdit", message: "No imported videos yet",
                                        container: container, columnWidth: width, maxArtworkHeight: 132)
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: tiled ? 16 : 4) {
                        ForEach(recentImports) { movie in
                            VideoFileButton(url: library.url(for: movie), filename: movie.displayFilename,
                                            date: movie.date, presentation: .picker(tiled: tiled)) {
                                choose(movie)
                            }
                            .disabled(importing)
                            .accessibilityIdentifier("editor.pick.\(movie.id)")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewStage(height: CGFloat, stacked: Bool, scroll: ScrollViewProxy) -> some View {
        let compareLoop = activeLoop.map { mark in { compareRange(mark) } }
        let marks = library.movies.first { $0.id == selected?.id }?.rangeMarks ?? []
        let hasSavedRanges = marks.contains { ($0.timeRange?.upperBound ?? .infinity) <= editor.duration }
        let rangeTarget = hasSavedRanges ? "editor-saved-ranges" : "editor-ranges"
        return VStack(alignment: .leading, spacing: 8) {
            VideoSurface(player: editor.preview.player, fill: false)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(SwevoStyle.surface.opacity(0.42))
                .overlay {
                    if editor.isLoading || editor.isPreparingPreview {
                        AccountLoadingIndicator(title: editor.isLoading ? "Preparing your video…" : "Preparing preview…")
                            .padding(12)
                            .background(SwevoStyle.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
                            .allowsHitTesting(false)
                    }
                }
            if editor.duration > 0 {
                VideoPlaybackControls(playback: editor.preview, timeline: editor.preview.timeline,
                                      enabled: canPlay && !editingLocked,
                                      canResume: canPlay && !editingLocked,
                                      scrubbing: $playbackScrubbing, retry: editor.retryPlayback,
                                      sourceFrames: editor.isShowingSource ? editor.thumbnails : nil,
                                      sourceDuration: editor.duration,
                                      trim: previewRange,
                                      compareLoop: compareLoop,
                                      rangesTitle: hasSavedRanges ? "Saved ranges" : "Mark a range",
                                      openRanges: audioOnly || (focusesRanges && !hasSavedRanges) ? nil : {
                        scroll.scrollTo(rangeTarget, anchor: .top)
                    })
                    .pageHorizontalMargins()
                if focusesRanges {
                    ReviewRangeMarkers(playback: editor.preview, duration: editor.duration,
                                       start: $reviewStart, end: $reviewEnd, stacked: stacked,
                                       restoreOriginal: editor.isShowingSource ? nil : {
                        editor.preview.pause()
                        editor.restoreSourcePreview(seekTo: rangeStart)
                    })
                    .disabled(!canPlay || editingLocked || playbackScrubbing)
                    .pageHorizontalMargins()
                }
            } else if !editor.isLoading, let error = editor.error {
                VStack(alignment: .leading, spacing: 6) {
                    ErrorNote(message: error)
                    EditorCommand(title: "Retry") { retryID = UUID() }
                }
                .pageHorizontalMargins()
            }
        }
        .id("editor-preview")
    }

    private func inspector(for movie: PracticeRecording, stackedTrim: Bool, scroll: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if focusesRanges { ranges(for: movie, scroll: scroll) }
            VStack(alignment: .leading, spacing: 12) {
                if !audioOnly { toolPicker }
                controls(stackedTrim: stackedTrim).id("editor-adjustments")
                if !audioOnly {
                    EditorCommand(title: "Preview changes", symbol: .play) {
                        editingRangeName = false
                        scroll.scrollTo("editor-preview", anchor: .top)
                        Task { await editor.applyPreview() }
                    }.swevoGlass()
                }
            }.disabled(editingLocked)
            if let operationError {
                ErrorNote(message: operationError).id("editor-feedback")
            }
            if let savedExport {
                SavedVideoExport(movie: savedExport, sharing: sharingExport, disabled: departure.running) {
                    shareExport(savedExport)
                }.id(savedExport.id)
            }
            if focusesRanges {
                exportControls(for: movie)
            } else if !audioOnly {
                ranges(for: movie, scroll: scroll)
            }
        }
    }

    private func ranges(for movie: PracticeRecording, scroll: ScrollViewProxy) -> some View {
        VideoRangePanel(playback: editor.preview, movieID: movie.id, duration: editor.duration,
                        start: rangeStart, end: rangeEnd, saveAndLoop: focusesRanges, activeLoopID: activeLoop?.id,
                        editingName: $editingRangeName, compareRange: compareRange,
                        playRange: { mark in
            guard let range = mark.timeRange else { return }
            activeLoop = mark
            editor.playRange(range)
            scroll.scrollTo("editor-preview", anchor: .top)
        }, trimToRange: { range in
            editor.preview.pause()
            var recipe = editor.recipe
            recipe.start = range.lowerBound
            recipe.end = range.upperBound
            editor.recipe = recipe
            editor.restoreSourcePreview(seekTo: range.lowerBound)
            tool = "Trim"
            scroll.scrollTo("editor-adjustments", anchor: .top)
        })
        .id(movie.id)
        .disabled(!canPlay || editingLocked)
        .id("editor-ranges")
    }

    private func compareRange(_ mark: VideoRangeMark) {
        guard let selected, canPlay, !editingLocked else { return }
        editingRangeName = false
        editor.preview.pause()
        frameComparison = RangeFrameRequest(source: library.url(for: selected), mark: mark)
    }

    private func interruptPreview() {
        resumePreview = resumePreview || editor.preview.intendsPlayback
        editor.preview.pause()
    }

    private func resumePreviewIfPossible() {
        playPendingLoop()
        guard resumePreview, scenePhase == .active, !ads.isPresenting else { return }
        resumePreview = false
        guard selected != nil, canPlay, !departure.running else { return }
        editor.preview.play()
    }

    private func playPendingLoop() {
        guard let mark = pendingLoop, editor.duration > 0, canPlay, !editingLocked else { return }
        pendingLoop = nil
        guard let range = mark.timeRange, range.upperBound <= editor.duration else {
            error = "This range no longer fits the video."
            return
        }
        activeLoop = mark
        editor.playRange(range)
    }

    @ViewBuilder private var changeVideo: some View {
        if !editingLocked {
            EditorCommand(title: "Change video", symbol: .folder) {
                editingRangeName = false
                selected = nil
                pendingLoop = nil
                error = nil
                savedExport = nil
                editor.close()
            }
        }
    }

    private var toolPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) { toolTabs(stacked: false) }
            VStack(alignment: .leading, spacing: 2) { toolTabs(stacked: true) }
        }
        .padding(4)
        .swevoGlass(cornerRadius: 14)
    }

    private func toolTabs(stacked: Bool) -> some View {
        ForEach(tools, id: \.self) { value in
            let selected = tool == value
            Button {
                editingRangeName = false
                tool = value
            } label: {
                LocalizedText(value)
                    .font(.capture(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: !stacked, vertical: true)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: stacked ? .leading : .center)
                    .foregroundStyle(selected ? SwevoStyle.accent : SwevoStyle.paper)
                    .overlay(alignment: stacked ? .leading : .bottom) {
                        if selected {
                            Capsule().fill(SwevoStyle.accent)
                                .frame(width: stacked ? 2 : 24, height: stacked ? 18 : 2)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    private func controls(stackedTrim: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch tool {
            case "Frame":
                toolHeading("Framing")
                FlowChoices(values: VideoFrame.allCases.map(\.rawValue), selected: editor.recipe.frame.rawValue) { value in editor.recipe.frame = VideoFrame(rawValue: value) ?? .original }
                framingActions
                toolNote("Kstep crops from the center. Tap Preview changes to check the framing.")
            case "Speed":
                toolHeading("Video speed")
                FlowChoices(values: ["0.5×", "0.75×", "1×", "1.5×", "2×"], selected: String(format: "%g×", editor.recipe.speed)) { value in editor.recipe.speed = Double(value.replacingOccurrences(of: "×", with: "")) ?? 1 }
                finalDuration
            case "Audio":
                if audioOnly {
                    toolHeading("Audio track")
                    toolNote("Export this video’s audio as an M4A file. The video must contain an audio track.")
                } else {
                    toolHeading("Video sound")
                    EditorCommand(title: editor.recipe.muted ? "Audio: Muted" : "Audio: Original",
                                  symbol: editor.recipe.muted ? .mute : .sound) { editor.recipe.muted.toggle() }
                    EditorCommand(title: "Extract audio as M4A", symbol: .download) {
                        editingRangeName = false
                        export(audio: true, title: selected?.title ?? "Audio")
                    }
                    toolNote("Audio extraction uses your trim and speed settings.")
                }
            default:
                trimControls(stacked: stackedTrim)
                finalDuration
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func trimControls(stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                             : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            trimPoint("Start", label: "Trim start", value: Binding(get: { editor.recipe.start }, set: {
                editor.recipe.start = max(0, min($0, editor.recipe.end - 0.1))
                editor.restoreSourcePreview(seekTo: editor.recipe.start)
            }))
            trimPoint("End", label: "Trim end", value: Binding(get: { editor.recipe.end }, set: {
                editor.recipe.end = min(editor.duration, max($0, editor.recipe.start + 0.1))
                editor.restoreSourcePreview(seekTo: editor.recipe.end)
            }))
        }
    }

    private func trimPoint(_ title: String, label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LocalizedText(title).font(.capture(.footnote, weight: .semibold))
                .foregroundStyle(SwevoStyle.secondary)
            Text(verbatim: durationLabel(value.wrappedValue, fractional: true))
                .font(.capture(.title3, weight: .semibold)).monospacedDigit()
                .environment(\.layoutDirection, .leftToRight)
            SwevoScrubber(value: value, range: 0...max(0.1, editor.duration), label: label, showsPlayhead: true)
                .background(alignment: .center) { Capsule().fill(SwevoStyle.line).frame(height: 4) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var framingActions: some View {
        let rotate = EditorCommand(title: "Rotate 90° · \((editor.recipe.quarterTurns % 4) * 90)°") {
            editor.recipe.quarterTurns = (editor.recipe.quarterTurns + 1) % 4
        }
        let mirror = EditorCommand(title: editor.recipe.mirrored ? "Mirror: On" : "Mirror: Off") {
            editor.recipe.mirrored.toggle()
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                rotate.fixedSize()
                mirror.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                rotate
                mirror
            }
        }
    }

    private var finalDuration: some View {
        LocalizedText("Final duration · \(durationLabel((editor.recipe.end - editor.recipe.start) / editor.recipe.speed))")
            .font(.capture(.footnote, weight: .semibold))
            .foregroundStyle(SwevoStyle.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toolHeading(_ title: String) -> some View {
        LocalizedText(title).font(.capture(.headline))
            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }

    private func toolNote(_ message: String) -> some View {
        LocalizedText(message).font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func exportDock(for movie: PracticeRecording) -> some View {
        exportControls(for: movie)
            .padding(6)
            .frame(maxWidth: 640)
            .swevoGlass(cornerRadius: 16)
            .pageHorizontalMargins()
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .swevoScreenBackground()
    }

    private func exportControls(for movie: PracticeRecording) -> some View {
        let command = EditorCommand(title: audioOnly ? "Export audio as M4A" : "Export video",
                                    symbol: .download, emphasized: true, expanded: true) {
            export(audio: audioOnly, title: movie.title)
        }
        let settings = EditorCommand(title: editor.recipe.quality.rawValue, symbol: .settings) {
            editor.preview.pause()
            showingExportSettings = true
        }
        .accessibilityLabel("Export settings")
        .accessibilityValue(Text(verbatim: editor.recipe.quality.rawValue))
        .accessibilityIdentifier("editor.exportSettings")

        return Group {
            if departure.running {
                exportProgress
            } else {
                Group {
                    if audioOnly {
                        command
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                settings.fixedSize()
                                command.fixedSize(horizontal: false, vertical: true)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                command
                                settings
                            }
                        }
                    }
                }.disabled(editingLocked)
            }
        }
    }

    private var exportProgress: some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    exportStatus.fixedSize()
                    Spacer(minLength: 0)
                    EditorCommand(title: "Cancel export") { departure.request() }.fixedSize()
                }
                VStack(alignment: .leading, spacing: 0) {
                    exportStatus
                    EditorCommand(title: "Cancel export") { departure.request() }
                }
            }
            GeometryReader { geometry in
                Capsule().fill(SwevoStyle.line)
                    .overlay(alignment: .leading) {
                        Capsule().fill(SwevoStyle.accent)
                            .frame(width: geometry.size.width * CGFloat(min(1, max(0, editor.progress))))
                    }
            }
            .frame(height: 4).padding(.horizontal, 8).padding(.bottom, 5)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
        }
    }

    private var exportStatus: some View {
        LocalizedText(editor.isExporting ? "Exporting · \(Int(editor.progress * 100))%" : "Preparing export…")
            .font(.capture(.subheadline)).monospacedDigit()
            .padding(.horizontal, 8)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var exportSettings: some View {
        ScenePage { _ in
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 8) {
                    SceneTitle("Export settings", size: 28)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    IconButton(symbol: .close, label: "Close") { showingExportSettings = false }
                        .swevoGlass(cornerRadius: 22)
                }
                FlowChoices(values: ExportQuality.allCases.map(\.rawValue), selected: editor.recipe.quality.rawValue) { value in
                    editor.recipe.quality = ExportQuality(rawValue: value) ?? .full
                }
                toolNote("MP4 · Up to the selected resolution · 30 fps\nSmaller resolutions reduce export size. Source videos are never upscaled.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func choose(_ movie: PracticeRecording) {
        openedRequest = nil
        selected = movie
        error = nil
        savedExport = nil
    }

    private func shareExport(_ movie: PracticeRecording) {
        guard !sharingExport, !departure.running else { return }
        guard commerce.canExportMedia else { showingExportMembership = true; return }
        editor.preview.pause()
        error = nil
        sharingExport = true
        shareTask = Task {
            defer { sharingExport = false; shareTask = nil }
            do {
                let url = try await library.shareFile(for: movie, commerce: commerce)
                if !Task.isCancelled { shareURL = SharedFile(url: url) }
            }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func export(audio: Bool, title: String) {
        guard exportTask == nil, !sharingExport else { return }
        guard commerce.canExportMedia else { showingExportMembership = true; return }
        error = nil
        exportTask = Task {
            defer { exportTask = nil; departure.finish() }
            guard let output = await editor.export(audioOnly: audio) else { return }
            if Task.isCancelled { try? FileManager.default.removeItem(at: output); return }
            do {
                defer { try? FileManager.default.removeItem(at: output) }
                try commerce.requireMediaExport()
                let saved = try await library.importMovie(output, exported: true, title: title + (audio ? " · Audio" : " · Edit"))
                if !Task.isCancelled { savedExport = saved }
            } catch is CancellationError { }
            catch { self.error = "The export finished but could not be added to your library. \(error.localizedDescription)" }
        }
        departure.begin { exportTask?.cancel(); editor.cancelExport() }
    }
}

private struct EditorCommand: View {
    let title: String
    var symbol: SwevoGlyph? = nil
    var emphasized = false
    var expanded = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if expanded {
                ActionLabel(title: title, symbol: symbol, primary: emphasized)
            } else {
                HStack(spacing: 7) {
                    if let symbol { Glyph(symbol: symbol, size: 16, tint: emphasized ? SwevoStyle.ink : SwevoStyle.accent) }
                    LocalizedText(title).font(.capture(.footnote, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(emphasized ? SwevoStyle.ink : SwevoStyle.accent)
                .background(emphasized ? SwevoStyle.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
        }.buttonStyle(PressStyle())
    }
}

struct SavedVideoExport: View {
    let movie: PracticeRecording
    let sharing: Bool
    var disabled = false
    let share: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("Saved in Exports").font(.capture(.subheadline, weight: .semibold))
                .foregroundStyle(SwevoStyle.accent)
            Text(verbatim: movie.displayFilename)
                .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ActionButton(title: "Share or save to Files", primary: false, busy: sharing, action: share)
                .disabled(disabled)
        }
    }
}

private struct VideoOpenRequest: Equatable {
    let movieID: UUID?
    let retryID: UUID
}

private struct ReviewRangeMarkers: View {
    @ObservedObject var playback: PlaybackController
    let duration: Double
    @Binding var start: Double?
    @Binding var end: Double?
    let stacked: Bool
    let restoreOriginal: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("Mark a range").font(.capture(.headline))
                .accessibilityAddTraits(.isHeader)
            if let restoreOriginal {
                EditorCommand(title: "Show original", symbol: .play, action: restoreOriginal)
                    .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            } else {
                LocalizedText("Scrub to a frame, then set the start or end.")
                    .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                let layout = stacked ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    marker("Set start", time: start ?? 0, binding: $start)
                        .accessibilityIdentifier("video.range.setStart")
                    marker("Set end", time: end ?? duration, binding: $end)
                        .accessibilityIdentifier("video.range.setEnd")
                }
                .disabled(playback.isLoading || playback.error != nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marker(_ title: String, time: Double, binding: Binding<Double?>) -> some View {
        Button {
            let time = playback.player.currentTime().seconds
            guard time.isFinite else { return }
            playback.pause()
            binding.wrappedValue = min(duration, max(0, time))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                LocalizedText(title).font(.capture(.footnote, weight: .semibold))
                    .foregroundStyle(SwevoStyle.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: durationLabel(time, fractional: true)).monospacedDigit()
                    .font(.capture(.subheadline, weight: .semibold))
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct VideoRangePanel: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.locale) private var locale
    @ObservedObject var playback: PlaybackController
    let movieID: UUID
    let duration: Double
    let start: Double
    let end: Double
    let saveAndLoop: Bool
    let activeLoopID: UUID?
    let editingName: FocusState<Bool>.Binding
    let compareRange: (VideoRangeMark) -> Void
    let playRange: (VideoRangeMark) -> Void
    let trimToRange: (ClosedRange<Double>) -> Void
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        let movie = library.movies.first { $0.id == movieID }
        let marks = (movie?.rangeMarks ?? []).filter { ($0.timeRange?.upperBound ?? .infinity) <= duration }
        return VStack(alignment: .leading, spacing: 12) {
            if marks.isEmpty && !saveAndLoop {
                LocalizedText("Mark a range to loop it and compare frames.")
                    .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            makeRange
            if let error { ErrorNote(message: error) }
            if let movie, !marks.isEmpty {
                LocalizedText("Saved ranges").font(.capture(.headline))
                    .accessibilityAddTraits(.isHeader)
                    .id("editor-saved-ranges")
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(marks) { mark in
                        if let range = mark.timeRange {
                            rangeRow(mark, range: range, url: library.url(for: movie))
                        }
                    }
                }
            }
        }
    }

    private var makeRange: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !saveAndLoop {
                LocalizedText("Trim").font(.capture(.caption, weight: .semibold))
                    .foregroundStyle(SwevoStyle.secondary)
                timeRange(start: start, end: end)
                    .font(.capture(.subheadline, weight: .semibold)).foregroundStyle(SwevoStyle.paper)
            }
            TextField("Range name (optional)", text: $name,
                      prompt: Text("Range name (optional)").foregroundStyle(SwevoStyle.secondary))
                .font(.capture(.subheadline)).swevoField()
                .focused(editingName).submitLabel(.done)
                .onSubmit { saveRange() }
                .keyboardInputRegion("editor-range-name")
                .accessibilityIdentifier("video.range.name")
            EditorCommand(title: saveAndLoop ? "Save and loop" : "Save range",
                          symbol: saveAndLoop ? .play : .bookmark, emphasized: true, expanded: saveAndLoop,
                          action: saveRange)
                .accessibilityIdentifier("video.range.save")
        }
        .padding(12).swevoGlass(cornerRadius: 14)
    }

    private func rangeRow(_ mark: VideoRangeMark, range: ClosedRange<Double>, url: URL) -> some View {
        let isLooping = activeLoopID == mark.id && playback.repeatedRange == range
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VideoFileThumbnail(url: url, timestamp: mark.start)
                    .frame(width: 76, height: 50).clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: mark.name.nilIfBlank ?? L10n.text("Unnamed range", language: AppLanguage.from(locale)))
                        .font(.capture(.subheadline, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    timeRange(start: mark.start, end: mark.end)
                        .font(.capture(.footnote, weight: .semibold))
                        .foregroundStyle(isLooping ? SwevoStyle.accent : SwevoStyle.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                IconButton(symbol: .close, label: "Remove range") {
                    error = nil
                    do {
                        try library.removeRange(mark, from: movieID)
                        if isLooping {
                            playback.pause()
                            playback.stopRepeating()
                        }
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { rangeActions(mark, range: range, isLooping: isLooping) }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) { rangeActions(mark, range: range, isLooping: isLooping) }
            }
        }
        .padding(10)
        .background(SwevoStyle.accent.opacity(isLooping ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(isLooping ? SwevoStyle.accent : SwevoStyle.line)
                .frame(height: 1).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    @ViewBuilder private func rangeActions(_ mark: VideoRangeMark, range: ClosedRange<Double>, isLooping: Bool) -> some View {
        EditorCommand(title: isLooping ? "Stop loop" : "Loop range", symbol: isLooping ? .pause : .play, emphasized: true) {
            editingName.wrappedValue = false
            if isLooping {
                playback.pause()
                playback.stopRepeating()
            } else {
                playRange(mark)
            }
        }
        EditorCommand(title: "Compare 3 frames", symbol: .feed) {
            compareRange(mark)
        }.accessibilityIdentifier("video.range.compareFrames")
        EditorCommand(title: "Use for trim", symbol: .edit) {
            editingName.wrappedValue = false
            trimToRange(range)
        }
    }

    private func timeRange(start: Double, end: Double) -> some View {
        Text(verbatim: "\(durationLabel(start, fractional: true)) – \(durationLabel(end, fractional: true))")
            .monospacedDigit().environment(\.layoutDirection, .leftToRight)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func saveRange() {
        guard start.isFinite, end.isFinite, start >= 0, end - start >= 1.0 / 600, end <= duration else {
            error = "Choose a start and end for the range."
            return
        }
        editingName.wrappedValue = false
        do {
            let mark = try library.addRange(start...end, name: name, to: movieID)
            name = ""
            error = nil
            if saveAndLoop { playRange(mark) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RangeFrameRequest: Identifiable {
    let source: URL
    let mark: VideoRangeMark
    var id: UUID { mark.id }

    func title(in language: AppLanguage) -> String {
        mark.name.nilIfBlank ?? L10n.text("Unnamed range", language: language)
    }

    @MainActor
    func readFrames(maximumSize: CGFloat = 1440) async throws -> [RangeStill] {
        guard source.isFileURL, FileManager.default.isReadableFile(atPath: source.path) else {
            throw SwevoError.service("This file can’t be read. Choose the video again from Files.")
        }
        guard let range = mark.timeRange else { throw SwevoError.service("Choose a start and end for the range.") }
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumSize, height: maximumSize)
        let tolerance = CMTime(value: 1, timescale: 8)
        generator.requestedTimeToleranceBefore = tolerance
        let length = range.upperBound - range.lowerBound
        // At the end of the asset, sample just before the last boundary.
        let samples: [(RangeStill.Position, Double)] = [
            (.start, range.lowerBound),
            (.middle, range.lowerBound + length / 2),
            (.end, range.upperBound - min(length / 8, 1.0 / 60))
        ]
        do {
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, range.upperBound <= duration else {
                throw SwevoError.service("This range no longer fits the video.")
            }
            var frames: [RangeStill] = []
            for (position, time) in samples {
                try Task.checkCancellation()
                generator.requestedTimeToleranceAfter = position == .end ? .zero : tolerance
                let result = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 60_000))
                let actual = result.actualTime.seconds
                frames.append(RangeStill(position: position, image: result.image, time: actual.isFinite ? actual : time))
            }
            try Task.checkCancellation()
            return frames
        } catch let error as SwevoError {
            throw error
        } catch {
            try Task.checkCancellation()
            throw SwevoError.service("Couldn’t read these frames. Try again.")
        }
    }
}

struct RangeStill: Identifiable, Sendable {
    enum Position: String, Sendable {
        case start, middle, end

        var title: String {
            switch self {
            case .start: "Start"
            case .middle: "Middle"
            case .end: "End"
            }
        }
    }

    let position: Position
    let image: CGImage
    let time: Double
    var id: Position { position }
}

private struct SharedRangeStills: Identifiable, Sendable {
    let folder: URL
    let files: [URL]
    var id: URL { folder }
}

@MainActor
private struct RangeFrameComparison: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    let request: RangeFrameRequest
    @State private var frames: [RangeStill] = []
    @State private var selectedPosition: RangeStill.Position = .start
    @State private var loadAttempt = UUID()
    @State private var loadError: String?
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Compare 3 frames") { dismiss() }.disabled(exporting)
            ScenePage { container in
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: request.title(in: AppLanguage.from(locale)))
                        .font(.capture(.title3, display: true))
                        .fixedSize(horizontal: false, vertical: true)
                    if let selected = frames.first(where: { $0.position == selectedPosition }) {
                        frameStrip(in: container)
                        RangeShareActions(context: .comparison(request, frames), busy: $exporting)
                        preview(selected, in: container)
                    } else if let loadError {
                        ErrorNote(message: loadError)
                        ActionButton(title: "Retry", primary: false) { loadAttempt = UUID() }
                    } else {
                        AccountLoadingIndicator(title: "Reading video frames…")
                    }
                }
            }
        }.swevoScreenBackground().foregroundStyle(SwevoStyle.paper)
            .interactiveDismissDisabled(exporting)
            .task(id: loadAttempt) { await loadFrames() }
    }

    private func preview(_ frame: RangeStill, in container: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(decorative: frame.image, scale: 1).resizable().scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: min(350, max(130, container.size.height * 0.4)))
                .background(SwevoStyle.ink)
            frameCaption(frame)
        }
    }

    private func frameStrip(in container: GeometryProxy) -> some View {
        let bounds = CGRect(origin: .zero, size: container.size)
        let wide = typeSize <= .xLarge && SwevoStyle.pageContentWidth(in: container) >= 300
            && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        return layout {
            ForEach(frames) { frame in
                let selected = frame.position == selectedPosition
                Button { selectedPosition = frame.position } label: {
                    let cell = wide ? AnyLayout(VStackLayout(alignment: .leading, spacing: 7))
                                    : AnyLayout(HStackLayout(spacing: 12))
                    cell {
                        Image(decorative: frame.image, scale: 1).resizable().scaledToFit()
                            .frame(width: wide ? nil : 70, height: 54)
                            .frame(maxWidth: wide ? .infinity : nil)
                            .background(SwevoStyle.ink)
                            .accessibilityHidden(true)
                        frameCaption(frame)
                    }.padding(7).frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected ? SwevoStyle.accent.opacity(0.12) : SwevoStyle.surface,
                                    in: RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? SwevoStyle.accent : SwevoStyle.line)
                                .allowsHitTesting(false)
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(PressStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func frameCaption(_ frame: RangeStill) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LocalizedText(frame.position.title).font(.capture(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: durationLabel(frame.time, fractional: true)).font(.capture(.caption))
                .monospacedDigit().foregroundStyle(SwevoStyle.secondary)
                .environment(\.layoutDirection, .leftToRight)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadFrames() async {
        loadError = nil
        do {
            frames = try await request.readFrames()
        } catch {
            if !Task.isCancelled { loadError = error.localizedDescription }
        }
    }
}

@MainActor
struct RangeShareActions: View {
    enum Context {
        case comparison(RangeFrameRequest, [RangeStill])
        case practice(source: URL, marks: [VideoRangeMark], stacked: Bool, loop: (VideoRangeMark) -> Void)
    }

    private enum Format { case comparison, stills }

    @EnvironmentObject private var commerce: CommerceStore
    @Environment(\.locale) private var locale
    let context: Context
    @Binding var busy: Bool
    @State private var exportTask: Task<Void, Never>?
    @State private var exportError: String?
    @State private var selectedRangeID: UUID?
    @State private var showingPlus = false
    @State private var sharedStills: SharedRangeStills?
    @State private var practiceComparison: RangeFrameRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch context {
            case .comparison(let request, let frames):
                comparisonActions(request, frames: frames).disabled(busy)
                exportNote
                if busy { AccountLoadingIndicator(title: "Preparing export…") }
                if let exportError { ErrorNote(message: exportError) }
            case .practice(let source, let marks, let stacked, let loop):
                SectionLabel(title: "Saved ranges").accessibilityAddTraits(.isHeader)
                exportNote
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(marks) { mark in
                        practiceRow(RangeFrameRequest(source: source, mark: mark),
                                    showPreview: marks.first?.id == mark.id, stacked: stacked) {
                            loop(mark)
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingPlus) { MembershipView(exportRequired: true) }
        .sheet(item: $practiceComparison) { request in RangeFrameComparison(request: request) }
        .sheet(item: $sharedStills) { ShareSheet(items: $0.files) }
        .onDisappear { exportTask?.cancel() }
    }

    @ViewBuilder private var exportNote: some View {
        if !commerce.hasVerifiedPlus {
            LocalizedText("Export is included with Plus.").font(.capture(.footnote))
                .foregroundStyle(SwevoStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func comparisonActions(_ request: RangeFrameRequest, frames: [RangeStill]) -> some View {
        let collage = EditorCommand(title: "Share three-frame collage", symbol: .download,
                                    emphasized: true, expanded: true) {
            export(request, frames: frames, format: .comparison)
        }.accessibilityIdentifier("video.range.shareComparison")
        let stills = EditorCommand(title: "Export JPEG stills", symbol: .feed) {
            export(request, frames: frames, format: .stills)
        }.accessibilityIdentifier("video.range.exportStills")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                collage.fixedSize(horizontal: true, vertical: false)
                stills.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 4) {
                collage
                stills
            }
        }
    }

    private func practiceRow(_ request: RangeFrameRequest, showPreview: Bool, stacked: Bool,
                             loop: @escaping () -> Void) -> some View {
        let start = durationLabel(request.mark.start, fractional: true)
        let end = durationLabel(request.mark.end, fractional: true)
        let exportingThisRange = selectedRangeID == request.id
        let replay = EditorCommand(title: "Loop range", symbol: .play, emphasized: true, action: loop)
            .accessibilityIdentifier("practice.review.loop.\(request.id.uuidString)")
        let compare = EditorCommand(title: "Compare 3 frames", symbol: .feed) { practiceComparison = request }
            .accessibilityIdentifier("practice.review.compare.\(request.id.uuidString)")
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: request.title(in: AppLanguage.from(locale)))
                    .font(.capture(.headline)).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(start) – \(end)")
                    .font(.capture(.footnote)).monospacedDigit().foregroundStyle(SwevoStyle.secondary)
                    .environment(\.layoutDirection, .leftToRight)
                    .fixedSize(horizontal: false, vertical: true)
            }.accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        replay.fixedSize(horizontal: true, vertical: false)
                        compare.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        replay
                        compare
                    }
                }
                EditorCommand(title: "Share three-frame collage", symbol: .download) {
                    export(request, format: .comparison)
                }
                .accessibilityIdentifier("practice.review.shareComparison.\(request.id.uuidString)")
            }.disabled(busy)

            if exportingThisRange {
                if busy { AccountLoadingIndicator(title: "Preparing export…") }
                if let exportError { ErrorNote(message: exportError) }
            }
            if showPreview { RangePreview(request: request, stacked: stacked).id(request.id) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .swevoGlass(cornerRadius: 15)
    }

    private func export(_ request: RangeFrameRequest, frames: [RangeStill]? = nil, format: Format) {
        guard !busy, exportTask == nil else { return }
        exportError = nil
        guard commerce.canExportMedia else { showingPlus = true; return }
        busy = true
        selectedRangeID = request.id
        let owner = commerce.api.session?.userId.value
        let language = AppLanguage.from(locale)
        exportTask = Task {
            defer { exportTask = nil; busy = false }
            var staged: SharedRangeStills?
            do {
                try commerce.requireMediaExport()
                let stills: [RangeStill]
                if let frames { stills = frames }
                else { stills = try await request.readFrames() }
                try Task.checkCancellation()
                try commerce.requireMediaExport()
                guard owner == commerce.api.session?.userId.value else { throw SwevoError.unauthorized }
                let images = try imagesToShare(stills, request: request, language: language, format: format)
                let writer = Task.detached(priority: .userInitiated) { try Self.stageJPEGs(images) }
                let result = try await withTaskCancellationHandler {
                    try await writer.value
                } onCancel: { writer.cancel() }
                staged = result
                try Task.checkCancellation()
                try commerce.requireMediaExport()
                guard owner == commerce.api.session?.userId.value else { throw SwevoError.unauthorized }
                sharedStills = result
            } catch {
                if let staged { try? FileManager.default.removeItem(at: staged.folder) }
                if !Task.isCancelled { exportError = error.localizedDescription }
            }
        }
    }

    private func imagesToShare(_ frames: [RangeStill], request: RangeFrameRequest, language: AppLanguage,
                               format: Format) throws -> [(name: String, image: CGImage)] {
        switch format {
        case .stills:
            return frames.enumerated().map { index, frame in
                ("\(index + 1)-\(frame.position.rawValue).jpg", frame.image)
            }
        case .comparison:
            let comparison = RangeComparisonImage(title: request.title(in: language), frames: frames, language: language)
            let renderer = ImageRenderer(content: comparison)
            renderer.scale = 2
            renderer.isOpaque = true
            guard let image = renderer.cgImage else { throw SwevoError.service("Couldn’t create the comparison image. Try again.") }
            return [("Kstep-range-\(request.id.uuidString.prefix(8)).jpg", image)]
        }
    }

    nonisolated private static func stageJPEGs(_ images: [(name: String, image: CGImage)]) throws -> SharedRangeStills {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("SwevoRangeStills", isDirectory: true)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let expiry = Date().addingTimeInterval(-7 * 86_400)
        for old in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            if let created = try? old.resourceValues(forKeys: [.creationDateKey]).creationDate, created < expiry {
                try? fm.removeItem(at: old)
            }
        }
        do {
            let options = [kCGImageDestinationLossyCompressionQuality as String: 0.92] as CFDictionary
            var files: [URL] = []
            for image in images {
                try Task.checkCancellation()
                let file = folder.appendingPathComponent(image.name)
                guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                    throw SwevoError.service("Couldn’t export the JPEGs. Try again.")
                }
                CGImageDestinationAddImage(destination, image.image, options)
                guard CGImageDestinationFinalize(destination) else {
                    throw SwevoError.service("Couldn’t export the JPEGs. Try again.")
                }
                files.append(file)
            }
            try Task.checkCancellation()
            return SharedRangeStills(folder: folder, files: files)
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }
}

private struct RangeComparisonImage: View {
    let title: String
    let frames: [RangeStill]
    let language: AppLanguage
    private let imageWidth: CGFloat = 256

    var body: some View {
        let height = frames.first.map { imageWidth * CGFloat($0.image.height) / CGFloat($0.image.width) } ?? 144
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: title).font(.system(size: 28, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .top, spacing: 12) {
                ForEach(frames) { frame in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(decorative: frame.image, scale: 1).resizable().scaledToFit()
                            .frame(width: imageWidth, height: min(440, max(132, height)))
                            .background(SwevoStyle.ink)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(verbatim: L10n.text(frame.position.title, language: language))
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(SwevoStyle.accent)
                            Spacer(minLength: 0)
                            Text(verbatim: durationLabel(frame.time, fractional: true))
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .environment(\.layoutDirection, .leftToRight)
                        }.environment(\.layoutDirection, language.direction)
                    }.frame(width: imageWidth)
                }
            }.environment(\.layoutDirection, .leftToRight)
        }.padding(24).frame(width: imageWidth * 3 + 72)
            .foregroundStyle(SwevoStyle.paper).background(SwevoStyle.background)
            .environment(\.layoutDirection, language.direction)
    }
}

private struct VideoPlaybackControls: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var timeline: PlaybackTimeline
    let enabled: Bool
    let canResume: Bool
    @Binding var scrubbing: Bool
    let retry: () -> Void
    let sourceFrames: [UIImage?]?
    let sourceDuration: Double
    let trim: ClosedRange<Double>
    let compareLoop: (() -> Void)?
    let rangesTitle: String
    let openRanges: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    playbackStatus.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    reviewCommands.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 0) {
                    playbackStatus
                    reviewCommands
                }
            }
            PlayerProgressControl(playback: playback, timeline: timeline, enabled: enabled,
                                  canResume: canResume, scrubbing: $scrubbing,
                                  tint: SwevoStyle.accent, showsPlayhead: sourceFrames != nil)
                .background {
                    if let sourceFrames {
                        EditorFilmstrip(frames: sourceFrames, duration: sourceDuration,
                                        trim: trim, looping: playback.repeatedRange)
                    }
                }
            if let error = playback.error {
                ErrorNote(message: "Preview could not play. \(error)")
                EditorCommand(title: "Retry", action: retry).disabled(!enabled)
            }
        }
        .padding(9)
        .swevoGlass(cornerRadius: 16)
    }

    private var playbackStatus: some View {
        let playing = playback.intendsPlayback
        let mode = playback.repeatedRange != nil ? "Looping" : sourceFrames == nil ? "Edited preview" : "Original"
        let duration = timeline.duration > 0 || sourceFrames == nil ? timeline.duration : sourceDuration
        let elapsed = durationLabel(timeline.elapsed, fractional: true)
        let total = Text(verbatim: durationLabel(duration, fractional: true))
            .foregroundStyle(SwevoStyle.secondary)
        return HStack(spacing: 9) {
            IconButton(symbol: playing ? .pause : .play, label: playing ? "Pause preview" : "Play preview") {
                playback.toggle()
            }
            .background(SwevoStyle.raised, in: RoundedRectangle(cornerRadius: 10))
            .disabled(!enabled || playback.error != nil)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(elapsed) / \(total)")
                    .font(.capture(.subheadline, weight: .semibold)).monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
                LocalizedText(mode).font(.capture(.caption))
                    .foregroundStyle(playback.repeatedRange != nil ? SwevoStyle.accent : SwevoStyle.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            if playback.isLoading && playing {
                ProgressView().tint(SwevoStyle.accent).accessibilityLabel("Loading…")
            }
        }
    }

    @ViewBuilder private var reviewCommands: some View {
        if playback.repeatedRange != nil {
            EditorCommand(title: "Stop loop", symbol: .pause) {
                playback.pause()
                playback.stopRepeating()
            }.disabled(!enabled)
        }
        if playback.repeatedRange != nil, let compareLoop {
            EditorCommand(title: "Compare 3 frames", symbol: .feed, action: compareLoop)
                .disabled(!enabled)
                .accessibilityIdentifier("editor.compareLoop")
        } else if let openRanges {
            EditorCommand(title: rangesTitle, symbol: .bookmark, action: openRanges)
                .accessibilityIdentifier("editor.openRanges")
        }
    }
}

private struct EditorFilmstrip: View {
    let frames: [UIImage?]
    let duration: Double
    let trim: ClosedRange<Double>
    let looping: ClosedRange<Double>?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let cellWidth = width / CGFloat(max(1, frames.count))
            let start = offset(for: trim.lowerBound, width: width)
            let end = offset(for: trim.upperBound, width: width)
            ZStack(alignment: .leading) {
                SwevoStyle.raised
                HStack(spacing: 0) {
                    ForEach(frames.indices, id: \.self) { index in
                        Group {
                            if let frame = frames[index] {
                                Image(uiImage: frame).resizable().scaledToFill()
                            } else {
                                SwevoStyle.surface
                            }
                        }
                        .frame(width: cellWidth, height: height)
                        .clipped()
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(SwevoStyle.ink.opacity(0.65)).frame(width: 1)
                        }
                    }
                }
                Color.black.opacity(0.58).frame(width: start)
                Color.black.opacity(0.58).frame(width: width - end).offset(x: end)
                RoundedRectangle(cornerRadius: 6).strokeBorder(SwevoStyle.accent, lineWidth: 1)
                    .frame(width: max(0, end - start)).offset(x: start)
                if let looping {
                    let loopStart = offset(for: looping.lowerBound, width: width)
                    let loopEnd = offset(for: looping.upperBound, width: width)
                    Capsule().fill(SwevoStyle.accent)
                        .frame(width: max(0, loopEnd - loopStart), height: 4)
                        .padding(.bottom, 3)
                        .frame(height: height, alignment: .bottom)
                        .offset(x: loopStart)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 6))
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func offset(for time: Double, width: CGFloat) -> CGFloat {
        width * CGFloat(min(1, max(0, time / duration)))
    }
}

struct VideoImportActions: View {
    enum Presentation: Equatable {
        case standard, prominent
        case library(stacked: Bool, photosFirst: Bool = false)
        case sourcePair(stacked: Bool)
    }

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let onImported: (PracticeRecording) -> Void
    @Binding var importing: Bool
    var presentation: Presentation = .standard
    @State private var photo: PhotosPickerItem?
    @State private var showingFiles = false
    @State private var error: String?

    private var prominent: Bool { presentation == .prominent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if importing {
                HStack(spacing: 10) {
                    ProgressView().tint(SwevoStyle.accent).accessibilityHidden(true)
                    LocalizedText("Importing…").font(.capture(.subheadline, weight: .semibold))
                }.frame(minHeight: 48)
            } else if case let .sourcePair(stacked) = presentation {
                pairedSources(stacked: stacked || typeSize > .xLarge)
            } else if case let .library(stacked, photosFirst) = presentation {
                librarySources(stacked: stacked || typeSize > .xLarge, photosFirst: photosFirst)
            } else {
                let paired = prominent && !typeSize.isAccessibilitySize
                let layout = paired ? AnyLayout(HStackLayout(spacing: 8))
                                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                layout {
                    fileButton
                    PhotosPicker(selection: $photo, matching: .videos, photoLibrary: .shared()) {
                        photosLabel
                            .frame(minHeight: prominent ? 78 : 48)
                            .swevoGlass(cornerRadius: 14)
                    }.buttonStyle(PressStyle())
                        .fixedSize(horizontal: paired, vertical: false)
                        .accessibilityIdentifier("video.import.photos")
                }
            }
            if let error { ErrorNote(message: error) }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.movie]) { result in
            do {
                let url = try result.get()
                importVideo { try await library.importMovie(url) }
            } catch { showImportError(error) }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            importVideo {
                guard let media = try await item.loadTransferable(type: ImportedMovie.self) else {
                    throw SwevoError.unsupportedMedia
                }
                defer { try? FileManager.default.removeItem(at: media.url) }
                return try await library.importMovie(media.url, title: media.suggestedTitle ?? L10n.text("Imported video"))
            }
        }
    }

    private func pairedSources(stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button { showingFiles = true } label: {
                pairedSourceLabel("Files", symbol: .folder, primary: true)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Open video file")
            .accessibilityIdentifier("video.import.files")

            PhotosPicker(selection: $photo, matching: .videos, photoLibrary: .shared()) {
                pairedSourceLabel("Photos", symbol: .feed, primary: false)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Choose from Photos")
            .accessibilityIdentifier("video.import.photos")
        }
    }

    private func pairedSourceLabel(_ title: String, symbol: SwevoGlyph, primary: Bool) -> some View {
        HStack(spacing: 9) {
            Glyph(symbol: symbol, size: 17, tint: primary ? SwevoStyle.ink : SwevoStyle.accent)
                .frame(width: 32, height: 34)
                .background(primary ? SwevoStyle.accent : SwevoStyle.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8))
            LocalizedText(title).font(.capture(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .foregroundStyle(SwevoStyle.paper)
        .swevoGlass(cornerRadius: 13)
        .contentShape(.interaction, RoundedRectangle(cornerRadius: 13))
    }

    private func librarySources(stacked: Bool, photosFirst: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        let divider = Rectangle().fill(SwevoStyle.line)
            .frame(width: stacked ? nil : 1, height: stacked ? 1 : nil)
            .padding(stacked ? .horizontal : .vertical, 10)
            .allowsHitTesting(false).accessibilityHidden(true)
        let files = Button { showingFiles = true } label: {
            librarySourceLabel(photosFirst ? "Files" : "Open video", glyph: .folder, primary: !photosFirst)
        }
        .buttonStyle(PressStyle())
        .fixedSize(horizontal: !stacked && photosFirst, vertical: false)
        .overlay(alignment: stacked ? .top : .leading) { if photosFirst { divider } }
        .accessibilityLabel("Open video file")
        .accessibilityIdentifier("video.import.files")

        let photos = PhotosPicker(selection: $photo, matching: .videos, photoLibrary: .shared()) {
            librarySourceLabel(photosFirst ? "Choose from Photos" : "Photos", glyph: .feed, primary: photosFirst)
        }
        .buttonStyle(PressStyle())
        .fixedSize(horizontal: !stacked && !photosFirst, vertical: false)
        .overlay(alignment: stacked ? .top : .leading) { if !photosFirst { divider } }
        .accessibilityLabel("Choose from Photos")
        .accessibilityIdentifier("video.import.photos")

        return layout {
            if photosFirst {
                photos
                files
            } else {
                files
                photos
            }
        }
        .padding(4)
        .swevoGlass(cornerRadius: 20)
    }

    private func librarySourceLabel(_ title: String, glyph: SwevoGlyph, primary: Bool) -> some View {
        HStack(spacing: 10) {
            Glyph(symbol: glyph, size: 18, tint: primary ? SwevoStyle.ink : SwevoStyle.accent)
                .frame(width: primary ? 34 : 24, height: 34)
                .background(primary ? SwevoStyle.accent : .clear, in: Circle())
            LocalizedText(title).font(.capture(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .foregroundStyle(SwevoStyle.paper)
        .contentShape(Rectangle())
    }

    private var fileButton: some View {
        Button { showingFiles = true } label: {
            HStack(spacing: 12) {
                Glyph(symbol: .folder, size: prominent ? 24 : 18, tint: SwevoStyle.ink)
                    .frame(width: prominent ? 48 : 34, height: prominent ? 48 : 34)
                    .background(SwevoStyle.accent, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    LocalizedText(prominent ? "Open video" : "Open video file")
                        .font(.capture(prominent ? .title2 : .subheadline, weight: .semibold, display: prominent))
                    if prominent { LocalizedText("Files").font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary) }
                }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(minHeight: prominent ? 78 : 48)
            .foregroundStyle(SwevoStyle.paper)
            .swevoGlass(cornerRadius: 16)
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityLabel("Open video file")
            .accessibilityIdentifier("video.import.files")
    }

    private var photosLabel: some View {
        let stacked = prominent && !typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 5)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Glyph(symbol: .feed, size: stacked ? 23 : 18, tint: SwevoStyle.accent)
            LocalizedText(prominent ? "Photos" : "Choose from Photos")
                .font(.capture(stacked ? .footnote : .subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: stacked ? nil : .infinity, alignment: .leading)
        }.padding(.horizontal, 14).padding(.vertical, 8)
            .frame(minWidth: stacked ? 80 : 44)
            .foregroundStyle(SwevoStyle.paper)
            .contentShape(Rectangle())
    }

    private func importVideo(_ operation: @escaping () async throws -> PracticeRecording) {
        guard !importing else { return }
        importing = true
        error = nil
        Task {
            defer {
                photo = nil
                importing = false
            }
            do {
                let movie = try await operation()
                onImported(movie)
            } catch { showImportError(error) }
        }
    }

    private func showImportError(_ error: Error) {
        let failure = error as NSError
        guard !(error is CancellationError),
              !(failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError),
              !(failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) else { return }
        if failure.domain == NSCocoaErrorDomain,
           [NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadNoPermissionError].contains(failure.code) {
            self.error = "This file can’t be read. Choose the video again from Files."
        } else {
            self.error = error.localizedDescription
        }
    }
}

struct VideoFileButton: View {
    enum Presentation: Equatable {
        case row, featured, thumbnail
        case picker(tiled: Bool)
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    let url: URL
    let filename: String
    let date: Date
    var presentation: Presentation = .row
    var fallbackCover: URL? = nil
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if case let .picker(tiled) = presentation {
                pickerLabel(tiled: tiled)
            } else if presentation == .thumbnail {
                coverLabel(featured: false)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .swevoGlass(cornerRadius: 16)
                    .contentShape(.interaction, RoundedRectangle(cornerRadius: 16))
            } else if presentation == .featured && !typeSize.isAccessibilitySize {
                coverLabel(featured: true)
                    .contentShape(Rectangle())
            } else {
                HStack(spacing: 12) {
                    VideoFileThumbnail(url: url, fallbackCover: fallbackCover)
                        .frame(width: 64, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    fileLabel
                }
                .padding(.vertical, 5)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(PressStyle())
    }

    private func pickerLabel(tiled: Bool) -> some View {
        let layout = tiled ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                           : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            VideoFileThumbnail(url: url, maximumSize: tiled ? 720 : 360, fallbackCover: fallbackCover)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(width: tiled ? nil : 104)
                .clipShape(.rect(cornerRadius: 8))
            fileLabel
        }
        .padding(.vertical, tiled ? 0 : 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func coverLabel(featured: Bool) -> some View {
        VStack(alignment: .leading, spacing: featured ? 10 : 0) {
            VideoFileThumbnail(url: url, maximumSize: featured ? 1080 : 640, fallbackCover: fallbackCover)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    let size: CGFloat = featured ? 48 : 34
                    Glyph(symbol: .play, size: featured ? 21 : 15, tint: SwevoStyle.paper)
                        .frame(width: size, height: size)
                        .swevoGlass(cornerRadius: size / 2)
                        .padding(featured ? 10 : 8)
                        .allowsHitTesting(false)
                }
            fileLabel
                .padding(.horizontal, featured ? 0 : 12)
                .padding(.vertical, featured ? 3 : 10)
        }
    }

    private var fileLabel: some View {
        let name = Text(verbatim: filename).font(.capture(.subheadline, weight: .semibold))
            .foregroundStyle(SwevoStyle.paper)
        let opened = LocalizedDateText(date: date)
            .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if presentation == .thumbnail || presentation == .picker(tiled: true) {
                    name.lineLimit(2, reservesSpace: true).truncationMode(.middle)
                    opened.lineLimit(typeSize.isAccessibilitySize ? 2 : 1, reservesSpace: true)
                } else {
                    name.fixedSize(horizontal: false, vertical: true)
                    opened
                }
                if let detail {
                    LocalizedText(detail).font(.capture(.caption)).foregroundStyle(SwevoStyle.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if presentation != .thumbnail {
                Glyph(symbol: .back, size: 13, tint: SwevoStyle.secondary).rotationEffect(.degrees(180))
            }
        }
    }
}

struct VideoFileThumbnail: View {
    let url: URL
    var maximumSize: CGFloat = 216
    var isAudio = false
    var fallbackCover: URL? = nil
    var timestamp: Double = 0
    var contentMode: ContentMode = .fill
    @State private var frame: CGImage?
    @State private var needsCover = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                contentMode == .fit ? SwevoStyle.ink : SwevoStyle.raised
                if let frame {
                    Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if needsCover, let fallbackCover {
                    MediaCover(url: fallbackCover)
                } else {
                    Glyph(symbol: isAudio ? .sound : .feed,
                          size: 22, tint: SwevoStyle.secondary)
                }
            }
            .clipped()
        }
        .accessibilityHidden(true)
        .task(id: url) {
            frame = nil
            needsCover = false
            guard !isAudio else { return }
            guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else { needsCover = true; return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maximumSize, height: maximumSize)
            if timestamp > 0 {
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
            }
            let time = CMTime(seconds: timestamp, preferredTimescale: 600)
            let result = try? await generator.image(at: time)
            guard !Task.isCancelled else { return }
            frame = result?.image
            needsCover = frame == nil
        }
    }
}

struct FlowChoices: View {
    let values: [String]
    let selected: String
    var action: (String) -> Void
    var body: some View {
        ChoiceStrip(values: values, selected: selected, select: action)
    }
}
struct SharedFile: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
