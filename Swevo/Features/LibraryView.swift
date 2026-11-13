import SwiftUI
import AVFoundation

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingExportMembership = false
    var edit: (PracticeRecording) -> Void
    @Binding var filter: String
    @State private var player: PlayerRoute?
    @State private var sharing: SharedFile?
    @State private var removing: PracticeRecording?
    @State private var removingDownload: OfflineVideo?
    @State private var sharingMovieID: UUID?
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    private var category: Category { Category(rawValue: filter) ?? .saved }
    private var localMovies: [PracticeRecording] {
        library.movies.filter { $0.isExport == (category == .exports) }
    }

    private enum Category: String, CaseIterable, Identifiable {
        case saved = "Saved"
        case offline = "Downloads"
        case imports = "Imports"
        case exports = "Exports"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .saved: "Favorites"
            case .offline: "Offline videos"
            case .imports, .exports: rawValue
            }
        }
        var glyph: SwevoGlyph {
            switch self {
            case .saved: .bookmark
            case .offline: .download
            case .imports: .folder
            case .exports: .edit
            }
        }
    }

    var body: some View {
        GeometryReader { container in
            let showsSidebar = container.size.width >= 620 && !typeSize.isAccessibilitySize && !hasReservedRegion(container)
            let layout = showsSidebar
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 18))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    libraryHeader
                    layout {
                        archiveIndex(sidebar: showsSidebar)
                            .frame(maxWidth: showsSidebar ? 156 : .infinity, alignment: .leading)
                        librarySection
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.swevoPage()
            }
        }.swevoScreenBackground().sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
            .sheet(isPresented: $showingExportMembership) { MembershipView(exportRequired: true) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
            .sheet(item: $removingDownload) { video in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SheetHeading(title: "Remove offline video?") { removingDownload = nil }
                        Text(verbatim: video.clip.title).font(.capture(.headline)).lineLimit(3)
                        LocalizedText("This removes only the offline copy. Your favorite stays saved.")
                            .foregroundStyle(SwevoStyle.secondary)
                        ActionButton(title: "Remove download", primary: false) {
                            offline.remove(video); removingDownload = nil
                        }
                        ActionButton(title: "Keep it") { removingDownload = nil }
                    }.padding(24)
                }.swevoScreenBackground().presentationDetents([.medium, .large])
            }
            .sheet(item: $removing) { movie in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SheetHeading(title: "Delete this local copy?") { removing = nil }
                        Text(verbatim: movie.title).font(.capture(.headline))
                        LocalizedText("The copy in Swevo will be removed. The original in Photos or Files will stay untouched.").foregroundStyle(SwevoStyle.secondary)
                        ActionButton(title: "Delete local copy") { library.delete(movie); removing = nil }
                        ActionButton(title: "Keep it", primary: false) { removing = nil }
                    }.padding(24)
                }.swevoScreenBackground().presentationDetents([.medium, .large])
            }
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            libraryTitle
            Divider().overlay(SwevoStyle.accent.opacity(0.55))
        }.padding(.bottom, 2)
    }

    private var libraryTitle: some View {
        LocalizedText("Shot archive").font(.capture(.title, display: true))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func hasReservedRegion(_ container: GeometryProxy) -> Bool {
        guard #available(iOS 27.1, *) else { return false }
        let bounds = CGRect(origin: .zero, size: container.size)
        let regions = container.reservedRegions(kind: .division) + container.reservedRegions(kind: .occlusion)
        return regions.contains { $0.isActive && bounds.intersects($0.frame) }
    }

    private func archiveIndex(sidebar: Bool) -> some View {
        Group {
            if sidebar {
                VStack(spacing: 0) {
                    ForEach(Category.allCases) { entry in
                        archiveTab(entry)
                        if entry != .exports { Divider().overlay(SwevoStyle.line) }
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(Category.allCases) { archiveTab($0, stacked: true) }
                    }
                    VStack(spacing: 4) {
                        ForEach(Category.allCases) { archiveTab($0) }
                    }
                }
            }
        }.padding(4).background { CaptureSurface(tone: .mist) }
    }

    private func archiveTab(_ entry: Category, stacked: Bool = false) -> some View {
        let selected = category == entry
        let ink = selected ? SwevoStyle.ink : SwevoStyle.paper
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        return Button { filter = entry.rawValue } label: {
            layout {
                Glyph(symbol: entry.glyph, size: 14, tint: selected ? ink : SwevoStyle.accent)
                LocalizedText(entry.title).font(.capture(.footnote, weight: .semibold))
                    .fixedSize(horizontal: stacked, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 9).padding(.vertical, 8).frame(minHeight: stacked ? 58 : 44)
                .foregroundStyle(ink)
                .background(selected ? SwevoStyle.accent : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var librarySection: some View {
        let total = count(in: category)
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: category.title, detail: "\(total) \(total == 1 ? "item" : "items") · On this device")
                .accessibilityAddTraits(.isHeader)
            if category == .offline { DownloadAllowanceSummary() }
            downloadStatus
            switch category {
            case .saved:
                if library.favorites.isEmpty {
                    LibraryEmptyState(title: "Build your shot reference library.", message: "Save tutorials as you watch. Come back to the parts you want to drill.")
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(library.favorites) { clip in favoriteRow(clip) }
                    }
                }
            case .offline:
                if offline.videos.isEmpty {
                    LibraryEmptyState(title: "Available offline",
                                      message: "Download a lesson from its playback options to watch without a connection.")
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(offline.videos) { video in downloadRow(video) }
                    }
                }
            case .imports, .exports:
                if localMovies.isEmpty {
                    LibraryEmptyState(title: category == .exports ? "Ready for your next upload." : "Your practice, in focus.",
                                      message: category == .exports ? "Finish a video or extract its audio in Practice. Your exports will be collected here." : "Choose your camera footage in Practice to keep a local working copy.")
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(localMovies) { movie in movieRow(movie) }
                    }
                }
            }
        }
    }

    private func count(in entry: Category) -> Int {
        switch entry {
        case .saved: library.favorites.count
        case .offline: offline.videos.count
        case .imports: library.movies.lazy.filter { !$0.isExport }.count
        case .exports: library.movies.lazy.filter(\.isExport).count
        }
    }

    @ViewBuilder private var downloadStatus: some View {
        if offline.downloadingID != nil || offline.error != nil {
            VStack(alignment: .leading, spacing: 8) {
                if offline.downloadingID != nil {
                    if let title = offline.currentTitle {
                        Text(verbatim: title).font(.capture(.subheadline, weight: .semibold)).lineLimit(2)
                    }
                    LocalizedText("Downloading · \(Int(offline.progress * 100))%")
                        .font(.capture(.caption)).monospacedDigit()
                    Button("Cancel download") { Task { await offline.cancel() } }
                        .buttonStyle(LibraryActionStyle())
                }
                if let error = offline.error {
                    ErrorNote(message: error)
                    if offline.downloadingID != nil {
                        Button("Retry") { Task { await offline.retryCompletion() } }
                            .buttonStyle(LibraryActionStyle())
                    }
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func favoriteRow(_ clip: LessonClip) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button { player = PlayerRoute(clips: library.favorites, startID: clip.id) } label: {
                HStack(spacing: 10) {
                    playableCover(clip.coverURL, width: 92, height: 56)
                    lessonTitle(clip)
                }.contentShape(Rectangle())
            }.buttonStyle(PressStyle())
            removeButton(.bookmark, title: "Remove saved video") { library.toggle(clip) }
        }
        .modifier(LibraryRowSurface())
    }

    private func playableCover(_ url: URL?, width: CGFloat, height: CGFloat) -> some View {
        MediaCover(url: url)
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: 4))
            .overlay(alignment: .bottomTrailing) {
                Glyph(symbol: .play, size: 15, tint: SwevoStyle.paper)
                    .frame(width: 28, height: 28)
                    .background(SwevoStyle.ink.opacity(0.88), in: RoundedRectangle(cornerRadius: 3))
                    .padding(3).allowsHitTesting(false)
            }.accessibilityHidden(true)
    }

    private func lessonTitle(_ clip: LessonClip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: clip.title).font(.capture(.subheadline, weight: .semibold)).lineLimit(3)
            if !clip.channel.isEmpty {
                Text(verbatim: clip.channel).font(.capture(.caption))
                    .foregroundStyle(SwevoStyle.secondary).lineLimit(2)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func downloadRow(_ video: OfflineVideo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { playDownload(video) } label: {
                HStack(spacing: 12) {
                    itemGlyph(.play)
                    Text(verbatim: video.clip.title).font(.capture(.subheadline, weight: .semibold)).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(PressStyle())
            HStack(spacing: 8) {
                VideoExportEntry(clip: offline.playable(video.clip), compact: true)
                Spacer(minLength: 0)
                removeButton(.close, title: "Remove download") { removingDownload = video }
            }
        }
        .modifier(LibraryRowSurface())
    }

    private func movieRow(_ movie: PracticeRecording) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                itemGlyph(movie.filename.hasSuffix("m4a") ? .sound : movie.isExport ? .download : .feed)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: movie.title).font(.capture(.subheadline, weight: .semibold)).lineLimit(2)
                    LocalizedDateText(date: movie.date).font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                removeButton(.close, title: "Delete local file") { removing = movie }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { movieActions(movie) }
                VStack(alignment: .leading, spacing: 6) { movieActions(movie) }
            }
        }
        .modifier(LibraryRowSurface())
    }

    @ViewBuilder private func movieActions(_ movie: PracticeRecording) -> some View {
        if movie.filename.hasSuffix("m4a") == false {
            Button("Edit") { edit(movie) }.buttonStyle(LibraryActionStyle())
        }
        Button(LocalizedStringKey(sharingMovieID == movie.id ? "Preparing export…" : "Export")) {
            shareMovie(movie)
        }.buttonStyle(LibraryActionStyle()).disabled(sharingMovieID != nil)
    }

    private func itemGlyph(_ symbol: SwevoGlyph) -> some View {
        Glyph(symbol: symbol, size: 19, tint: SwevoStyle.accent)
            .frame(width: 46, height: 46)
            .background(SwevoStyle.raised, in: RoundedRectangle(cornerRadius: 5))
            .accessibilityHidden(true)
    }

    private func removeButton(_ symbol: SwevoGlyph, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Glyph(symbol: symbol, size: 16, tint: SwevoStyle.paper)
                .frame(width: 36, height: 36)
                .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 5))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityLabel(LocalizedStringKey(title))
    }

    private func playDownload(_ video: OfflineVideo) {
        let clips = offline.videos.compactMap { item -> LessonClip? in
            offline.cached(item.id) == nil ? nil : offline.playable(item.clip)
        }
        if clips.contains(where: { $0.id == video.id }) {
            player = PlayerRoute(clips: clips, startID: video.id)
        } else { offline.error = "This download is no longer on this device. Download it again." }
    }

    private func shareMovie(_ movie: PracticeRecording) {
        guard commerce.canExportMedia else {
            showingExportMembership = true
            return
        }
        sharingMovieID = movie.id
        Task {
            defer { sharingMovieID = nil }
            do { sharing = SharedFile(url: try await library.shareFile(for: movie, commerce: commerce)) }
            catch { library.error = error.localizedDescription }
        }
    }
}

