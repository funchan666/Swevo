import OSLog
import SwiftUI

struct BrowserLessonSearch: Equatable {
    let query: String
    var url: URL? {
        var address = URLComponents(string: "https://www.google.com/search")
        address?.queryItems = [URLQueryItem(name: "q", value: query)]
        // Search engines treat an unescaped plus sign as a space.
        if let encoded = address?.percentEncodedQuery {
            address?.percentEncodedQuery = encoded.replacingOccurrences(of: "+", with: "%2B")
        }
        return address?.url
    }
}

@MainActor
final class FeedStore: ObservableObject {
    @Published private(set) var entries: [PlaybackQueueEntry]
    @Published private(set) var loading = false
    @Published private(set) var hasMore = true
    @Published var error: String?
    @Published private(set) var emptySearch: BrowserLessonSearch?
    var clips: [LessonClip] { entries.map(\.clip) }
    private var feedID: String?
    private var cursor: String?
    private var roundVideoIDs = Set<String>()
    private var requestQuery = ""
    private var query = ""
    private var generation = UUID()
    private let diagnostics = Logger(subsystem: "app.swevo", category: "LessonFeed")

    init(seed: [LessonClip] = []) {
        entries = seed.map { PlaybackQueueEntry(id: $0.id, clip: $0) }
        hasMore = seed.isEmpty
    }

    func invalidatePendingLoad() {
        generation = UUID()
        loading = false
    }

    func isNearEnd(_ id: String?) -> Bool {
        guard let id, let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        return index >= entries.count - 3
    }

