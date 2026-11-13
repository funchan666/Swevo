import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    var openAccount: () -> Void
    var discover: () -> Void
    var openTools: () -> Void
    @Binding var link: String
    @State private var error: String?
    @State private var linkFailure = ""
    @State private var showingLinkFailure = false
    @State private var channel: ChannelRoute?
    @State private var searchRequest: LessonSearch?
    @State private var paywall = false
    @State private var channels: [LandingInfo] = []
    @State private var channelRetry = 0
    @State private var showingLinkGuide = false
    @State private var showingGuide = false
    @State private var showingJournal = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @SceneStorage("shot.movement") private var movement = ShotMovement.pushIn
    @SceneStorage("shot.duration") private var seconds = 6
    @SceneStorage("shot.focusLock") private var lockedFocus = false
    @FocusState private var focused: Bool
    var body: some View {
        let request = ChannelRequest(links: commerce.release?.lcList?["us"] ?? [], attempt: channelRetry)
        GeometryReader { container in
            let layout = shotWorkspaceLayout(in: container)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    layout {
                        VStack(alignment: .leading, spacing: 14) {
                            shotPlanner
                            cameraAction(.edit, title: "Review your footage", action: openTools)
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 16) {
                            linkComposer
                            connection
                            cameraAction(.feed, title: "Watch tutorials", action: discover)
                            referenceFootage
                            ShotGuideEntry(compact: true) { showingGuide = true }
                            recentLinks
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }.swevoPage()
            }
        }.swevoScreenBackground().scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnOutsideTap($focused, scope: "home-link-input")
            .sheet(item: $channel) { ChannelView(route: $0) }
            .fullScreenCover(item: $searchRequest) { request in
                DiscoverView(initialSearch: request.query, canDismiss: true) { query, clip in
                    library.record(link: query, title: clip.title)
                }
            }
            .fullScreenCover(isPresented: $showingLinkFailure) {
                AccountDecisionDialog(title: "Couldn’t open this link", message: linkFailure,
                                      confirmTitle: "Back to link", confirm: { showingLinkFailure = false })
                    .presentationBackground(.clear)
            }
            .sheet(isPresented: $paywall) { MembershipView() }
            .sheet(isPresented: $showingLinkGuide) { LinkGuideSheet() }
            .sheet(isPresented: $showingJournal) {
                ShotPracticeView(initialMovement: movement, initialSeconds: seconds, initialFocusLock: lockedFocus)
            }
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

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { headerContent }
            VStack(alignment: .leading, spacing: 6) { headerContent }
        }
    }

    @ViewBuilder private var headerContent: some View {
            Text(verbatim: "Swevo").font(.capture(.title2, display: true))
                .foregroundStyle(SwevoStyle.paper).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0).frame(maxHeight: 0)
            Button {
                paywall = true
            } label: {
                LocalizedText(commerce.premium ? "Plus" : "Get Plus")
                    .font(.capture(.footnote, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(SwevoStyle.paper)
                    .background(SwevoStyle.raised, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
            }.buttonStyle(PressStyle())
            IconButton(symbol: .settings, label: "Open Me and account settings", action: openAccount)
    }

    @ViewBuilder private var connection: some View {
        if api.session == nil { ConnectionPanel() }
        if let error {
            MessagePanel(title: "Couldn’t load lesson collections", message: error, actionTitle: "Try again") {
                channelRetry += 1
            }
        }
    }

    private var shotPlanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            LocalizedText("Plan the next shot").font(.capture(.largeTitle, display: true))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            shotFrame
            VStack(alignment: .leading, spacing: 6) {
                LocalizedText("Camera move").font(.capture(.subheadline, weight: .semibold))
                    .foregroundStyle(SwevoStyle.secondary)
                ChoiceStrip(values: ShotMovement.allCases.map(\.label), selected: movement.label) { label in
                    if let move = ShotMovement.allCases.first(where: { $0.label == label }) { movement = move }
                }
            }
            Divider().overlay(SwevoStyle.line)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { durationControls; focusControl.fixedSize(horizontal: true, vertical: false) }
                VStack(alignment: .leading, spacing: 8) { durationControls; focusControl }
            }
            Button { showingJournal = true } label: {
                HStack(spacing: 10) {
                    LocalizedText("Shot log").font(.capture(.headline, display: true))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Glyph(symbol: .edit, size: 19, tint: SwevoStyle.ink)
                }.padding(12).frame(minHeight: 49)
                    .foregroundStyle(SwevoStyle.ink)
                    .background(SwevoStyle.accent, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
            }.buttonStyle(PressStyle()).accessibilityIdentifier("practice.openJournal")
        }
    }

    private var shotFrame: some View {
        let art: GuideArtwork.Subject = switch movement {
        case .pushIn: .steady
        case .track: .track
        case .reveal: .reveal
        case .parallax: .parallax
        case .orbit, .tilt: .setup
        }
        return SwevoStyle.raised.aspectRatio(2.5, contentMode: .fit)
            .overlay { GuideArtwork(subject: art) }
            .clipShape(.rect(cornerRadius: 5))
            .accessibilityHidden(true)
    }

    private var durationControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText("Target length").font(.capture(.caption))
                .foregroundStyle(SwevoStyle.secondary)
            Text("\(seconds) s").font(.capture(.headline, display: true)).monospacedDigit()
                .accessibilityLabel(Text("Target length"))
                .accessibilityValue(Text("\(seconds) s"))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { lengthButtons }
                VStack(alignment: .leading, spacing: 6) { lengthButtons }
            }
        }
    }

    @ViewBuilder private var lengthButtons: some View {
        Button { seconds -= 1 } label: { lengthLabel("Shorter") }
            .buttonStyle(PressStyle()).disabled(seconds <= ShotPracticeJournal.amountRange.lowerBound)
        Button { seconds += 1 } label: { lengthLabel("Longer") }
            .buttonStyle(PressStyle()).disabled(seconds >= ShotPracticeJournal.amountRange.upperBound)
    }

    private func lengthLabel(_ title: String) -> some View {
        LocalizedText(title).font(.capture(.footnote, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(SwevoStyle.paper)
            .background(SwevoStyle.raised, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
    }

    private var focusControl: some View {
        Button { lockedFocus.toggle() } label: {
            LocalizedText(lockedFocus ? "Focus locked" : "Auto focus")
                .font(.capture(.caption, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.vertical, 6).frame(minHeight: 44)
                .foregroundStyle(lockedFocus ? SwevoStyle.ink : SwevoStyle.paper)
                .background(lockedFocus ? SwevoStyle.accent : SwevoStyle.raised,
                            in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityAddTraits(lockedFocus ? .isSelected : [])
    }

    @ViewBuilder private var referenceFootage: some View {
        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                LocalizedText("Camera lesson collections").font(.capture(.title3, display: true))
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

    private func shotWorkspaceLayout(in container: GeometryProxy) -> AnyLayout {
        var width = container.size.width - 40
        var occupied = false
        if #available(iOS 27.1, *) {
            let margins = container.contentMargins(for: .container, edges: .horizontal)
            width = container.size.width - margins.leading - margins.trailing
            let regions = container.reservedRegions(kind: .division) + container.reservedRegions(kind: .occlusion)
            let bounds = CGRect(origin: .zero, size: container.size)
            occupied = regions.contains { $0.isActive && bounds.intersects($0.frame) }
        }
        if width >= 560, !typeSize.isAccessibilitySize, !occupied {
            return AnyLayout(HStackLayout(alignment: .top, spacing: 24))
        }
        return AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
    }

    private var linkComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedText("Open a camera lesson").font(.capture(.headline, display: true))
                .foregroundStyle(SwevoStyle.paper).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                Glyph(symbol: .link, size: 17, tint: SwevoStyle.accent).padding(.leading, 12)
                TextField("Swevo link or lesson code", text: $link, axis: .vertical)
                    .lineLimit(1...3).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused).font(.capture(.subheadline)).foregroundStyle(SwevoStyle.paper)
                    .tint(SwevoStyle.accent)
                    .padding(.horizontal, 10).padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(LocalizedStringKey("Swevo link or lesson code"))
                if !link.isEmpty {
                    Button {
                        link = ""
                        focused = true
                    } label: {
                        Glyph(symbol: .close, size: 13, tint: SwevoStyle.paper)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(ComposerPressStyle())
                        .accessibilityLabel(LocalizedStringKey("Clear link"))
                        .accessibilityIdentifier("home.clearLink")
                }
            }
                .environment(\.layoutDirection, .leftToRight)
                .background(SwevoStyle.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? SwevoStyle.accent : SwevoStyle.line)
                        .allowsHitTesting(false)
                }
                .keyboardInputRegion("home-link-input")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { pasteButton; openLessonButton }
                VStack(alignment: .leading, spacing: 8) { openLessonButton; pasteButton }
            }
            HStack(spacing: 10) {
                allowanceLabel
                Spacer(minLength: 0)
                Button { showingLinkGuide = true } label: {
                    LocalizedText("How to").font(.capture(.caption, weight: .semibold))
                        .underline().foregroundStyle(SwevoStyle.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(ComposerPressStyle())
                    .accessibilityIdentifier("home.linkHelp")
            }
        }.padding(16).background { CaptureSurface(tone: .mist) }
    }
    private var canOpenLink: Bool { searchRequest == nil && link.nilIfBlank != nil }
    private var openLessonButton: some View {
        Button(action: resolve) {
            HStack(spacing: 10) {
                LocalizedText("Open lesson").font(.capture(.subheadline, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Glyph(symbol: .play, size: 14, tint: canOpenLink ? SwevoStyle.ink : SwevoStyle.secondary)
            }.padding(.horizontal, 14).padding(.vertical, 10)
                .frame(minHeight: 44)
                .foregroundStyle(canOpenLink ? SwevoStyle.ink : SwevoStyle.secondary)
                .background(canOpenLink ? SwevoStyle.accent : SwevoStyle.background, in: RoundedRectangle(cornerRadius: 6))
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
            LocalizedText("Paste").font(.capture(.footnote, weight: .semibold))
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
            showLinkFailure("Copy a Swevo link or lesson code first, then tap Paste.")
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
    private func cameraAction(_ symbol: SwevoGlyph, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Glyph(symbol: symbol, size: 20, tint: SwevoStyle.accent)
                LocalizedText(title).font(.capture(.headline, display: true))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.padding(12).frame(minHeight: 48)
                .foregroundStyle(SwevoStyle.paper)
                .background { CaptureSurface(tone: .mist) }
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }
    private func resolve() {
        guard let text = link.nilIfBlank, searchRequest == nil else { return }
        focused = false
        guard api.session != nil else { showLinkFailure("Your connection is not ready yet. Please try again."); return }
        // Preserve exactly what was entered. Search owns loading, errors and cursor
        // pagination; do not fall back to the old landing-page resolver.
        searchRequest = LessonSearch(query: text)
    }
    private func showLinkFailure(_ message: String) {
        linkFailure = message
        showingLinkFailure = true
    }
}

// Disabled artwork already has its own legible palette; do not fade the entire
// button into the paper surface as the shared legacy PressStyle does.
private struct ComposerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct LessonSearch: Identifiable {
    let id = UUID()
    let query: String
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
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: route.title) { dismiss() }
            ScrollView {
                LazyVStack(spacing: 18) {
                    CaptureArtwork(kind: .notebook, height: 140)
                    if items.isEmpty, !loading, error == nil { MessagePanel(title: "Nothing here yet", message: "This channel has no available videos.") }
                    ForEach(items, id: \.stableID) { item in
                        Button { open(item) } label: {
                            HStack(spacing: 16) {
                                MediaCover(url: WebAddress.media(item.coverImage), folder: item.isFolder == true)
                                    .frame(width: 80, height: 94).clipShape(RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(verbatim: item.name ?? L10n.text("Untitled")).font(.capture(.headline)).lineLimit(3)
                                    LocalizedText(item.isFolder == true ? "\(item.childrenFileNum ?? 0) videos" : durationLabel(item.length ?? 0))
                                        .font(.caption.monospacedDigit()).foregroundStyle(SwevoStyle.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Glyph(symbol: item.isFolder == true ? .folder : .play, size: 20)
                            }
                        }.buttonStyle(PressStyle())
                    }
                    if let error { ErrorNote(message: error) }
                    if hasMore { ActionButton(title: error == nil ? "Load more" : "Try again", primary: false, busy: loading) { Task { await load() } } }
                }.padding(22)
            }
        }.swevoScreenBackground().foregroundStyle(.white)
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
        VStack(spacing: 0) {
            SheetHeading(title: "Open your next lesson") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    CaptureArtwork(kind: .lesson, height: 150)
                    FeatureRow(symbol: .link, title: "1. Copy a Swevo link", detail: "Use a lesson link or code shared through Swevo.")
                    FeatureRow(symbol: .search, title: "2. Paste it above", detail: "Tap Paste or enter the lesson code exactly as received. Codes are case-sensitive.")
                    FeatureRow(symbol: .play, title: "3. Open and watch", detail: "Tap Open lesson to find matching lessons, then swipe to watch.")
                    LocalizedText("No results? Check your input, or ask the sender for a new link.")
                        .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                    ActionButton(title: "Got it") { dismiss() }
                }.swevoPage()
            }
        }.swevoScreenBackground().foregroundStyle(.white)
    }
}