private struct LibraryRowSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8).background { CaptureSurface(tone: .mist) }
    }
}

private struct LibraryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.capture(.footnote, display: true))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(SwevoStyle.accent)
            .background(SwevoStyle.raised, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .opacity(!enabled ? 0.58 : configuration.isPressed ? 0.72 : 1)
    }
}

// Uses the existing original bitmap action surfaces; no new system artwork.
struct OfflineDownloadButton: View {
    let clip: LessonClip
    var starting = false
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var downloadGate = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DownloadAllowanceSummary()
            if offline.cached(clip.id) != nil || clip.playbackURL.isFileURL {
                LocalizedText("Available offline").font(.capture(.subheadline)).foregroundStyle(SwevoStyle.accent)
                DownloadCompletionNotice()
            } else if starting || offline.preparingID == clip.id {
                ActionButton(title: "Preparing download…", primary: false, busy: true) { }
                LocalizedText("Preparing download…").font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
            } else if offline.downloadingID == clip.id {
                LocalizedText("Downloading · \(Int(offline.progress * 100))%").font(.capture(.caption))
                ActionButton(title: "Cancel download", primary: false) { Task { await offline.cancel() } }
            } else {
                ActionButton(title: "Download for offline", primary: false) {
                    if quota.mayDownload(clip.id, premium: commerce.premium) {
                        Task { await offline.download(clip) }
                    } else { downloadGate = true }
                }.disabled(offline.busy || clip.playbackURL.isFileURL)
                    .accessibilityIdentifier("player.downloadOffline")
                if offline.isRestoring {
                    LocalizedText("Restoring downloads…").font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                } else if offline.busy {
                    LocalizedText("Another download is in progress.").font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                }
            }
            VideoExportEntry(clip: clip)
            if let error = offline.error {
                ErrorNote(message: error)
                if offline.downloadingID == clip.id {
                    ActionButton(title: "Retry", primary: false) { Task { await offline.retryCompletion() } }
                }
            }
        }.sheet(isPresented: $downloadGate) { MembershipView(rewardKind: .download) }
    }
}

