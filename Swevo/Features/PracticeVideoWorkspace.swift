import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

enum VideoTool: String, Identifiable, CaseIterable {
    case audio, speed, frame, studio
    var id: String { rawValue }
    var title: String {
        switch self {
        case .audio: return "Extract audio"
        case .speed: return "Change speed"
        case .frame: return "Reframe video"
        case .studio: return "Edit video"
        }
    }
    var detail: String {
        switch self {
        case .audio: return "Save a video’s audio as an M4A file."
        case .speed: return "Slow down or speed up a clip."
        case .frame: return "Crop, rotate or mirror a video."
        case .studio: return "Trim a clip and adjust its framing, speed or audio."
        }
    }
    var editorTab: String {
        switch self {
        case .audio: return "Audio"
        case .speed: return "Speed"
        case .frame: return "Frame"
        case .studio: return "Trim"
        }
    }
    var glyph: SwevoGlyph {
        switch self {
        case .audio: return .sound
        case .speed: return .play
        case .frame: return .feed
        case .studio: return .edit
        }
    }
}

struct ToolsView: View {
    @State private var selectedTool: VideoTool?
    private let tools: [VideoTool] = [.frame, .speed, .audio]
    var body: some View {
        ScenePage(artwork: nil, depth: 48, openingGap: 0) { _ in
            SceneTitle("Tools", size: 38)
        } content: { _ in
            VStack(alignment: .leading, spacing: 16) {
                editorAction
                VStack(spacing: 0) {
                    ForEach(tools) { tool in
                        Button { selectedTool = tool } label: {
                            FeatureRow(symbol: tool.glyph, title: tool.title, detail: tool.detail)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }.buttonStyle(PressStyle())
                            .accessibilityIdentifier("tools.\(tool.rawValue)")
                        if tool != .audio { Divider().overlay(SwevoStyle.line) }
                    }
                }
            }
        }
            .sheet(item: $selectedTool) { EditorSheet(initialTool: $0) }
    }

