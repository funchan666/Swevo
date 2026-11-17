import Foundation
import Combine
import GoogleMobileAds
import UserMessagingPlatform
import UIKit
import OSLog

@MainActor
final class RewardedAds: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var busy = false
    @Published private var presentingAd = false
    @Published private var presentingPrivacyForm = false
    @Published private(set) var privacyOptionsRequired = false
    @Published private(set) var privacyOptionsError: String?
    @Published private var consentTask: Task<Void, Never>?
    var isPresenting: Bool { presentingAd || presentingPrivacyForm }
    var isPreparingPrivacy: Bool { consentTask != nil }
    @Published var error: String?
    @Published var message: String?
    @Published var luckyReward: LuckyRewardNotice?
    @Published private(set) var startupFinished = false
    private var startupStarted = false
    @Published private(set) var isPreparingAppOpen = false
    private var appOpenTask: Task<Void, Never>?
    private var appOpenPreloadTask: Task<Void, Error>?
    private var preloadUnitID: String?
    private var preloadRequestID: UUID?
    private var preparedAppOpen: AppOpenAd?
    private var preparedAppOpenDate: Date?
    private var preparedUnitID: String?
    private var presentedPlacement: GoogleAdPlacement?
    private let appOpenLog = Logger(subsystem: "app.swevo", category: "AppOpen")
    private let privacyLog = Logger(subsystem: "app.swevo", category: "AdPrivacy")
    private var appOpenStage = "idle"
    private var appOpenDeadline: Task<Void, Never>?
    private var appOpenAttempt: UUID?
    private var appOpenHistoryKey: String?
    private var returnedFromBackground = false
    private var appOpenAd: AppOpenAd?
    private var rewarded: RewardedAd?
    private var unavailableReward: (() -> Void)?
    private var rewardGranted = false
    private var rewardAttempt: UUID?
    @Published private(set) var completedReward: UUID?
    private var started = false
    private let packagedAppID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
    private enum ConsentStep { case refresh, form, complete }
    private var consentStep = ConsentStep.refresh
    private var privacyFormID = UUID()

    func watch(commerce: CommerceStore, quota: QuotaStore, kind: AllowanceKind) async {
        guard !Task.isCancelled, !busy, !isPresenting, !isPreparingAppOpen else { return }
        quota.resetIfNeeded()
        guard quota.canRequestReward(for: kind, premium: commerce.premium) else { return }
        guard commerce.rightsVerified, let policy = commerce.policy, let owner = commerce.api.session?.userId.value else {
            error = "Rewarded ads are not available right now. No views have been deducted."; return
        }
        let attemptID = UUID()
        rewardAttempt = attemptID
        busy = true
        defer {
            if rewardAttempt == attemptID { busy = false; rewardAttempt = nil }
        }
        error = nil
        message = nil
        luckyReward = nil
        rewardGranted = false
        unavailableReward = nil
        let testMode = commerce.api.configuration.adsTestMode
        guard let placement = GoogleAdPlacement.resolve(for: policy.rewardedAdType, packagedAppID: packagedAppID,
                                                        testMode: testMode, release: commerce.release) else {
            appOpenLog.error("Rewarded placement unavailable; testMode=\(testMode), demoAppID=\(self.packagedAppID == GoogleDemoAds.appID), getV2Ready=\(commerce.release != nil)")
            grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
            return
        }
        let unitID = placement.unitID
        let demoMode = placement.isOfficialDemo
        if !demoMode, !ConsentInformation.shared.canRequestAds { startConsentFlowIfNeeded(commerce: commerce) }
        let initialPrivacyFormID = privacyFormID
        var timeout: Task<Void, Never>?
        func armDeadline() {
            timeout?.cancel()
            let formID = privacyFormID
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(12)) } catch { return }
                guard let self, self.rewardAttempt == attemptID, self.privacyFormID == formID,
                      !self.isPresenting else { return }
                self.rewardAttempt = nil
                self.busy = false
                self.grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
            }
        }
        // Time spent interacting with the UMP form is outside the ad load deadline.
        armDeadline()
        defer { timeout?.cancel() }
        do {
            if !demoMode { await consentTask?.value }
            try Task.checkCancellation()
            guard rewardAttempt == attemptID else { return }
            if initialPrivacyFormID != privacyFormID { armDeadline() }
            try prepareSDK(demoMode: demoMode)
            let ad = try await RewardedAd.load(with: unitID, request: Request())
            try Task.checkCancellation()
            guard rewardAttempt == attemptID, UIApplication.shared.applicationState == .active else { return }
            guard canRequestAds(demoMode: demoMode) else { throw SwevoError.service("Ads are unavailable with your current privacy choices.") }
            try ad.canPresent(from: nil)
            guard commerce.api.session?.userId.value == owner, !commerce.premium else { throw SwevoError.unauthorized }
            rewarded = ad
            unavailableReward = { [weak self] in
                self?.grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
            }
            ad.fullScreenContentDelegate = self
            let rewardID = UUID()
            presentingAd = true
            ad.present(from: nil) { [weak self, weak ad] in
                guard let self, let ad, self.rewarded === ad, !self.rewardGranted else { return }
                do {
                    try quota.reward(rewardID, owner: owner, kind: kind)
                    self.rewardGranted = true
                    self.message = kind == .watch ? "Your viewing allowance has been updated." : "Your download allowance has been updated."
                } catch { self.error = "The ad finished, but its reward could not be saved. \(error.localizedDescription)" }
            }
        } catch {
            guard rewardAttempt == attemptID else { return }
            presentingAd = false
            let failure = error as NSError
            // Preparation, consent configuration and load failures all mean no ad.
            // Explicit cancellation never earns a gift or bypasses consent.
            if Task.isCancelled || error is CancellationError ||
                (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) { return }
            appOpenLog.error("Rewarded ad unavailable; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
            grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
        }
    }
    func cancelRewardLoading() {
        guard !isPresenting else { return }
        rewardAttempt = nil
        busy = false
    }

    private func grantUnavailableReward(_ attempt: UUID, owner: String, commerce: CommerceStore,
                                        quota: QuotaStore, kind: AllowanceKind) {
        do {
            guard commerce.api.session?.userId.value == owner else { throw SwevoError.unauthorized }
            guard !commerce.premium else { return }
            if let gift = try quota.rewardNoFill(attempt, owner: owner, kind: kind) {
                error = nil
                message = nil
                luckyReward = LuckyRewardNotice(message: gift)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func startConsentFlowIfNeeded(commerce: CommerceStore, accountAccess: AccountAccessFlow? = nil) {
        guard consentStep != .complete, consentTask == nil, !isPresenting,
              !commerce.api.configuration.adsTestMode, let packagedAppID, packagedAppID != GoogleDemoAds.appID,
              packagedAppID.range(of: #"^ca-app-pub-[0-9]{16}~[0-9]{10}$"#, options: .regularExpression) != nil else { return }
        clearAppOpenInventory()
        consentTask = Task { [weak self] in
            guard let self else { return }
            defer { self.consentTask = nil }
            await self.gatherConsent {
                !commerce.busy && !commerce.preparingPurchase && accountAccess?.isBusy != true
            }
        }
    }

    private func gatherConsent(mayPresent: () -> Bool) async {
        let information = ConsentInformation.shared
        defer { updatePrivacyOptionsAvailability() }
        if consentStep == .refresh {
            do {
                try await information.requestConsentInfoUpdate(with: RequestParameters())
                consentStep = .form
                updatePrivacyOptionsAvailability()
            } catch {
                logPrivacyError(error, during: "consent update")
                // The SDK may still permit ads using the choices from the previous session.
                return
            }
        }
        guard information.consentStatus == .required else {
            consentStep = .complete
            return
        }

        // Load separately so a late response can wait for an active presenter.
        guard UIApplication.shared.applicationState == .active, mayPresent() else { return }
        do {
            let form = try await ConsentForm.load()
            guard UIApplication.shared.applicationState == .active, !isPresenting, mayPresent() else { return }
            beginPrivacyPresentation()
            defer { presentingPrivacyForm = false }
            try await form.present(from: nil)
            consentStep = .complete
        } catch {
            logPrivacyError(error, during: "consent form")
        }
    }

    private func updatePrivacyOptionsAvailability() {
        let required = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        if privacyOptionsRequired != required { privacyOptionsRequired = required }
    }

    private func beginPrivacyPresentation() {
        presentingPrivacyForm = true
        privacyFormID = UUID()
        returnedFromBackground = false
        if appOpenAttempt != nil { finishAppOpen(reason: "privacy-form", preservePreparation: true) }
        clearAppOpenInventory()
    }

    private func logPrivacyError(_ error: Error, during operation: String) {
        let failure = error as NSError
        privacyLog.error("UMP \(operation, privacy: .public) failed; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
    }

    private func canRequestAds(demoMode: Bool) -> Bool {
        // The demo path is available only to vetted Google demo placements.
        !presentingPrivacyForm && (demoMode || (consentTask == nil && ConsentInformation.shared.canRequestAds))
    }

    private func prepareSDK(demoMode: Bool) throws {
        guard canRequestAds(demoMode: demoMode) else { throw SwevoError.service("Ads are unavailable with your current privacy choices.") }
        startSDKIfNeeded()
    }

    private func startSDKIfNeeded() {
        guard !started else { return }
        started = true
        // Google-only integration: start once, then request ads immediately, as
        // in Google's quick start. Adapter completion must not block the app.
        MobileAds.shared.start { [weak self] _ in
            self?.appOpenLog.info("Google Mobile Ads initialization callback received")
        }
    }

    private func clearAppOpenInventory() {
        appOpenPreloadTask?.cancel()
        appOpenPreloadTask = nil
        preloadUnitID = nil
        preloadRequestID = nil
        preparedAppOpen = nil
        preparedAppOpenDate = nil
        preparedUnitID = nil
    }

    private func preloadAppOpen(_ placement: GoogleAdPlacement) async throws {
        try Task.checkCancellation()
        try prepareSDK(demoMode: placement.isOfficialDemo)
        let unitID = placement.unitID
        if preparedUnitID == unitID, preparedAppOpen != nil, let date = preparedAppOpenDate,
           Date().timeIntervalSince(date) >= 0, Date().timeIntervalSince(date) < 4 * 60 * 60 {
            appOpenLog.info("Using preloaded app-open ad")
            return
        }
        if let task = appOpenPreloadTask, preloadUnitID == unitID {
            try await task.value
            return
        }
        clearAppOpenInventory()
        preloadUnitID = unitID
        let requestID = UUID()
        preloadRequestID = requestID
        // This task belongs to the inventory cache, not a splash-screen deadline.
        let task = Task<Void, Error> { @MainActor [weak self] in
            let began = ContinuousClock.now
            do {
                try Task.checkCancellation()
                guard let self, self.canRequestAds(demoMode: placement.isOfficialDemo) else { throw CancellationError() }
                let ad = try await AppOpenAd.load(with: unitID, request: Request())
                try Task.checkCancellation()
                guard self.preloadRequestID == requestID,
                      self.canRequestAds(demoMode: placement.isOfficialDemo) else { throw CancellationError() }
                self.preparedAppOpen = ad
                self.preparedAppOpenDate = Date()
                self.preparedUnitID = unitID
                self.appOpenPreloadTask = nil
                self.preloadUnitID = nil
                self.preloadRequestID = nil
                self.appOpenLog.notice("App-open inventory ready after \(began.duration(to: .now).description, privacy: .public)")
            } catch {
                if let self, self.preloadRequestID == requestID {
                    self.appOpenPreloadTask = nil
                    self.preloadUnitID = nil
                    self.preloadRequestID = nil
                    let failure = error as NSError
                    self.appOpenLog.error("App-open inventory failed; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
                }
                throw error
            }
        }
        appOpenPreloadTask = task
        try await task.value
    }

    // Cold start includes pre-login guest preparation. Foreground returns use the same gate.
    func beginStartup(commerce: CommerceStore, accountAccess: AccountAccessFlow) {
        guard !startupStarted else { return }
        startupStarted = true
        startConsentFlowIfNeeded(commerce: commerce, accountAccess: accountAccess)
        requestAppOpen(commerce: commerce, accountAccess: accountAccess, coldStart: true)
    }

    func didEnterBackground() {
        // An ad or SDK consent browser returning to the app must not recursively trigger an ad.
        returnedFromBackground = !isPresenting && !busy
        if isPreparingAppOpen { finishAppOpen(reason: "background", preservePreparation: true) }
    }

    func didBecomeActive(commerce: CommerceStore, accountAccess: AccountAccessFlow) {
        guard startupStarted else { return }
        if !busy { startConsentFlowIfNeeded(commerce: commerce, accountAccess: accountAccess) }
        guard returnedFromBackground else { return }
        returnedFromBackground = false
        requestAppOpen(commerce: commerce, accountAccess: accountAccess, coldStart: false)
    }

    private func requestAppOpen(commerce: CommerceStore, accountAccess: AccountAccessFlow, coldStart: Bool) {
        guard appOpenAttempt == nil, !busy, !isPresenting,
              !commerce.busy, !commerce.preparingPurchase, !accountAccess.isBusy else {
            appOpenLog.info("App-open skipped; another operation is active, coldStart=\(coldStart)")
            if coldStart { startupFinished = true }
            return
        }
        let attempt = UUID()
        appOpenAttempt = attempt
        isPreparingAppOpen = true
        // Bound only this presentation opportunity. A slow network must not keep
        // the home screen locked or discard inventory for the next foreground.
        let waitingBudget = coldStart ? 2.0 : 1.0
        appOpenStage = "authentication"
        appOpenLog.info("App-open opportunity started; coldStart=\(coldStart), budget=\(waitingBudget)")
        scheduleAppOpenDeadline(attempt: attempt, seconds: waitingBudget)
        appOpenTask = Task { [weak self] in
            guard let self else { return }
            let testMode = commerce.api.configuration.adsTestMode
            let demoPlacement = testMode ? GoogleDemoAds.placement(for: 1, packagedAppID: self.packagedAppID) : nil
            do {
                try await commerce.api.prepareVisitor()
                try Task.checkCancellation()
                guard let owner = commerce.api.session?.userId.value else {
                    self.finishAppOpen(attempt: attempt, reason: "guest-unavailable"); return
                }
                if self.appOpenAttempt == attempt { self.appOpenStage = "rights-and-configuration" }
                self.appOpenLog.info("App-open guest authentication ready")
                if let demoPlacement, !commerce.premium {
                    // Demo inventory can load during verification. Presentation still checks account rights.
                    Task { try? await self.preloadAppOpen(demoPlacement) }
                }
                let reuseVerifiedDemoRights = !coldStart && demoPlacement != nil && commerce.verifiedCurrentAccount
                defer {
                    if reuseVerifiedDemoRights, commerce.api.session?.userId.value == owner {
                        Task { await commerce.refresh() }
                    }
                }
                if !reuseVerifiedDemoRights { await commerce.refresh() }
                try Task.checkCancellation()
                guard commerce.api.session?.userId.value == owner,
                      commerce.verifiedCurrentAccount, !commerce.premium else {
                    self.finishAppOpen(attempt: attempt, reason: commerce.premium ? "membership" : "rights-unavailable"); return
                }
                let unit = commerce.release?.adList?.first {
                    $0.adType == 1 && $0.advertiser?.lowercased() == "google"
                }
                guard let placement = demoPlacement ?? GoogleAdPlacement.resolve(for: 1, packagedAppID: self.packagedAppID,
                                                                                 testMode: testMode, release: commerce.release) else {
                    self.appOpenLog.error("App-open placement unavailable; testMode=\(testMode), demoAppID=\(self.packagedAppID == GoogleDemoAds.appID), getV2Ready=\(commerce.release != nil)")
                    self.finishAppOpen(attempt: attempt, reason: "ad-configuration-unavailable"); return
                }
                // Test builds use the backend interval when present, otherwise the
                // baseline demo default of 0 minutes. Production requires a server value.
                let interval = unit?.displayInterval ?? (placement.isOfficialDemo ? 0 : nil)
                let unitID = placement.unitID
                let key = "swevo.app-open.last-impression.\(commerce.api.configuration.servicePackageName).\(commerce.api.configuration.apiBaseURL?.host ?? "none").\(placement.isOfficialDemo ? "demo" : "production")"
                self.appOpenLog.info("App-open rights/configuration ready; intervalMinutes=\(interval ?? -1)")
                if self.appOpenAttempt == attempt { self.appOpenStage = "ad-preparation" }
                if !placement.isOfficialDemo { await self.consentTask?.value }
                try Task.checkCancellation()
                guard AppOpenTiming.isDue(intervalMinutes: interval,
                    lastShown: UserDefaults.standard.object(forKey: key) as? Date) else {
                    Task { try? await self.preloadAppOpen(placement) }
                    self.finishAppOpen(attempt: attempt, reason: "interval-not-due")
                    return
                }
                try await self.preloadAppOpen(placement)
                try Task.checkCancellation()
                guard self.appOpenAttempt == attempt, commerce.api.session?.userId.value == owner,
                      commerce.verifiedCurrentAccount, !commerce.premium, UIApplication.shared.applicationState == .active,
                      !self.busy, !self.isPresenting, self.canRequestAds(demoMode: placement.isOfficialDemo),
                      !commerce.busy, !commerce.preparingPurchase,
                      !accountAccess.isBusy, self.preparedUnitID == unitID, let ad = self.preparedAppOpen,
                      AppOpenTiming.isDue(intervalMinutes: interval,
                        lastShown: UserDefaults.standard.object(forKey: key) as? Date) else {
                    self.finishAppOpen(attempt: attempt, reason: "conditions-changed"); return
                }
                do { try ad.canPresent(from: nil) }
                catch {
                    self.preparedAppOpen = nil
                    self.preparedAppOpenDate = nil
                    self.preparedUnitID = nil
                    let failure = error as NSError
                    self.appOpenLog.error("App-open presenter unavailable; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
                    self.finishAppOpen(attempt: attempt, reason: "presenter-unavailable")
                    return
                }
                self.preparedAppOpen = nil
                self.preparedAppOpenDate = nil
                self.preparedUnitID = nil
                self.presentedPlacement = placement
                self.appOpenStage = "presenting"
                self.appOpenLog.info("App-open ad ready; presenting")
                self.appOpenAd = ad
                self.appOpenHistoryKey = key
                ad.fullScreenContentDelegate = self
                self.appOpenDeadline?.cancel()
                self.isPreparingAppOpen = false
                self.presentingAd = true
                ad.present(from: nil)
            } catch {
                if self.appOpenAttempt == attempt {
                    let failure = error as NSError
                    self.appOpenLog.info("App-open preparation failed; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
                }
                self.finishAppOpen(attempt: attempt, reason: "preparation-failed")
            }
        }
    }

    private func scheduleAppOpenDeadline(attempt: UUID, seconds: Double) {
        appOpenDeadline?.cancel()
        appOpenDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.appOpenAttempt == attempt, !self.isPresenting else { return }
            self.finishAppOpen(attempt: attempt, reason: "deadline", preservePreparation: true)
        }
    }

    private func finishAppOpen(attempt: UUID? = nil, reason: String, preservePreparation: Bool = false) {
        if let attempt, attempt != appOpenAttempt { return }
        appOpenLog.notice("App-open ended; reason=\(reason, privacy: .public), stage=\(self.appOpenStage, privacy: .public)")
        appOpenStage = "idle"
        appOpenAttempt = nil
        appOpenDeadline?.cancel()
        appOpenDeadline = nil
        if !preservePreparation { appOpenTask?.cancel() }
        appOpenTask = nil
        appOpenAd = nil
        appOpenHistoryKey = nil
        isPreparingAppOpen = false
        presentingAd = false
        startupFinished = true
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        guard let current = appOpenAd, ad === current, let key = appOpenHistoryKey else { return }
        UserDefaults.standard.set(Date(), forKey: key)
        appOpenLog.notice("App-open impression recorded")
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        guard let current = appOpenAd, ad === current else { return }
        appOpenLog.info("App-open presentation callback received")
    }

    func privacyOptions() async {
        guard privacyOptionsRequired, !isPreparingPrivacy, !busy, !isPreparingAppOpen, !isPresenting,
              UIApplication.shared.applicationState == .active else { return }
        privacyOptionsError = nil
        beginPrivacyPresentation()
        defer {
            updatePrivacyOptionsAvailability()
            presentingPrivacyForm = false
        }
        do { try await ConsentForm.presentPrivacyOptionsForm(from: nil) }
        catch {
            logPrivacyError(error, during: "privacy options")
            privacyOptionsError = "Couldn’t open ad privacy settings. Try again."
        }
    }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if let current = appOpenAd, ad === current {
            finishPresentedAppOpen(reason: "dismissed")
            return
        }
        guard let current = rewarded, ad === current else { return }
        rewarded = nil
        unavailableReward = nil
        presentingAd = false
        if rewardGranted { completedReward = UUID() }
        else if error == nil { message = "No reward was received. Finish the ad to receive your reward." }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        if let current = appOpenAd, ad === current {
            let failure = error as NSError
            appOpenLog.error("App-open presentation failed; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
            finishPresentedAppOpen(reason: "presentation-failed")
            return
        }
        guard let current = rewarded, ad === current else { return }
        rewarded = nil
        presentingAd = false
        let fallback = unavailableReward
        unavailableReward = nil
        if !rewardGranted { fallback?() }
    }

    private func finishPresentedAppOpen(reason: String) {
        let placement = presentedPlacement
        presentedPlacement = nil
        finishAppOpen(reason: reason)
        if let placement { Task { try? await self.preloadAppOpen(placement) } }
    }
}

struct LuckyRewardNotice: Identifiable {
    let id = UUID()
    let message: String
}