// A separate, always-visible workflow; users need not visit the cache panel.
struct VideoExportEntry: View {
    let clip: LessonClip
    var compact = false
    @State private var showingExport = false
    @EnvironmentObject private var commerce: CommerceStore
    var body: some View {
        Group {
            if compact {
                Button("Export") { showingExport = true }.buttonStyle(LibraryActionStyle())
            } else {
                ActionButton(title: "Export video", primary: false) { showingExport = true }
            }
        }.accessibilityIdentifier("player.openExport")
            .sheet(isPresented: $showingExport) {
                if commerce.canExportMedia { OfflineExportSheet(clip: clip) }
                else { MembershipView(exportRequired: true) }
            }
    }
}

private struct OfflineExportSheet: View {
    let clip: LessonClip
    @Environment(\.dismiss) private var dismiss
    @StateObject private var departure = ExportDeparture()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeading(title: "Export video") { departure.request { dismiss() } }
                Text(verbatim: clip.title).font(.capture(.subheadline)).lineLimit(2)
                OfflineExportButton(clip: clip)
            }.padding(22)
        }.swevoScreenBackground().presentationDetents([.medium, .large])
            .environmentObject(departure)
            .modifier(ExportDepartureProtection(departure: departure))
    }
}

// One owner for the close button, explicit cancel and interactive dismissal.
@MainActor
final class ExportDeparture: ObservableObject {
    @Published private(set) var running = false
    @Published var confirming = false
    private var cancellation: (() -> Void)?
    private var afterCancellation: (() -> Void)?
    func begin(cancel: @escaping () -> Void) { running = true; cancellation = cancel }
    func finish() {
        running = false; cancellation = nil
        confirming = false; afterCancellation = nil
    }
    func request(_ close: @escaping () -> Void = {}) {
        guard running else { close(); return }
        afterCancellation = close; confirming = true
    }
    func keepWorking() { confirming = false; afterCancellation = nil }
    func stop() {
        let close = afterCancellation
        cancellation?()
        confirming = false; afterCancellation = nil
        close?()
    }
}

