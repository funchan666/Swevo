import SwiftUI
import OSLog

@main
struct SwevoApp: App {
    @AppStorage(AppLanguage.preferenceKey) private var languageCode = AppLanguage.systemSelection
    @Environment(\.scenePhase) private var appPhase
    @State private var systemLanguage = AppLanguage.systemLanguage()
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? systemLanguage }
    @StateObject private var api: APIClient
    @StateObject private var library: LibraryStore
    @StateObject private var quota: QuotaStore
    @StateObject private var commerce: CommerceStore
    @StateObject private var offline: OfflineStore
    @StateObject private var ads: RewardedAds
    @StateObject private var accountAccess = AccountAccessFlow()
    init() {
        let api = APIClient()
        let quota = QuotaStore()
        _api = StateObject(wrappedValue: api)
        _library = StateObject(wrappedValue: LibraryStore())
        _quota = StateObject(wrappedValue: quota)
        let commerce = CommerceStore(api: api, quota: quota)
        _commerce = StateObject(wrappedValue: commerce)
        _offline = StateObject(wrappedValue: OfflineStore(api: api, quota: quota, commerce: commerce))
        _ads = StateObject(wrappedValue: RewardedAds())
    }
    var body: some Scene {
        WindowGroup {
            SwevoStartupHost().environmentObject(api).environmentObject(library)
                .environmentObject(quota).environmentObject(commerce).environmentObject(ads).environmentObject(offline)
                .environmentObject(accountAccess)
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.direction)
                .font(.capture(.body))
                .preferredColorScheme(.dark).tint(SwevoStyle.accent)
                .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                    systemLanguage = AppLanguage.systemLanguage()
                }
                .onChange(of: appPhase) { _, phase in
                    if phase == .active { systemLanguage = AppLanguage.systemLanguage() }
                }
        }
    }
}

// Keeps launch feedback visible during the bounded cold-start ad opportunity.
// Guest authentication prepares configuration and opens the app directly.
struct SwevoStartupHost: View {
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finished = false
    @State private var startupBegan = ContinuousClock.now