    func load(api: APIClient, search: String? = nil) async {
        if let search {
            generation = UUID()
            entries = []; feedID = nil; cursor = nil; hasMore = true; loading = false
            query = search; requestQuery = search; roundVideoIDs = []
            emptySearch = nil
        }
        guard !loading else { return }
        let current = generation
        loading = true
        error = nil
        defer { if generation == current { loading = false } }
        do {
            var sawInvalidMedia = false
            // Skip a few duplicate/invalid pages, but never spin on an empty service.
            for _ in 0..<3 {
                if !hasMore {
                    // Do not replace an unmatched explicit query with recommendations.
                    if entries.isEmpty, requestQuery.nilIfBlank != nil { break }
                    feedID = nil; cursor = nil; roundVideoIDs = []
                    requestQuery = "" // Finished search/collection -> fresh recommendation round.
                    hasMore = true
                }
                let previousCursor = cursor
                let response = try await api.feed(query: requestQuery, feedID: feedID, cursor: cursor)
                try Task.checkCancellation()
                guard current == generation else { return }
                let playable = response.list.compactMap(\.clip)
                let rejected = response.list.count - playable.count
                if rejected > 0 {
                    sawInvalidMedia = true
                    diagnostics.notice("Lesson feed discarded \(rejected) rows with missing IDs or unusable media addresses")
                }
                let additions = playable.filter { roundVideoIDs.insert($0.id).inserted }
                    .map { PlaybackQueueEntry(id: UUID().uuidString, clip: $0) }
                feedID = response.feedId?.nilIfBlank
                cursor = response.nextCursor?.nilIfBlank
                hasMore = response.hasMore && cursor != nil && cursor != previousCursor
                if !additions.isEmpty { entries += additions; return }
                if response.list.isEmpty {
                    hasMore = false
                    break
                }
            }
            if entries.isEmpty {
                if sawInvalidMedia {
                    error = query.nilIfBlank == nil ? "No playable videos were returned. Try again."
                                                  : "Check the link and try again."
                } else if requestQuery.nilIfBlank != nil {
                    emptySearch = BrowserLessonSearch(query: requestQuery)
                }
            }
            if !entries.isEmpty { error = "No more videos are available right now. Try again." }
        } catch is CancellationError {
            // Leaving a screen/search is not a service failure.
        } catch {
            if current == generation, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
struct DiscoverView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    private let canDismiss: Bool
    private let onExit: (() -> Void)?
    private let returnToLinkInput: (() -> Void)?
    @EnvironmentObject private var offline: OfflineStore
    private var displayEntries: [PlaybackQueueEntry] {
        feed.entries.map { PlaybackQueueEntry(id: $0.id, clip: offline.playable($0.clip)) }
    }
    private let morePageID = "recommendation-tail"
    @EnvironmentObject private var api: APIClient
    @StateObject private var feed = FeedStore()
    @StateObject private var players = PlaybackPool()
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var visible = false
    @State private var activeID: String?
    @State private var browserSearch: PolicyDocument?
    @State private var loadedUserID: String?
    init(initialSearch: String = "", canDismiss: Bool = false, onExit: (() -> Void)? = nil,
         returnToLinkInput: (() -> Void)? = nil) {
        self.canDismiss = canDismiss
        self.onExit = onExit
        self.returnToLinkInput = returnToLinkInput
        _search = State(initialValue: initialSearch)
    }
    var body: some View {
        VStack(spacing: 0) {
            PlayerHeader(exit: canDismiss || onExit != nil ? exitPlayer : nil)
            if api.session == nil || feed.entries.isEmpty {
                lessonStatusPage
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(displayEntries) { entry in
                            let clip = entry.clip
                            Group {
                                if let playback = players.controllers[entry.id] {
                                    ClipPage(clip: clip, active: activeID == entry.id, playback: playback,
                                             didStartPlaying: { players.prepareNext(after: entry.id) },
                                             didStopPlaying: { if activeID == entry.id { players.suspend() } },
                                             onSwipeExit: exitPlayer)
                                } else {
                                    PlayerPoster(url: clip.coverURL)
                                }
                            }.containerRelativeFrame([.horizontal, .vertical]).clipped().id(entry.id)
                        }
                        if !feed.entries.isEmpty {
                            VStack(spacing: 16) {
                                if let error = feed.error { ErrorNote(message: error) }
                                ActionButton(title: feed.loading ? "Loading videos…" : feed.error == nil ? "Load more" : "Try again",
                                             primary: false) { Task { await feed.load(api: api) } }
                                    .disabled(feed.loading)
                            }.pageHorizontalMargins()
                                .containerRelativeFrame([.horizontal, .vertical]).id(morePageID)
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.paging).scrollPosition(id: $activeID, anchor: .top).scrollIndicators(.hidden)
                    .onChange(of: activeID) { _, id in
                        players.update(entries: displayEntries, selectedID: id)
                    }
            }
        }.swevoScreenBackground()
            .modifier(PlayerPagingAccess(entries: displayEntries, selectedID: $activeID, tailID: morePageID, players: players))
            .onChange(of: library.downloadsRequest) { _, request in
                if request != nil { players.releaseAll(); if canDismiss { dismiss() } }
            }
            .onAppear { visible = true; players.update(entries: displayEntries, selectedID: activeID) }
            .task(id: api.session?.userId.value) { await loadInitialFeed() }
            .onChange(of: activeID) { _, id in
                guard visible, api.session != nil,
                      id == morePageID || feed.isNearEnd(id) else { return }
                Task { guard visible else { return }; await feed.load(api: api) }
            }
            .onChange(of: feed.entries) { previous, entries in
                guard visible else { return }
                if activeID == morePageID, entries.count > previous.count {
                    activeID = entries[previous.count].id
                } else if !entries.contains(where: { $0.id == activeID }) { activeID = entries.first?.id }
                players.update(entries: displayEntries, selectedID: activeID)
            }
            .onDisappear { visible = false; feed.invalidatePendingLoad(); players.releaseAll() }
            .fullScreenCover(item: $browserSearch) { document in
                PolicyBrowser(document: document, webSearch: true)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { players.suspend() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in players.trimMemory() }
    }

    private var lessonStatusPage: some View {
        let ready = loadedUserID != nil && loadedUserID == api.session?.userId.value
        let empty = ready && feed.entries.isEmpty && !feed.loading && feed.error == nil
        return ScenePage(artwork: empty ? nil : "SceneLessons", depth: empty ? 0 : 128,
                         artworkOpacity: 0.50) { _ in
            if api.session == nil {
                ConnectionPanel(loadingTitle: "Connecting to the video service…")
            } else if feed.loading || !ready {
                HStack(spacing: 12) {
                    ProgressView().tint(SwevoStyle.accent).accessibilityHidden(true)
                    LocalizedText(search.nilIfBlank == nil ? "Loading videos…" : "Finding video…")
                        .font(.capture(.subheadline))
                }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            } else if let error = feed.error {
                VStack(alignment: .leading, spacing: 12) {
                    MessagePanel(title: "Couldn’t load videos", message: error, actionTitle: "Try again") {
                        Task { await loadInitialFeed() }
                    }
                    if search.nilIfBlank != nil, let returnToLinkInput {
                        EmptyStateAction(title: "Edit link", symbol: .link, action: returnToLinkInput)
                    }
                }
            }
        } content: { container in
            if empty {
                let request = feed.emptySearch
                VStack(alignment: .leading, spacing: 14) {
                    EmptyStateScene(artwork: "EmptyLessons", title: request == nil ? "No videos available" : "No matching video",
                                    message: request == nil ? nil : "Check the link and try again.", container: container)
                    if request == nil {
                        EmptyStateAction(title: "Try again", symbol: .feed, primary: true) {
                            Task { await loadInitialFeed() }
                        }
                    }
                    if let returnToLinkInput {
                        EmptyStateAction(title: "Edit link", symbol: .link, primary: request != nil, action: returnToLinkInput)
                    }
                    if let request, WebAddress.media(request.query) == nil, WebAddress.landingCode(request.query) != nil {
                        EmptyStateAction(title: "Search in browser", symbol: .search, primary: returnToLinkInput == nil) {
                            openBrowserSearch(request)
                        }
                    }
                }
            }
        }
    }

    private func loadInitialFeed() async {
        loadedUserID = nil
        guard let userID = api.session?.userId.value else { return }
        await feed.load(api: api, search: search)
        guard !Task.isCancelled, api.session?.userId.value == userID else { return }
        loadedUserID = userID
        activeID = feed.entries.first?.id
    }

    private func openBrowserSearch(_ request: BrowserLessonSearch) {
        guard let url = request.url else { return }
        players.suspend()
        browserSearch = PolicyDocument(title: "Web search", url: url)
    }
    private func exitPlayer() {
        guard canDismiss || onExit != nil else { return }
        players.releaseAll()
        if let onExit { onExit() } else { dismiss() }
    }

}

struct PlayerScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    let route: PlayerRoute
    @State private var visible = false
    @State private var activeID: String?
    @StateObject private var feed: FeedStore
    @StateObject private var players = PlaybackPool()
    @Environment(\.scenePhase) private var scenePhase
    private let morePageID = "collection-recommendation-tail"
    private var displayEntries: [PlaybackQueueEntry] {
        feed.entries.map { PlaybackQueueEntry(id: $0.id, clip: offline.playable($0.clip)) }
    }
    init(route: PlayerRoute) {
        self.route = route
        _activeID = State(initialValue: route.startID)
        _feed = StateObject(wrappedValue: FeedStore(seed: route.clips))
    }
    var body: some View {
        VStack(spacing: 0) {
            PlayerHeader(exit: exitPlayer)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(displayEntries) { entry in
                            let clip = entry.clip
                            Group {
                                if let playback = players.controllers[entry.id] {
                                    ClipPage(clip: clip, active: activeID == entry.id,
                                             supportsPaging: displayEntries.count > 1 || route.continuesRecommendations,
                                             playback: playback,
                                             didStartPlaying: { players.prepareNext(after: entry.id) },
                                             didStopPlaying: { if activeID == entry.id { players.suspend() } },
                                             onSwipeExit: exitPlayer)
                                } else { PlayerPoster(url: clip.coverURL) }
                            }.containerRelativeFrame([.horizontal, .vertical]).clipped().id(entry.id)
                        }
                        if route.continuesRecommendations {
                            VStack(spacing: 16) {
                                if let error = feed.error { ErrorNote(message: error) }
                                ActionButton(title: feed.loading ? "Loading videos…" : feed.error == nil ? "Load more" : "Try again",
                                             primary: false) {
                                    Task { await feed.load(api: api) }
                                }
                                .disabled(feed.loading)
                            }.pageHorizontalMargins()
                                .containerRelativeFrame([.horizontal, .vertical]).id(morePageID)
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging).scrollPosition(id: $activeID, anchor: .top)
                .scrollIndicators(.hidden)
                .task { proxy.scrollTo(route.startID, anchor: .top) }
            }
        }.swevoScreenBackground().preferredColorScheme(.dark)
            .onChange(of: library.downloadsRequest) { _, request in if request != nil { exitPlayer() } }
            .modifier(PlayerPagingAccess(entries: displayEntries, selectedID: $activeID, tailID: morePageID, players: players))
            .onAppear {
                visible = true
                players.update(entries: displayEntries, selectedID: activeID)
                continueFeedIfNeeded(activeID)
            }
            .onChange(of: activeID) { _, id in
                players.update(entries: displayEntries, selectedID: id)
                continueFeedIfNeeded(id)
            }
            .onChange(of: feed.entries) { previous, entries in
                guard visible else { return }
                if activeID == morePageID, entries.count > previous.count { activeID = entries[previous.count].id }
                players.update(entries: displayEntries, selectedID: activeID)
            }
            .onDisappear { visible = false; feed.invalidatePendingLoad(); players.releaseAll() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { players.suspend() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in players.trimMemory() }
    }
    private func exitPlayer() {
        players.releaseAll()
        dismiss()
    }
    private func continueFeedIfNeeded(_ id: String?) {
        guard visible, route.continuesRecommendations, id == morePageID || feed.isNearEnd(id) else { return }
        Task { guard visible else { return }; await feed.load(api: api) }
    }
}

private struct PlaybackGateKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
    var playbackGatePresented: Bool {
        get { self[PlaybackGateKey.self] }
        set { self[PlaybackGateKey.self] = newValue }
    }
}

// Enforce admission at the paging boundary, so denied pages cannot strand the
// user on a succession of unplayable videos. Returning to admitted clips is free.
private struct PlayerPagingAccess: ViewModifier {
    let entries: [PlaybackQueueEntry]
    @Binding var selectedID: String?
    let tailID: String
    @ObservedObject var players: PlaybackPool
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var admittedID: String?
    @State private var requestedID: String?
    @State private var showingWatchOptions = false
    @State private var swipeOrigin: String?
    @State private var trackingSwipe = false
    @State private var swipeEnded: UUID?
    @AppStorage("swevo.player.completedSwipeHint.v6") private var completedHint = false

