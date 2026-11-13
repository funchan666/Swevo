import SwiftUI
import StoreKit

struct MembershipView: View {
    var rewardKind: AllowanceKind? = nil
    var exportRequired = false
    @Environment(\.locale) private var locale
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?
    @State private var attemptedPurchaseAction = false
    @State private var purchaseTask: Task<Void, Never>?
    @State private var rewardTask: Task<Void, Never>?
    @State private var requestedReward = false
    @State private var acknowledgedLuckyReward = false

    private var plans: [SKProduct] {
        (commerce.policy?.products ?? []).compactMap { entry in
            commerce.products.first { $0.productIdentifier == entry.id }
        }
    }
    private var selectedPlan: SKProduct? {
        plans.first(where: { $0.productIdentifier == selectedID }) ?? plans.first
    }
    private var purchasing: Bool { commerce.preparingPurchase || commerce.busy || purchaseTask != nil }
    private var interactionLocked: Bool { purchasing || commerce.loadingPlans || ads.busy || ads.isPresenting }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                membershipIntro

                if exportRequired {
                    LocalizedText("Export is included with Plus.")
                        .font(.capture(.subheadline, weight: .semibold)).foregroundStyle(SwevoStyle.paper)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if commerce.premium {
                    VStack(alignment: .leading, spacing: 10) {
                        LocalizedText("Your membership is active").font(.capture(.headline))
                        if let expiration = commerce.expiration {
                            LocalizedText("Access through \(expiration.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))).")
                                .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background { CaptureSurface(tone: .mist) }
                    renewalDisclosure
                } else {
                    if api.session == nil { ConnectionPanel() }
                    if !plans.isEmpty { planPicker }
                    if let error = commerce.plansError {
                        ErrorNote(message: error)
                        Button("Retry") { Task { await commerce.loadPlans() } }
                            .buttonStyle(CompactActionStyle()).disabled(interactionLocked)
                    }
                    renewalDisclosure
                    VStack(spacing: 12) {
                        purchaseAction
                        if purchasing {
                            loadingMark(width: 42)
                        }
                    }
                }

                restoreLink

                if attemptedPurchaseAction {
                    if let error = commerce.error { ErrorNote(message: error) }
                    if let message = commerce.message {
                        LocalizedText(message).font(.capture(.subheadline)).foregroundStyle(SwevoStyle.accent)
                    }
                }

                PolicyLinks(compact: true)

                studioArtwork

                if !exportRequired, !commerce.premium, api.session != nil { rewardOption }
            }.swevoPage()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SheetHeading(title: "Plus") {
                cancelRewardRequest()
                dismiss()
            }
                .disabled(purchasing || ads.isPresenting).padding(.bottom, 8)
                .swevoScreenBackground()
        }
        .swevoScreenBackground().foregroundStyle(.white)
        .task {
            async let rights: Void = commerce.refresh()
            await commerce.loadPlans()
            await rights
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in quota.resetIfNeeded() }
        .onDisappear {
            purchaseTask?.cancel(); purchaseTask = nil
            if !ads.isPresenting { cancelRewardRequest() }
        }
        .onChange(of: ads.completedReward) { _, completion in
            if requestedReward, completion != nil { dismiss() }
        }
        .interactiveDismissDisabled(purchasing || ads.isPresenting)
        .fullScreenCover(item: $ads.luckyReward, onDismiss: {
            if acknowledgedLuckyReward && requestedReward { dismiss() }
        }) { reward in
            LuckyRewardView(message: reward.message) {
                acknowledgedLuckyReward = true
                ads.luckyReward = nil
            }
                .presentationBackground(.clear)
        }
    }

    private var purchaseButtonTitle: String {
        if commerce.loadingProducts || commerce.loadingPlans { return "Checking with Apple…" }
        if commerce.preparingPurchase { return "Preparing your subscription…" }
        if commerce.busy { return "Confirming your purchase…" }
        return "Subscribe"
    }

    private var membershipIntro: some View {
        VStack(alignment: .leading, spacing: 12) {
            membershipCopy(titleColor: SwevoStyle.paper, detailColor: SwevoStyle.secondary)
            Divider().overlay(SwevoStyle.line)
        }
    }

    private var studioArtwork: some View {
        membershipArtwork(2.5)
            .clipShape(.rect(cornerRadius: 4))
            .padding(4)
            .background(SwevoStyle.raised, in: RoundedRectangle(cornerRadius: 6))
    }