    var body: some View {
        ZStack {
            SwevoStyle.background.ignoresSafeArea()
            // Mount once so local content and authentication prepare while the
            // bounded app-open opportunity runs, without rebuilding navigation.
            SwevoRootView()
                .allowsHitTesting(finished)
                .accessibilityHidden(!finished)
            if !finished {
                SwevoStartupView().transition(.opacity)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !finished else { return }
            ads.beginStartup(commerce: commerce, accountAccess: accountAccess)
        }
        .onReceive(ads.$startupFinished) { complete in
            if complete, !finished {
                Logger(subsystem: "app.swevo", category: "Startup")
                    .info("Home became interactive after \(startupBegan.duration(to: .now).description, privacy: .public)")
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { finished = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { ads.didEnterBackground() }
            if phase == .active {
                ads.didBecomeActive(commerce: commerce, accountAccess: accountAccess)
            }
        }
    }
}

struct SwevoStartupView: View {
    var body: some View {
        ProgressView()
            .tint(SwevoStyle.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .all)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LocalizedStringKey("Kstep is starting"))
            .background(SwevoStyle.background.ignoresSafeArea())
    }
}

enum SwevoTab: Int, Hashable {
    // SceneStorage persists these raw values independently of the display order.
    case home = 0, files = 1, cameraMoves = 2, me = 3

    static let displayOrder: [Self] = [.home, .cameraMoves, .files, .me]

    var name: String { ["Videos", "Files", "Camera moves", "Me"][rawValue] }
    var artwork: String { ["GlyphFeed", "GlyphFolder", "GlyphLibrary", "GlyphSettings"][rawValue] }
    var identifier: String { self == .cameraMoves ? "tab.cameraMoves" : "tab.\(name.lowercased())" }
}

// Keep a semantic title for VoiceOver and the system's overflow labels.
private struct SwevoTabItem: View {
    let tab: SwevoTab
    @Environment(\.locale) private var locale
    var body: some View {
        Label {
            Text(verbatim: L10n.display(tab.name, language: AppLanguage.from(locale)))
        } icon: {
            Image(tab.artwork).renderingMode(.template)
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel(Text(verbatim: L10n.text(tab.name, language: AppLanguage.from(locale))))
        .accessibilityIdentifier(tab.identifier)
    }
}

private extension View {
    func swevoTab(_ tab: SwevoTab, nativeBar: Bool) -> some View {
        tabItem { SwevoTabItem(tab: tab) }
            .tag(tab)
            .toolbar(nativeBar ? .visible : .hidden, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
    }
}

private struct SwevoTabDock: View {
    static let maximumWidth: CGFloat = 304
    private static let tabSpacing: CGFloat = 4
    private static let buttonHeight: CGFloat = 48
    private static let rimPadding: CGFloat = 5
    private static let bottomGap: CGFloat = 6
    static let occupiedHeight = buttonHeight + 2 * rimPadding + bottomGap
    @Binding var selection: SwevoTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tray = Capsule()
        tabButtons
            .background { selectionGlass }
            .padding(Self.rimPadding)
            .background {
                if reduceTransparency {
                    tray.fill(SwevoStyle.surface)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                tray.strokeBorder(
                    LinearGradient(colors: [SwevoStyle.paper.opacity(0.44), SwevoStyle.paper.opacity(0.22)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1
                )
                .allowsHitTesting(false)
            }
            .frame(maxWidth: Self.maximumWidth)
            .padding(.horizontal, 12)
            .padding(.bottom, Self.bottomGap)
            .animation(reduceMotion ? nil : .smooth(duration: 0.29), value: selection)
    }

    private var tabButtons: some View {
        HStack(spacing: Self.tabSpacing) {
            ForEach(SwevoTab.displayOrder, id: \.self) { tab in
                let selected = selection == tab
                let tint = selected ? SwevoStyle.paper : SwevoStyle.secondary
                Button { selection = tab } label: {
                    TintedArtwork(name: tab.artwork, tint: tint)
                        .frame(width: 24, height: 24)
                        .shadow(color: SwevoStyle.ink.opacity(0.86), radius: 2, x: 0, y: 1)
                        .padding(.bottom, 3)
                        .frame(minWidth: 44, maxWidth: .infinity, minHeight: Self.buttonHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(LocalizedStringKey(tab.name))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier(tab.identifier)
            }
        }
    }

    private var selectionGlass: some View {
        GeometryReader { geometry in
            let tabCount = CGFloat(SwevoTab.displayOrder.count)
            let gaps = Self.tabSpacing * (tabCount - 1)
            let width = max(0, (geometry.size.width - gaps) / tabCount)
            let selectedIndex = SwevoTab.displayOrder.firstIndex(of: selection) ?? 0
            let inset = CGFloat(selectedIndex) * (width + Self.tabSpacing)

            Capsule().fill(SwevoStyle.accent)
                .frame(width: 14, height: 2)
                .padding(.bottom, 5)
                .frame(width: min(58, width), height: 42, alignment: .bottom)
                .swevoGlass(cornerRadius: 21, tint: SwevoStyle.accent.opacity(0.38))
                .overlay {
                    Capsule().strokeBorder(
                        LinearGradient(colors: [SwevoStyle.paper.opacity(0.62), SwevoStyle.accent.opacity(0.20)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                }
                .frame(width: width, height: geometry.size.height)
                .padding(.leading, inset)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct EditorPresentation: Identifiable {
    let id = UUID()
    let movie: PracticeRecording?
    var tool: VideoTool = .studio
}

struct SwevoRootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var offline: OfflineStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.self) private var environment
    @SceneStorage("root.tab") private var tab: SwevoTab = .home
    @State private var editing: EditorPresentation?
    @State private var importing = false
    @State private var libraryFilter = "Imports"
    @State private var showingFileTools = false
    @State private var showingPlus = false
    @State private var showingLessons = false
    @State private var returnToLessonEntry = false
    var body: some View {
        GeometryReader { container in
            let nativeBar = usesNativeTabBar(in: container)
            TabView(selection: $tab) {
                videosTab.swevoTab(.home, nativeBar: nativeBar)
                CameraMovesView(openPlus: openPlus).swevoTab(.cameraMoves, nativeBar: nativeBar)
                filesTab.swevoTab(.files, nativeBar: nativeBar)
                AccountView().swevoTab(.me, nativeBar: nativeBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.swevoTabDockInset, nativeBar ? 0 : SwevoTabDock.occupiedHeight)
            .overlay(alignment: .bottom) {
                if !nativeBar {
                    SwevoTabDock(selection: $tab)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(importing)
        }
            .tint(SwevoStyle.accent)
            .foregroundStyle(SwevoStyle.paper)
            .sheet(item: $editing) { EditorSheet(initialMovie: $0.movie, initialTool: $0.tool) }
            .fullScreenCover(isPresented: $showingPlus) { MembershipView(showsRewardOptions: false) }
            .fullScreenCover(isPresented: $showingLessons, onDismiss: {
                if returnToLessonEntry {
                    returnToLessonEntry = false
                    tab = .home
                }
            }) {
                DiscoverView(canDismiss: true, returnToLinkInput: {
                    returnToLessonEntry = true
                    showingLessons = false
                })
            }
            .overlay(alignment: .top) {
                if !showingLessons { DownloadCompletionNotice().padding(.top, 8) }
            }
            .onChange(of: library.downloadsRequest) { _, request in
                if request != nil { openFiles("Downloads") }
            }
            .task(id: api.session?.userId.value) {
                guard api.session != nil else { return }
                if !commerce.rightsVerified || commerce.release == nil { await commerce.refresh() }
                await offline.resumePending()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { quota.resetIfNeeded() }
            }
            .overlay(alignment: .top) {
                if let message = library.error {
                    HStack {
                        LocalizedText(message).font(.capture(.subheadline))
                        IconButton(symbol: .close, label: "Dismiss message") { library.error = nil }
                    }.padding(14).background(SwevoStyle.raised, in: RoundedRectangle(cornerRadius: 18)).padding()
                }
            }
            .modifier(AccountBusyModifier())
    }

    private var videosTab: some View {
        NavigationStack {
            HomeView(importing: $importing,
                     edit: { editing = EditorPresentation(movie: $0) },
                     review: { editing = EditorPresentation(movie: $0, tool: .ranges) },
                     openLibrary: { openFiles("Imports") },
                     openCameraMoves: { tab = .cameraMoves }, openPlus: openPlus)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var filesTab: some View {
        NavigationStack {
            LibraryView(edit: { editing = EditorPresentation(movie: $0) },
                        browseVideos: { showingLessons = true },
                        openEditor: { editing = EditorPresentation(movie: nil) },
                        openTools: { showingFileTools = true },
                        openPlus: openPlus, filter: $libraryFilter, importing: $importing)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showingFileTools) {
                    ToolsView(openPlus: openPlus)
                        .sceneDismiss(symbol: .back, label: "Back", edge: .leading) { showingFileTools = false }
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
    }

    private func openFiles(_ filter: String) {
        libraryFilter = filter
        showingFileTools = false
        tab = .files
    }

    private func openPlus() { showingPlus = true }

    private func usesNativeTabBar(in container: GeometryProxy) -> Bool {
        if container.size.width < 224 { return true }
        guard #available(iOS 27.1, *) else { return false }
        if environment.toolbarVerticalEdge != nil { return true }

        let width = min(SwevoTabDock.maximumWidth, container.size.width - 24)
        let height = min(SwevoTabDock.occupiedHeight, container.size.height)
        let dock = CGRect(x: (container.size.width - width) / 2, y: container.size.height - height,
                          width: width, height: height)
        return SwevoStyle.intersectsReservedRegion(dock, in: container)
    }
}

// A network recovery surface, not a second login or consent gate.
struct ConnectionPanel: View {
    @EnvironmentObject private var api: APIClient
    var loadingTitle = "Connecting to Kstep…"
    @State private var error: String?
    @State private var connecting = false
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 24) {
            if let error {
                MessagePanel(title: "Couldn’t connect to Kstep", message: error)
                ActionButton(title: "Try again", busy: connecting) { attempt += 1 }
            } else {
                AccountLoadingIndicator(title: loadingTitle)
            }
            PolicyLinks()
        }
        .frame(maxWidth: 440).frame(maxWidth: .infinity)
        .task(id: attempt) {
            guard api.session == nil else { return }
            connecting = true
            error = nil
            defer { connecting = false }
            do { try await api.prepareVisitor() }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