    func body(content: Content) -> some View {
        content
            .environment(\.playbackGatePresented, showingWatchOptions)
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { value in
                guard !showingWatchOptions, abs(value.translation.height) > abs(value.translation.width) else { return }
                if !trackingSwipe { trackingSwipe = true; swipeOrigin = admittedID; swipeEnded = nil }
            }.onEnded { _ in swipeEnded = UUID() })
            .task(id: swipeEnded) {
                guard swipeEnded != nil else { return }
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                trackingSwipe = false; swipeOrigin = nil
            }
            .onAppear { admit(selectedID) }
            .onChange(of: selectedID) { _, value in admit(value) }
            .fullScreenCover(isPresented: $showingWatchOptions, onDismiss: finishWatchOptions) {
                WatchLimitPrompt()
            }
    }
    private func canWatch(_ id: String) -> Bool {
        guard let clip = entries.first(where: { $0.id == id })?.clip else { return false }
        return clip.playbackURL.isFileURL || quota.mayWatch(clip.id, premium: commerce.premium)
    }
    private func admit(_ id: String?) {
        guard !showingWatchOptions, let id else { return }
        if let admittedID, !entries.contains(where: { $0.id == admittedID }) { self.admittedID = nil }
        let isTail = id == tailID
        if isTail { quota.resetIfNeeded() }
        if canWatch(id) || (isTail && !quota.canRequestReward(for: .watch, premium: commerce.premium)) {
            if !isTail {
                if trackingSwipe, let swipeOrigin, swipeOrigin != id, admittedID != id {
                    completedHint = true
                }
                admittedID = id
            }
            return
        }
        guard isTail || entries.contains(where: { $0.id == id }) else { return }
        players.controllers.values.forEach { $0.pause() }
        players.suspend()
        if let admittedID, admittedID != id {
            // A new deliberate swipe may prompt again; dismissal itself never does.
            if quota.canRequestReward(for: .watch, premium: commerce.premium) {
                requestedID = id
                showingWatchOptions = true
            }
            selectedID = admittedID
        } else {
            admittedID = id
            if quota.claimWatchLimitPrompt(premium: commerce.premium) {
                requestedID = id
                showingWatchOptions = true
            }
        }
    }

    private func finishWatchOptions() {
        guard let requestedID else { return }
        self.requestedID = nil
        quota.resetIfNeeded()
        if canWatch(requestedID) || (requestedID == tailID && !quota.canRequestReward(for: .watch, premium: commerce.premium)) {
            selectedID = requestedID
        }
    }
}

private enum WatchAccessPage: String, Identifiable {
    case options, membership
    var id: String { rawValue }
}

private struct WatchLimitPrompt: View {
    private static let maximumWidth: CGFloat = 352
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var showingPlans = false
    @State private var adAttempt: AdAttempt?
    @State private var adTask: Task<Void, Never>?
    @State private var adUnavailable = false

    private struct AdAttempt {
        let previousCompletion: UUID?
        let previousNotice: UUID?
    }

