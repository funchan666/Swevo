import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var importing: Bool
    let edit: (PracticeRecording) -> Void
    let review: (PracticeRecording) -> Void
    let openLibrary: () -> Void
    let openCameraMoves: () -> Void
    let openPlus: () -> Void
    @SceneStorage("home.linkDraft") private var link = ""
    @FocusState private var linkFocused: Bool
    @State private var linkError: String?
    @State private var searchRequest: LessonSearch?
    @State private var editLinkAfterSearch = false
    @State private var player: PlayerRoute?
    @State private var recentVideoID: RecentVideo.ID?

    private var videoHistory: [RecentVideo] {
        let local = library.movies.filter { $0.lastOpenedAt != nil && !$0.isAudio }.map(RecentVideo.local)
        let downloads = offline.videos.filter { $0.lastOpenedAt != nil }.map(RecentVideo.offline)
        let online = library.watchedVideos(for: api.offlineOwnerID).map(RecentVideo.online)
        let ordered = (local + downloads + online).sorted { $0.date > $1.date }
        var seen = Set<String>()
        return ordered.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        let history = videoHistory
        return ScenePage { container in
            let width = min(680, SwevoStyle.pageContentWidth(in: container))
            let bounds = CGRect(origin: .zero, size: container.size)
            let compact = typeSize > .xLarge
            let wide = !compact && width >= 620 && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
            let columnWidth = wide ? (width - 24) / 2 : width
            let stacksControls = columnWidth < 280 || compact
            let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                              : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))

            VStack(alignment: .leading, spacing: 16) {
                linkComposer(stacked: width < 280 || compact)
                layout {
                    VStack(alignment: .leading, spacing: 12) {
                        VideoImportActions(onImported: edit, importing: $importing,
                                           presentation: .sourcePair(stacked: stacksControls))
                        if wide { cameraMovesEntry(width: columnWidth) }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    historySection(history, in: container, columnWidth: wide ? columnWidth : nil)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if !wide { cameraMovesEntry(width: columnWidth) }
                if !library.history.isEmpty { previousLinks }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnOutsideTap($linkFocused, scope: "home-video-link")
        .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
        .fullScreenCover(item: $searchRequest, onDismiss: {
            if editLinkAfterSearch {
                editLinkAfterSearch = false
                linkFocused = true
            }
        }) { request in
            DiscoverView(initialSearch: request.query, canDismiss: true, returnToLinkInput: {
                editLinkAfterSearch = true
                searchRequest = nil
            })
        }
    }

    private func linkComposer(stacked: Bool) -> some View {
        let hasLink = !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let source = WebAddress.media(link)?.host
        let actionLayout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                   : AnyLayout(HStackLayout(spacing: 12))
        let title = SceneTitle("Open video", size: 27)
        let plus = PlusEntryButton(action: openPlus)
        return VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    title.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    plus.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 0) {
                    title
                    plus
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Glyph(symbol: .link, size: 20, tint: SwevoStyle.accent)
                    TextField("Paste a video link", text: Binding(get: { link }, set: {
                        link = $0
                        linkError = nil
                    }), prompt: Text("Paste a video link").foregroundStyle(SwevoStyle.secondary))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($linkFocused).submitLabel(.go).onSubmit { openLink(link) }
                    .font(.capture(.body)).environment(\.layoutDirection, .leftToRight)
                    .foregroundStyle(SwevoStyle.paper).tint(SwevoStyle.accent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .accessibilityLabel("Video link")
                    .accessibilityIdentifier("home.videoLink")
                    if !link.isEmpty {
                        IconButton(symbol: .close, label: "Clear link") {
                            link = ""
                            linkError = nil
                            linkFocused = true
                        }
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, link.isEmpty ? 14 : 4)

                Rectangle().fill(SwevoStyle.line).frame(height: 1)
                    .padding(.horizontal, 14)
                    .accessibilityHidden(true)

                actionLayout {
                    Button(action: pasteLink) {
                        LocalizedText("Paste").font(.capture(.subheadline, weight: .semibold))
                            .foregroundStyle(SwevoStyle.accent)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("home.pasteLink")
                    if !stacked { Spacer(minLength: 0) }
                    openLinkButton(hasLink: hasLink, expands: stacked)
                }
                .padding(8)
            }
            .swevoGlass(cornerRadius: 18, tint: SwevoStyle.raised.opacity(0.55))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(SwevoStyle.accent.opacity(linkFocused ? 1 : 0.34))
                    .allowsHitTesting(false)
            }
            .keyboardInputRegion("home-video-link")

            if let linkError {
                ErrorNote(message: linkError)
            } else if let source {
                Text(verbatim: source).font(.capture(.caption))
                    .foregroundStyle(SwevoStyle.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
    }

    private func openLinkButton(hasLink: Bool, expands: Bool) -> some View {
        let ink = hasLink ? SwevoStyle.ink : SwevoStyle.paper
        return Button { openLink(link) } label: {
            HStack(spacing: 8) {
                Glyph(symbol: .play, size: 13, tint: ink)
                LocalizedText("Open link").font(.capture(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .frame(minWidth: 44, maxWidth: expands ? .infinity : nil, minHeight: 44)
            .foregroundStyle(ink)
            .background(hasLink ? SwevoStyle.accent : SwevoStyle.paper.opacity(0.12), in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle()).disabled(!hasLink || searchRequest != nil)
        .accessibilityLabel("Open link")
        .accessibilityIdentifier("home.openLesson")
    }

    private func pasteLink() {
        guard let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            linkError = "Copy a video link first."
            return
        }
        link = value
        linkError = nil
    }

    private func openLink(_ value: String) {
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, searchRequest == nil else { return }
        link = query
        linkError = nil
        linkFocused = false
        searchRequest = LessonSearch(query: query)
    }

    private func historySection(_ history: [RecentVideo], in container: GeometryProxy, columnWidth: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            historyHeader
            if history.isEmpty {
                emptyHistory(in: container, columnWidth: columnWidth)
            } else {
                let showsNextCard = history.count > 1 && !typeSize.isAccessibilitySize
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(history) { video in
                            recentButton(video)
                                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                                    showsNextCard ? min(340, width * 0.86) : width
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $recentVideoID, anchor: .leading)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
    }

    private var historyHeader: some View {
        let title = LocalizedText("Recently opened").font(.capture(.headline))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                title.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                viewFilesShortcut.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                viewFilesShortcut
            }
        }
    }

    private func emptyHistory(in container: GeometryProxy, columnWidth: CGFloat?) -> some View {
        let width = columnWidth ?? min(680, SwevoStyle.pageContentWidth(in: container))
        let artHeight = min(112, max(78, container.size.height * 0.18))
        let showsArt = typeSize <= .xLarge && width >= 270 && ArtworkCatalog.has("EmptyImports")
        return LocalizedText("No recent videos").font(.capture(.subheadline))
            .foregroundStyle(SwevoStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: showsArt ? width * 0.54 : .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, minHeight: showsArt ? artHeight : 60, alignment: .leading)
        .background(alignment: .trailing) {
            if showsArt {
                SceneImage(name: "EmptyImports")
                    .frame(width: min(360, width * 0.72), height: artHeight)
                    .opacity(0.72)
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.18), location: 0.26),
                            .init(color: .black, location: 0.60),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1)
                        ], startPoint: .leading, endPoint: .trailing)
                    }
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.18),
                            .init(color: .black, location: 0.76),
                            .init(color: .clear, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
            }
        }
    }

    private var previousLinks: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Link history").accessibilityAddTraits(.isHeader)
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(library.history) { visit in
                    HStack(spacing: 10) {
                        Button { openLink(visit.link) } label: {
                            HStack(spacing: 12) {
                                Glyph(symbol: .link, size: 19, tint: SwevoStyle.secondary)
                                    .frame(width: 64, height: 42)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: visit.title).font(.capture(.subheadline, weight: .semibold))
                                        .fixedSize(horizontal: false, vertical: true)
                                    LocalizedDateText(date: visit.date).font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(PressStyle())
                        IconButton(symbol: .close, label: "Remove history item") { library.removeVisit(visit) }
                    }
                }
            }
            Button("Clear link history") { library.clearHistory() }
                .buttonStyle(MatteActionStyle())
        }
    }

    private var viewFilesShortcut: some View {
        Button {
            linkFocused = false
            openLibrary()
        } label: {
            HStack(spacing: 7) {
                Glyph(symbol: .folder, size: 14, tint: SwevoStyle.accent)
                LocalizedText("View files").font(.capture(.footnote, weight: .semibold))
                    .foregroundStyle(SwevoStyle.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Glyph(symbol: .back, size: 9, tint: SwevoStyle.accent).rotationEffect(.degrees(180))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                Capsule().strokeBorder(SwevoStyle.accent.opacity(0.26)).padding(.vertical, 4)
            }
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityIdentifier("home.files")
    }

    private func cameraMovesEntry(width: CGFloat) -> some View {
        let artwork = "SceneShot"
        let showsArtwork = width >= 280 && typeSize <= .xLarge && ArtworkCatalog.has(artwork)
        let shape = RoundedRectangle(cornerRadius: 18)

        return Button {
            linkFocused = false
            openCameraMoves()
        } label: {
            HStack(alignment: .bottom, spacing: 12) {
                SceneTitle("Camera moves", size: 22)
                    .foregroundStyle(SwevoStyle.paper)
                    .accessibilityRemoveTraits(.isHeader)
                    .frame(maxWidth: showsArtwork ? width * 0.54 : .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Glyph(symbol: .back, size: 13, tint: SwevoStyle.ink)
                    .rotationEffect(.degrees(180))
                    .frame(width: 38, height: 36)
                    .background(SwevoStyle.accent, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: showsArtwork ? 112 : 64, alignment: .bottomLeading)
            .background {
                if showsArtwork {
                    SceneImage(name: artwork)
                        .overlay {
                            LinearGradient(stops: [
                                .init(color: SwevoStyle.background.opacity(0.98), location: 0),
                                .init(color: SwevoStyle.background.opacity(0.87), location: 0.40),
                                .init(color: SwevoStyle.background.opacity(0.18), location: 0.76),
                                .init(color: SwevoStyle.background.opacity(0.08), location: 1)
                            ], startPoint: .leading, endPoint: .trailing)
                        }
                }
            }
            .background(SwevoStyle.surface)
            .clipShape(shape)
            .overlay { shape.strokeBorder(SwevoStyle.line).allowsHitTesting(false) }
            .contentShape(.interaction, shape)
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("home.cameraMoves")
    }

    @ViewBuilder private func recentButton(_ video: RecentVideo) -> some View {
        switch video {
        case .local(let movie):
            VideoFileButton(url: library.url(for: movie), filename: movie.displayFilename, date: video.date,
                            presentation: .thumbnail) {
                edit(movie)
            }
            .overlay(alignment: .topTrailing) {
                if movie.rangeMarks?.isEmpty == false {
                    IconButton(symbol: .bookmark, label: "Review saved ranges") { review(movie) }
                        .swevoGlass(cornerRadius: 22).padding(6)
                }
            }
        case .offline(let download):
            VideoFileButton(url: download.url, filename: download.displayFilename, date: video.date,
                            presentation: .thumbnail, fallbackCover: download.clip.coverURL) {
                guard offline.cached(download.id) != nil else {
                    offline.error = "This download is no longer on this device. Download it again."
                    library.openDownloads()
                    return
                }
                let clip = offline.playable(download.clip)
                player = PlayerRoute(clips: [clip], startID: clip.id)
            }
        case .online(let visit):
            let entry = VideoFileButton(url: offline.cached(visit.id)?.url ?? visit.clip.playbackURL,
                                       filename: visit.clip.title, date: video.date,
                                       presentation: .thumbnail, fallbackCover: visit.clip.coverURL) {
                if api.session == nil, offline.cached(visit.id) == nil {
                    library.error = "Connect to replay this video."
                } else {
                    let clip = offline.playable(visit.clip)
                    player = PlayerRoute(clips: [clip], startID: clip.id)
                }
            }
            entry.overlay(alignment: .topTrailing) {
                IconButton(symbol: .close, label: "Remove history item") { library.removeWatch(visit) }
                    .swevoGlass(cornerRadius: 22).padding(6)
            }
        }
    }
}

private enum RecentVideo: Identifiable {
    case local(PracticeRecording), offline(OfflineVideo), online(WatchedVideo)

    var id: String {
        switch self {
        case .local(let movie): "file-\(movie.id.uuidString)"
        case .offline(let download): "remote-\(download.id)"
        case .online(let visit): "remote-\(visit.id)"
        }
    }

    var date: Date {
        switch self {
        case .local(let movie): movie.lastOpenedAt ?? movie.date
        case .offline(let download): download.lastOpenedAt ?? .distantPast
        case .online(let visit): visit.date
        }
    }
}

struct CameraMovesView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let openPlus: () -> Void
    @SceneStorage("shot.movement") private var movement = ShotMovement.pushIn
    @SceneStorage("shot.duration") private var seconds = 6
    @SceneStorage("shot.focusLock") private var lockedFocus = false
    @State private var error: String?
    @State private var channel: ChannelRoute?
    @State private var browsing = false
    @State private var channels: [LandingInfo] = []
    @State private var channelRetry = 0
    @State private var destination: Destination?

    private enum Destination: Identifiable {
        case notes, planner, records
        case example(String)

        var id: String {
            switch self {
            case .notes: "notes"
            case .planner: "planner"
            case .records: "records"
            case .example(let id): "example-\(id)"
            }
        }
    }

    var body: some View {
        let request = ChannelRequest(links: commerce.release?.lcList?["us"] ?? [], attempt: channelRetry)
        ScenePage(artwork: "SceneLessons", depth: 224, openingGap: 0) { _ in
            let headingLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            headingLayout {
                SceneTitle("Camera moves", size: 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PlusEntryButton(action: openPlus)
                    .fixedSize(horizontal: true, vertical: false)
            }
        } content: { container in
            let width = min(680, SwevoStyle.pageContentWidth(in: container))
            let bounds = CGRect(origin: .zero, size: container.size)
            let hasReservedRegion = SwevoStyle.intersectsReservedRegion(bounds, in: container)
            let stacked = width < 320 || typeSize > .xLarge || hasReservedRegion
            let wide = !stacked && width >= 600
            let workflowLayout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                                      : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))

            VStack(alignment: .leading, spacing: 24) {
                browseEntry(width: width, showsArtwork: !stacked)
                examples(width: width, wide: wide, stacked: stacked)
                workflowLayout {
                    plannerEntry
                    recordsEntry(showsThumbnail: !stacked)
                }
                connection
                referenceFootage
            }
        }
            .sheet(item: $channel) { ChannelView(route: $0) }
            .fullScreenCover(isPresented: $browsing) {
                DiscoverView(canDismiss: true)
            }
            .sheet(item: $destination) { destination in
                switch destination {
                case .notes:
                    ShotGuideView()
                case .example(let id):
                    ShotGuideView(initialNoteID: id)
                case .planner:
                    ShotPlannerView(movement: $movement, seconds: $seconds, lockedFocus: $lockedFocus)
                case .records:
                    ShotPracticeView(initialMovement: movement, initialSeconds: seconds,
                                     initialFocusLock: lockedFocus, startInHistory: true)
                }
            }
            .onChange(of: library.downloadsRequest) { _, request in
                guard request != nil else { return }
                browsing = false
                channel = nil
            }
            .task(id: request) {
                guard !Task.isCancelled else { return }
                channels = []
                error = nil
                guard !request.links.isEmpty else { return }
                do {
                    let result = try await api.channels(links: request.links)
                    if !Task.isCancelled { channels = result }
                } catch {
                    if !Task.isCancelled { self.error = error.localizedDescription }
                }
            }
    }

    private func browseEntry(width: CGFloat, showsArtwork: Bool) -> some View {
        let artwork = "SceneEdit"
        let photoWidth = showsArtwork && ArtworkCatalog.has(artwork) ? min(244, width * 0.44) : 0
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return Button { browsing = true } label: {
            HStack(spacing: 12) {
                Glyph(symbol: .play, size: 17, tint: SwevoStyle.ink)
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("Browse videos").font(.capture(.headline, weight: .semibold))
                    LocalizedText("Find a shot to try.").font(.capture(.footnote))
                        .foregroundStyle(SwevoStyle.ink.opacity(0.80))
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: photoWidth > 0 ? 84 : 56, alignment: .leading)
            .foregroundStyle(SwevoStyle.ink)
            .background(SwevoStyle.accent)
            .padding(.trailing, photoWidth)
            .background(alignment: .trailing) {
                if photoWidth > 0 {
                    SceneImage(name: artwork).frame(width: photoWidth)
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(SwevoStyle.line).allowsHitTesting(false) }
            .contentShape(.interaction, shape)
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("cameraMoves.browseVideos")
    }

    private func examples(width: CGFloat, wide: Bool, stacked: Bool) -> some View {
        let moves = ShotNote.all.filter { $0.category == "Movement" }
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        let supportingPhotoWidth: CGFloat? = wide || stacked ? nil : width * 0.60

        return VStack(alignment: .leading, spacing: 12) {
            LocalizedText("Shot examples").font(.capture(.headline))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let featured = moves.first {
                layout {
                    exampleButton(featured, aspect: wide ? 4.0 / 3 : 16.0 / 9, featured: true)
                        .frame(width: wide ? min(350, (width - 20) * 0.55) : nil)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(moves.dropFirst()) { note in
                            exampleButton(note, photoWidth: supportingPhotoWidth, aspect: wide ? 2.0 : 3.0 / 2)
                        }
                    }
                }
            }
            LearningLink(symbol: .folder, title: "Shot field notes") { destination = .notes }
                .accessibilityIdentifier("shotGuide.open")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exampleButton(_ note: ShotNote, photoWidth: CGFloat? = nil, aspect: CGFloat,
                               featured: Bool = false) -> some View {
        let layout = photoWidth == nil ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                       : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return Button { destination = .example(note.id) } label: {
            layout {
                Color.clear.aspectRatio(aspect, contentMode: .fit)
                    .background { SceneImage(name: note.artwork) }
                    .clipShape(.rect(cornerRadius: 12))
                    .frame(width: photoWidth)
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        LocalizedText(note.shortTitle).font(.capture(featured ? .title3 : .headline, weight: .semibold))
                        if featured {
                            LocalizedText(note.summary).font(.capture(.footnote))
                                .foregroundStyle(SwevoStyle.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Glyph(symbol: .back, size: 12, tint: SwevoStyle.accent).rotationEffect(.degrees(180))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("cameraMoves.example.\(note.id)")
    }

    private var plannerEntry: some View {
        let duration = Text(verbatim: "\(seconds) s").monospacedDigit()
            .font(.capture(.title, weight: .semibold))
            .foregroundStyle(SwevoStyle.accent)
            .environment(\.layoutDirection, .leftToRight)
            .fixedSize(horizontal: false, vertical: true)
        let settings = VStack(alignment: .leading, spacing: 4) {
            LocalizedText(movement.label).font(.capture(.subheadline, weight: .semibold))
            LocalizedText(lockedFocus ? "Focus locked" : "Autofocus").font(.capture(.footnote))
                .foregroundStyle(SwevoStyle.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)

        return Button { destination = .planner } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SceneTitle("Shot planner", size: 24)
                        .accessibilityRemoveTraits(.isHeader)
                    Spacer(minLength: 0)
                    Glyph(symbol: .back, size: 13, tint: SwevoStyle.accent)
                        .rotationEffect(.degrees(180))
                }
                Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        duration
                        settings
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) {
                        duration
                        settings
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .swevoGlass(cornerRadius: 17)
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("cameraMoves.planner")
    }

    private func recordsEntry(showsThumbnail: Bool) -> some View {
        Button { destination = .records } label: {
            HStack(spacing: 12) {
                if showsThumbnail && ArtworkCatalog.has("SceneJournal") {
                    SceneImage(name: "SceneJournal")
                        .frame(width: 72, height: 54)
                        .clipShape(.rect(cornerRadius: 8))
                } else {
                    Glyph(symbol: .library, size: 20, tint: SwevoStyle.accent)
                        .frame(width: 32)
                }
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("Practice records").font(.capture(.headline))
                        .fixedSize(horizontal: false, vertical: true)
                    LocalizedText("Review your footage").font(.capture(.footnote))
                        .foregroundStyle(SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .back, size: 13, tint: SwevoStyle.secondary)
                    .rotationEffect(.degrees(180))
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .overlay(alignment: .top) {
                Divider().overlay(SwevoStyle.line).allowsHitTesting(false).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("cameraMoves.records")
    }

    @ViewBuilder private var connection: some View {
        if api.session == nil { ConnectionPanel() }
        if let error {
            MessagePanel(title: "Couldn’t load collections", message: error, actionTitle: "Try again") {
                channelRetry += 1
            }
        }
    }

    @ViewBuilder private var referenceFootage: some View {
        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                LocalizedText("Video collections").font(.capture(.headline))
                    .accessibilityAddTraits(.isHeader)
                ForEach(channels.indices, id: \.self) { index in
                    let item = channels[index]
                    if let info = item.extraInfo, let title = info.channelName, let short = info.externalLinks {
                        Button { channel = ChannelRoute(link: short, title: title) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                MediaCover(url: WebAddress.media(item.shortCover)).aspectRatio(3.0, contentMode: .fit)
                                    .clipShape(.rect(cornerRadius: 4)).accessibilityHidden(true)
                                Text(verbatim: title).font(.capture(.subheadline, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let count = info.videoFileCount {
                                    LocalizedText("\(count) videos").font(.capture(.caption))
                                        .foregroundStyle(SwevoStyle.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

}

private struct LearningLink: View {
    let symbol: SwevoGlyph
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Glyph(symbol: symbol, size: 18, tint: SwevoStyle.secondary)
                LocalizedText(title).font(.capture(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .back, size: 13, tint: SwevoStyle.secondary).rotationEffect(.degrees(180))
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .foregroundStyle(SwevoStyle.paper)
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }
}

private struct ShotPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var movement: ShotMovement
    @Binding var seconds: Int
    @Binding var lockedFocus: Bool
    @State private var showingJournal = false
    @State private var showingPresets = false

    var body: some View {
        ScenePage(depth: 44) { _ in
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Camera move").accessibilityAddTraits(.isHeader)
                ChoiceStrip(values: ShotMovement.allCases.map(\.label), selected: movement.label) { label in
                    if let move = ShotMovement.allCases.first(where: { $0.label == label }) { movement = move }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 12) {
                        durationControls.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        focusControl.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        durationControls
                        focusControl
                    }
                }
                ActionButton(title: "Practice") { showingJournal = true }
                    .accessibilityIdentifier("practice.openJournal")
                LearningLink(symbol: .bookmark, title: "Shot presets") { showingPresets = true }
                    .accessibilityIdentifier("practice.openPresets")
            }
        }
        .sceneDismiss { dismiss() }
        .sheet(isPresented: $showingJournal) {
            ShotPracticeView(initialMovement: movement, initialSeconds: seconds, initialFocusLock: lockedFocus)
        }
        .sheet(isPresented: $showingPresets) {
            ShotPresetsView(movement: $movement, seconds: $seconds, lockedFocus: $lockedFocus)
        }
    }

    private var durationControls: some View {
        VStack(alignment: .leading, spacing: 3) {
            LocalizedText("Target duration").font(.capture(.caption))
                .foregroundStyle(SwevoStyle.secondary)
            HStack(spacing: 0) {
                Button { seconds -= 1 } label: { lengthLabel("−") }
                    .buttonStyle(PressStyle()).disabled(seconds <= ShotPracticeJournal.amountRange.lowerBound)
                    .accessibilityLabel(LocalizedStringKey("Shorter"))
                Text(verbatim: "\(seconds) s").font(.capture(.headline)).monospacedDigit()
                    .fixedSize().padding(.horizontal, 4)
                    .accessibilityLabel(LocalizedStringKey("Target duration"))
                    .accessibilityValue(Text(verbatim: "\(seconds) s"))
                Button { seconds += 1 } label: { lengthLabel("+") }
                    .buttonStyle(PressStyle()).disabled(seconds >= ShotPracticeJournal.amountRange.upperBound)
                    .accessibilityLabel(LocalizedStringKey("Longer"))
            }
            .background(SwevoStyle.surface, in: Capsule())
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    private func lengthLabel(_ title: String) -> some View {
        Text(verbatim: title).font(.capture(.title3, weight: .semibold))
            .frame(minWidth: 44, minHeight: 44).foregroundStyle(SwevoStyle.accent)
            .contentShape(Rectangle())
    }

    private var focusControl: some View {
        Button { lockedFocus.toggle() } label: {
            LocalizedText(lockedFocus ? "Focus locked" : "Autofocus")
                .font(.capture(.footnote, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 44)
                .foregroundStyle(lockedFocus ? SwevoStyle.accent : SwevoStyle.paper)
                .background(lockedFocus ? SwevoStyle.raised : SwevoStyle.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(lockedFocus ? SwevoStyle.accent.opacity(0.5) : SwevoStyle.line).allowsHitTesting(false) }
                .contentShape(.interaction, Capsule())
        }.buttonStyle(PressStyle()).accessibilityAddTraits(lockedFocus ? .isSelected : [])
    }
}

@MainActor
private struct ShotPresetsView: View {
    private struct Preset: Codable, Equatable {
        let seconds: Int
        let lockedFocus: Bool
    }

    @Binding var movement: ShotMovement
    @Binding var seconds: Int
    @Binding var lockedFocus: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var commerce: CommerceStore
    @AppStorage("swevo.shotPresets.v1") private var storedPresets: Data?
    @State private var showingMembership = false
    @State private var checkingMembership = false
    @State private var saveFailed = false

    init(movement: Binding<ShotMovement>, seconds: Binding<Int>, lockedFocus: Binding<Bool>) {
        _movement = movement
        _seconds = seconds
        _lockedFocus = lockedFocus
    }

    private var currentPreset: Preset { Preset(seconds: seconds, lockedFocus: lockedFocus) }
    private var presets: [String: Preset]? {
        guard let storedPresets else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: Preset].self, from: storedPresets),
              decoded.values.allSatisfy({ ShotPracticeJournal.amountRange.contains($0.seconds) }) else { return nil }
        return decoded
    }

    var body: some View {
        ScenePage(depth: 44) { _ in
            VStack(alignment: .leading, spacing: 16) {
                LocalizedText("Save one setup per camera move on this device.")
                    .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if commerce.hasVerifiedPlus {
                    if let presets {
                        currentShot(saved: presets[movement.rawValue])
                        if !presets.isEmpty { savedShots(presets) }
                    } else {
                        ErrorNote(message: "Shot presets could not be opened on this device.")
                    }
                } else if commerce.premium {
                    LocalizedText("Connect to verify Plus and use shot presets.")
                        .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                    ActionButton(title: "Verify membership", primary: false, busy: checkingMembership) {
                        checkingMembership = true
                        Task {
                            await commerce.refresh()
                            checkingMembership = false
                        }
                    }
                } else {
                    ActionButton(title: "View Plus plans") {
                        showingMembership = true
                    }
                }
            }
        }
        .sceneDismiss { dismiss() }
        .fullScreenCover(isPresented: $showingMembership) { MembershipView() }
    }

    private func currentShot(saved: Preset?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Current setup").accessibilityAddTraits(.isHeader)
            presetLabel(movement, preset: currentPreset)
            if saved == currentPreset {
                LocalizedText("Preset saved").font(.capture(.footnote, weight: .semibold))
                    .foregroundStyle(SwevoStyle.accent)
            } else {
                ActionButton(title: saved == nil ? "Save preset" : "Update preset", primary: false, action: savePreset)
            }
            if saveFailed { ErrorNote(message: "This change could not be saved. Please try again.") }
        }
        .padding(14)
        .swevoGlass()
    }

    private func savedShots(_ presets: [String: Preset]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Saved presets").accessibilityAddTraits(.isHeader)
            ForEach(ShotMovement.allCases) { move in
                if let preset = presets[move.rawValue] {
                    Button {
                        guard commerce.hasVerifiedPlus else { return }
                        movement = move
                        seconds = preset.seconds
                        lockedFocus = preset.lockedFocus
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            presetLabel(move, preset: preset)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Glyph(symbol: .back, size: 14, tint: SwevoStyle.accent).rotationEffect(.degrees(180))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6).frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }.buttonStyle(PressStyle())
                        .accessibilityHint(LocalizedStringKey("Applies this preset to the shot planner."))
                }
            }
        }
    }

    private func presetLabel(_ move: ShotMovement, preset: Preset) -> some View {
        let focus = L10n.text(preset.lockedFocus ? "Focus locked" : "Autofocus", language: AppLanguage.from(locale))
        return VStack(alignment: .leading, spacing: 3) {
            LocalizedText(move.label).font(.capture(.subheadline, weight: .semibold))
                .foregroundStyle(SwevoStyle.paper)
            LocalizedText("%@ s · %@", preset.seconds.formatted(.number.locale(locale)), focus)
                .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func savePreset() {
        guard commerce.hasVerifiedPlus, var presets, ShotPracticeJournal.amountRange.contains(seconds) else { return }
        presets[movement.rawValue] = currentPreset
        do {
            storedPresets = try JSONEncoder().encode(presets)
            saveFailed = false
        } catch { saveFailed = true }
    }
}

// The disabled composer button has its own color treatment.
private struct LessonSearch: Identifiable {
    let id = UUID()
    let query: String

    init(query: String = "") { self.query = query }
}

private struct ChannelRequest: Equatable {
    let links: [String]
    let attempt: Int
}

struct ChannelView: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    let route: ChannelRoute
    @State private var items: [RemoteLessonFile] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var error: String?
    @State private var child: ChannelRoute?
    @State private var player: PlayerRoute?
    private var emptyChannel: Bool { items.isEmpty && !loading && !hasMore && error == nil }

    var body: some View {
        ScenePage(artwork: nil, depth: 64, openingGap: 0) { _ in
            Text(verbatim: route.title).font(.capture(.headline))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                .padding(.trailing, 50)
        } content: { container in
            LazyVStack(alignment: .leading, spacing: 14) {
                if emptyChannel {
                    EmptyStateScene(artwork: "EmptyLessons", title: "No videos available", container: container)
                    EmptyStateAction(title: "Back", symbol: .back, primary: true) { dismiss() }
                }
                ForEach(items, id: \.stableID) { item in
                    Button { open(item) } label: {
                        HStack(spacing: 16) {
                            MediaCover(url: WebAddress.media(item.coverImage), folder: item.isFolder == true)
                                .frame(width: 80, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(verbatim: item.name ?? L10n.text("Untitled")).font(.capture(.headline)).lineLimit(3)
                                LocalizedText(item.isFolder == true ? "\(item.childrenFileNum ?? 0) videos" : durationLabel(item.length ?? 0))
                                    .font(.caption.monospacedDigit()).foregroundStyle(SwevoStyle.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Glyph(symbol: item.isFolder == true ? .folder : .play, size: 18, tint: SwevoStyle.accent)
                        }.contentShape(Rectangle())
                    }.buttonStyle(PressStyle())
                }
                if let error { ErrorNote(message: error) }
                if hasMore {
                    let title = loading ? "Loading videos…" : error == nil ? "Load more" : "Try again"
                    ActionButton(title: title, primary: false) { Task { await load() } }
                        .disabled(loading)
                }
            }
        }
            .sceneDismiss { dismiss() }
            .task { if items.isEmpty { await load() } }
            .sheet(item: $child) { ChannelView(route: $0) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
    }
    private func load() async {
        guard !loading, hasMore else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let result = try await api.channelPage(link: route.link, page: page)
            var seen = Set(items.map(\.stableID))
            items += result.list.filter { $0.name?.nilIfBlank != nil && !$0.stableID.isEmpty && seen.insert($0.stableID).inserted }
            hasMore = page * 20 < result.total && !result.list.isEmpty
            page += 1
        } catch { self.error = error.localizedDescription }
    }
    private func open(_ item: RemoteLessonFile) {
        if item.isFolder == true, let link = item.landingPage?.nilIfBlank {
            child = ChannelRoute(link: link, title: item.name ?? "Folder")
        } else if let clip = item.clip(channel: route.title) {
            player = PlayerRoute(clips: items.compactMap { $0.clip(channel: route.title) }, startID: clip.id, continuesRecommendations: true)
        } else { error = "This item does not contain a playable video." }
    }
}
