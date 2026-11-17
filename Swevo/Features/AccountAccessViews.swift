import SwiftUI
import WebKit

@MainActor
final class AccountAccessFlow: ObservableObject {
    @Published private(set) var busyMessage: String?
    var isBusy: Bool { busyMessage != nil }

    func perform(_ message: String, operation: () async throws -> Void) async throws {
        guard !isBusy else { throw CancellationError() }
        busyMessage = message
        defer { busyMessage = nil }
        await Task.yield()
        try await operation()
    }
}

struct AccountLoadingIndicator: View {
    let title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 20) {
            ProgressView().tint(SwevoStyle.accent).accessibilityHidden(true)
            LocalizedText(title).font(.capture(.subheadline, weight: .semibold)).multilineTextAlignment(.center)
        }.padding(22).frame(maxWidth: 250)
            .foregroundStyle(.white)
            .background { CaptureSurface(tone: .plum) }
            .accessibilityElement(children: .combine)
    }
}

struct AccountBusyModifier: ViewModifier {
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    func body(content: Content) -> some View {
        content.allowsHitTesting(!accountAccess.isBusy)
            .accessibilityHidden(accountAccess.isBusy)
            .overlay {
                if let message = accountAccess.busyMessage {
                    ZStack {
                        Color.black.opacity(0.58).ignoresSafeArea()
                        AccountLoadingIndicator(title: message).padding(24)
                    }.accessibilityAddTraits(.isModal)
                }
            }
    }
}

// Native text/layout over the app's existing surfaces; no rendered text artwork.
struct AccountDecisionDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    var showsPolicies = false
    var destructive = false
    var cancel: (() -> Void)? = nil
    let confirm: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LocalizedText(title).font(.capture(.headline)).foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                    LocalizedText(message).font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsPolicies { PolicyLinks() }
                    VStack(spacing: 10) {
                        Button(action: confirm) {
                            LocalizedText(confirmTitle).font(.capture(.subheadline, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.75)
                                .multilineTextAlignment(.center).padding(.horizontal, 16).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(destructive ? SwevoStyle.danger : SwevoStyle.ink)
                                .background { CaptureSurface(tone: destructive ? .plum : .accent) }
                        }.buttonStyle(PressStyle())
                        if let cancel { ActionButton(title: "Cancel", primary: false, action: cancel) }
                    }
                }.padding(20).frame(maxWidth: 360)
                    .background { CaptureSurface(tone: .plum) }
                    .padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(Color.black.opacity(0.68).ignoresSafeArea())
            .accessibilityAddTraits(.isModal)
            .interactiveDismissDisabled()
            .onAppear { titleFocused = true }
    }
}

struct PolicyDocument: Identifiable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }
}

struct PolicyLinks: View {
    var compact = false
    @EnvironmentObject private var api: APIClient
    @State private var document: PolicyDocument?
    var body: some View {
        Group {
            if compact { linkLayout.buttonStyle(PressStyle()) }
            else { linkLayout.buttonStyle(CompactActionStyle()) }
        }.sheet(item: $document) { PolicyBrowser(document: $0) }
    }
    private var linkLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: compact ? 16 : 10) { links }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: compact ? 0 : 10) { links }
        }.font(.capture(.footnote, weight: .medium)).foregroundStyle(SwevoStyle.accent)
    }
    @ViewBuilder private var links: some View {
        if let url = api.configuration.termsURL {
            policyLink("Terms of Use", url: url)
        }
        if let url = api.configuration.privacyURL {
            policyLink("Privacy Policy", url: url)
        }
    }

    private func policyLink(_ title: String, url: URL) -> some View {
        Button { document = PolicyDocument(title: title, url: url) } label: {
            LocalizedText(title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 44, minHeight: compact ? 44 : nil, alignment: .leading)
                .contentShape(Rectangle())
        }
    }
}

@MainActor
final class PolicyBrowserState: ObservableObject {
    @Published var loading = true
    @Published var error: String?
    @Published var requestID = 0
    @Published var canGoBack = false
    @Published var currentURL: URL?
    var retryURL: URL?
    weak var webView: WKWebView?
    func retry() { error = nil; loading = true; requestID += 1 }
    func goBack() { webView?.goBack() }
}

struct PolicyBrowser: View {
    let document: PolicyDocument
    var webSearch = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = PolicyBrowserState()
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: document.title) { dismiss() }
            if webSearch {
                HStack(spacing: 12) {
                    IconButton(symbol: .back, label: "Back") { state.goBack() }
                        .disabled(!state.canGoBack)
                    Text(verbatim: state.currentURL?.host ?? document.url.host ?? "")
                        .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 16).padding(.bottom, 8)
            }
            ZStack {
                PolicyWebView(url: document.url, state: state, webSearch: webSearch)
                    .accessibilityHidden(state.loading || state.error != nil)
                if let error = state.error {
                    SwevoStyle.background
                    ScrollView {
                        MessagePanel(title: "Couldn’t open this page", message: error,
                                     actionTitle: "Try again", action: { state.retry() }).padding(24)
                    }
                } else if state.loading {
                    SwevoStyle.background
                    AccountLoadingIndicator(title: webSearch ? "Opening page…" : "Opening document…").padding(24)
                }
            }
        }.swevoScreenBackground().foregroundStyle(.white)
    }
}