    private var rewardNotice: LuckyRewardNotice? {
        guard let adAttempt, let notice = ads.luckyReward, notice.id != adAttempt.previousNotice else { return nil }
        return notice
    }
    private var canContinue: Bool {
        commerce.premium || (quota.error == nil && (quota.unlimited || quota.watchesLeft > 0))
    }
    private var canStartAd: Bool {
        quota.canRequestReward(for: .watch, premium: commerce.premium)
            && !ads.busy && !ads.isPresenting && !ads.isPreparingAppOpen
    }
    private var title: String {
        if rewardNotice != nil { return "No ad available" }
        if canContinue { return "Your viewing allowance has been updated." }
        return "Daily view limit reached"
    }

    var body: some View {
        Group {
            if showingPlans {
                MembershipView(showsRewardOptions: false)
            } else {
                dialog
            }
        }
        .presentationBackground(.clear)
        .onChange(of: ads.completedReward) { _, completion in
            guard let adAttempt, let completion, completion != adAttempt.previousCompletion else { return }
            close()
        }
        .onDisappear {
            if !ads.isPresenting { cancelAdRequest() }
        }
    }

    private var dialog: some View {
        GeometryReader { container in
            let area = visibleArea(in: container)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 8) {
                        LocalizedText(title)
                            .font(.capture(.title3, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($titleFocused)
                        IconButton(symbol: .close, label: "Close", action: close)
                            .disabled(ads.isPresenting)
                    }
                    choices
                }
                .foregroundStyle(SwevoStyle.paper)
                .padding(16)
                .frame(maxWidth: Self.maximumWidth)
                .swevoGlass(cornerRadius: 24)
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: area.height)
            }
            .frame(width: area.width, height: area.height)
            .padding(.leading, area.minX).padding(.top, area.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.black.opacity(0.62).ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { if !ads.isPresenting { close() } }
        .onAppear { titleFocused = true }
    }

