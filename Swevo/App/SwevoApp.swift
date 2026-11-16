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

// Keeps the original splash visible during the bounded cold-start ad opportunity.
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
            Color("LaunchBackground").ignoresSafeArea()
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
            if phase == .active, finished {
                ads.didBecomeActive(commerce: commerce, accountAccess: accountAccess)
            }
        }
    }
}

struct SwevoStartupView: View {
    var body: some View {
        // Same centred mark as LaunchScreen.storyboard, so the hand-off does not jump.
        SwevoIllustration(name: "LaunchMark", height: 108).frame(width: 108)
            .overlay(alignment: .bottom) { ProgressView().tint(SwevoStyle.accent).offset(y: 52) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .all)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LocalizedStringKey("Swevo is starting"))
            .background(Color("LaunchBackground").ignoresSafeArea())
    }
}

enum SwevoTab: Int, CaseIterable, Hashable {
    case home, tools, library, me
    var name: String { ["Videos", "Tools", "Files", "Me"][rawValue] }
    var artwork: String { ["GlyphFeed", "GlyphEdit", "GlyphFolder", "GlyphSettings"][rawValue] }
    var identifier: String { "tab.\(name.lowercased())" }
}

// System tab item: title and original image, so the bar can follow iPhone Duo's
// vertical bar layout and move titles into the system overflow when needed.
private struct SwevoTabItem: View {
    let tab: SwevoTab
    @Environment(\.locale) private var locale
    var body: some View {
        Label {
            Text(verbatim: L10n.display(tab.name, language: AppLanguage.from(locale)))
        } icon: {
            Image(tab.artwork).renderingMode(.template)
        }
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
    static let maximumWidth: CGFloat = 488
    @Binding var selection: SwevoTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SwevoTab.allCases, id: \.self) { tab in
                let selected = selection == tab
                Button { selection = tab } label: {
                    VStack(spacing: 3) {
                        TintedArtwork(name: tab.artwork, tint: selected ? SwevoStyle.accent : SwevoStyle.paper)
                            .frame(width: 22, height: 22)
                        LocalizedText(tab.name)
                            .font(.capture(.caption2, weight: selected ? .semibold : .medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 5)
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(selected ? SwevoStyle.accent : SwevoStyle.paper)
                    .background {
                        if selected {
                            let shape = RoundedRectangle(cornerRadius: 17)
                            shape.fill(SwevoStyle.accent.opacity(0.16))
                                .overlay { shape.strokeBorder(SwevoStyle.accent.opacity(0.35)) }
                                .matchedGeometryEffect(id: "selected-tab", in: highlight)
                                .transition(.identity)
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(LocalizedStringKey(tab.name))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier(tab.identifier)
            }
        }
        .padding(5)
        .swevoGlass(cornerRadius: 23)
        .frame(maxWidth: Self.maximumWidth)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selection)
    }
}

private struct EditorPresentation: Identifiable {
    let id = UUID()
    let movie: PracticeRecording?
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
    @State private var showingLearning = false
    @State private var showingLessons = false
    @State private var returnToLessonEntry = false
    var body: some View {
        GeometryReader { container in
            let nativeBar = usesNativeTabBar(in: container)
            TabView(selection: $tab) {
                HomeView(importing: $importing, edit: { editing = EditorPresentation(movie: $0) }, openLibrary: {
                    libraryFilter = "Imports"
                    tab = .library
                }, openLearning: { showingLearning = true })
                    .swevoTab(.home, nativeBar: nativeBar)
                ToolsView().swevoTab(.tools, nativeBar: nativeBar)
                LibraryView(edit: { editing = EditorPresentation(movie: $0) },
                            watchTutorials: { showingLessons = true },
                            openEditor: { editing = EditorPresentation(movie: nil) },
                            filter: $libraryFilter, importing: $importing)
                    .swevoTab(.library, nativeBar: nativeBar)
                AccountView().swevoTab(.me, nativeBar: nativeBar)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !nativeBar {
                    SwevoTabDock(selection: $tab)
                }
            }
            .disabled(importing)
        }
            .tint(SwevoStyle.accent)
            .foregroundStyle(SwevoStyle.paper)
            .sheet(item: $editing) { EditorSheet(initialMovie: $0.movie) }
            .sheet(isPresented: $showingLearning) { LearningView() }
            .fullScreenCover(isPresented: $showingLessons, onDismiss: {
                if returnToLessonEntry {
                    returnToLessonEntry = false
                    tab = .home
                    showingLearning = true
                }
            }) {
                DiscoverView(canDismiss: true, openLessonEntry: {
                    returnToLessonEntry = true
                    showingLessons = false
                })
            }
            .overlay(alignment: .top) {
                if !showingLessons { DownloadCompletionNotice().padding(.top, 8) }
            }
            .task(id: library.downloadsRequest) {
                guard library.downloadsRequest != nil else { return }
                // Full-screen players dismiss first; then move the underlying tab.
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                showingLearning = false
                libraryFilter = "Downloads"
                tab = .library
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

    private func usesNativeTabBar(in container: GeometryProxy) -> Bool {
        if environment.dynamicTypeSize.isAccessibilitySize || container.size.width < 224 { return true }
        guard #available(iOS 27.1, *) else { return false }
        if environment.toolbarVerticalEdge != nil { return true }

        let width = min(SwevoTabDock.maximumWidth, container.size.width - 24)
        let height = min(84, container.size.height)
        let dock = CGRect(x: (container.size.width - width) / 2, y: container.size.height - height,
                          width: width, height: height)
        return SwevoStyle.intersectsReservedRegion(dock, in: container)
    }
}

// A network recovery surface, not a second login or consent gate.
struct ConnectionPanel: View {
    @EnvironmentObject private var api: APIClient
    var loadingTitle = "Connecting to Swevo…"
    @State private var error: String?
    @State private var connecting = false
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 24) {
            if let error {
                MessagePanel(title: "Couldn’t connect to Swevo", message: error)
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
