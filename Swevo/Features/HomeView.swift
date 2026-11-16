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
    let openLearning: () -> Void
    @SceneStorage("home.linkDraft") private var link = ""
    @FocusState private var linkFocused: Bool
    @State private var linkError: String?
    @State private var searchRequest: LessonSearch?
    @State private var editLinkAfterSearch = false
    @State private var player: PlayerRoute?

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
        let latest = history.first
        return ScenePage(artwork: latest == nil ? "EmptyImports" : nil,
                         depth: latest == nil ? 172 : 0, artworkOpacity: 0.96) { container in
            let bounds = CGRect(origin: .zero, size: container.size)
            let wide = latest != nil && !typeSize.isAccessibilitySize
                && SwevoStyle.pageContentWidth(in: container) >= 600
                && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
            let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                              : AnyLayout(VStackLayout(alignment: .leading, spacing: 22))

            VStack(alignment: .leading, spacing: 22) {
                layout {
                    VStack(alignment: .leading, spacing: 12) {
                        VideoImportActions(onImported: edit, importing: $importing, presentation: .prominent)
                        linkComposer
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    if let latest {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(title: "Last opened").accessibilityAddTraits(.isHeader)
                            recentButton(latest, featured: true)
                            if case .local(let movie) = latest, movie.rangeMarks?.isEmpty == false {
                                shortcut("Review saved ranges", glyph: .bookmark) { review(movie) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                shortcuts
                historySection(history.dropFirst(), hasVideos: latest != nil)
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

    private var linkComposer: some View {
        let hasLink = !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let stacks = typeSize.isAccessibilitySize
        let layout = stacks ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                            : AnyLayout(HStackLayout(spacing: 0))
        return VStack(alignment: .leading, spacing: 8) {
            layout {
                HStack(spacing: 8) {
                    Glyph(symbol: .link, size: 18, tint: SwevoStyle.accent)
                    TextField("Video URL", text: Binding(get: { link }, set: {
                        link = $0
                        linkError = nil
                    }))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($linkFocused).submitLabel(.go).onSubmit { openLink(link) }
                    .font(.capture(.subheadline)).environment(\.layoutDirection, .leftToRight)
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
                .padding(.leading, 14).frame(minHeight: 54)
                .keyboardInputRegion("home-video-link")

                HStack(spacing: 4) {
                    Button("Paste", action: pasteLink).font(.capture(.footnote, weight: .semibold))
                        .foregroundStyle(SwevoStyle.accent)
                        .fixedSize(horizontal: !stacks, vertical: true).padding(.horizontal, 4)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle()).buttonStyle(PressStyle())
                        .accessibilityIdentifier("home.pasteLink")
                    Button { openLink(link) } label: {
                        Glyph(symbol: .play, size: 16, tint: hasLink ? SwevoStyle.ink : SwevoStyle.secondary)
                            .frame(width: 36, height: 36)
                            .background(hasLink ? SwevoStyle.accent : SwevoStyle.raised, in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(PressStyle()).disabled(!hasLink || searchRequest != nil)
                        .accessibilityLabel("Open link")
                        .accessibilityIdentifier("home.openLesson")
                }.padding(.horizontal, 6).padding(.vertical, 4)
            }
            .swevoGlass(cornerRadius: 16)
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(linkFocused ? SwevoStyle.accent : Color.clear)
                    .allowsHitTesting(false)
            }
            if let linkError { ErrorNote(message: linkError) }
        }
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

    @ViewBuilder private func historySection(_ history: ArraySlice<RecentVideo>, hasVideos: Bool) -> some View {
        if !history.isEmpty || !library.history.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !history.isEmpty { SectionLabel(title: "Video history").accessibilityAddTraits(.isHeader) }
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(history) { video in
                        recentButton(video, featured: false)
                        Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
                    }
                }
                if !library.history.isEmpty { previousLinks }
            }
        } else if !hasVideos {
            EmptyStateCopy(message: "Videos you open appear here.")
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

    private var shortcuts: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                                  : AnyLayout(HStackLayout(spacing: 16))
        return VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
            layout {
                shortcut("View files", glyph: .library, action: openLibrary)
                shortcut("Browse and practice", glyph: .bookmark, action: openLearning)
            }
        }
    }

    private func shortcut(_ title: String, glyph: SwevoGlyph, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Glyph(symbol: glyph, size: 17, tint: SwevoStyle.accent)
                LocalizedText(title).font(.capture(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }

    @ViewBuilder private func recentButton(_ video: RecentVideo, featured: Bool) -> some View {
        switch video {
        case .local(let movie):
            VideoFileButton(url: library.url(for: movie), filename: movie.displayFilename, date: video.date,
                            featured: featured,
                            detail: !featured && movie.rangeMarks?.isEmpty == false ? "Saved ranges" : nil) {
                edit(movie)
            }
        case .offline(let download):
            VideoFileButton(url: download.url, filename: download.displayFilename, date: video.date,
                            featured: featured, fallbackCover: download.clip.coverURL) {
                guard offline.cached(download.id) != nil else {
                    offline.error = "This download is no longer on this device. Download it again."
                    library.openDownloads()
                    return
                }
                let clip = offline.playable(download.clip)
                player = PlayerRoute(clips: [clip], startID: clip.id)
            }
        case .online(let visit):
            let entry = VideoFileButton(url: visit.clip.playbackURL, filename: visit.clip.title, date: video.date,
                                       featured: featured, fallbackCover: visit.clip.coverURL) {
                if api.session == nil, offline.cached(visit.id) == nil {
                    library.error = "Connect to replay this video."
                } else {
                    let clip = offline.playable(visit.clip)
                    player = PlayerRoute(clips: [clip], startID: clip.id)
                }
            }
            let remove = IconButton(symbol: .close, label: "Remove history item") { library.removeWatch(visit) }
            if featured && !typeSize.isAccessibilitySize {
                entry.overlay(alignment: .topTrailing) {
                    remove.swevoGlass(cornerRadius: 22).padding(8)
                }
            } else {
                HStack(spacing: 10) {
                    entry
                    remove
                }
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

struct LearningView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var channel: ChannelRoute?
    @State private var browsing = false
    @State private var channels: [LandingInfo] = []
    @State private var channelRetry = 0
    @State private var showingGuide = false
    @State private var showingPlanner = false

    var body: some View {
        let request = ChannelRequest(links: commerce.release?.lcList?["us"] ?? [], attempt: channelRetry)
        ScenePage(artwork: "SceneLessons", depth: 96, artworkOpacity: 0.58) { _ in
            VStack(alignment: .leading, spacing: 20) {
                connection
                VStack(spacing: 0) {
                    LearningLink(symbol: .play, title: "Browse videos") {
                        browsing = true
                    }
                    Divider().overlay(SwevoStyle.line)
                    LearningLink(symbol: .edit, title: "Shot planner") {
                        showingPlanner = true
                    }
                    Divider().overlay(SwevoStyle.line)
                    LearningLink(symbol: .folder, title: "Shot field notes") {
                        showingGuide = true
                    }
                    .accessibilityIdentifier("shotGuide.open")
                }
                referenceFootage
            }
        }
            .sceneDismiss { dismiss() }
            .sheet(item: $channel) { ChannelView(route: $0) }
            .fullScreenCover(isPresented: $browsing) {
                DiscoverView(canDismiss: true)
            }
            .sheet(isPresented: $showingPlanner) { ShotPlannerView() }
            .sheet(isPresented: $showingGuide) { ShotGuideView() }
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
    @SceneStorage("shot.movement") private var movement = ShotMovement.pushIn
    @SceneStorage("shot.duration") private var seconds = 6
    @SceneStorage("shot.focusLock") private var lockedFocus = false
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
                ActionButton(title: "Shot log", primary: false) { showingJournal = true }
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
        .sheet(isPresented: $showingMembership) { MembershipView() }
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
        ScenePage(artwork: emptyChannel ? "EmptyLessons" : nil, depth: emptyChannel ? 134 : 64,
                  openingGap: 0, artworkOpacity: 0.45) { _ in
            Text(verbatim: route.title).font(.capture(.headline))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                .padding(.trailing, 50)
        } content: { _ in
            LazyVStack(spacing: 14) {
                if emptyChannel {
                    VStack(alignment: .leading, spacing: 14) {
                        EmptyStateCopy(message: "This channel has no available videos.")
                        EmptyStateAction(title: "Back", symbol: .back) { dismiss() }
                    }.frame(maxWidth: .infinity, alignment: .leading)
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