    @ViewBuilder private var choices: some View {
        let notice = rewardNotice
        if notice != nil || canContinue {
            if let notice {
                LocalizedText(notice.message).font(.capture(.subheadline))
                    .foregroundStyle(SwevoStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ActionButton(title: "Continue watching", action: close)
                .disabled(ads.isPresenting)
        } else {
            ActionButton(title: adAttempt != nil && ads.busy ? "Loading ad…" : "Watch an ad for more views",
                         action: requestAd)
                .disabled(!canStartAd)
                .accessibilityIdentifier("watchLimit.watchAd")
            ActionButton(title: "View Plus plans", primary: false) {
                cancelAdRequest()
                showingPlans = true
            }
            .disabled(ads.isPresenting)
            .accessibilityIdentifier("watchLimit.viewPlans")
            if adAttempt != nil, !ads.busy, !ads.isPresenting {
                if let error = ads.error {
                    ErrorNote(message: error)
                } else if let message = ads.message ?? (adUnavailable ? "No ad available" : nil) {
                    LocalizedText(message).font(.capture(.footnote))
                        .foregroundStyle(SwevoStyle.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func requestAd() {
        guard canStartAd else { return }
        adTask?.cancel()
        let attempt = AdAttempt(previousCompletion: ads.completedReward, previousNotice: ads.luckyReward?.id)
        adAttempt = attempt
        adUnavailable = false
        adTask = Task {
            await ads.watch(commerce: commerce, quota: quota, kind: .watch)
            guard !Task.isCancelled else { return }
            adTask = nil
            adUnavailable = !ads.isPresenting && rewardNotice == nil && ads.completedReward == attempt.previousCompletion
        }
    }

    private func cancelAdRequest() {
        if rewardNotice != nil { ads.luckyReward = nil }
        if let adTask {
            adTask.cancel()
            ads.cancelRewardLoading()
        }
        adTask = nil
        adAttempt = nil
    }

    private func close() {
        cancelAdRequest()
        dismiss()
    }

    private func visibleArea(in container: GeometryProxy) -> CGRect {
        var area = CGRect(origin: .zero, size: container.size)
        guard #available(iOS 27.1, *) else { return area }
        let regions = container.reservedRegions(kind: .occlusion) + container.reservedRegions(kind: .division)
        for region in regions where region.isActive {
            let width = min(Self.maximumWidth, area.width)
            let column = CGRect(x: area.midX - width / 2, y: area.minY, width: width, height: area.height)
            let obstruction = area.intersection(region.frame)
            guard !obstruction.isEmpty, column.intersects(obstruction) else { continue }
            let pane = largestPane(in: area, excluding: obstruction)
            if !pane.isEmpty { area = pane }
        }
        return area
    }
}

private func largestPane(in area: CGRect, excluding obstruction: CGRect) -> CGRect {
    let candidates = [
        CGRect(x: area.minX, y: area.minY, width: obstruction.minX - area.minX, height: area.height),
        CGRect(x: obstruction.maxX, y: area.minY, width: area.maxX - obstruction.maxX, height: area.height),
        CGRect(x: area.minX, y: area.minY, width: area.width, height: obstruction.minY - area.minY),
        CGRect(x: area.minX, y: obstruction.maxY, width: area.width, height: area.maxY - obstruction.maxY)
    ]
    return candidates.max { $0.width * $0.height < $1.width * $1.height } ?? area
}

// Count the cue only after an uninterrupted presentation. The old flag could
// be consumed by buffering or a sheet before the user had time to read it.
private struct PlayerSwipeHint: View {
    let eligible: Bool
    @AppStorage("swevo.player.completedSwipeHint.v6") private var alreadyShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var showing = false
    var body: some View {
        VStack(spacing: 0) {
            if showing && eligible && !alreadyShown && phase == .active {
                HStack(spacing: 7) {
                    Image("SwipeHand").resizable().scaledToFit()
                        .frame(width: 20, height: 20).accessibilityHidden(true)
                    LocalizedText("Swipe up or down to change videos")
                        .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4).padding(.top, 3)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showing)
        .task(id: eligible && phase == .active) {
            showing = false
            guard eligible, phase == .active, !alreadyShown else { return }
            do {
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                showing = true
                try await Task.sleep(for: .seconds(6))
                try Task.checkCancellation()
                alreadyShown = true
            } catch { }
            showing = false
        }
    }
}

private enum PlayerOptions: String, Identifiable {
    case speed, more
    var id: String { rawValue }
}

struct ClipPage: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    @Environment(\.playbackGatePresented) private var pagingGate
    @Environment(\.dynamicTypeSize) private var typeSize
    let clip: LessonClip
    let active: Bool
    var supportsPaging = true
    @ObservedObject var playback: PlaybackController
    var didStartPlaying: () -> Void = {}
    var didStopPlaying: () -> Void = {}
    var onSwipeExit: () -> Void = {}
    @State private var visible = false
    @State private var firstFrameReady = false
    @State private var accessChecked = false
    @State private var resumeAfterSheet = false
    @State private var resumeAfterInterruption = false
    @State private var watchAccess: WatchAccessPage?
    @State private var options: PlayerOptions?
    @State private var editorAfterOptions = false
    @State private var editor = false
    @State private var downloadPanel = false
    @State private var downloadStarting = false
    @State private var downloadReward = false
    @State private var recorded = false
    @State private var allowed = false
    @State private var scrubbing = false
    @State private var dockContentHeight: CGFloat = 136
    @State private var favoriteError: String?

    private var hasOpenPanel: Bool { watchAccess != nil || options != nil || editor || downloadPanel || downloadReward }
    private var canControlPlayback: Bool {
        active && allowed && firstFrameReady && phase == .active && !ads.isPresenting
            && !pagingGate && !hasOpenPanel
    }
    var body: some View {
        playerViewport
            .foregroundStyle(SwevoStyle.paper)
            .clipped()
            .onAppear { visible = true; if active { activate() } }
            .onChange(of: active) { _, active in
                resumeAfterInterruption = false
                if active { activate() } else { favoriteError = nil; resumeAfterSheet = false; playback.pause() }
            }
            .onChange(of: playback.isPlaying) { _, playing in
                if playing, active, visible, !recorded {
                    recorded = clip.playbackURL.isFileURL || quota.recordWatch(clip.id, premium: commerce.premium)
                    if clip.playbackURL.isFileURL {
                        offline.markOpened(clip.id)
                    } else if recorded, let owner = commerce.api.session?.userId.value {
                        library.recordWatch(clip, owner: owner)
                    }
                    if !recorded { playback.pause(); allowed = false }
                }
                if playing, active, recorded { didStartPlaying() }
                if !playing, active { didStopPlaying() }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                guard active, visible, playback.isPlaying, !clip.playbackURL.isFileURL else { return }
                if !quota.recordWatch(clip.id, premium: commerce.premium) { playback.pause(); allowed = false }
            }
            .onChange(of: phase) { _, state in
                if state != .active { interruptPlayback() } else { resumeIfNeeded() }
            }
            .onChange(of: ads.isPresenting) { _, presenting in
                if presenting { interruptPlayback() } else { resumeIfNeeded() }
            }
            .onDisappear { visible = false; resumeAfterInterruption = false; playback.pause() }
            .onChange(of: library.downloadsRequest) { _, request in
                if request != nil {
                    editorAfterOptions = false
                    options = nil
                    downloadPanel = false
                    editor = false
                }
            }
            .onChange(of: watchAccess != nil) { _, presented in if presented { playback.pause() } }
            .onChange(of: pagingGate) { _, presented in
                if presented { playback.pause() } else if active { activate() }
            }
            .fullScreenCover(item: $watchAccess, onDismiss: { if active { activate() } }) { page in
                switch page {
                case .options: WatchLimitPrompt()
                case .membership: MembershipView(showsRewardOptions: false)
                }
            }
            .sheet(item: $options, onDismiss: finishOptions) { selection in
                playbackOptions(selection)
            }
            .sheet(isPresented: $editor, onDismiss: resumeAfterControls) { EditorSheet() }
            .sheet(isPresented: $downloadPanel, onDismiss: resumeAfterControls) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SheetHeading(title: "Downloads") { downloadPanel = false }
                        Text(verbatim: clip.title).font(.capture(.subheadline)).lineLimit(2)
                        OfflineDownloadButton(clip: clip, starting: downloadStarting)
                    }.padding(22)
                }.swevoScreenBackground().presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $downloadReward, onDismiss: resumeAfterControls) {
                MembershipView(rewardKind: .download)
            }
    }
    private var playerViewport: some View {
        GeometryReader { viewport in
            let (area, fold) = playbackArea(in: viewport)
            let size = area.size
            let sideBySide = fold.map { $0.height >= $0.width }
                ?? (size.width >= 620 && size.width > size.height * 1.35 && size.height < 460)
            let gap = fold.map { sideBySide ? $0.width : $0.height } ?? (sideBySide ? 8 : 0)
            let dockWidth = sideBySide ? fold.map { size.width - $0.maxX } ?? min(320, size.width * 0.38) : nil
            let dockHeight = sideBySide ? nil : fold.map { size.height - $0.maxY }
            let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .center, spacing: gap))
                                    : AnyLayout(VStackLayout(spacing: gap))
            layout {
                videoStage
                    .frame(width: sideBySide ? fold?.minX : nil, height: sideBySide ? nil : fold?.minY)
                playbackDock(heightLimit: sideBySide ? size.height : dockHeight ?? size.height * 0.46)
                    .frame(width: dockWidth, height: dockHeight)
            }
            .frame(width: size.width, height: size.height)
            .padding(.leading, area.minX).padding(.top, area.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var videoStage: some View {
        ZStack {
            SwevoStyle.background
            VideoSurface(player: playback.player, fill: false, onReadyForDisplay: { firstFrameReady = $0 })
                .allowsHitTesting(false)
            if !firstFrameReady {
                PlayerPoster(url: clip.coverURL)
            }
            Color.clear.contentShape(Rectangle())
                .onTapGesture {
                    guard canControlPlayback, playback.error == nil else { return }
                    playback.toggle()
                }
                .simultaneousGesture(DragGesture(minimumDistance: 32).onEnded { value in
                    guard active, visible, phase == .active, !ads.isPresenting,
                          !pagingGate, !hasOpenPanel, !scrubbing,
                          value.translation.width < -90,
                          abs(value.translation.width) > abs(value.translation.height) * 1.7 else { return }
                    onSwipeExit()
                })
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func playbackDock(heightLimit: CGFloat) -> some View {
        let height = min(dockContentHeight, max(0, heightLimit - 28))
        return ScrollView {
            dockContent
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height.rounded(.up) }) {
                    dockContentHeight = $0
                }
        }
        .frame(height: height)
        .scrollDisabled(dockContentHeight <= height)
        .scrollBounceBehavior(.basedOnSize)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: 620)
        .swevoGlass(cornerRadius: 18)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private var dockContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            playbackFeedback
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: clip.title).font(.capture(.subheadline, weight: .semibold))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let channel = clip.channel.nilIfBlank {
                    Text(verbatim: channel).font(.capture(.caption))
                        .foregroundStyle(SwevoStyle.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

            PlayerProgressControl(playback: playback, timeline: playback.timeline,
                                  enabled: canControlPlayback, canResume: canControlPlayback,
                                  scrubbing: $scrubbing, tint: SwevoStyle.accent, showsTimecodes: true)
                .padding(.horizontal, 4)
            Divider().overlay(SwevoStyle.line).allowsHitTesting(false).accessibilityHidden(true)
            dockActions
            if active, let favoriteError {
                HStack(spacing: 6) {
                    ErrorNote(message: favoriteError)
                    IconButton(symbol: .close, label: "Dismiss message") { self.favoriteError = nil }
                }
            }
            PlayerSwipeHint(eligible: supportsPaging && active && visible && playback.error == nil &&
                            !pagingGate && !hasOpenPanel && !ads.isPresenting)
        }
    }

    private var dockActions: some View {
        let play = Button { playback.toggle() } label: {
            Glyph(symbol: playback.intendsPlayback ? .pause : .play, size: 19, tint: SwevoStyle.ink)
                .frame(width: 44, height: 44)
                .background(SwevoStyle.accent, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(LocalizedStringKey(playback.intendsPlayback ? "Pause video" : "Play video"))
        .accessibilityIdentifier("player.playPause")
        .disabled(!canControlPlayback || playback.error != nil)
        let speed = Button { showOptions(.speed) } label: {
            VStack(spacing: 3) {
                Text(verbatim: rateText(playback.speed)).font(.capture(.subheadline, weight: .semibold))
                    .monospacedDigit().foregroundStyle(SwevoStyle.accent)
                LocalizedText("Speed").font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Speed")
        .accessibilityValue(Text(verbatim: rateText(playback.speed)))
        .accessibilityIdentifier("player.speed")
        let saved = library.isSaved(clip)
        let favorite = PlayerDockButton(artwork: saved ? .saved : .save, title: saved ? "Saved" : "Save",
                                        accessibilityTitle: saved ? "Remove from favorites" : "Save to favorites",
                                        selected: saved, action: save)
        let download = PlayerCacheButton(clip: clip, starting: downloadStarting, action: cacheVideo)
        let more = PlayerDockButton(artwork: .more, title: "More", accessibilityTitle: "Playback options") {
            showOptions(.more)
        }

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                play
                speed.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                favorite.fixedSize(horizontal: true, vertical: false)
                download.fixedSize(horizontal: true, vertical: false)
                more.fixedSize(horizontal: true, vertical: false)
            }
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    play
                    speed
                    Spacer(minLength: 0)
                    more
                }
                HStack(spacing: 5) {
                    favorite.frame(maxWidth: .infinity)
                    download.frame(maxWidth: .infinity)
                }
            }
        }
        .disabled(!active || hasOpenPanel || pagingGate || ads.isPresenting)
    }

    @ViewBuilder private var playbackFeedback: some View {
        if active && visible && !pagingGate && !hasOpenPanel {
            if accessChecked && !allowed {
                let limitReached = quota.canRequestReward(for: .watch, premium: commerce.premium)
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText(limitReached ? "Daily view limit reached" : "Playback unavailable")
                        .font(.capture(.subheadline, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: limitReached ? "Get more views" : "View membership") {
                        watchAccess = limitReached ? .options : .membership
                    }
                }.padding(4)
            } else if let error = playback.error {
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("Couldn’t load video").font(.capture(.subheadline, weight: .semibold))
                    ErrorNote(message: error)
                    ActionButton(title: "Try again", primary: false) { activate(reload: true) }
                }.padding(4)
            } else if allowed && (playback.isLoading || (!firstFrameReady && playback.intendsPlayback)) {
                PlayerLoadingFeedback(buffering: firstFrameReady)
            }
        }
    }

    private func playbackArea(in viewport: GeometryProxy) -> (CGRect, CGRect?) {
        var area = CGRect(origin: .zero, size: viewport.size)
        guard #available(iOS 27.1, *) else { return (area, nil) }
        // The default frames mirror with the layout's leading and trailing edges.
        for region in viewport.reservedRegions(kind: .occlusion) where region.isActive {
            let obstruction = area.intersection(region.frame)
            if !obstruction.isNull && !obstruction.isEmpty {
                area = largestPane(in: area, excluding: obstruction)
            }
        }
        for region in viewport.reservedRegions(kind: .division) where region.isActive {
            let split = area.intersection(region.frame)
            guard !split.isNull, !split.isEmpty else { continue }
            let vertical = split.height >= split.width
            let before = vertical ? split.minX - area.minX : split.minY - area.minY
            let after = vertical ? area.maxX - split.maxX : area.maxY - split.maxY
            if min(before, after) >= (vertical ? 164 : 100) {
                return (area, split.offsetBy(dx: -area.minX, dy: -area.minY))
            }
            area = largestPane(in: area, excluding: split)
        }
        return (area, nil)
    }

    private func rateText(_ rate: Float) -> String {
        "\(rate.formatted(.number.locale(locale)))×"
    }

    private func showOptions(_ selection: PlayerOptions) {
        resumeAfterSheet = playback.intendsPlayback
        playback.pause()
        options = selection
    }

    private func finishOptions() {
        if editorAfterOptions {
            editorAfterOptions = false
            if active && visible && !pagingGate { editor = true }
        } else {
            resumeAfterControls()
        }
    }

    private func playbackOptions(_ selection: PlayerOptions) -> some View {
        ScenePage { _ in
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 8) {
                    SceneTitle(selection == .speed ? "Speed" : "Playback options", size: 28)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    IconButton(symbol: .close, label: "Close") { options = nil }
                        .swevoGlass(cornerRadius: 16)
                }
                if selection == .speed {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach([Float(0.5), 1, 1.5, 2], id: \.self) { rate in
                                Button {
                                    playback.setSpeed(rate)
                                    options = nil
                                } label: {
                                    Text(verbatim: rateText(rate)).font(.capture(.headline)).monospacedDigit()
                                        .fixedSize().padding(.horizontal, 14).frame(minHeight: 44)
                                        .foregroundStyle(playback.speed == rate ? SwevoStyle.ink : SwevoStyle.paper)
                                        .background(playback.speed == rate ? SwevoStyle.accent : SwevoStyle.raised,
                                                    in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityAddTraits(playback.speed == rate ? .isSelected : [])
                            }
                        }
                    }.scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                } else {
                    VideoExportEntry(clip: clip)
                    ActionButton(title: "Edit a local video", primary: false) {
                        editorAfterOptions = true
                        options = nil
                    }
                    LocalizedText("Supported streams adjust quality to your connection.")
                        .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.presentationDetents([.medium, .large])
    }

    private func activate(reload: Bool = false) {
        guard active, visible, phase == .active, !ads.isPresenting, !pagingGate,
              !hasOpenPanel else { return }
        recorded = false
        accessChecked = true
        allowed = clip.playbackURL.isFileURL || quota.mayWatch(clip.id, premium: commerce.premium)
        if !allowed {
            playback.pause()
            // Paging owns automatic prompts; this page retains the explicit reward action.
            return
        }
        if playback.loadedURL != clip.playbackURL || reload {
            firstFrameReady = false
            playback.load(clip.playbackURL, autoplay: true)
        }
        else { playback.play() }
    }
    private func resumeAfterControls() {
        guard resumeAfterSheet, active, visible, phase == .active,
              !ads.isPresenting, !hasOpenPanel else { return }
        resumeAfterSheet = false
        activate()
    }
    private func interruptPlayback() {
        if active, visible, playback.intendsPlayback { resumeAfterInterruption = true }
        playback.pause()
    }
    private func resumeIfNeeded() {
        guard resumeAfterInterruption || resumeAfterSheet, active, visible, phase == .active,
              !ads.isPresenting, !hasOpenPanel else { return }
        resumeAfterInterruption = false
        resumeAfterSheet = false
        activate()
    }
    private func cacheVideo() {
        // Acknowledge every tap before starting asynchronous preparation. The
        // presented panel observes the store through completion and late errors.
        if downloadStarting || offline.cached(clip.id) != nil || offline.busy || clip.playbackURL.isFileURL {
            showDownloadPanel()
        } else if !quota.mayDownload(clip.id, premium: commerce.premium) {
            resumeAfterSheet = playback.intendsPlayback
            playback.pause(); downloadReward = true
        } else {
            downloadStarting = true
            showDownloadPanel()
            Task { @MainActor in
                defer { downloadStarting = false }
                await offline.download(clip)
            }
        }
    }
    private func showDownloadPanel() {
        guard !downloadPanel else { return }
        resumeAfterSheet = playback.intendsPlayback
        playback.pause(); downloadPanel = true
    }
    private func save() {
        favoriteError = nil
        if !library.toggle(offline.cached(clip.id)?.clip ?? clip) {
            favoriteError = "Favorites could not be updated. Please try again."
            library.error = nil // This full-screen surface owns the feedback.
        }
    }
}

private struct PlayerHeader: View {
    let exit: (() -> Void)?

    var body: some View {
        VStack(spacing: 3) {
            if let exit {
                PlayerExitButton(action: exit)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .pageHorizontalMargins()
            }
            DownloadCompletionNotice()
        }
    }
}

private struct PlayerExitButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Glyph(symbol: .close, size: 12, tint: SwevoStyle.paper)
                LocalizedText("Exit").font(.capture(.footnote, weight: .semibold))
                    .foregroundStyle(SwevoStyle.paper).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .frame(minWidth: 44, minHeight: 44)
            .swevoGlass(cornerRadius: 14)
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityLabel(LocalizedStringKey("Exit"))
            .accessibilityIdentifier("player.exit")
    }
}

private struct PlayerCacheButton: View {
    let clip: LessonClip
    let starting: Bool
    let action: () -> Void
    @EnvironmentObject private var offline: OfflineStore
    private var cached: Bool { offline.cached(clip.id) != nil || clip.playbackURL.isFileURL }
    private var status: String {
        if cached { return "Offline" }
        if offline.downloadingID == clip.id { return "\(Int(offline.progress * 100))%" }
        if starting || offline.preparingID == clip.id { return "Preparing…" }
        return "Download"
    }
    var body: some View {
        Button(action: action) {
            PlayerDockLabel(artwork: .download, title: status, selected: cached)
        }.buttonStyle(PressStyle())
            .accessibilityLabel(LocalizedStringKey(cached ? "Available offline" : "Download for offline viewing"))
            .accessibilityValue(LocalizedStringKey(status))
            .accessibilityIdentifier("player.cacheVideo")
    }
}

struct PlayerProgressControl: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var timeline: PlaybackTimeline
    let enabled: Bool
    let canResume: Bool
    @Binding var scrubbing: Bool
    var tint: Color = .white
    var showsPlayhead = false
    var showsTimecodes = false
    @State private var scrubPosition: Double = 0
    @State private var resumeAfterScrub = false

    var body: some View {
        if showsTimecodes {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(verbatim: durationLabel(scrubbing ? scrubPosition : timeline.elapsed))
                        .foregroundStyle(tint)
                    Spacer(minLength: 6)
                    Text(verbatim: durationLabel(timeline.duration))
                        .foregroundStyle(SwevoStyle.secondary)
                }.font(.capture(.caption, weight: .semibold)).monospacedDigit()
                scrubber
            }.environment(\.layoutDirection, .leftToRight)
        } else {
            scrubber.overlay(alignment: .top) {
                if scrubbing {
                    Text(verbatim: "\(durationLabel(scrubPosition)) / \(durationLabel(timeline.duration))")
                        .environment(\.layoutDirection, .leftToRight)
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, showsPlayhead ? 6 : 0)
                        .background(showsPlayhead ? SwevoStyle.ink : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .offset(y: -8)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var scrubber: some View {
        SwevoScrubber(value: Binding(
                get: { scrubbing ? scrubPosition : timeline.elapsed },
                set: {
                    scrubPosition = $0
                    // During a drag, move the UI only. Seek once on release.
                    if !scrubbing { playback.seek($0) }
                }
            ), range: 0...max(0.01, timeline.duration), label: "Playback position",
                         tint: tint, trackHeight: scrubbing ? 5 : showsTimecodes ? 4 : 2,
                         showsPlayhead: showsPlayhead, showsThumb: showsTimecodes,
                         onEditingChanged: { editing in
                if editing {
                    scrubPosition = timeline.elapsed
                    resumeAfterScrub = playback.intendsPlayback
                    scrubbing = true
                    playback.pause()
                } else {
                    playback.seek(scrubPosition)
                    scrubbing = false
                    if resumeAfterScrub && canResume {
                        playback.play()
                    }
                    resumeAfterScrub = false
                }
            })
            .disabled(!enabled || timeline.duration <= 0 || playback.error != nil)
    }
}

private struct PlayerPoster: View {
    let url: URL?
    var body: some View {
        SwevoStyle.background.overlay {
            GeometryReader { geometry in
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        }
                    }
                }
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct PlayerLoadingFeedback: View {
    let buffering: Bool
    @State private var revealed = false
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().tint(SwevoStyle.accent).accessibilityHidden(true)
            LocalizedText(buffering ? "Buffering…" : "Loading…")
                .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
        }.padding(.horizontal, 4).opacity(revealed ? 1 : 0).accessibilityHidden(!revealed)
            .task {
                do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); revealed = true }
                catch { }
            }
            .onDisappear { revealed = false }
    }
}

