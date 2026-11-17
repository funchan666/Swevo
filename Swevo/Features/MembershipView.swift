import SwiftUI
import StoreKit

struct PlusEntryButton: View {
    let action: () -> Void

    var body: some View {
        let shape = Capsule()
        return Button(action: action) {
            HStack(spacing: 4) {
                SwevoIllustration(name: "LaunchMark", height: 24).frame(width: 24)
                LocalizedText("Plus").font(.capture(.footnote, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 5)
            .frame(minHeight: 36)
            .foregroundStyle(SwevoStyle.accent)
            .background(SwevoStyle.surface.opacity(0.88), in: shape)
            .overlay { shape.strokeBorder(SwevoStyle.accent.opacity(0.30)).allowsHitTesting(false) }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(LocalizedStringKey("Kstep Plus"))
        .accessibilityIdentifier("membership.tabEntry")
    }
}

struct MembershipView: View {
    var rewardKind: AllowanceKind? = nil
    var exportRequired = false
    var showsRewardOptions = true
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var ads: RewardedAds
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?
    @State private var planTask: Task<Void, Never>?
    @State private var purchaseAction: PurchaseAction?
    @State private var purchaseTask: Task<Void, Never>?
    @State private var rewardTask: Task<Void, Never>?
    @State private var requestedReward = false
    @State private var acknowledgedLuckyReward = false

    private enum PurchaseAction { case subscribe, restore }

    private var configuredPlans: [CommerceConfiguration.Product] { commerce.policy?.products ?? [] }

    private var plans: [SKProduct] {
        configuredPlans.compactMap { entry in
            commerce.products.first { $0.productIdentifier == entry.id }
        }.filter { !commerce.period($0, locale: locale).isEmpty }
    }
    private var selectedPlan: SKProduct? {
        plans.first(where: { $0.productIdentifier == selectedID }) ?? plans.first
    }
    private var purchasing: Bool { commerce.preparingPurchase || commerce.busy || purchaseTask != nil }
    private var loadingCatalog: Bool { planTask != nil || commerce.loadingPlans }
    private var interactionLocked: Bool { purchasing || loadingCatalog || ads.busy || ads.isPresenting }

    var body: some View {
        GeometryReader { container in
            let dockWidth = min(680, container.size.width)
            let dockHeight = min(typeSize.isAccessibilitySize ? 176 : 132, container.size.height)
            let dock = CGRect(x: (container.size.width - dockWidth) / 2, y: container.size.height - dockHeight,
                              width: dockWidth, height: dockHeight)
            let pinsPurchaseBar = container.size.height >= (typeSize.isAccessibilitySize ? 520 : 340)
                && !SwevoStyle.intersectsReservedRegion(dock, in: container)
            let billingInBar = pinsPurchaseBar && container.size.height >= 480 && !typeSize.isAccessibilitySize
            let compact = container.size.height < 660
            ScrollViewReader { scroll in
                VStack(spacing: 0) {
                    topActions {
                        scroll.scrollTo("membership.content", anchor: .top)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 16) {
                                pageTitle(compact: compact)
                                membershipContent(in: container, billingInBar: billingInBar)
                                    .id("membership.content")
                            }
                            .pageHorizontalMargins()
                            .frame(maxWidth: 680)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .padding(.top, 8).padding(.bottom, 16)
                            if !pinsPurchaseBar { purchaseBar(showsBilling: false) }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .clipped()
                    if pinsPurchaseBar { purchaseBar(showsBilling: billingInBar) }
                }
                .background(alignment: .top) {
                    SceneArtwork(name: "ScenePlusCover")
                        .frame(height: compact ? 128 : 168)
                        .opacity(0.78)
                        .ignoresSafeArea(.container, edges: .top)
                }
                .onChange(of: commerce.error ?? commerce.message) { _, feedback in
                    if feedback != nil, purchaseAction != nil || commerce.canRetryPurchaseConfirmation {
                        scroll.scrollTo("membership.content", anchor: .top)
                    }
                }
            }
        }
        .swevoScreenBackground()
        .foregroundStyle(SwevoStyle.paper)
        .tint(SwevoStyle.accent)
        .task { await commerce.refresh() }
        .task { await commerce.loadPlans() }
        .onDisappear {
            planTask?.cancel(); planTask = nil
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

    private func topActions(onRestore: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconButton(symbol: .back, label: "Back") {
                cancelRewardRequest()
                dismiss()
            }
            .swevoGlass(cornerRadius: 22)
            .disabled(purchasing || ads.isPresenting)
            Spacer(minLength: 0)
            restoreButton(onRestore: onRestore)
        }
        .pageHorizontalMargins()
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func pageTitle(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SceneTitle("Kstep Plus", size: compact ? 30 : 36)
            if exportRequired {
                LocalizedText("Export is included with Plus.")
                    .font(.capture(.subheadline, weight: .semibold))
                    .foregroundStyle(SwevoStyle.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func membershipContent(in container: GeometryProxy, billingInBar: Bool) -> some View {
        let width = min(640, SwevoStyle.pageContentWidth(in: container))
        let bounds = CGRect(origin: .zero, size: container.size)
        let allowsColumns = typeSize <= .xLarge && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
        let wide = allowsColumns && width >= 620
        let planWidth = wide ? (width - 24) / 2 : width
        let pairedPlans = allowsColumns && planWidth >= 310
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))

        return VStack(alignment: .leading, spacing: 12) {
            if purchaseAction != nil || commerce.canRetryPurchaseConfirmation { purchaseFeedback }
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    if commerce.premium {
                        activeMembership
                    } else {
                        planSelection(paired: pairedPlans)
                        if !billingInBar, !loadingCatalog, !commerce.canRetryPurchaseConfirmation, let selectedPlan {
                            renewalDisclosure(for: selectedPlan)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                benefits.frame(maxWidth: .infinity, alignment: .leading)
            }
            PolicyLinks(style: .inline)
            if !exportRequired, !commerce.premium, api.session != nil {
                AllowanceStatusPanel()
                if showsRewardOptions { rewardOption }
            }
        }
    }

    @ViewBuilder private func purchaseBar(showsBilling: Bool) -> some View {
        if commerce.canRetryPurchaseConfirmation || (!commerce.premium && !configuredPlans.isEmpty) {
            VStack(alignment: .leading, spacing: 6) {
                if commerce.canRetryPurchaseConfirmation {
                    ActionButton(title: "Retry purchase confirmation", primary: false, busy: purchasing) {
                        purchaseAction = .subscribe
                        purchaseTask = Task {
                            await commerce.retryPurchaseConfirmation()
                            purchaseTask = nil
                        }
                    }.disabled(interactionLocked)
                        .accessibilityIdentifier("membership.retryPurchase")
                } else {
                    if showsBilling, !loadingCatalog, let selectedPlan {
                        renewalDisclosure(for: selectedPlan)
                    }
                    checkoutButton
                }
            }
            .pageHorizontalMargins()
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .background(SwevoStyle.background)
            .overlay(alignment: .top) {
                Divider().overlay(SwevoStyle.line)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("Plus benefits").font(.capture(.headline))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            benefit(.feed, "JPEG stills and comparison images",
                    "Share three frames or one image with the range name and timestamps.", featured: true)
                .padding(12)
                .background(SwevoStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 8) {
                benefit(.edit, "Video and audio export", "MP4 up to 1080p · M4A")
                benefit(.play, "No daily viewing or download limits", "Skip opening ads")
                benefit(.bookmark, "Shot presets", "Save movement, duration and focus settings.")
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
        }
    }

    private func benefit(_ symbol: SwevoGlyph, _ title: String, _ detail: String,
                         featured: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Glyph(symbol: symbol, size: featured ? 21 : 16, tint: SwevoStyle.accent)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                LocalizedText(title).font(.capture(.subheadline, weight: .semibold))
                LocalizedText(detail).font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var activeMembership: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText("Plus active").font(.capture(.headline)).foregroundStyle(SwevoStyle.accent)
            if let expiration = commerce.expiration {
                let date = expiration.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
                LocalizedText("Access through %@.", date)
                    .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
            }
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                Link(destination: url) {
                    LocalizedText("Manage subscription").font(.capture(.footnote, weight: .semibold))
                        .foregroundStyle(SwevoStyle.accent)
                        .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(PressStyle())
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .swevoGlass(cornerRadius: 18)
    }

    @ViewBuilder private var purchaseFeedback: some View {
        if let error = commerce.error {
            ErrorNote(message: error)
        } else if let message = commerce.message {
            LocalizedText(message).font(.capture(.subheadline)).foregroundStyle(SwevoStyle.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func planSelection(paired: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LocalizedText("Subscription plans").font(.capture(.headline))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if configuredPlans.isEmpty {
                LocalizedText("Subscription setup is incomplete. Please contact support.")
                    .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                planPicker(paired: paired && configuredPlans.count == 2)
                if !loadingCatalog, plans.count < configuredPlans.count {
                    LocalizedText(commerce.plansError ?? "This plan isn’t available from Apple yet. Please try again later.")
                        .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if selectedPlan != nil {
                        Button(action: reloadPlans) {
                            LocalizedText("Reload plans")
                        }
                        .buttonStyle(CompactActionStyle())
                        .disabled(interactionLocked)
                    }
                }
            }
            if api.session == nil { ConnectionPanel() }
        }
    }

    private var purchaseButtonTitle: String {
        if commerce.preparingPurchase { return "Preparing purchase…" }
        if commerce.busy { return "Checking purchases…" }
        if loadingCatalog { return "Loading plans…" }
        return selectedPlan == nil ? "Reload plans" : "Subscribe"
    }

    private func planPicker(paired: Bool) -> some View {
        let layout = paired ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
                            : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        return layout {
            ForEach(configuredPlans) { entry in
                planOption(entry, column: paired)
                if !paired, entry.id != configuredPlans.last?.id {
                    Divider().overlay(SwevoStyle.line).padding(.horizontal, 12)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            if paired {
                Rectangle().fill(SwevoStyle.line).frame(width: 1).padding(.vertical, 12)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .clipShape(.rect(cornerRadius: 16))
        .swevoGlass(cornerRadius: 16)
    }

    @ViewBuilder private func planOption(_ entry: CommerceConfiguration.Product, column: Bool) -> some View {
        let product = plans.first { $0.productIdentifier == entry.id }
        let selected = selectedPlan?.productIdentifier == entry.id
        let name = planName(product, fallback: entry.label)
        let price = Group {
            if let product {
                planPrice(commerce.price(product), selected: selected)
            } else {
                LocalizedText(loadingCatalog ? "Checking with Apple…" : "Price unavailable")
                    .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        let period = Group {
            if let product { planPeriod(commerce.period(product, locale: locale)) }
        }
        let stacked = VStack(alignment: .leading, spacing: 4) {
            name
            price
            period
        }
        let label = Group {
            if column {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            name
                            period
                        }.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        price.fixedSize(horizontal: true, vertical: false)
                    }
                    stacked
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: column ? 98 : 60, alignment: column ? .topLeading : .leading)
        .foregroundStyle(SwevoStyle.paper)

        if let product {
            Button { selectedID = product.productIdentifier } label: {
                label.background(selected ? SwevoStyle.accent.opacity(0.10) : Color.clear)
                    .overlay(alignment: column ? .bottom : .leading) {
                        if selected {
                            Capsule().fill(SwevoStyle.accent)
                                .frame(width: column ? nil : 2, height: column ? 2 : nil)
                                .padding(column ? .horizontal : .vertical, 12)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle()).disabled(interactionLocked)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("membership.plan.\(entry.id)")
        } else {
            label.accessibilityElement(children: .combine)
        }
    }

    private func planName(_ product: SKProduct?, fallback: String) -> some View {
        Group {
            if let period = product?.subscriptionPeriod, period.numberOfUnits == 1, period.unit == .month {
                LocalizedText("Monthly")
            } else if let period = product?.subscriptionPeriod, period.numberOfUnits == 1, period.unit == .year {
                LocalizedText("Yearly")
            } else if let product {
                let title = product.localizedTitle
                    .replacingOccurrences(of: "Swevo", with: "Kstep", options: .caseInsensitive)
                    .replacingOccurrences(of: "KStep", with: "Kstep", options: .caseInsensitive)
                Text(verbatim: title)
            } else {
                LocalizedText(fallback)
            }
        }.font(.capture(.headline, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func planPeriod(_ period: String) -> some View {
        LocalizedText("Billed every %@", period).font(.capture(.footnote))
            .foregroundStyle(SwevoStyle.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func planPrice(_ price: String, selected: Bool) -> some View {
        Text(verbatim: price).environment(\.layoutDirection, .leftToRight)
            .font(.capture(.title2, weight: .semibold)).monospacedDigit()
            .foregroundStyle(selected ? SwevoStyle.accent : SwevoStyle.paper)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func renewalDisclosure(for plan: SKProduct) -> some View {
        LocalizedText("%@ every %@. Renews automatically until canceled.",
                      commerce.price(plan), commerce.period(plan, locale: locale))
            .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var checkoutButton: some View {
        let canShowOffer = selectedPlan != nil && !loadingCatalog
        return Button {
            if canShowOffer { subscribe() } else { reloadPlans() }
        } label: {
            ActionLabel(title: purchaseButtonTitle, primary: canShowOffer, busy: purchasing || loadingCatalog)
        }.buttonStyle(PressStyle())
            .disabled(interactionLocked || (canShowOffer && api.session == nil))
            .accessibilityIdentifier(canShowOffer ? "membership.subscribe" : "membership.retryPlans")
    }

    private func reloadPlans() {
        guard !interactionLocked else { return }
        planTask = Task {
            await commerce.loadPlans()
            planTask = nil
        }
    }

    private func subscribe() {
        guard !interactionLocked, let plan = selectedPlan else { return }
        purchaseAction = .subscribe
        purchaseTask = Task {
            await commerce.purchase(planID: plan.productIdentifier)
            purchaseTask = nil
        }
    }

    private var rewardOption: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rewardKind.map { [$0] } ?? AllowanceKind.allCases) { kind in
                if quota.canRequestReward(for: kind, premium: commerce.premium) {
                    if quota.completedAds(kind) >= 3 {
                        LocalizedText(quota.rewardSummary(for: kind))
                            .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                    }
                    ActionButton(title: kind == .watch ? "Watch an ad for more views" : "Watch an ad for more downloads",
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
            LocalizedText("After reaching a daily limit, finish an ad to get more views or downloads.")
                .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = ads.error { ErrorNote(message: error) }
            if let message = ads.message {
                LocalizedText(message).font(.capture(.footnote)).foregroundStyle(SwevoStyle.accent)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
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

    private func restoreButton(onRestore: @escaping () -> Void) -> some View {
        Button {
            purchaseAction = .restore
            commerce.restore()
            onRestore()
        } label: {
            LocalizedText("Restore purchases")
                .font(.capture(.footnote, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(SwevoStyle.accent)
                .swevoGlass(cornerRadius: 22)
                .contentShape(RoundedRectangle(cornerRadius: 22))
        }.disabled(interactionLocked).buttonStyle(PressStyle())
            .accessibilityIdentifier("membership.restore")
    }
}

struct AccountView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    @State private var paywall = false
    private var unavailable: Bool {
        accountAccess.isBusy || commerce.busy || commerce.preparingPurchase || ads.busy || ads.isPresenting
    }

    var body: some View {
        ScenePage(artwork: "SceneAccountCover", depth: 176, openingGap: 0) { _ in
            membershipEntry
        } content: { container in
            accountContent(in: container)
        }
        .fullScreenCover(isPresented: $paywall) { MembershipView() }
    }

    private func accountContent(in container: GeometryProxy) -> some View {
        let bounds = CGRect(origin: .zero, size: container.size)
        let width = min(640, SwevoStyle.pageContentWidth(in: container))
        let hasReservedRegion = SwevoStyle.intersectsReservedRegion(bounds, in: container)
        let wide = api.session != nil && width >= 620 && typeSize <= .xLarge && !hasReservedRegion
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))

        return layout {
            VStack(alignment: .leading, spacing: 12) {
                if api.session != nil {
                    allowance
                    accountDetails
                } else { ConnectionPanel() }
            }.frame(maxWidth: .infinity, alignment: .leading)
            AccountSettingsSection()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var accountDetails: some View {
        if let id = api.session?.userId.value {
            LocalizedText("ID · %@", id).monospacedDigit().textSelection(.enabled)
                .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var membershipEntry: some View {
        let title = HStack(spacing: 8) {
            SwevoIllustration(name: "LaunchMark", height: 42).frame(width: 42)
            VStack(alignment: .leading, spacing: 4) {
                SceneTitle("Kstep Plus", size: 25).accessibilityRemoveTraits(.isHeader)
                if api.session != nil, commerce.premium || commerce.rightsVerified {
                    LocalizedText(commerce.premium ? "Plus active" : "Free plan")
                        .font(.capture(.footnote, weight: .medium))
                        .foregroundStyle(commerce.premium ? SwevoStyle.accent : SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        let action = HStack(spacing: 8) {
            LocalizedText(commerce.premium ? "View membership" : "View plans")
                .font(.capture(.footnote, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Glyph(symbol: .back, size: 11, tint: SwevoStyle.accent).rotationEffect(.degrees(180))
        }.foregroundStyle(SwevoStyle.accent)

        return Button { paywall = true } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    title.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    Rectangle().fill(SwevoStyle.line).frame(width: 1, height: 26)
                        .accessibilityHidden(true)
                    action.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 12) {
                    title
                    action
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .foregroundStyle(SwevoStyle.paper)
            .swevoGlass(cornerRadius: 20, tint: SwevoStyle.surface.opacity(0.74))
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(SwevoStyle.accent.opacity(0.23))
                    .allowsHitTesting(false)
            }
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(PressStyle()).disabled(unavailable)
            .accessibilityIdentifier("account.membership")
            .padding(.top, 40)
            .padding(.bottom, 8)
    }

    private var allowance: some View {
        VStack(alignment: .leading, spacing: 8) {
            AllowanceStatusPanel()
            if commerce.premium {
                LocalizedText("Included with your membership")
                    .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button { paywall = true } label: {
                    HStack(spacing: 6) {
                        LocalizedText("Get more").font(.capture(.footnote, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Glyph(symbol: .back, size: 11, tint: SwevoStyle.accent).rotationEffect(.degrees(180))
                    }.frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(SwevoStyle.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle()).disabled(unavailable)
                .accessibilityLabel("Get more daily views and downloads")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

struct AllowanceStatusPanel: View {
    var kinds = AllowanceKind.allCases
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @State private var showsUsageDetails = false

    private var hasUsage: Bool { quota.usage != nil && quota.error == nil }
    private var canShowDetails: Bool { api.session != nil && hasUsage && !commerce.premium }
    private var detailsVisible: Bool { canShowDetails && showsUsageDetails }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            allowanceHeading
            if api.session == nil {
                LocalizedText("Connect to refresh your allowance.")
                    .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if commerce.premium || hasUsage {
                    statusRows
                } else if quota.error == nil {
                    HStack(spacing: 10) {
                        ProgressView().tint(SwevoStyle.accent).accessibilityHidden(true)
                        LocalizedText("Loading daily limits…")
                            .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(minHeight: 44)
                }
                if let error = quota.error { ErrorNote(message: error) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { quota.resetIfNeeded() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in quota.resetIfNeeded() }
    }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(kinds) { kind in
                if kind != kinds.first { rule }
                allowanceStatus(kind)
            }
            if detailsVisible {
                rule
                AllowanceResetText().padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 14)
        .background(SwevoStyle.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 14))
    }

    private var rule: some View {
        Rectangle().fill(SwevoStyle.line).frame(height: 1).accessibilityHidden(true)
    }

    @ViewBuilder private var allowanceHeading: some View {
        let title = LocalizedText(kinds == [.download] ? "Daily limits" : "Online video")
            .font(.capture(.headline))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)

        if canShowDetails {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    title.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    usageDetailsButton.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 0) {
                    title
                    usageDetailsButton
                }
            }
        } else {
            title
        }
    }

    private var usageDetailsButton: some View {
        let down = layoutDirection == .leftToRight ? -90.0 : 90.0
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.20)) {
                showsUsageDetails.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                LocalizedText(showsUsageDetails ? "Hide details" : "Usage details")
                    .font(.capture(.footnote, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Glyph(symbol: .back, size: 10, tint: SwevoStyle.accent)
                    .rotationEffect(.degrees(showsUsageDetails ? -down : down))
            }
            .foregroundStyle(SwevoStyle.accent)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("account.usageDetails")
    }

    private func allowanceStatus(_ kind: AllowanceKind) -> some View {
        let isWatch = kind == .watch
        let unlimited = commerce.premium || quota.isUnlimited(kind)
        let remaining = quota.remaining(kind)
        let available = unlimited || remaining > 0
        let title = LocalizedText(isWatch ? "Online viewing" : "Offline downloads")
            .font(.capture(.subheadline, weight: .medium))
            .foregroundStyle(SwevoStyle.paper)
            .fixedSize(horizontal: false, vertical: true)
        let status = LocalizedText(unlimited ? "Unlimited" : (available ? "Available today" : "Daily limit reached"))
            .font(.capture(.footnote, weight: .medium))
            .foregroundStyle(available ? SwevoStyle.accent : SwevoStyle.danger)
            .fixedSize(horizontal: false, vertical: true)

        return HStack(alignment: .top, spacing: 10) {
            Glyph(symbol: isWatch ? .play : .download, size: 16, tint: SwevoStyle.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        title.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        status.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        title
                        status
                    }
                }
                if detailsVisible, !unlimited {
                    LocalizedText("%@ left · %@ total today", remaining.formatted(.number.locale(locale)),
                                  quota.totalAllowance(for: kind).formatted(.number.locale(locale)))
                        .font(.capture(.footnote)).monospacedDigit()
                        .foregroundStyle(SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
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
                    SceneImage(name: "ScenePlus").frame(height: 100)
                        .mask { LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.70),
                            .init(color: .clear, location: 1)
                        ], startPoint: .top, endPoint: .bottom) }
                        .padding([.top, .horizontal], -20)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                    LocalizedText("No ad available").font(.capture(.headline)).foregroundStyle(.white)
                    LocalizedText(message)
                        .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: "Close", action: dismiss)
                }.padding(20).frame(maxWidth: 360)
                    .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 28))
                    .clipShape(.rect(cornerRadius: 28))
                    .padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(Color.black.opacity(0.68).ignoresSafeArea())
            .accessibilityAddTraits(.isModal).interactiveDismissDisabled()
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { appeared = true } }
    }
}


struct AllowanceResetText: View {
    var tint: Color = SwevoStyle.secondary
    @Environment(\.locale) private var locale
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let next = QuotaStore.nextReset(after: context.date)
            LocalizedText("Resets %@ (local time)", localTime(next))
                .font(.capture(.caption)).foregroundStyle(tint)
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
