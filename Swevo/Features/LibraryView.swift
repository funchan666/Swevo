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
    let openTools: () -> Void
    let openPlus: () -> Void
    @Binding var filter: String
    @Binding var importing: Bool
    @State private var player: PlayerRoute?
    @State private var sharing: SharedFile?
    @State private var removing: PracticeRecording?
    @State private var removingDownload: OfflineVideo?
    @State private var sharingMovieID: UUID?
    @State private var editingDownloadID: String?
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
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
            case .imports: "EmptyImports"
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
            case .imports: "Your original stays untouched."
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
            let width = min(640, SwevoStyle.pageContentWidth(in: container))
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let headerBounds = CGRect(x: 0, y: 0, width: container.size.width, height: 72)
            let stackedHeader = width < 352 || typeSize > .xLarge
                || SwevoStyle.intersectsReservedRegion(headerBounds, in: container)
            VStack(alignment: .leading, spacing: 16) {
                libraryHeader(stacked: stackedHeader)
                if query.isEmpty {
                    libraryContents(in: container, width: width)
                } else {
                    searchResults(for: query, stackedRows: width < 285 || typeSize.isAccessibilitySize)
                }
            }
        }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnOutsideTap($searchFocused, scope: "library-search")
            .onDisappear { searchFocused = false }
            .onChange(of: filter) { _, _ in endSearch() }
            .onChange(of: library.downloadsRequest) { _, _ in endSearch() }
            .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
            .fullScreenCover(isPresented: $showingExportMembership) { MembershipView(exportRequired: true) }
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
                        LocalizedText("This deletes the selected copy from your Kstep library.")
                            .foregroundStyle(SwevoStyle.secondary)
                        ActionButton(title: "Delete local copy") { library.delete(movie); removing = nil }
                        ActionButton(title: "Cancel", primary: false) { removing = nil }
                    }.padding(24)
                }.swevoScreenBackground().presentationDetents([.medium, .large])
            }
    }

    private func libraryHeader(stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                             : AnyLayout(HStackLayout(spacing: 8))
        let tools = toolsEntry.fixedSize(horizontal: !stacked, vertical: false)
        let plus = PlusEntryButton(action: openPlus)
            .fixedSize(horizontal: !stacked, vertical: false)
        return layout {
            HStack(spacing: 8) {
                librarySearch
                if !stacked { tools }
            }
            HStack(spacing: 8) {
                if stacked {
                    tools
                    Spacer(minLength: 0)
                }
                plus
            }
        }
    }

    private var toolsEntry: some View {
        Button {
            searchFocused = false
            openTools()
        } label: {
            HStack(spacing: 6) {
                Glyph(symbol: .edit, size: 16, tint: SwevoStyle.accent)
                LocalizedText("Tools").font(.capture(.footnote, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(SwevoStyle.paper)
            .background { Capsule().strokeBorder(SwevoStyle.line).padding(.vertical, 4) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(importing)
        .accessibilityIdentifier("library.tools")
    }

    private var librarySearch: some View {
        HStack(spacing: 0) {
            Button { searchFocused = true } label: {
                Glyph(symbol: .search, size: 17, tint: SwevoStyle.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHidden(true)
            TextField("Search files", text: $searchQuery,
                      prompt: Text("Search files").foregroundStyle(SwevoStyle.secondary))
                .font(.capture(.subheadline))
                .foregroundStyle(SwevoStyle.paper)
                .tint(SwevoStyle.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.trailing, searchQuery.isEmpty ? 12 : 0)
                .accessibilityLabel("Search files")
                .accessibilityIdentifier("library.search")
            if !searchQuery.isEmpty {
                IconButton(symbol: .close, label: "Clear search") { searchQuery = "" }
            }
        }
        .swevoGlass(cornerRadius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(searchFocused ? SwevoStyle.accent : .clear)
                .allowsHitTesting(false)
        }
        .keyboardInputRegion("library-search")
        .layoutPriority(1)
    }

    private func endSearch() {
        searchQuery = ""
        searchFocused = false
    }

    private func libraryContents(in container: GeometryProxy, width: CGFloat) -> some View {
        let bounds = CGRect(origin: .zero, size: container.size)
        let showsSidebar = width >= 560 && typeSize <= .xLarge
            && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
        let sidebarWidth: CGFloat = 156
        let gap: CGFloat = 24
        let sectionWidth = showsSidebar ? width - sidebarWidth - gap : width
        let layout = showsSidebar
            ? AnyLayout(HStackLayout(alignment: .top, spacing: gap))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        return layout {
            archiveIndex(sidebar: showsSidebar)
                .frame(maxWidth: showsSidebar ? sidebarWidth : .infinity, alignment: .leading)
            librarySection(in: container, columnWidth: showsSidebar ? sectionWidth : nil,
                           stackedRows: sectionWidth < 285 || typeSize.isAccessibilitySize)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func searchResults(for query: String, stackedRows: Bool) -> some View {
        let movies = library.movies.filter { $0.displayFilename.localizedStandardContains(query) }
        let downloads = offline.videos.filter { $0.displayFilename.localizedStandardContains(query) }
        let favorites = library.favorites.filter { $0.title.localizedStandardContains(query) }

        return LazyVStack(alignment: .leading, spacing: 0) {
            if offline.busy || !downloads.isEmpty { downloadStatus }
            if movies.isEmpty, downloads.isEmpty, favorites.isEmpty, !offline.isRestoring {
                VStack(alignment: .leading, spacing: 6) {
                    LocalizedText("No matches").font(.capture(.headline))
                        .accessibilityAddTraits(.isHeader)
                    LocalizedText("Try a different name.").font(.capture(.subheadline))
                        .foregroundStyle(SwevoStyle.secondary)
                    Button("Clear search", action: endSearch)
                        .buttonStyle(LibraryActionStyle())
                        .padding(.top, 4)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 16)
            }
            searchSection(.imports, items: movies.filter { !$0.isExport }) { movieRow($0, stacked: stackedRows) }
            searchSection(.offline, items: downloads) { downloadRow($0, stacked: stackedRows) }
            searchSection(.exports, items: movies.filter(\.isExport)) { movieRow($0, stacked: stackedRows) }
            searchSection(.saved, items: favorites) { favoriteRow($0, stacked: stackedRows) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func searchSection<Item: Identifiable, Row: View>(
        _ category: Category, items: [Item], @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items, content: row)
            } header: {
                HStack(spacing: 8) {
                    Glyph(symbol: category.glyph, size: 15, tint: SwevoStyle.secondary)
                    LocalizedText(category.title).font(.capture(.headline))
                }
                .padding(.top, 14)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private func archiveIndex(sidebar: Bool) -> some View {
        let rows = VStack(spacing: 0) {
            ForEach(Category.allCases) { entry in archiveTab(entry, vertical: true) }
        }
        return Group {
            if sidebar || typeSize.isAccessibilitySize {
                rows
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Category.allCases) { entry in archiveTab(entry, vertical: false) }
                    }
                    .background(alignment: .bottom) {
                        Rectangle().fill(SwevoStyle.line).frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    rows
                }
            }
        }
    }

    private func archiveTab(_ entry: Category, vertical: Bool) -> some View {
        let selected = category == entry
        let glyph = Glyph(symbol: entry.glyph, size: 15, tint: selected ? SwevoStyle.accent : SwevoStyle.secondary)
        let title = LocalizedText(entry.title)
            .font(.capture(.footnote, weight: .semibold))
            .fixedSize(horizontal: !vertical, vertical: true)
        let countText = Text(count(in: entry), format: .number)
        let total = countText
            .font(.capture(.caption, weight: .medium)).monospacedDigit()
            .foregroundStyle(selected ? SwevoStyle.accent : SwevoStyle.secondary)
        return Button { filter = entry.rawValue } label: {
            Group {
                if vertical {
                    HStack(spacing: 8) {
                        glyph
                        title
                        Spacer(minLength: 0)
                        total
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        title
                        HStack(spacing: 5) {
                            total
                            Spacer(minLength: 0)
                            glyph
                        }
                    }
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: vertical ? 48 : 58, alignment: .leading)
            .foregroundStyle(selected ? SwevoStyle.accent : SwevoStyle.paper)
            .overlay(alignment: .bottom) {
                if selected || vertical {
                    Rectangle().fill(selected ? SwevoStyle.accent : SwevoStyle.line)
                        .frame(height: selected ? 2 : 1)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityLabel(LocalizedStringKey(entry.title))
            .accessibilityValue(countText)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func librarySection(in container: GeometryProxy, columnWidth: CGFloat?, stackedRows: Bool) -> some View {
        let empty = showsEmptyState
        return VStack(alignment: .leading, spacing: 16) {
            if empty || category == .imports {
                sectionIntro(empty: empty, in: container, columnWidth: columnWidth, stacked: stackedRows)
            }
            switch category {
            case .saved:
                LazyVStack(spacing: 0) {
                    ForEach(library.favorites) { clip in favoriteRow(clip, stacked: stackedRows) }
                }
            case .offline:
                downloadStatus
                LazyVStack(spacing: 0) {
                    ForEach(offline.videos) { video in downloadRow(video, stacked: stackedRows) }
                }
                DownloadAllowanceSummary()
            case .imports, .exports:
                LazyVStack(spacing: 0) {
                    ForEach(localMovies) { movie in movieRow(movie, stacked: stackedRows) }
                }
            }
        }
    }

    private func sectionIntro(empty: Bool, in container: GeometryProxy, columnWidth: CGFloat?, stacked: Bool) -> some View {
        let artwork = category.emptyArtwork
        let width = columnWidth ?? min(container.size.width, 680)
        let artworkHeight = empty && ArtworkCatalog.has(artwork)
            ? min(164, width * 0.42, container.size.height * 0.28) : 0

        return VStack(alignment: .leading, spacing: 16) {
            if empty {
                VStack(alignment: .leading, spacing: 6) {
                    SceneTitle(category.emptyTitle, size: 26)
                    LocalizedText(category.emptyMessage).font(.capture(.subheadline))
                        .foregroundStyle(SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 380, alignment: .leading)
            }
            if category == .imports {
                VideoImportActions(onImported: edit, importing: $importing,
                                   presentation: empty ? .sourcePair(stacked: stacked) : .library(stacked: stacked))
            } else if category.opensOnlineVideos {
                EmptyStateAction(title: "Browse videos", symbol: .play, primary: true, action: browseVideos)
            } else {
                EmptyStateAction(title: "Edit a video", symbol: .edit, primary: true, action: openEditor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, artworkHeight * 0.76)
        .background(alignment: .top) {
            if artworkHeight > 0 {
                SceneImage(name: artwork)
                    .frame(width: columnWidth == nil ? width : nil, height: artworkHeight)
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.18),
                            .init(color: .black, location: 0.50),
                            .init(color: .black.opacity(0.25), location: 0.76),
                            .init(color: .clear, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .mask {
                        if columnWidth != nil || width < container.size.width {
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.12),
                                .init(color: .black, location: 0.90),
                                .init(color: .clear, location: 1)
                            ], startPoint: .leading, endPoint: .trailing)
                        } else {
                            Color.black
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
                .swevoGlass(cornerRadius: 16)
        }
    }

    private func favoriteRow(_ clip: LessonClip, stacked: Bool) -> some View {
        let url = offline.cached(clip.id)?.url ?? clip.playbackURL
        return HStack(spacing: 4) {
            Button { player = PlayerRoute(clips: library.favorites, startID: clip.id) } label: {
                fileLabel(clip.title, stacked: stacked,
                          thumbnail: VideoFileThumbnail(url: url, maximumSize: 480, fallbackCover: clip.coverURL),
                          actionGlyph: .play) {
                    if let channel = clip.channel.nilIfBlank { Text(verbatim: channel) }
                }
            }.buttonStyle(PressStyle())
            IconButton(symbol: .bookmark, label: "Remove from favorites") { library.toggle(clip) }
        }
        .modifier(LibraryRowSurface())
    }

    private func fileLabel<Detail: View>(_ filename: String, stacked: Bool, thumbnail: VideoFileThumbnail,
                                         actionGlyph: SwevoGlyph? = nil, @ViewBuilder detail: () -> Detail) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                             : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            thumbnail
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: stacked ? 160 : 116)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    if let actionGlyph {
                        Glyph(symbol: actionGlyph, size: 12, tint: SwevoStyle.paper)
                            .frame(width: 26, height: 26)
                            .background(SwevoStyle.ink.opacity(0.88), in: RoundedRectangle(cornerRadius: 5))
                            .padding(4).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: filename)
                    .font(.capture(.headline)).foregroundStyle(SwevoStyle.paper)
                detail()
                    .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func downloadRow(_ video: OfflineVideo, stacked: Bool) -> some View {
        let available = video.hasLocalFile
        let actionsLayout = stacked || typeSize > .xLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 2) {
            Button { playDownload(video) } label: {
                fileLabel(video.displayFilename, stacked: stacked,
                          thumbnail: VideoFileThumbnail(url: video.url, maximumSize: 480, fallbackCover: video.clip.coverURL),
                          actionGlyph: available ? .play : nil) {
                    LocalizedText(available ? "Available offline" : "Download needed")
                }
            }.buttonStyle(PressStyle())
            HStack(alignment: .bottom, spacing: 8) {
                if available {
                    actionsLayout { downloadActions(video) }
                } else {
                    Button("Download again") { Task { await offline.download(video.clip) } }
                        .buttonStyle(LibraryActionStyle()).disabled(offline.busy)
                }
                Spacer(minLength: 0)
                IconButton(symbol: .close, label: "Remove download") { removingDownload = video }
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

    private func movieRow(_ movie: PracticeRecording, stacked: Bool) -> some View {
        let thumbnail = VideoFileThumbnail(url: library.url(for: movie), maximumSize: 480, isAudio: movie.isAudio)
        let label = fileLabel(movie.displayFilename, stacked: stacked, thumbnail: thumbnail,
                              actionGlyph: movie.isAudio ? nil : .edit) {
            LocalizedDateText(date: movie.date)
        }
        return VStack(alignment: .leading, spacing: 2) {
            if movie.isAudio {
                label
            } else {
                Button { edit(movie) } label: { label }.buttonStyle(PressStyle())
            }
            HStack(spacing: 8) {
                Button(LocalizedStringKey(sharingMovieID == movie.id ? "Preparing export…" : "Share")) { shareMovie(movie) }
                    .buttonStyle(LibraryActionStyle()).disabled(sharingMovieID != nil)
                Spacer(minLength: 0)
                IconButton(symbol: .close, label: "Delete local file") { removing = movie }
            }
        }
        .modifier(LibraryRowSurface())
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
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(SwevoStyle.line).frame(height: 1)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

private struct LibraryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.capture(.footnote, weight: .semibold))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .foregroundStyle(SwevoStyle.accent)
            .background(configuration.isPressed ? SwevoStyle.raised : .clear, in: RoundedRectangle(cornerRadius: 8))
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
        }.fullScreenCover(isPresented: $downloadGate) { MembershipView(rewardKind: .download) }
    }
}

// A separate, always-visible workflow; users need not visit the cache panel.
struct VideoExportEntry: View {
    let clip: LessonClip
    var compact = false
    @State private var showingExport = false
    @State private var showingMembership = false
    @EnvironmentObject private var commerce: CommerceStore
    var body: some View {
        Group {
            if compact {
                Button("Export", action: openExport).buttonStyle(LibraryActionStyle())
            } else {
                ActionButton(title: "Export video", primary: false, action: openExport)
            }
        }.accessibilityIdentifier("player.openExport")
            .sheet(isPresented: $showingExport) { OfflineExportSheet(clip: clip) }
            .fullScreenCover(isPresented: $showingMembership, onDismiss: {
                if commerce.canExportMedia { showingExport = true }
            }) {
                MembershipView(exportRequired: true)
            }
    }

    private func openExport() {
        if commerce.canExportMedia { showingExport = true }
        else { showingMembership = true }
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
        .fullScreenCover(isPresented: $downloadGate) { MembershipView(exportRequired: true) }
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
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingReward = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AllowanceStatusPanel(kinds: [.download])
            if quota.canRequestReward(for: .download, premium: commerce.premium) {
                ActionButton(title: "Get more downloads", primary: false) { showingReward = true }
            }
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .fullScreenCover(isPresented: $showingReward) { MembershipView(rewardKind: .download) }
    }
}