struct SwevoScrubber: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    var tint: Color = SwevoStyle.accent
    var trackHeight: CGFloat = 4
    var showsPlayhead = false
    var showsThumb = false
    var onEditingChanged: (Bool) -> Void = { _ in }
    @GestureState private var dragging = false
    @State private var editing = false
    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard value.isFinite, range.lowerBound.isFinite, span.isFinite, span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if showsPlayhead {
                    Capsule().fill(tint).frame(width: 3, height: 44)
                        .offset(x: max(0, geometry.size.width - 3) * fraction)
                } else {
                    Capsule().fill(Color.white.opacity(0.3)).frame(height: trackHeight)
                    Capsule().fill(tint).frame(width: geometry.size.width * fraction, height: trackHeight)
                    if showsThumb {
                        Circle().fill(tint).frame(width: 10, height: 10)
                            .offset(x: max(0, geometry.size.width - 10) * fraction)
                    }
                }
            }
                .frame(width: geometry.size.width, height: 44, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).updating($dragging) { _, state, _ in state = true }.onChanged { gesture in
                    if !editing { editing = true; onEditingChanged(true) }
                    value = range.lowerBound + min(1, max(0, gesture.location.x / max(1, geometry.size.width))) * (range.upperBound - range.lowerBound)
                }.onEnded { _ in finishEditing() })
        }.frame(height: 44).environment(\.layoutDirection, .leftToRight)
            .accessibilityElement().accessibilityLabel(LocalizedStringKey(label))
            .onChange(of: dragging) { _, dragging in if !dragging { finishEditing() } }
            .accessibilityValue(durationLabel(value)).accessibilityAdjustableAction { direction in
                value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? 1 : -1)))
            }
    }
    private func finishEditing() {
        guard editing else { return }
        editing = false
        onEditingChanged(false)
    }
}

private enum PlayerArtwork: String, CaseIterable, Hashable {
    // Original single-colour playback artwork.
    case save = "PlayerFavorite", saved = "PlayerFavorited", download = "PlayerDownload", more = "PlayerMore"
}

private struct PlayerDockLabel: View {
    let artwork: PlayerArtwork
    let title: String
    let selected: Bool

    var body: some View {
        VStack(spacing: 3) {
            TintedArtwork(name: artwork.rawValue, tint: selected ? SwevoStyle.accent : SwevoStyle.paper)
                .frame(width: 19, height: 19)
            LocalizedText(title).font(.capture(.caption, weight: .semibold)).monospacedDigit()
                .foregroundStyle(selected ? SwevoStyle.accent : SwevoStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(minWidth: 44, minHeight: 44)
        .background(selected ? SwevoStyle.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

private struct PlayerDockButton: View {
    let artwork: PlayerArtwork
    let title: String
    let accessibilityTitle: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PlayerDockLabel(artwork: artwork, title: title, selected: selected)
        }.buttonStyle(PressStyle())
            .accessibilityLabel(LocalizedStringKey(accessibilityTitle))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