struct ExportDepartureProtection: ViewModifier {
    @ObservedObject var departure: ExportDeparture
    func body(content: Content) -> some View {
        content.interactiveDismissDisabled(departure.running)
            .accessibilityHidden(departure.confirming)
            .overlay {
                if departure.confirming {
                    GeometryReader { container in
                        ScrollView {
                            VStack(spacing: 18) {
                                LocalizedText("Stop this export?").font(.capture(.headline))
                                LocalizedText("The export is still in progress. Leaving now cancels it. Your video stays safe.")
                                    .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                ActionButton(title: "Keep exporting", action: departure.keepWorking)
                                ActionButton(title: "Stop export", primary: false, action: departure.stop)
                            }.padding(22).frame(maxWidth: 360)
                                .background { CaptureSurface(tone: .plum) }.padding(20)
                                .frame(maxWidth: .infinity, minHeight: container.size.height)
                        }.background(.black.opacity(0.7))
                            .accessibilityAddTraits(.isModal)
                    }
                }
            }
    }
}

struct DownloadCompletionNotice: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        Group {
            if offline.completedDownloadID != nil {
                HStack(spacing: 12) {
                    LocalizedText("Downloaded. Watch offline in Library.")
                        .font(.capture(.caption)).fixedSize(horizontal: false, vertical: true)
                    Button("View") {
                        offline.completedDownloadID = nil
                        library.openDownloads()
                    }.buttonStyle(CompactActionStyle())
                    IconButton(symbol: .close, label: "Dismiss message") { offline.completedDownloadID = nil }
                }.padding(12).foregroundStyle(SwevoStyle.paper)
                    .background { CaptureSurface(tone: .plum) }
                    .padding(.horizontal, 12)
            }
        }.task(id: offline.completedDownloadID) {
            guard let notice = offline.completedDownloadID else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            if offline.completedDownloadID == notice { offline.completedDownloadID = nil }
        }
    }
}