    private var editorAction: some View {
        Button { selectedTool = .studio } label: {
            HStack(spacing: 8) {
                Glyph(symbol: .edit, size: 20, tint: SwevoStyle.ink)
                LocalizedText(VideoTool.studio.title).font(.capture(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .back, size: 13, tint: SwevoStyle.ink).rotationEffect(.degrees(180))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 48)
            .foregroundStyle(SwevoStyle.ink)
            .background { CaptureSurface(tone: .accent) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("tools.studio")
    }
}

struct EditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialMovie: PracticeRecording? = nil
    var initialTool: VideoTool = .studio
    @StateObject private var departure = ExportDeparture()
    var body: some View {
        EditorWorkspace(initialMovie: initialMovie, initialTool: initialTool) {
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

    init(initialMovie: PracticeRecording? = nil, initialTool: VideoTool = .studio, close: @escaping () -> Void) {
        self.initialTool = initialTool
        self.close = close
        _selected = State(initialValue: initialMovie)
        _tool = State(initialValue: initialTool.editorTab)
    }
    var body: some View {
        ScrollViewReader { scroll in
            workspace.onChange(of: savedExport?.id) { _, id in
                if let id { scroll.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var workspace: some View {
        ScenePage(artwork: nil, depth: 62, openingGap: 0) { _ in
            VStack(alignment: .leading, spacing: 6) {
                SceneTitle(initialTool.title, size: 32)
                if selected == nil {
                    LocalizedText(initialTool.detail)
                        .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(.trailing, 50)
        } content: { container in
            VStack(alignment: .leading, spacing: 24) {
                if let selected {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            selectedTitle(selected).fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 0)
                            changeVideo
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            selectedTitle(selected)
                            changeVideo
                        }
                    }
                    let canPlay = scenePhase == .active && !ads.isPresenting && shareURL == nil && !showingExportMembership
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
                    }
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
                        controls.disabled(departure.running || editor.isExporting || editor.isPreparingPreview || sharingExport)
                        if let error = editor.error { ErrorNote(message: error) }
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
            .sceneDismiss(disabled: importing, action: close)
            .interactiveDismissDisabled(importing || departure.running)
            .sheet(item: $shareURL) { ShareSheet(items: [$0.url]) }
            .sheet(isPresented: $showingExportMembership) { MembershipView(exportRequired: true) }
            .task(id: VideoOpenRequest(movieID: selected?.id, retryID: retryID)) {
                guard let selected else { return }
                playbackScrubbing = false
                await editor.open(library.url(for: selected), onReady: { library.markOpened(selected) })
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
        VStack(alignment: .leading, spacing: 12) {
            VideoImportActions(onImported: choose, importing: $importing)
            LocalizedText("Swevo makes a copy for editing.")
                .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectedTitle(_ movie: PracticeRecording) -> some View {
        Text(verbatim: movie.displayFilename).font(.capture(.subheadline, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
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
                LocalizedText("Trim video").font(.capture(.title3, weight: .bold))
                if !editor.thumbnails.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(Array(editor.thumbnails.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 42, height: 64).clipped()
                            }
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 10))
                }
                HStack { LocalizedText("Start"); Spacer(); Text(verbatim: durationLabel(editor.recipe.start)).monospacedDigit() }
                SwevoScrubber(value: Binding(get: { editor.recipe.start }, set: {
                    editor.recipe.start = min($0, editor.recipe.end - 0.1)
                    editor.restoreSourcePreview(seekTo: editor.recipe.start)
                }), range: 0...max(0.1, editor.duration), label: "Trim start")
                HStack { LocalizedText("End"); Spacer(); Text(verbatim: durationLabel(editor.recipe.end)).monospacedDigit() }
                SwevoScrubber(value: Binding(get: { editor.recipe.end }, set: {
                    editor.recipe.end = max($0, editor.recipe.start + 0.1)
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
            if let error = playback.error {
                ErrorNote(message: "Preview could not play. \(error)")
                ActionButton(title: "Retry", primary: false, action: retry).disabled(!enabled)
            }
        }
    }
}

struct VideoImportActions: View {
    @EnvironmentObject private var library: LibraryStore
    let onImported: (PracticeRecording) -> Void
    @Binding var importing: Bool
    var sideBySide = false
    @State private var photo: PhotosPickerItem?
    @State private var showingFiles = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if importing {
                HStack(spacing: 10) {
                    ProgressView().tint(SwevoStyle.accent).accessibilityHidden(true)
                    LocalizedText("Importing…").font(.capture(.subheadline, weight: .semibold))
                }.frame(minHeight: 48)
            } else {
                let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                                        : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                layout {
                    Button { showingFiles = true } label: {
                        importLabel("Open video file", symbol: .folder, primary: true)
                    }.buttonStyle(PressStyle())
                        .accessibilityIdentifier("video.import.files")
                    PhotosPicker(selection: $photo, matching: .videos, photoLibrary: .shared()) {
                        importLabel("Choose from Photos", symbol: .feed, primary: false)
                    }.buttonStyle(PressStyle())
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

    private func importLabel(_ title: String, symbol: SwevoGlyph, primary: Bool) -> some View {
        let color = primary ? SwevoStyle.ink : SwevoStyle.paper
        return HStack(spacing: 10) {
            Glyph(symbol: symbol, size: 18, tint: primary ? color : SwevoStyle.secondary)
            LocalizedText(title).font(.capture(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 48)
        .foregroundStyle(color)
        .background { CaptureSurface(tone: primary ? .accent : .plum) }
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if featured && !typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    VideoFileThumbnail(url: url, maximumSize: 1080, fallbackCover: fallbackCover)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay(alignment: .bottomTrailing) {
                            Glyph(symbol: .play, size: 17, tint: SwevoStyle.paper)
                                .frame(width: 36, height: 36)
                                .background(SwevoStyle.ink.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                                .padding(8).allowsHitTesting(false)
                        }
                    fileLabel.padding(12)
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
            guard FileManager.default.isReadableFile(atPath: url.path) else { needsCover = true; return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maximumSize, height: maximumSize)
            let result = try? await generator.image(at: .zero)
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
