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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: WorkspaceSelection?

    private struct WorkspaceSelection: Identifiable {
        let id = UUID()
        let tool: VideoTool
        let movie: PracticeRecording?
    }

    var body: some View {
        let movie = library.movies.lazy.filter { !$0.isAudio }.max { first, second in
            (first.lastOpenedAt ?? .distantPast, first.date) < (second.lastOpenedAt ?? .distantPast, second.date)
        }
        ScenePage(artwork: movie == nil ? "SceneEdit" : nil, depth: 248, openingGap: 0) { height in
            opening(movie: movie, height: height)
        } content: { container in
            let stacked = typeSize > .xLarge || SwevoStyle.pageContentWidth(in: container) < 320
                || SwevoStyle.intersectsReservedRegion(CGRect(origin: .zero, size: container.size), in: container)
            VStack(alignment: .leading, spacing: 18) {
                rangeAction(movie: movie)
                quickTools(movie: movie, stacked: stacked)
            }
        }
        .sheet(item: $selection) { selection in
            EditorSheet(initialMovie: selection.movie, initialTool: selection.tool)
        }
    }

    private func opening(movie: PracticeRecording?, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            editorAction(movie: movie)
            if movie != nil {
                Button {
                    selection = WorkspaceSelection(tool: .studio, movie: nil)
                } label: {
                    HStack(spacing: 8) {
                        Glyph(symbol: .folder, size: 16, tint: SwevoStyle.accent)
                        LocalizedText("Change video").font(.capture(.footnote, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(SwevoStyle.accent)
                    .padding(.trailing, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, movie == nil ? 0 : 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
        .background {
            if let movie {
                VideoFileThumbnail(url: library.url(for: movie), maximumSize: 1080)
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.15),
                            .init(color: SwevoStyle.background.opacity(0.86), location: 0.65),
                            .init(color: SwevoStyle.background, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .allowsHitTesting(false)
            }
        }
    }

    private func editorAction(movie: PracticeRecording?) -> some View {
        Button {
            selection = WorkspaceSelection(tool: .studio, movie: movie)
        } label: {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if let movie {
                        LocalizedText(VideoTool.studio.title).font(.capture(.subheadline, weight: .semibold))
                            .foregroundStyle(SwevoStyle.accent)
                        Text(verbatim: movie.displayFilename)
                            .font(.capture(.title2, weight: .semibold))
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    } else {
                        SceneTitle(VideoTool.studio.title, size: 42).accessibilityRemoveTraits(.isHeader)
                        LocalizedText("Choose a video from Photos or Files to start editing.")
                            .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .edit, size: 24, tint: SwevoStyle.ink)
                    .frame(width: 56, height: 56)
                    .background(SwevoStyle.accent, in: Circle())
            }
            .foregroundStyle(SwevoStyle.paper)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("tools.studio")
    }

    private func rangeAction(movie: PracticeRecording?) -> some View {
        let mark = movie?.rangeMarks?.first { $0.timeRange != nil }
        return Button {
            selection = WorkspaceSelection(tool: .ranges, movie: movie)
        } label: {
            HStack(spacing: 12) {
                if let movie, let mark {
                    VideoFileThumbnail(url: library.url(for: movie), timestamp: mark.start)
                        .id(mark.id)
                        .frame(width: 56, height: 44)
                        .clipShape(.rect(cornerRadius: 8))
                } else {
                    Glyph(symbol: .bookmark, size: 20, tint: SwevoStyle.accent)
                        .frame(width: 44, height: 44)
                        .background(SwevoStyle.accent.opacity(0.10), in: .rect(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText(mark == nil ? VideoTool.ranges.title : "Review saved ranges")
                        .font(.capture(.headline))
                    if let mark {
                        if !mark.name.isEmpty {
                            Text(verbatim: mark.name).font(.capture(.subheadline))
                        }
                        let start = durationLabel(mark.start, fractional: true)
                        let end = durationLabel(mark.end, fractional: true)
                        Text(verbatim: "\(start) – \(end)")
                            .font(.capture(.footnote)).monospacedDigit()
                            .foregroundStyle(SwevoStyle.secondary)
                            .environment(\.layoutDirection, .leftToRight)
                    } else {
                        LocalizedText(VideoTool.ranges.detail).font(.capture(.footnote))
                            .foregroundStyle(SwevoStyle.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .back, size: 13, tint: SwevoStyle.accent).rotationEffect(.degrees(180))
            }
            .padding(.vertical, 10)
            .foregroundStyle(SwevoStyle.paper)
            .overlay(alignment: .bottom) {
                Divider().overlay(SwevoStyle.line).allowsHitTesting(false).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("tools.ranges")
    }

    private func quickTools(movie: PracticeRecording?, stacked: Bool) -> some View {
        let frame = quickTool(.frame, movie: movie, featured: !stacked)
        let divider = Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
        let secondaryTools = VStack(spacing: 0) {
            quickTool(.speed, movie: movie)
            divider
            quickTool(.audio, movie: movie)
        }
        return Group {
            if stacked {
                VStack(spacing: 0) {
                    frame
                    divider
                    secondaryTools
                }
            } else {
                HStack(spacing: 0) {
                    frame
                    divider
                    secondaryTools
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .swevoGlass(cornerRadius: 20)
    }

    private func quickTool(_ tool: VideoTool, movie: PracticeRecording?, featured: Bool = false) -> some View {
        let layout = featured ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                              : AnyLayout(HStackLayout(alignment: .top, spacing: 9))
        return Button {
            selection = WorkspaceSelection(tool: tool, movie: movie)
        } label: {
            layout {
                Glyph(symbol: tool.glyph, size: featured ? 30 : 16, tint: SwevoStyle.accent)
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText(tool.title).font(.capture(featured ? .headline : .subheadline, weight: .semibold))
                    LocalizedText(tool.detail).font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, featured ? 16 : 12)
            .padding(.vertical, featured ? 16 : 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .foregroundStyle(SwevoStyle.paper)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("tools.\(tool.rawValue)")
    }
}

struct EditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialMovie: PracticeRecording? = nil
    var initialTool: VideoTool = .studio
    var onVideoOpened: ((PracticeRecording) -> Void)? = nil
    @StateObject private var departure = ExportDeparture()
    var body: some View {
        EditorWorkspace(initialMovie: initialMovie, initialTool: initialTool, onVideoOpened: onVideoOpened) {
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
    let initialTool: VideoTool
    let onVideoOpened: ((PracticeRecording) -> Void)?
    let close: () -> Void
    @StateObject private var editor = VideoEditor()
    @State private var selected: PracticeRecording?
    @State private var importing = false
    @State private var error: String?
    @State private var shareURL: SharedFile?
    @State private var savedExport: PracticeRecording?
    @State private var sharingExport = false
    @State private var shareTask: Task<Void, Never>?
    @State private var playbackScrubbing = false
    @State private var resumePreview = false
    @State private var retryID = UUID()
    @State private var tool = "Trim"
    @State private var exportTask: Task<Void, Never>?
    private let tools = ["Trim", "Frame", "Speed", "Audio", "Export"]

    init(initialMovie: PracticeRecording? = nil, initialTool: VideoTool = .studio,
         onVideoOpened: ((PracticeRecording) -> Void)? = nil, close: @escaping () -> Void) {
        self.initialTool = initialTool
        self.onVideoOpened = onVideoOpened
        self.close = close
        _selected = State(initialValue: initialMovie)
        _tool = State(initialValue: initialTool.editorTab)
    }
    var body: some View {
        ScrollViewReader { scroll in
            workspace(scroll).onChange(of: savedExport?.id) { _, id in
                if let id { scroll.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private func workspace(_ scroll: ScrollViewProxy) -> some View {
        ScenePage { container in
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let selected {
                            Text(verbatim: selected.displayFilename).font(.capture(.headline))
                                .fixedSize(horizontal: false, vertical: true)
                            changeVideo
                        } else {
                            LocalizedText(initialTool.detail).font(.capture(.subheadline))
                                .foregroundStyle(SwevoStyle.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    IconButton(symbol: .close, label: "Close", action: close)
                        .swevoGlass(cornerRadius: 22).disabled(importing)
                }
                if let selected {
                    let canPlay = scenePhase == .active && !ads.isPresenting && shareURL == nil && !showingExportMembership
                    let canMarkRange = canPlay && !departure.running && !editor.isPreparingPreview && !sharingExport
                    VStack(alignment: .leading, spacing: 8) {
                        VideoSurface(player: editor.preview.player, fill: false)
                            .frame(maxWidth: .infinity)
                            .frame(height: min(470, max(150, container.size.height * 0.48)))
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        VideoPlaybackControls(playback: editor.preview, timeline: editor.preview.timeline,
                                              enabled: canPlay && editor.duration > 0 && !editor.isPreparingPreview && !departure.running,
                                              canResume: canPlay,
                                              scrubbing: $playbackScrubbing, retry: editor.retryPlayback)
                    }.id("editor-preview")
                    if editor.isLoading {
                        LocalizedText("Preparing your video…").foregroundStyle(SwevoStyle.secondary)
                    } else if editor.duration <= 0, let error = editor.error {
                        ErrorNote(message: error)
                        ActionButton(title: "Retry", primary: false) { retryID = UUID() }
                    }
                    if editor.isPreparingPreview { AccountLoadingIndicator(title: "Preparing preview…").frame(maxWidth: .infinity) }
                    if editor.duration > 0 {
                        if initialTool == .studio {
                            ChoiceStrip(values: tools, selected: tool) { tool = $0 }
                        }
                        controls.id("editor-adjustments")
                            .disabled(departure.running || editor.isExporting || editor.isPreparingPreview || sharingExport)
                        if let error = editor.error { ErrorNote(message: error) }
                        if initialTool == .ranges {
                            ranges(for: selected, scroll: scroll).disabled(!canMarkRange)
                        }
                    }
                    if departure.running {
                        VStack(spacing: 14) {
                            LocalizedText(editor.isExporting ? "Exporting · \(Int(editor.progress * 100))%" : "Preparing export…")
                                .font(.capture(.subheadline)).monospacedDigit()
                            GeometryReader { geometry in
                                Color.clear.background(SwevoStyle.raised)
                                    .overlay(alignment: .leading) { SwevoStyle.accent.frame(width: geometry.size.width * CGFloat(editor.progress)) }
                            }.frame(height: 4)
                            ActionButton(title: "Cancel export", primary: false) { departure.request() }
                        }
                    } else if editor.duration > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            ActionButton(title: initialTool == .audio ? "Export audio as M4A" : "Export video") {
                                export(audio: initialTool == .audio, title: selected.title)
                            }
                            if initialTool != .audio {
                                ActionButton(title: "Preview changes", primary: false) { Task { await editor.applyPreview() } }
                            }
                        }
                        .disabled(editor.isPreparingPreview || sharingExport)
                    }
                    if let error { ErrorNote(message: error) }
                    if let savedExport {
                        SavedVideoExport(movie: savedExport, sharing: sharingExport, disabled: departure.running) {
                            shareExport(savedExport)
                        }.id(savedExport.id)
                    }
                    if initialTool == .studio, tool == "Trim", editor.duration > 0 {
                        ranges(for: selected, scroll: scroll).disabled(!canMarkRange)
                    }
                } else {
                    importPrompt
                    if let error { ErrorNote(message: error) }
                    if !library.importedMovies.isEmpty {
                        SectionLabel(title: "Recent imports")
                        LazyVStack(spacing: 4) {
                            ForEach(library.importedMovies) { movie in
                                VideoFileButton(url: library.url(for: movie), filename: movie.displayFilename, date: movie.date) {
                                    choose(movie)
                                }.disabled(importing)
                            }
                        }
                    }
                }
            }
        }
            .interactiveDismissDisabled(importing || departure.running)
            .scrollDismissesKeyboard(.interactively)
            .sheet(item: $shareURL) { ShareSheet(items: [$0.url]) }
            .sheet(isPresented: $showingExportMembership) { MembershipView(exportRequired: true) }
            .task(id: VideoOpenRequest(movieID: selected?.id, retryID: retryID)) {
                guard let selected else { return }
                playbackScrubbing = false
                await editor.open(library.url(for: selected)) {
                    library.markOpened(selected)
                    onVideoOpened?(selected)
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
            .onDisappear { editor.close(); exportTask?.cancel(); shareTask?.cancel() }
    }

    private func ranges(for movie: PracticeRecording, scroll: ScrollViewProxy) -> some View {
        VideoRangePanel(playback: editor.preview, movieID: movie.id, duration: editor.duration,
                        start: editor.recipe.start, end: editor.recipe.end, primary: initialTool == .ranges,
                        playRange: { range in
            editor.playRange(range)
            scroll.scrollTo("editor-preview", anchor: .top)
        }, trimToRange: { range in
            editor.preview.pause()
            editor.recipe.start = range.lowerBound
            editor.recipe.end = range.upperBound
            editor.restoreSourcePreview(seekTo: range.lowerBound)
            scroll.scrollTo("editor-adjustments", anchor: .top)
        }).id(movie.id)
    }

    private func interruptPreview() {
        resumePreview = resumePreview || editor.preview.intendsPlayback
        editor.preview.pause()
    }

    private func resumePreviewIfPossible() {
        guard resumePreview, scenePhase == .active, !ads.isPresenting else { return }
        resumePreview = false
        guard selected != nil, shareURL == nil, !showingExportMembership, !departure.running else { return }
        editor.preview.play()
    }

    private var importPrompt: some View {
        VideoImportActions(onImported: choose, importing: $importing)
    }

    @ViewBuilder private var changeVideo: some View {
        if !departure.running, !editor.isExporting, !editor.isPreparingPreview, !sharingExport {
            Button {
                selected = nil
                error = nil
                savedExport = nil
                editor.close()
            } label: {
                LocalizedText("Change video")
                    .font(.capture(.footnote, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(SwevoStyle.accent)
                    .contentShape(Rectangle())
            }.buttonStyle(PressStyle())
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch tool {
            case "Trim":
                if !editor.thumbnails.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(Array(editor.thumbnails.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 42, height: 64).clipped()
                            }
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 10))
                }
                HStack { LocalizedText("Start"); Spacer(); Text(verbatim: durationLabel(editor.recipe.start, fractional: true)).monospacedDigit() }
                SwevoScrubber(value: Binding(get: { editor.recipe.start }, set: {
                    editor.recipe.start = max(0, min($0, editor.recipe.end - 0.1))
                    editor.restoreSourcePreview(seekTo: editor.recipe.start)
                }), range: 0...max(0.1, editor.duration), label: "Trim start")
                HStack { LocalizedText("End"); Spacer(); Text(verbatim: durationLabel(editor.recipe.end, fractional: true)).monospacedDigit() }
                SwevoScrubber(value: Binding(get: { editor.recipe.end }, set: {
                    editor.recipe.end = min(editor.duration, max($0, editor.recipe.start + 0.1))
                    editor.restoreSourcePreview(seekTo: editor.recipe.end)
                }), range: 0...max(0.1, editor.duration), label: "Trim end")
                LocalizedText("Final duration · \(durationLabel((editor.recipe.end - editor.recipe.start) / editor.recipe.speed))").font(.capture(.footnote)).foregroundStyle(SwevoStyle.accent)
            case "Frame":
                LocalizedText("Framing").font(.capture(.title3, weight: .bold))
                FlowChoices(values: VideoFrame.allCases.map(\.rawValue), selected: editor.recipe.frame.rawValue) { value in editor.recipe.frame = VideoFrame(rawValue: value) ?? .original }
                ActionButton(title: "Rotate 90° · \((editor.recipe.quarterTurns % 4) * 90)°", primary: false) { editor.recipe.quarterTurns = (editor.recipe.quarterTurns + 1) % 4 }
                ActionButton(title: editor.recipe.mirrored ? "Mirror: On" : "Mirror: Off", primary: false) { editor.recipe.mirrored.toggle() }
                LocalizedText("Swevo crops from the center. Tap Preview changes to check the framing.")
                    .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
            case "Speed":
                LocalizedText("Video speed").font(.capture(.title3, weight: .bold))
                FlowChoices(values: ["0.5×", "0.75×", "1×", "1.5×", "2×"], selected: String(format: "%g×", editor.recipe.speed)) { value in editor.recipe.speed = Double(value.replacingOccurrences(of: "×", with: "")) ?? 1 }
            case "Audio":
                if initialTool == .audio {
                    LocalizedText("Audio track").font(.capture(.title3, weight: .bold))
                    LocalizedText("Export this video’s audio as an M4A file. The video must contain an audio track.")
                        .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                } else {
                    LocalizedText("Video sound").font(.capture(.title3, weight: .bold))
                    ActionButton(title: editor.recipe.muted ? "Audio: Muted" : "Audio: Original", primary: false) { editor.recipe.muted.toggle() }
                    ActionButton(title: "Extract audio as M4A", primary: false) { export(audio: true, title: selected?.title ?? "Audio") }
                    LocalizedText("Audio extraction uses your trim and speed settings.").font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                }
            default:
                LocalizedText("Export settings").font(.capture(.title3, weight: .bold))
                FlowChoices(values: ExportQuality.allCases.map(\.rawValue), selected: editor.recipe.quality.rawValue) { value in editor.recipe.quality = ExportQuality(rawValue: value) ?? .full }
                LocalizedText("MP4 · Up to the selected resolution · 30 fps\nSmaller resolutions reduce export size. Source videos are never upscaled.").font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
            }
        }.padding(22).background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private func choose(_ movie: PracticeRecording) {
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

private struct VideoRangePanel: View {
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject var playback: PlaybackController
    let movieID: UUID
    let duration: Double
    let start: Double
    let end: Double
    let primary: Bool
    let playRange: (ClosedRange<Double>) -> Void
    let trimToRange: (ClosedRange<Double>) -> Void
    @State private var name = ""
    @State private var error: String?
    @State private var frameRequest: RangeFrameRequest?
    @FocusState private var editingName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Range name (optional)", text: $name)
                .font(.capture(.subheadline)).swevoField()
                .focused($editingName).submitLabel(.done)
                .onSubmit { saveRange() }
                .accessibilityIdentifier("video.range.name")
            rangeCommand("Save range", symbol: .bookmark, emphasized: primary, action: saveRange)
                .accessibilityIdentifier("video.range.save")
            if let error { ErrorNote(message: error) }
            if let movie = library.movies.first(where: { $0.id == movieID }), let marks = movie.rangeMarks, !marks.isEmpty {
                SectionLabel(title: "Saved ranges").accessibilityAddTraits(.isHeader)
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(marks) { mark in
                        if let range = mark.timeRange, range.upperBound <= duration {
                            rangeRow(mark, range: range, url: library.url(for: movie))
                        }
                    }
                }
            }
        }.sheet(item: $frameRequest) { request in RangeFrameComparison(request: request) }
    }

    private func rangeRow(_ mark: VideoRangeMark, range: ClosedRange<Double>, url: URL) -> some View {
        let isLooping = playback.repeatedRange == range
        let startText = durationLabel(mark.start, fractional: true)
        let endText = durationLabel(mark.end, fractional: true)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VideoFileThumbnail(url: url, timestamp: mark.start)
                    .frame(width: 58, height: 40).clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    if !mark.name.isEmpty {
                        Text(verbatim: mark.name).font(.capture(.subheadline, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(verbatim: "\(startText) – \(endText)")
                        .font(.capture(.footnote, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(SwevoStyle.secondary).environment(\.layoutDirection, .leftToRight)
                        .fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: 4) { rangeActions(mark, range: range, url: url, isLooping: isLooping) }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) { rangeActions(mark, range: range, url: url, isLooping: isLooping) }
            }
            Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
        }.padding(.vertical, 5)
    }

    @ViewBuilder private func rangeActions(_ mark: VideoRangeMark, range: ClosedRange<Double>, url: URL, isLooping: Bool) -> some View {
        rangeCommand(isLooping ? "Stop loop" : "Loop range", symbol: isLooping ? .pause : .play, emphasized: true) {
            editingName = false
            if isLooping {
                playback.pause()
                playback.stopRepeating()
            } else {
                playRange(range)
            }
        }
        rangeCommand("Compare frames", symbol: .feed) {
            editingName = false
            playback.pause()
            playback.stopRepeating()
            frameRequest = RangeFrameRequest(source: url, mark: mark)
        }.accessibilityIdentifier("video.range.compareFrames")
        rangeCommand("Use for trim", symbol: .edit) {
            editingName = false
            trimToRange(range)
        }
    }

    private func rangeCommand(_ title: String, symbol: SwevoGlyph, emphasized: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Glyph(symbol: symbol, size: 15, tint: emphasized ? SwevoStyle.ink : SwevoStyle.accent)
                LocalizedText(title).font(.capture(.footnote, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 12).padding(.vertical, 4).frame(minHeight: 44)
                .foregroundStyle(emphasized ? SwevoStyle.ink : SwevoStyle.paper)
                .background(emphasized ? SwevoStyle.accent : Color.clear, in: Capsule())
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }

    private func saveRange() {
        guard start.isFinite, end.isFinite, start >= 0, start < end, end <= duration else {
            error = "Choose a start and end for the range."
            return
        }
        editingName = false
        do {
            try library.addRange(start...end, name: name, to: movieID)
            name = ""
            error = nil
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
    func readFrames() async throws -> [RangeStill] {
        guard source.isFileURL, FileManager.default.isReadableFile(atPath: source.path) else {
            throw SwevoError.service("This file can’t be read. Choose the video again from Files.")
        }
        guard let range = mark.timeRange else { throw SwevoError.service("Choose a start and end for the range.") }
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1440, height: 1440)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    let request: RangeFrameRequest
    @State private var frames: [RangeStill] = []
    @State private var selectedPosition: RangeStill.Position = .start
    @State private var loadAttempt = UUID()
    @State private var loadError: String?
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Compare frames") { dismiss() }.disabled(exporting)
            ScenePage { container in
                VStack(alignment: .leading, spacing: 16) {
                    if !request.mark.name.isEmpty {
                        Text(verbatim: request.mark.name).font(.capture(.title3, display: true))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let selected = frames.first(where: { $0.position == selectedPosition }) {
                        preview(selected, in: container)
                        frameStrip(in: container)
                        RangeShareActions(context: .comparison(request, frames), busy: $exporting)
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
        let wide = !typeSize.isAccessibilitySize && SwevoStyle.pageContentWidth(in: container) >= 300
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
        case practice(source: URL, marks: [VideoRangeMark])
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch context {
            case .comparison(let request, let frames):
                ActionButton(title: "Share comparison image") {
                    export(request, frames: frames, format: .comparison)
                }.disabled(busy).accessibilityIdentifier("video.range.shareComparison")
                ActionButton(title: "Export JPEG stills", primary: false) {
                    export(request, frames: frames, format: .stills)
                }.disabled(busy).accessibilityIdentifier("video.range.exportStills")
                if busy { AccountLoadingIndicator(title: "Preparing export…") }
                if let exportError { ErrorNote(message: exportError) }
            case .practice(let source, let marks):
                SectionLabel(title: "Share comparison image").accessibilityAddTraits(.isHeader)
                ForEach(marks) { mark in
                    practiceRow(RangeFrameRequest(source: source, mark: mark))
                }
            }
            if !commerce.hasVerifiedPlus {
                LocalizedText("Export is included with Plus.").font(.capture(.footnote))
                    .foregroundStyle(SwevoStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showingPlus) { MembershipView(exportRequired: true) }
        .sheet(item: $sharedStills) { ShareSheet(items: $0.files) }
        .onDisappear { exportTask?.cancel() }
    }

    private func practiceRow(_ request: RangeFrameRequest) -> some View {
        let start = durationLabel(request.mark.start, fractional: true)
        let end = durationLabel(request.mark.end, fractional: true)
        let selected = selectedRangeID == request.id
        return VStack(alignment: .leading, spacing: 4) {
            Button { export(request, format: .comparison) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: request.title(in: AppLanguage.from(locale)))
                            .font(.capture(.subheadline, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: "\(start) – \(end)")
                            .font(.capture(.caption)).monospacedDigit().foregroundStyle(SwevoStyle.secondary)
                            .environment(\.layoutDirection, .leftToRight)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if busy && selected {
                        ProgressView().tint(SwevoStyle.accent).frame(width: 44).accessibilityLabel("Preparing export…")
                    } else {
                        Glyph(symbol: .download, size: 19, tint: SwevoStyle.accent).frame(width: 44)
                    }
                }.padding(.vertical, 5).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(PressStyle()).disabled(busy)
                .accessibilityElement(children: .combine).accessibilityHint("Share comparison image")
                .accessibilityIdentifier("practice.review.shareComparison.\(request.id.uuidString)")
            if selected, let exportError { ErrorNote(message: exportError) }
            Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
        }
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
            return [("Swevo-range-\(request.id.uuidString.prefix(8)).jpg", image)]
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                let playing = playback.intendsPlayback
                IconButton(symbol: playing ? .pause : .play, label: playing ? "Pause preview" : "Play preview") {
                    playback.toggle()
                }
                .background { CaptureSurface(tone: .plum) }
                .disabled(!enabled || playback.error != nil)
                Text(verbatim: "\(durationLabel(timeline.elapsed)) / \(durationLabel(timeline.duration))")
                    .font(.capture(.footnote)).monospacedDigit()
                    .foregroundStyle(SwevoStyle.secondary)
                    .environment(\.layoutDirection, .leftToRight)
                if playback.isLoading && playing {
                    ProgressView().tint(SwevoStyle.accent).accessibilityLabel("Loading…")
                }
            }
            PlayerProgressControl(playback: playback, timeline: timeline, enabled: enabled,
                                  canResume: canResume, scrubbing: $scrubbing)
            if playback.repeatedRange != nil {
                Button("Stop loop") {
                    playback.pause()
                    playback.stopRepeating()
                }.buttonStyle(CompactActionStyle()).disabled(!enabled)
            }
            if let error = playback.error {
                ErrorNote(message: "Preview could not play. \(error)")
                ActionButton(title: "Retry", primary: false, action: retry).disabled(!enabled)
            }
        }
    }
}

struct VideoImportActions: View {
    enum Presentation {
        case standard, prominent, library
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
            } else if presentation == .library {
                librarySources
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

    private var librarySources: some View {
        let stacked = typeSize > .xLarge
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            Button { showingFiles = true } label: {
                librarySourceLabel("Open video", glyph: .folder, primary: true)
            }.buttonStyle(PressStyle())
                .accessibilityLabel("Open video file")
                .accessibilityIdentifier("video.import.files")

            PhotosPicker(selection: $photo, matching: .videos, photoLibrary: .shared()) {
                librarySourceLabel("Photos", glyph: .feed, primary: false)
            }.buttonStyle(PressStyle())
                .fixedSize(horizontal: !stacked, vertical: false)
                .overlay(alignment: stacked ? .top : .leading) {
                    Rectangle().fill(SwevoStyle.line)
                        .frame(width: stacked ? nil : 1, height: stacked ? 1 : nil)
                        .padding(stacked ? .horizontal : .vertical, 10)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .accessibilityLabel("Choose from Photos")
                .accessibilityIdentifier("video.import.photos")
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
    @Environment(\.dynamicTypeSize) private var typeSize
    let url: URL
    let filename: String
    let date: Date
    var featured = false
    var fallbackCover: URL? = nil
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if featured && !typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    VideoFileThumbnail(url: url, maximumSize: 1080, fallbackCover: fallbackCover)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay(alignment: .bottomTrailing) {
                            Glyph(symbol: .play, size: 21, tint: SwevoStyle.paper)
                                .frame(width: 48, height: 48)
                                .swevoGlass(cornerRadius: 24)
                                .padding(10).allowsHitTesting(false)
                        }
                    fileLabel.padding(.vertical, 3)
                }
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

    private var fileLabel: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: filename).font(.capture(.subheadline, weight: .semibold))
                    .foregroundStyle(SwevoStyle.paper)
                    .fixedSize(horizontal: false, vertical: true)
                LocalizedDateText(date: date)
                    .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                if let detail {
                    LocalizedText(detail).font(.capture(.caption)).foregroundStyle(SwevoStyle.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Glyph(symbol: .back, size: 13, tint: SwevoStyle.secondary).rotationEffect(.degrees(180))
        }
    }
}

struct VideoFileThumbnail: View {
    let url: URL
    var maximumSize: CGFloat = 216
    var isAudio = false
    var fallbackCover: URL? = nil
    var timestamp: Double = 0
    @State private var frame: CGImage?
    @State private var needsCover = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SwevoStyle.raised
                if let frame {
                    Image(decorative: frame, scale: 1).resizable().scaledToFill()
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