struct PolicyWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: PolicyBrowserState
    var webSearch = false
    func makeCoordinator() -> Coordinator { Coordinator(state: state, webSearch: webSearch) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.allowsLinkPreview = !webSearch
        view.isOpaque = false
        state.webView = view
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.requestID != state.requestID else { return }
        context.coordinator.requestID = state.requestID
        context.coordinator.load(URLRequest(url: state.retryURL ?? url, timeoutInterval: 30), in: view)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.stopLoading()
        coordinator.state.webView = nil
    }
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let state: PolicyBrowserState
        let webSearch: Bool
        var requestID: Int?
        private var appNavigationURL: URL?
        init(state: PolicyBrowserState, webSearch: Bool) { self.state = state; self.webSearch = webSearch }
        func load(_ request: URLRequest, in webView: WKWebView) {
            appNavigationURL = request.url
            state.retryURL = request.url
            webView.load(request)
        }
        // Documents and search results have no camera or microphone use case.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.loading = true
            state.error = nil
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            state.currentURL = webView.url
            state.canGoBack = webView.canGoBack
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.loading = false
            state.currentURL = webView.url
            state.canGoBack = webView.canGoBack
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            state.loading = false
            state.error = "The document was interrupted. Please try again."
        }
        private func fail(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            state.loading = false
            state.error = "Check your connection and try again."
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if !webSearch, url.scheme == "mailto", navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else if url.scheme == "https" || (webSearch && url.scheme == "http") || url.absoluteString == "about:blank" {
                if navigationAction.targetFrame?.isMainFrame != false { state.retryURL = url }
                if webSearch, navigationAction.targetFrame?.isMainFrame != false {
                    // Reissue page navigations as app loads so web links stay in this view.
                    if navigationAction.navigationType == .backForward ||
                        (navigationAction.targetFrame != nil && appNavigationURL == url) {
                        appNavigationURL = nil
                        decisionHandler(.allow)
                    } else {
                        decisionHandler(.cancel)
                        load(navigationAction.request, in: webView)
                    }
                    return
                }
                if navigationAction.targetFrame == nil {
                    webView.load(navigationAction.request)
                    decisionHandler(.cancel)
                } else { decisionHandler(.allow) }
            } else { decisionHandler(.cancel) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame,
               let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
                state.loading = false
                state.error = "This document is temporarily unavailable. Please try again."
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}

struct AccountSettingsSection: View {
    @Environment(\.openURL) private var openURL
    @State private var websiteError: String?
    @AppStorage(AppLanguage.preferenceKey) private var languageCode = AppLanguage.systemSelection
    @State private var languagePicker = false
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    private var unavailable: Bool { accountAccess.isBusy || commerce.busy || commerce.preparingPurchase || ads.busy || ads.isPreparingAppOpen || ads.isPresenting }
    private var hasPolicies: Bool { api.configuration.privacyURL != nil || api.configuration.termsURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LocalizedText("Settings").font(.capture(.headline))
                .accessibilityAddTraits(.isHeader)
            languagePreference
            if hasPolicies || ads.privacyOptionsRequired {
                VStack(alignment: .leading, spacing: 2) {
                    if hasPolicies {
                        LocalizedText("Privacy & terms").font(.capture(.subheadline, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        PolicyLinks(compact: true)
                    }
                    if ads.privacyOptionsRequired {
                        settingsLink("Advertising privacy") {
                            Task { await ads.privacyOptions() }
                        }
                        .disabled(ads.isPreparingPrivacy)
                        .accessibilityIdentifier("account.adPrivacy")
                        if let message = ads.privacyOptionsError { ErrorNote(message: message) }
                    }
                }
                .disabled(unavailable)
                Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
            }
            settingsFooter
            if let websiteError { ErrorNote(message: websiteError) }
        }
        .sheet(isPresented: $languagePicker) { LanguagePicker() }
    }

    private var languagePreference: some View {
        let title = HStack(spacing: 10) {
            Glyph(symbol: .settings, size: 17, tint: SwevoStyle.accent)
            LocalizedText("App language").font(.capture(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        let selectedLanguage = HStack(spacing: 8) {
            Group {
                if let language = AppLanguage(rawValue: languageCode) {
                    Text(verbatim: language.nativeName)
                } else {
                    LocalizedText("Follow system")
                }
            }
            .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Glyph(symbol: .back, size: 11, tint: SwevoStyle.accent).rotationEffect(.degrees(180))
        }
        return Button { languagePicker = true } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    title.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    selectedLanguage.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 6) {
                    title
                    selectedLanguage
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .overlay(alignment: .bottom) {
                Divider().overlay(SwevoStyle.line).allowsHitTesting(false).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("account.language")
    }

    @ViewBuilder private var settingsFooter: some View {
        let version = LocalizedText("Version %@", api.configuration.version)
            .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if let website = api.configuration.websiteURL {
            let websiteLink = settingsLink("Official website", symbol: .link) {
                websiteError = nil
                openURL(website) { accepted in
                    if !accepted { websiteError = "The browser could not open. Please try again." }
                }
            }.disabled(unavailable).accessibilityIdentifier("account.officialWebsite")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    websiteLink.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    version.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    websiteLink
                    version
                }
            }
        } else {
            version
        }
    }

    private func settingsLink(_ title: String, symbol: SwevoGlyph? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Glyph(symbol: symbol, size: 14, tint: SwevoStyle.accent) }
                LocalizedText(title)
                    .font(.capture(.footnote, weight: .medium)).foregroundStyle(SwevoStyle.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}