// Uncached exports use the same download admission and completion journal.
// Export is a Plus benefit; cached copies still pass the membership check.
private struct OfflineExportButton: View {
    let clip: LessonClip
    @EnvironmentObject private var departure: ExportDeparture
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var downloadGate = false
    @State private var preparingSource = false
    @State private var exportTask: Task<Void, Never>?
    @State private var sharing: SharedFile?
    @State private var exportError: String?
    @State private var exportedFile: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActionButton(title: preparingSource ? "Preparing export…" : exportTask == nil ? "Export video" : "Exporting…",
                         primary: false, busy: exportTask != nil, action: startExport)
                .accessibilityIdentifier("player.exportVideo")
            if !clip.playbackURL.isFileURL, offline.cached(clip.id) == nil {
                LocalizedText("We download the video before exporting. Existing downloads are reused.")
                    .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                DownloadAllowanceSummary()
            }
            if preparingSource, offline.downloadingID == clip.id {
                LocalizedText("Downloading · \(Int(offline.progress * 100))%").font(.capture(.caption))
            }
            if exportTask != nil {
                Button("Cancel export") { departure.request() }.buttonStyle(CompactActionStyle())
            }
            if let exportError { ErrorNote(message: exportError) }
        }
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $downloadGate) { MembershipView(exportRequired: true) }
        .onDisappear { exportTask?.cancel() }
    }

    private func startExport() {
        guard exportTask == nil else { return }
        guard commerce.canExportMedia else { downloadGate = true; return }
        if !clip.playbackURL.isFileURL, offline.cached(clip.id) == nil,
           !quota.mayDownload(clip.id, premium: commerce.premium) {
            downloadGate = true
            return
        }
        if let exportedFile, FileManager.default.fileExists(atPath: exportedFile.path) {
            sharing = SharedFile(url: exportedFile); return
        }
        exportError = nil
        exportTask = Task { @MainActor in
            defer { exportTask = nil; preparingSource = false; departure.finish() }
            var ownsDownload = false
            var converted: URL?
            defer { if let converted { try? FileManager.default.removeItem(at: converted) } }
            do {
                try commerce.requireMediaExport()
                var source = clip.playbackURL
                if !source.isFileURL || offline.cached(clip.id)?.isHLS == true {
                    preparingSource = true
                    // A cache request may already be finishing for this clip.
                    // Let it finish, then decide whether its result is a file
                    // or whether the original-file download is still needed.
                    if offline.downloadingID == clip.id {
                        for await downloadID in offline.$downloadingID.values {
                            try Task.checkCancellation()
                            if downloadID != clip.id { break }
                        }
                    }
                    try Task.checkCancellation()
                    if offline.cached(clip.id)?.isHLS != false, offline.downloadingID != clip.id {
                        guard !offline.busy else { throw SwevoError.service("Another download is in progress.") }
                        ownsDownload = true
                        await offline.download(clip, forExport: true)
                    }
                    // Subscribe to the shared download state, including its
                    // current value, so a very fast completion is not missed.
                    for await downloadID in offline.$downloadingID.values {
                        try Task.checkCancellation()
                        if let cached = offline.cached(clip.id), !cached.isHLS { source = cached.url; break }
                        guard downloadID == clip.id else {
                            throw SwevoError.service(offline.error ?? "Download failed. No download allowance was used.")
                        }
                    }
                    try Task.checkCancellation()
                    guard source.isFileURL else { throw SwevoError.storage }
                    preparingSource = false
                }
                var output = source
                if !["mp4", "mov", "m4v"].contains(source.pathExtension.lowercased()) {
                    let asset = AVURLAsset(url: source)
                    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
                          session.supportedFileTypes.contains(.mp4) else {
                        throw SwevoError.service("This video format cannot be exported. Please use an MP4 or MOV file.")
                    }
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                    converted = destination
                    session.outputURL = destination
                    session.outputFileType = .mp4
                    await withTaskCancellationHandler {
                        await withCheckedContinuation { continuation in
                            session.exportAsynchronously { continuation.resume() }
                        }
                    } onCancel: { session.cancelExport() }
                    try Task.checkCancellation()
                    guard session.status == .completed else {
                        throw SwevoError.service("Video export failed. Please try again.")
                    }
                    output = destination
                }
                try Task.checkCancellation()
                try commerce.requireMediaExport()
                let recording = try await library.importMovie(output, exported: true, title: clip.title)
                let url = try await library.shareFile(for: recording, commerce: commerce)
                exportedFile = url
                if !Task.isCancelled { sharing = SharedFile(url: url) }
            } catch is CancellationError {
                if ownsDownload, offline.downloadingID == clip.id { await offline.cancel() }
            }
            catch {
                exportError = error.localizedDescription
            }
        }
        departure.begin { exportTask?.cancel() }
    }
}

// Shared, live allowance display at the download decision and in the offline library.
struct DownloadAllowanceSummary: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingReward = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("Downloads left").font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
            LocalizedText(api.session == nil ? "Connect to refresh your allowance." :
                            commerce.premium || quota.downloadsUnlimited ? "Unlimited" :
                            quota.usage == nil ? "Loading…" : "\(quota.downloadsLeft) downloads left today")
                .font(.capture(.subheadline, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if quota.usage != nil, !commerce.premium { AllowanceResetText() }
            if quota.canRequestReward(for: .download, premium: commerce.premium) {
                ActionButton(title: "Get more downloads", primary: false) { showingReward = true }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background { CaptureSurface(tone: .plum) }
            .accessibilityElement(children: .contain)
            .onAppear { quota.resetIfNeeded() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in quota.resetIfNeeded() }
            .sheet(isPresented: $showingReward) { MembershipView(rewardKind: .download) }
    }
}

private struct LibraryEmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            LocalizedText(title).font(.capture(.headline))
            LocalizedText(message).font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.multilineTextAlignment(.center).padding(.horizontal, 12).padding(.vertical, 24)
            .frame(maxWidth: .infinity)
    }
}
