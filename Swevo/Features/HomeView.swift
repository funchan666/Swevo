import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var importing: Bool
    let edit: (PracticeRecording) -> Void
    let openLibrary: () -> Void
    let openLearning: () -> Void
    @State private var offlinePlayer: PlayerRoute?

    private var recentlyOpened: [RecentVideo] {
        let local = library.movies.filter { $0.lastOpenedAt != nil && !$0.isAudio }.map(RecentVideo.local)
        let downloads = offline.videos.filter { $0.lastOpenedAt != nil }.map(RecentVideo.offline)
        return Array((local + downloads).sorted { $0.date > $1.date }.prefix(3))
    }

    var body: some View {
        ScenePage(artwork: nil, depth: 48, openingGap: 0) { _ in
            SceneTitle("Videos", size: 38)
        } content: { container in
            let recent = recentlyOpened
            let bounds = CGRect(origin: .zero, size: container.size)
            let wide = !typeSize.isAccessibilitySize
                && SwevoStyle.pageContentWidth(in: container) >= 600
                && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
            let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                              : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    VideoImportActions(onImported: edit, importing: $importing, sideBySide: wide)
                    LocalizedText("Swevo makes a copy for editing.")
                        .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let latest = recent.first {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: "Recently opened").accessibilityAddTraits(.isHeader)
                        layout {
                            recentButton(latest, featured: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if recent.count > 1 {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(recent.dropFirst()) { movie in
                                        recentButton(movie)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
                VStack(spacing: 0) {
                    if !library.movies.isEmpty {
                        LearningLink(symbol: .folder, title: "View files", action: openLibrary)
                    }
                    LearningLink(symbol: .link, title: "Lesson link or code", detail: "Tutorials & practice", action: openLearning)
                }
            }
        }.fullScreenCover(item: $offlinePlayer) { PlayerScreen(route: $0) }
    }

    @ViewBuilder private func recentButton(_ video: RecentVideo, featured: Bool = false) -> some View {
        switch video {
        case .local(let movie):
            VideoFileButton(url: library.url(for: movie), filename: movie.displayFilename, date: video.date, featured: featured) {
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
                offlinePlayer = PlayerRoute(clips: [clip], startID: clip.id)
            }
        }
    }
}

private enum RecentVideo: Identifiable {
    case local(PracticeRecording), offline(OfflineVideo)

    var id: String {
        switch self {
        case .local(let movie): "file-\(movie.id.uuidString)"
        case .offline(let download): "offline-\(download.id)"
        }
    }

    var date: Date {
        switch self {
        case .local(let movie): movie.lastOpenedAt ?? movie.date
        case .offline(let download): download.lastOpenedAt ?? .distantPast
        }
    }
}

struct LearningView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @Environment(\.dismiss) private var dismiss
    @SceneStorage("home.linkDraft") private var link = ""
    @FocusState private var linkFocused: Bool
    @State private var error: String?
    @State private var linkFailure = ""
    @State private var showingLinkFailure = false
    @State private var channel: ChannelRoute?
    @State private var searchRequest: LessonSearch?
    @State private var channels: [LandingInfo] = []
    @State private var channelRetry = 0
    @State private var showingLinkGuide = false
    @State private var showingGuide = false
    @State private var showingPlanner = false

    var body: some View {
        let request = ChannelRequest(links: commerce.release?.lcList?["us"] ?? [], attempt: channelRetry)
        ScenePage(artwork: "SceneLessons", depth: 116, openingGap: 0, artworkOpacity: 0.45) { _ in
            SceneTitle("Tutorials & practice", size: 34).padding(.trailing, 50)
        } content: { _ in
            VStack(alignment: .leading, spacing: 20) {
                linkComposer
                connection
                VStack(spacing: 0) {
                    LearningLink(symbol: .play, title: "Watch tutorials") {
                        linkFocused = false
                        searchRequest = LessonSearch()
                    }
                    Divider().overlay(SwevoStyle.line)
                    LearningLink(symbol: .edit, title: "Shot planner") {
                        linkFocused = false
                        showingPlanner = true
                    }
                    Divider().overlay(SwevoStyle.line)
                    LearningLink(symbol: .folder, title: "Shot field notes") {
                        linkFocused = false
                        showingGuide = true
                    }
                    .accessibilityIdentifier("shotGuide.open")
                }
                referenceFootage
                recentLinks
            }
        }
            .sceneDismiss { dismiss() }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnOutsideTap($linkFocused, scope: "lesson-link-input")
            .sheet(item: $channel) { ChannelView(route: $0) }
            .fullScreenCover(item: $searchRequest) { request in
                DiscoverView(initialSearch: request.query, canDismiss: true, openLessonEntry: { searchRequest = nil }) { query, clip in
                    if query.nilIfBlank != nil { library.record(link: query, title: clip.title) }
                }
            }
            .fullScreenCover(isPresented: $showingLinkFailure) {
                AccountDecisionDialog(title: "Lesson search", message: linkFailure,
                                      confirmTitle: "Back to search", confirm: { showingLinkFailure = false })
                    .presentationBackground(.clear)
            }
            .sheet(isPresented: $showingLinkGuide) { LinkGuideSheet() }
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
            MessagePanel(title: "Couldn’t load lesson collections", message: error, actionTitle: "Try again") {
                channelRetry += 1
            }
        }
    }

    @ViewBuilder private var referenceFootage: some View {
        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                LocalizedText("Lesson collections").font(.capture(.title3, display: true))
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

    private var linkComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Lesson link or code")
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Glyph(symbol: .link, size: 17, tint: SwevoStyle.accent).padding(.leading, 12)
                TextField("Paste a link or type a code", text: $link, axis: .vertical)
                    .lineLimit(1...3).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($linkFocused).font(.capture(.subheadline)).foregroundStyle(SwevoStyle.paper)
                    .tint(SwevoStyle.accent)
                    .padding(.horizontal, 10).padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(LocalizedStringKey("Lesson link or code"))
                if !link.isEmpty {
                    Button {
                        link = ""
                        linkFocused = true
                    } label: {
                        Glyph(symbol: .close, size: 13, tint: SwevoStyle.paper)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(ComposerPressStyle())
                        .accessibilityLabel(LocalizedStringKey("Clear link or code"))
                        .accessibilityIdentifier("home.clearLink")
                }
            }
                .environment(\.layoutDirection, .leftToRight)
                .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(linkFocused ? SwevoStyle.accent : SwevoStyle.line)
                        .allowsHitTesting(false)
                }
                .keyboardInputRegion("lesson-link-input")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { pasteButton; openLessonButton }
                VStack(alignment: .leading, spacing: 8) { openLessonButton; pasteButton }
            }
            HStack(spacing: 10) {
                allowanceLabel
                Spacer(minLength: 0)
                Button { linkFocused = false; showingLinkGuide = true } label: {
                    LocalizedText("Link help").font(.capture(.caption, weight: .semibold))
                        .underline().foregroundStyle(SwevoStyle.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(ComposerPressStyle())
                    .accessibilityIdentifier("home.linkHelp")
            }
        }
    }
    private var canOpenLink: Bool { searchRequest == nil && link.nilIfBlank != nil }
    private var openLessonButton: some View {
        Button(action: resolve) {
            HStack(spacing: 10) {
                LocalizedText("Find lesson").font(.capture(.subheadline, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Glyph(symbol: .play, size: 14, tint: canOpenLink ? SwevoStyle.ink : SwevoStyle.secondary)
            }.padding(.horizontal, 14).padding(.vertical, 10)
                .frame(minHeight: 44)
                .foregroundStyle(canOpenLink ? SwevoStyle.ink : SwevoStyle.secondary)
                .background(canOpenLink ? SwevoStyle.accent : SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }.buttonStyle(ComposerPressStyle()).disabled(!canOpenLink)
            .accessibilityIdentifier("home.openLesson")
    }
    @ViewBuilder private var allowanceLabel: some View {
        if api.session != nil {
            LocalizedText(quota.usage == nil ? "Loading…" : commerce.premium || quota.unlimited ? "Unlimited viewing today" : "\(quota.watchesLeft) views left today")
                .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var pasteButton: some View {
        Button(action: pasteCopiedLink) {
            LocalizedText("Paste link").font(.capture(.footnote, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(minHeight: 44)
                .foregroundStyle(SwevoStyle.paper)
                .background { CaptureSurface(tone: .plum) }
                .contentShape(Rectangle())
        }.buttonStyle(ComposerPressStyle())
            .accessibilityIdentifier("home.pasteLink")
    }
    private func pasteCopiedLink() {
        guard let text = UIPasteboard.general.string, text.nilIfBlank != nil else {
            showLinkFailure("Copy a lesson link or code, then tap Paste link.")
            return
        }
        link = text
    }
    @ViewBuilder private var recentLinks: some View {
        if !library.history.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    LocalizedText("Recently opened").font(.capture(.headline))
                    Spacer()
                    Button("Clear") { library.clearHistory() }
                        .buttonStyle(MatteActionStyle())
                }
                ForEach(library.history.prefix(5)) { visit in
                    HStack {
                        Button { link = visit.link; resolve() } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: visit.title).font(.capture(.headline)).lineLimit(1)
                                Text(verbatim: visit.link).font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(PressStyle()).disabled(searchRequest != nil)
                        IconButton(symbol: .close, label: "Remove history item") { library.removeVisit(visit) }
                    }
                }
            }
        }
    }
    private func resolve() {
        guard let text = link.nilIfBlank, searchRequest == nil else { return }
        linkFocused = false
        guard api.session != nil else {
            showLinkFailure("Swevo hasn’t connected yet. Try again in a moment.")
            return
        }
        // Preserve exactly what was entered. Search owns loading, errors and cursor
        // pagination; do not fall back to the old landing-page resolver.
        searchRequest = LessonSearch(query: text)
    }
    private func showLinkFailure(_ message: String) {
        linkFailure = message
        showingLinkFailure = true
    }
}

private struct LearningLink: View {
    let symbol: SwevoGlyph
    let title: String
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Glyph(symbol: symbol, size: 18, tint: SwevoStyle.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    LocalizedText(title).font(.capture(.subheadline, weight: .semibold))
                    if let detail {
                        LocalizedText(detail).font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                    }
                }.fixedSize(horizontal: false, vertical: true)
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
        ScenePage(artwork: nil, depth: 64, openingGap: 0) { _ in
            SceneTitle("Shot planner", size: 34).padding(.trailing, 50)
        } content: { _ in
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
        ScenePage(artwork: nil, depth: 64, openingGap: 0) { _ in
            SceneTitle("Shot presets", size: 40).padding(.trailing, 50)
        } content: { _ in
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
private struct ComposerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

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
            Text(verbatim: route.title).font(.capture(.largeTitle, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                .padding(.trailing, 50)
        } content: { _ in
            LazyVStack(spacing: 14) {
                if emptyChannel {
                    VStack(alignment: .leading, spacing: 14) {
                        EmptyStateCopy(title: "No lessons available", message: "This channel has no available videos.")
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
                    let title = loading ? "Loading lessons…" : error == nil ? "Load more" : "Try again"
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

struct LinkGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScenePage(artwork: nil, depth: 64, openingGap: 0) { _ in
            SceneTitle("Use a link or code", size: 40).padding(.trailing, 50)
        } content: { _ in
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(symbol: .link, title: "1. Copy the link or code", detail: "Use the Swevo lesson link or code you received.")
                FeatureRow(symbol: .search, title: "2. Paste or type it", detail: "If you type the code, match the uppercase and lowercase letters.")
                FeatureRow(symbol: .play, title: "3. Find the lesson", detail: "Tap Find lesson, then swipe up or down to browse the results.")
                LocalizedText("If the lesson doesn’t appear, check the link or code and try again.")
                    .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                ActionButton(title: "Back to search") { dismiss() }
            }
        }
        .sceneDismiss { dismiss() }
    }
}