    private func membershipCopy(titleColor: Color, detailColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            membershipTitle.foregroundStyle(titleColor)
            LocalizedText("Unlimited views, downloads and media exports.")
                .font(.capture(.subheadline)).foregroundStyle(detailColor)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var membershipTitle: some View {
        LocalizedText("Studio access")
            .font(.capture(.title, display: true))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func membershipArtwork(_ ratio: CGFloat) -> some View {
        Color.clear.aspectRatio(ratio, contentMode: .fit)
            .overlay {
                GeometryReader { frame in
                    Image("PlusArtwork").resizable().scaledToFill()
                        .frame(width: frame.size.width, height: frame.size.height)
                        .clipped()
                }
            }.accessibilityHidden(true).allowsHitTesting(false)
    }

    private var planPicker: some View {
        VStack(spacing: 2) { planOptions }
            .padding(4).background(SwevoStyle.raised, in: RoundedRectangle(cornerRadius: 6))
    }

    private var planOptions: some View {
        ForEach(plans, id: \.productIdentifier) { plan in
            planOption(plan)
        }
    }

    private func planOption(_ product: SKProduct) -> some View {
        let selected = selectedPlan?.productIdentifier == product.productIdentifier
        let price = commerce.price(product)
        let period = commerce.period(product, locale: locale)
        let ink = selected ? SwevoStyle.ink : SwevoStyle.paper
        let secondary = selected ? SwevoStyle.paperSecondary : SwevoStyle.secondary
        return Button { selectedID = product.productIdentifier } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: product.localizedTitle).font(.capture(.headline, weight: .semibold))
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        LocalizedText("Billed every %@", period).font(.capture(.caption)).foregroundStyle(secondary)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        Text(verbatim: price).environment(\.layoutDirection, .leftToRight)
                            .font(.capture(.title3, display: true)).monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: price).environment(\.layoutDirection, .leftToRight)
                            .font(.capture(.title3, display: true)).monospacedDigit()
                        LocalizedText("Billed every %@", period).font(.capture(.caption)).foregroundStyle(secondary)
                    }
                }
            }.fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .foregroundStyle(ink)
                .background(selected ? SwevoStyle.accent : SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).disabled(interactionLocked)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("membership.plan.\(product.productIdentifier)")
    }

    private var renewalDisclosure: some View {
        LocalizedText("Renews automatically. Cancel in your Apple account at least 24 hours before renewal.")
            .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var purchaseAction: some View {
        Button(action: subscribe) {
            HStack(spacing: 12) {
                LocalizedText(purchaseButtonTitle).font(.capture(.headline, display: true))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .library, size: 18, tint: SwevoStyle.accent)
                    .frame(width: 36, height: 36)
                    .background(SwevoStyle.ink, in: RoundedRectangle(cornerRadius: 3))
                    .accessibilityHidden(true)
            }.padding(.horizontal, 10).padding(.vertical, 7).frame(minHeight: 50)
                .foregroundStyle(SwevoStyle.ink)
                .background(SwevoStyle.accent, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .disabled(interactionLocked || selectedPlan == nil)
            .accessibilityIdentifier("membership.subscribe")
    }

    private func subscribe() {
        guard !interactionLocked, let plan = selectedPlan else { return }
        attemptedPurchaseAction = true
        purchaseTask = Task {
            await commerce.purchase(planID: plan.productIdentifier)
            purchaseTask = nil
        }
    }

    private var rewardOption: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedText("Or, keep it free").font(.capture(.headline))
            ForEach(rewardKind.map { [$0] } ?? AllowanceKind.allCases) { kind in
                if quota.canRequestReward(for: kind, premium: commerce.premium) {
                    LocalizedText(quota.rewardSummary(for: kind)).font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                    if quota.completedAds(kind) >= 3 { AllowanceResetText() }
                    ActionButton(title: kind == .watch ? "Get more views" : "Get more downloads",
                                 primary: false, busy: ads.busy || ads.isPresenting) {
                        requestedReward = true
                        rewardTask = Task { await ads.watch(commerce: commerce, quota: quota, kind: kind) }
                    }.disabled(purchasing || ads.isPreparingAppOpen || ads.busy || ads.isPresenting)
                }
            }
            if ads.busy {
                HStack(spacing: 12) {
                    loadingMark(width: 28)
                    LocalizedText("Loading ad…").font(.capture(.footnote))
                    Spacer(minLength: 12)
                    Button("Cancel") { cancelRewardRequest() }
                        .buttonStyle(CompactActionStyle())
                }
            }
            LocalizedText(quota.unlimited ? "Unlimited views today" : "\(quota.watchesLeft) views left today")
            LocalizedText(quota.downloadsUnlimited ? "Unlimited downloads today" : "\(quota.downloadsLeft) downloads left today")
            AllowanceResetText()
            LocalizedText("Ad rewards unlock when the corresponding allowance runs out.")
                .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = ads.error { ErrorNote(message: error) }
            if let error = quota.error { ErrorNote(message: error) }
            if let message = ads.message {
                LocalizedText(message).font(.capture(.footnote)).foregroundStyle(SwevoStyle.accent)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private func cancelRewardRequest() {
        rewardTask?.cancel()
        rewardTask = nil
        ads.cancelRewardLoading()
    }

    private func loadingMark(width: CGFloat) -> some View {
        Image("SwevoLoadingMark").renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(SwevoStyle.accent)
            .frame(width: width, height: 14)
            .phaseAnimator([false, true]) { content, dimmed in
                content.opacity(reduceMotion || scenePhase != .active ? 1 : (dimmed ? 0.35 : 1))
            } animation: { _ in
                reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.6)
            }
            .accessibilityHidden(true)
    }

    private var restoreLink: some View {
        Button {
            attemptedPurchaseAction = true
            commerce.restore()
        } label: {
            LocalizedText("Restore purchases")
                .font(.capture(.footnote, display: true))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .foregroundStyle(SwevoStyle.accent)
                .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(SwevoStyle.line).allowsHitTesting(false) }
                .contentShape(Rectangle())
        }.disabled(interactionLocked).buttonStyle(PressStyle())
            .accessibilityIdentifier("membership.restore")
    }
}

