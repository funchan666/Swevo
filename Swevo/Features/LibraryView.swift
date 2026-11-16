import SwiftUI
import AVFoundation

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingExportMembership = false
    var edit: (PracticeRecording) -> Void
    var browseVideos: () -> Void
    var openEditor: () -> Void
    @Binding var filter: String
    @Binding var importing: Bool
    @State private var player: PlayerRoute?
    @State private var sharing: SharedFile?
    @State private var removing: PracticeRecording?
    @State private var removingDownload: OfflineVideo?
    @State private var sharingMovieID: UUID?
    @State private var editingDownloadID: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var category: Category { Category(rawValue: filter) ?? .imports }
    private var localMovies: [PracticeRecording] {
        category == .exports ? library.movies.filter(\.isExport) : library.importedMovies
    }

    private enum Category: String, CaseIterable, Identifiable {
        case imports = "Imports"
        case offline = "Downloads"
        case exports = "Exports"
        case saved = "Saved"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .saved: "Favorites"
            case .offline: "Offline"
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
        var emptyArtwork: String {
            switch self {
            case .saved: "EmptyFavorites"
            case .offline: "EmptyOffline"
            case .imports: "SceneArchive"
            case .exports: "EmptyExports"
            }
        }
        var emptyTitle: String {
            switch self {
            case .saved: "No favorites yet"
            case .offline: "No offline videos yet"
            case .imports: "Import a video"
            case .exports: "No exports yet"
            }
        }
        var emptyMessage: String {
            switch self {
            case .saved: "Save a video while watching to find it here."
            case .offline: "Download a video to watch it without a connection."
            case .imports: "Swevo makes a copy for editing."
            case .exports: "Videos and audio you export from the editor appear here."
            }
        }
        var opensOnlineVideos: Bool { self == .saved || self == .offline }
    }

    private var showsEmptyState: Bool {
        guard count(in: category) == 0 else { return false }
        if category == .offline {
            return !offline.busy && offline.error == nil
        }
        return library.error == nil
    }

    var body: some View {
        ScenePage { container in
            let width = SwevoStyle.pageContentWidth(in: container)
            let bounds = CGRect(origin: .zero, size: container.size)
            let showsSidebar = width >= 560 && !typeSize.isAccessibilitySize
                && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
            let layout = showsSidebar
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 26))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            layout {
                archiveIndex(vertical: showsSidebar || typeSize.isAccessibilitySize)
                    .frame(maxWidth: showsSidebar ? 176 : .infinity, alignment: .leading)
                librarySection(artworkWidth: showsSidebar ? nil : container.size.width,
                               artworkHeight: min(224, max(128, container.size.height * 0.34)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
            .sheet(isPresented: $showingExportMembership) { MembershipView(exportRequired: true) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
            .sheet(item: $removingDownload) { video in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SheetHeading(title: "Remove offline video?") { removingDownload = nil }
                        Text(verbatim: video.clip.title).font(.capture(.headline)).lineLimit(3)
                        LocalizedText("This removes the download from this device.")
                            .foregroundStyle(SwevoStyle.secondary)
                        ActionButton(title: "Remove download", primary: false) {
                            offline.remove(video); removingDownload = nil
                        }
                        ActionButton(title: "Cancel") { removingDownload = nil }
                    }.padding(24)
                }.swevoScreenBackground().presentationDetents([.medium, .large])
            }
            .sheet(item: $removing) { movie in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SheetHeading(title: "Delete this local copy?") { removing = nil }
                        Text(verbatim: movie.displayFilename).font(.capture(.headline))
                        LocalizedText("This deletes the selected copy from your Swevo library.")
                            .foregroundStyle(SwevoStyle.secondary)
                        ActionButton(title: "Delete local copy") { library.delete(movie); removing = nil }
                        ActionButton(title: "Cancel", primary: false) { removing = nil }
                    }.padding(24)
                }.swevoScreenBackground().presentationDetents([.medium, .large])
            }
    }

    private func archiveIndex(vertical: Bool) -> some View {
        Group {
            if vertical {
                VStack(spacing: 0) {
                    ForEach(Category.allCases) { entry in archiveTab(entry, vertical: true) }
                }
            } else {
                ScrollViewReader { scroll in
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                            ForEach(Category.allCases) { entry in
                                archiveTab(entry, vertical: false).id(entry.id)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .onChange(of: category, initial: true) { _, entry in
                        scroll.scrollTo(entry.id, anchor: .center)
                    }
                }
            }
        }
        .background(alignment: vertical ? .leading : .bottom) {
            Rectangle().fill(SwevoStyle.line)
                .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func archiveTab(_ entry: Category, vertical: Bool) -> some View {
        let selected = category == entry
        let total = count(in: entry)
        return Button { filter = entry.rawValue } label: {
            HStack(spacing: 6) {
                if vertical {
                    Glyph(symbol: entry.glyph, size: 15, tint: selected ? SwevoStyle.accent : SwevoStyle.secondary)
                }
                LocalizedText(entry.title)
                    .font(.capture(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if vertical { Spacer(minLength: 0) }
                if total > 0 {
                    Text(total, format: .number)
                        .font(.capture(.caption)).monospacedDigit()
                        .foregroundStyle(SwevoStyle.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(minWidth: 44, maxWidth: vertical ? .infinity : nil, minHeight: 48,
                   alignment: vertical ? .leading : .center)
            .foregroundStyle(selected ? SwevoStyle.accent : SwevoStyle.paper)
            .overlay(alignment: vertical ? .leading : .bottom) {
                if selected {
                    Rectangle().fill(SwevoStyle.accent)
                        .frame(width: vertical ? 2 : nil, height: vertical ? nil : 2)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func librarySection(artworkWidth: CGFloat?, artworkHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsEmptyState {
                emptyContent(artworkWidth: artworkWidth, artworkHeight: artworkHeight)
            }
            if category == .imports {
                VideoImportActions(onImported: edit, importing: $importing, presentation: .library)
                    .padding(.bottom, 4)
            }
            if category == .offline {
                DownloadAllowanceSummary()
                downloadStatus
            }
            switch category {
            case .saved:
                LazyVStack(spacing: 6) {
                    ForEach(library.favorites) { clip in favoriteRow(clip) }
                }
            case .offline:
                LazyVStack(spacing: 6) {
                    ForEach(offline.videos) { video in downloadRow(video) }
                }
            case .imports, .exports:
                LazyVStack(spacing: 6) {
                    ForEach(localMovies) { movie in movieRow(movie) }
                }
            }
        }
    }

    private func emptyContent(artworkWidth: CGFloat?, artworkHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SceneTitle(category.emptyTitle, size: 34)
            EmptyStateCopy(message: category.emptyMessage)
            if category.opensOnlineVideos {
                EmptyStateAction(title: "Browse videos", symbol: .play, action: browseVideos)
            } else if category == .exports {
                EmptyStateAction(title: "Open editor", symbol: .edit, action: openEditor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, artworkHeight * 0.8)
        .background(alignment: .top) {
            SceneArtwork(name: category.emptyArtwork)
                .frame(width: artworkWidth, height: artworkHeight)
                .opacity(0.94)
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
        if offline.busy || offline.error != nil {
            VStack(alignment: .leading, spacing: 8) {
                if offline.downloadingID != nil {
                    if let title = offline.currentTitle {
                        Text(verbatim: title).font(.capture(.subheadline, weight: .semibold)).lineLimit(2)
                    }
                    LocalizedText("Downloading · \(Int(offline.progress * 100))%")
                        .font(.capture(.caption)).monospacedDigit()
                    Button("Cancel download") { Task { await offline.cancel() } }
                        .buttonStyle(LibraryActionStyle())
                } else if offline.busy {
                    HStack(spacing: 9) {
                        ProgressView().tint(SwevoStyle.accent).accessibilityHidden(true)
                        LocalizedText(offline.isRestoring ? "Restoring downloads…" : "Preparing download…")
                            .font(.capture(.subheadline))
                    }
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
            removeButton(.bookmark, title: "Remove from favorites") { library.toggle(clip) }
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
        let available = video.hasLocalFile
        return VStack(alignment: .leading, spacing: 6) {
            Button { playDownload(video) } label: {
                HStack(spacing: 12) {
                    VideoFileThumbnail(url: video.url, fallbackCover: video.clip.coverURL)
                        .frame(width: 72, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: video.displayFilename).font(.capture(.subheadline, weight: .semibold))
                        LocalizedText(available ? "Available offline" : "Download needed")
                            .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }.contentShape(Rectangle())
            }.buttonStyle(PressStyle())
            HStack(spacing: 8) {
                if available {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { downloadActions(video) }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) { downloadActions(video) }
                    }
                } else {
                    Button("Download again") { Task { await offline.download(video.clip) } }
                        .buttonStyle(LibraryActionStyle()).disabled(offline.busy)
                }
                Spacer(minLength: 0)
                removeButton(.close, title: "Remove download") { removingDownload = video }
            }
        }
        .modifier(LibraryRowSurface())
    }

    @ViewBuilder private func downloadActions(_ video: OfflineVideo) -> some View {
        VideoExportEntry(clip: offline.playable(video.clip), compact: true)
        if !video.isHLS {
            Button(LocalizedStringKey(editingDownloadID == video.id ? "Importing…" : "Edit video")) {
                editDownload(video)
            }.buttonStyle(LibraryActionStyle()).disabled(importing)
        }
    }

    private func editDownload(_ video: OfflineVideo) {
        guard !importing else { return }
        guard let stored = offline.cached(video.id), !stored.isHLS else {
            offline.error = "This download is no longer on this device. Download it again."
            return
        }
        editingDownloadID = video.id
        importing = true
        Task {
            defer { editingDownloadID = nil; importing = false }
            do {
                let copy = try await library.importMovie(stored.url, title: stored.clip.title)
                edit(copy)
            } catch { library.error = error.localizedDescription }
        }
    }

    private func movieRow(_ movie: PracticeRecording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                if movie.isAudio {
                    HStack(spacing: 12) {
                        VideoFileThumbnail(url: library.url(for: movie), isAudio: true)
                            .frame(width: 64, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(verbatim: movie.displayFilename)
                            .font(.capture(.subheadline, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VideoFileButton(url: library.url(for: movie), filename: movie.displayFilename, date: movie.date) { edit(movie) }
                }
                removeButton(.close, title: "Delete local file") { removing = movie }
            }
            Button(LocalizedStringKey(sharingMovieID == movie.id ? "Preparing export…" : "Share")) { shareMovie(movie) }
                .buttonStyle(LibraryActionStyle()).disabled(sharingMovieID != nil)
        }
        .modifier(LibraryRowSurface())
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
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(SwevoStyle.line).frame(height: 1).allowsHitTesting(false) }
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
            .background(SwevoStyle.raised, in: RoundedRectangle(cornerRadius: 10))
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
                ActionButton(title: "Download for offline viewing", primary: false) {
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
                Text(verbatim: clip.title).font(.capture(.subheadline)).fixedSize(horizontal: false, vertical: true)
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
                    LocalizedText("Ready to watch offline")
                        .font(.capture(.caption)).fixedSize(horizontal: false, vertical: true)
                    Button("View") {
                        offline.completedDownloadID = nil
                        library.openDownloads()
                    }.buttonStyle(CompactActionStyle())
                        .accessibilityLabel(LocalizedStringKey("View offline videos"))
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
    @State private var savedExport: PracticeRecording?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let savedExport {
                SavedVideoExport(movie: savedExport, sharing: exportTask != nil) {
                    shareExport(savedExport)
                }
            } else {
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
            }
            if let exportError { ErrorNote(message: exportError) }
        }
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $downloadGate) { MembershipView(exportRequired: true) }
        .onDisappear { exportTask?.cancel() }
    }

    private func shareExport(_ recording: PracticeRecording) {
        guard exportTask == nil else { return }
        guard commerce.canExportMedia else { downloadGate = true; return }
        exportError = nil
        exportTask = Task {
            defer { exportTask = nil }
            do {
                let url = try await library.shareFile(for: recording, commerce: commerce)
                if !Task.isCancelled { sharing = SharedFile(url: url) }
            } catch is CancellationError { }
            catch { exportError = error.localizedDescription }
        }
    }

    private func startExport() {
        guard exportTask == nil else { return }
        guard commerce.canExportMedia else { downloadGate = true; return }
        if !clip.playbackURL.isFileURL, offline.cached(clip.id) == nil,
           !quota.mayDownload(clip.id, premium: commerce.premium) {
            downloadGate = true
            return
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
                if !Task.isCancelled { savedExport = recording }
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