struct AccountView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    @State private var paywall = false
    private var unavailable: Bool {
        accountAccess.isBusy || commerce.busy || commerce.preparingPurchase || ads.busy || ads.isPresenting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let session = api.session {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            accountIdentity(session.userId.value)
                            Spacer(minLength: 16)
                            accountStatus
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            accountIdentity(session.userId.value)
                            accountStatus
                        }
                    }
                    membershipCard
                    allowance
                } else { ConnectionPanel() }
                AccountSettingsSection()
                LocalizedText("Version \(api.configuration.version)")
                    .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.swevoScreenBackground().foregroundStyle(.white)
            .sheet(isPresented: $paywall) { MembershipView() }
    }

    private func accountIdentity(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            LocalizedText("Your practice space").font(.capture(.headline)).foregroundStyle(SwevoStyle.paper)
            LocalizedText("ID · \(id)").font(.caption.monospaced()).foregroundStyle(SwevoStyle.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountStatus: some View {
        LocalizedText(commerce.premium ? "Plus active" : "Free plan")
            .font(.capture(.caption, weight: .semibold))
            .foregroundStyle(commerce.premium ? SwevoStyle.accent : SwevoStyle.secondary)
    }

    private var membershipCard: some View {
        Button { paywall = true } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    membershipCopy
                    CaptureArtwork(kind: .pass, height: 126).frame(width: 132)
                }
                VStack(alignment: .leading, spacing: 12) {
                    CaptureArtwork(kind: .pass, height: 100)
                    membershipCopy
                }
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(SwevoStyle.paper, in: RoundedRectangle(cornerRadius: 24))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(PressStyle()).disabled(unavailable)
            .accessibilityIdentifier("account.membership")
    }

    private var membershipCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText(commerce.premium ? "Your all-access pass." : "Go further with Plus.")
                .font(.capture(.title3, weight: .semibold)).foregroundStyle(SwevoStyle.ink)
            LocalizedText("Unlimited views. Unlimited downloads.")
                .font(.capture(.footnote)).foregroundStyle(SwevoStyle.paperSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText(commerce.premium ? "Manage membership" : "Explore plans")
                .font(.capture(.footnote, weight: .semibold)).foregroundStyle(SwevoStyle.ink)
                .padding(.top, 8)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var allowance: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                LocalizedText("Today").font(.capture(.headline))
                Spacer()
                if !commerce.premium {
                    Button("Get more") { paywall = true }
                        .font(.capture(.footnote, weight: .semibold)).foregroundStyle(SwevoStyle.accent)
                        .frame(minHeight: 44).buttonStyle(PressStyle()).disabled(unavailable)
                        .accessibilityLabel("Get more daily views and downloads")
                }
            }
            HStack(alignment: .top, spacing: 20) {
                balance(value: commerce.premium || quota.unlimited ? "Unlimited" : "\(quota.watchesLeft)", label: "Views left")
                balance(value: commerce.premium || quota.downloadsUnlimited ? "Unlimited" : "\(quota.downloadsLeft)", label: "Downloads left")
            }
            if commerce.premium {
                LocalizedText("Included with your membership").font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
            } else { AllowanceResetText() }
        }
    }

    private func balance(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(value).font(value == "Unlimited" ? .headline : .title.weight(.semibold))
                .monospacedDigit().foregroundStyle(SwevoStyle.paper)
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText(label).font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LuckyRewardView: View {
    let message: String
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    CaptureArtwork(kind: .pass, height: 108)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                        .accessibilityHidden(true)
                    LocalizedText("A little luck, on us").font(.capture(.headline)).foregroundStyle(.white)
                    LocalizedText("No ad is available right now. \(message)")
                        .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: "Keep exploring", action: dismiss)
                }.padding(20).frame(maxWidth: 360)
                    .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 28))
                    .padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(Color.black.opacity(0.68).ignoresSafeArea())
            .accessibilityAddTraits(.isModal).interactiveDismissDisabled()
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { appeared = true } }
    }
}


struct AllowanceResetText: View {
    @Environment(\.locale) private var locale
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let next = QuotaStore.nextReset(after: context.date)
            LocalizedText("Resets %@ (local time)", localTime(next))
                .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func localTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

}
