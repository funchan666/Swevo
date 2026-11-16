import SwiftUI
import StoreKit

struct MembershipView: View {
    var rewardKind: AllowanceKind? = nil
    var exportRequired = false
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
    @State private var purchaseAction: PurchaseAction?
    @State private var purchaseTask: Task<Void, Never>?
    @State private var rewardTask: Task<Void, Never>?
    @State private var requestedReward = false
    @State private var acknowledgedLuckyReward = false

    private enum PurchaseAction { case subscribe, restore }

    private var plans: [SKProduct] {
        (commerce.policy?.products ?? []).compactMap { entry in
            commerce.products.first { $0.productIdentifier == entry.id }
        }.filter { !commerce.period($0, locale: locale).isEmpty }
    }
    private var selectedPlan: SKProduct? {
        plans.first(where: { $0.productIdentifier == selectedID }) ?? plans.first
    }
    private var purchasing: Bool { commerce.preparingPurchase || commerce.busy || purchaseTask != nil }
    private var interactionLocked: Bool { purchasing || commerce.loadingPlans || ads.busy || ads.isPresenting }

    var body: some View {
        ScenePage(artwork: "ScenePlusCover", depth: 172, openingGap: 0, artworkOpacity: 0.92) { _ in
            VStack(alignment: .leading, spacing: 4) {
                LocalizedText("Swevo Plus").font(.capture(.largeTitle, weight: .semibold, display: true))
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                restoreLink
            }.padding(.trailing, 48)
        } content: { container in
            membershipContent(in: container)
        }
        .sceneDismiss(disabled: purchasing || ads.isPresenting) {
            cancelRewardRequest()
            dismiss()
        }
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

    private func membershipContent(in container: GeometryProxy) -> some View {
        let width = SwevoStyle.pageContentWidth(in: container)
        let bounds = CGRect(origin: .zero, size: container.size)
        let allowsColumns = !typeSize.isAccessibilitySize && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
        let wide = allowsColumns && width >= 620
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 32))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))

        return VStack(alignment: .leading, spacing: 24) {
            if purchaseAction == .restore { purchaseFeedback }
            exportHighlight
            layout {
                checkout.frame(maxWidth: .infinity, alignment: .leading)
                benefits.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !exportRequired, !commerce.premium, api.session != nil { rewardOption }
        }
    }

    private var checkout: some View {
        VStack(alignment: .leading, spacing: 12) {
            if commerce.premium {
                activeMembership
            } else {
                planSelection
            }
            if commerce.canRetryPurchaseConfirmation {
                ActionButton(title: "Retry purchase confirmation", primary: false, busy: purchasing) {
                    purchaseAction = .subscribe
                    purchaseTask = Task {
                        await commerce.retryPurchaseConfirmation()
                        purchaseTask = nil
                    }
                }.disabled(interactionLocked)
                    .accessibilityIdentifier("membership.retryPurchase")
            } else if !commerce.premium {
                if let selectedPlan { renewalDisclosure(for: selectedPlan) }
                if selectedPlan != nil || commerce.loadingPlans || purchasing { subscribeButton }
            }
            if purchaseAction == .subscribe || (purchaseAction == nil && commerce.canRetryPurchaseConfirmation) {
                purchaseFeedback
            }
            PolicyLinks(compact: true)
        }
    }

    private var exportHighlight: some View {
        VStack(alignment: .leading, spacing: 10) {
            if exportRequired {
                LocalizedText("Export is included with Plus.")
                    .font(.capture(.footnote, weight: .semibold)).foregroundStyle(SwevoStyle.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 14) {
                Glyph(symbol: .feed, size: 23, tint: SwevoStyle.ink)
                    .frame(width: 44, height: 44).background(SwevoStyle.accent, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("JPEG stills and comparison images").font(.capture(.title3, weight: .semibold, display: true))
                    LocalizedText("Share three frames or one image with the range name and timestamps.")
                        .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                }.fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
        }.padding(.bottom, 15).overlay(alignment: .bottom) { Divider().overlay(SwevoStyle.line).accessibilityHidden(true) }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Plus benefits").accessibilityAddTraits(.isHeader)
            benefit(.edit, "MP4 video export", "Up to 1080p")
            benefit(.sound, "M4A audio export")
            Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
            benefit(.bookmark, "Shot presets", "Save movement, duration and focus settings.")
            benefit(.play, "No daily viewing or download limits")
            benefit(.home, "Skip opening ads")
        }
    }

    private func benefit(_ symbol: SwevoGlyph, _ title: String, _ detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Glyph(symbol: symbol, size: 17, tint: SwevoStyle.accent)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                LocalizedText(title).font(.capture(.subheadline, weight: .semibold))
                if let detail {
                    LocalizedText(detail).font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                }
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
        if let error = commerce.error { ErrorNote(message: error) }
        if let message = commerce.message {
            LocalizedText(message).font(.capture(.subheadline)).foregroundStyle(SwevoStyle.accent)
        }
    }

    private var planSelection: some View {
        let invalidPlans = !commerce.loadingPlans && !commerce.products.isEmpty && plans.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            if !plans.isEmpty { planPicker }
            if api.session == nil { ConnectionPanel() }
            if let error = commerce.plansError ?? (invalidPlans ?
                "This plan isn’t available from Apple yet. Please try again later." : nil) {
                ErrorNote(message: error)
                ActionButton(title: "Retry", primary: false) { Task { await commerce.loadPlans() } }
                    .disabled(interactionLocked)
            }
        }
    }

    private var purchaseButtonTitle: String {
        if commerce.preparingPurchase { return "Preparing purchase…" }
        if commerce.busy { return "Checking purchases…" }
        if commerce.loadingPlans { return "Loading plans…" }
        return "Subscribe"
    }

    private var planPicker: some View {
        VStack(spacing: 0) {
            ForEach(plans, id: \.productIdentifier) { plan in
                planOption(plan)
                if plan.productIdentifier != plans.last?.productIdentifier {
                    Divider().overlay(SwevoStyle.line).padding(.horizontal, 14).accessibilityHidden(true)
                }
            }
        }.clipShape(.rect(cornerRadius: 16)).swevoGlass(cornerRadius: 16)
    }

    private func planOption(_ product: SKProduct) -> some View {
        let selected = selectedPlan?.productIdentifier == product.productIdentifier
        let price = commerce.price(product)
        let period = commerce.period(product, locale: locale)
        return Button { selectedID = product.productIdentifier } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        planName(product)
                        planPeriod(period)
                    }.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    planPrice(price, selected: selected).fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    planName(product)
                    planPrice(price, selected: selected)
                    planPeriod(period)
                }
            }.padding(.horizontal, 16).padding(.vertical, 13)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .foregroundStyle(SwevoStyle.paper)
                .background(selected ? SwevoStyle.accent.opacity(0.10) : Color.clear)
                .overlay(alignment: .leading) {
                    if selected {
                        Capsule().fill(SwevoStyle.accent).frame(width: 3).padding(.vertical, 10).allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).disabled(interactionLocked)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("membership.plan.\(product.productIdentifier)")
    }

    private func planName(_ product: SKProduct) -> some View {
        Group {
            if let period = product.subscriptionPeriod, period.numberOfUnits == 1, period.unit == .month {
                LocalizedText("Monthly")
            } else if let period = product.subscriptionPeriod, period.numberOfUnits == 1, period.unit == .year {
                LocalizedText("Yearly")
            } else {
                Text(verbatim: product.localizedTitle)
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
            .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var subscribeButton: some View {
        Button(action: subscribe) {
            HStack(spacing: 12) {
                LocalizedText(purchaseButtonTitle).font(.capture(.headline, display: true))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if purchasing || commerce.loadingPlans {
                    loadingMark(width: 30, tint: SwevoStyle.accent).frame(width: 44, height: 44)
                } else if selectedPlan != nil {
                    Glyph(symbol: .back, size: 16, tint: SwevoStyle.ink).rotationEffect(.degrees(180))
                        .frame(width: 44, height: 44).background(SwevoStyle.accent, in: Circle())
                }
            }.padding(.leading, 16).padding(.trailing, 7).padding(.vertical, 7).frame(minHeight: 58)
                .foregroundStyle(SwevoStyle.paper)
                .swevoGlass(cornerRadius: 29)
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .disabled(interactionLocked || selectedPlan == nil)
            .accessibilityIdentifier("membership.subscribe")
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
            LocalizedText("Daily limits").font(.capture(.headline))
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
            LocalizedText(quota.unlimited ? "Unlimited views today" : "\(quota.watchesLeft) views left today")
            LocalizedText(quota.downloadsUnlimited ? "Unlimited downloads today" : "\(quota.downloadsLeft) downloads left today")
            AllowanceResetText()
            LocalizedText("After reaching a daily limit, finish an ad to get more views or downloads.")
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

    private func loadingMark(width: CGFloat, tint: Color = SwevoStyle.accent) -> some View {
        Image("SwevoLoadingMark").renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(tint)
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
            purchaseAction = .restore
            commerce.restore()
        } label: {
            LocalizedText("Restore purchases")
                .font(.capture(.footnote, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .foregroundStyle(SwevoStyle.accent)
                .contentShape(Rectangle())
        }.disabled(interactionLocked).buttonStyle(PressStyle())
            .accessibilityIdentifier("membership.restore")
    }
}

struct AccountView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
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
        ScenePage { container in
            accountContent(in: container)
        }
        .sheet(isPresented: $paywall) { MembershipView() }
    }

    private func accountContent(in container: GeometryProxy) -> some View {
        let bounds = CGRect(origin: .zero, size: container.size)
        let wide = api.session != nil && SwevoStyle.pageContentWidth(in: container) >= 620
            && !typeSize.isAccessibilitySize && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))

        return VStack(alignment: .leading, spacing: 24) {
            layout {
                VStack(alignment: .leading, spacing: 12) {
                    membershipEntry
                    if api.session != nil {
                        allowance
                        accountDetails
                    } else { ConnectionPanel() }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    AccountSettingsSection()
                    LocalizedText("Version %@", api.configuration.version)
                        .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
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
        let status = api.session == nil ? "Swevo Plus" : (commerce.premium ? "Plus active" : "Free plan")
        return Button { paywall = true } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText(status)
                        .font(.capture(.footnote, weight: .semibold))
                    LocalizedText(commerce.premium ? "View membership" : "View Plus plans")
                        .font(.capture(.headline))
                }.fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: .back, size: 15, tint: SwevoStyle.ink).rotationEffect(.degrees(180))
            }.padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 62)
                .foregroundStyle(SwevoStyle.ink)
                .background(SwevoStyle.accent, in: RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(PressStyle()).disabled(unavailable)
            .accessibilityIdentifier("account.membership")
    }

    private var allowance: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    allowanceTitle.fixedSize()
                    Spacer(minLength: 0)
                    if !commerce.premium { moreAllowance.fixedSize(horizontal: true, vertical: false) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    allowanceTitle
                    if !commerce.premium { moreAllowance }
                }
            }
            if commerce.premium || quota.usage != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 16) {
                        balance(.watch).fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        balance(.download).fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        balance(.watch)
                        balance(.download)
                    }
                }
                Divider().overlay(SwevoStyle.ink.opacity(0.12)).accessibilityHidden(true)
                if commerce.premium {
                    LocalizedText("Included with your membership")
                        .font(.capture(.footnote)).foregroundStyle(SwevoStyle.paperSecondary)
                } else {
                    AllowanceResetText(tint: SwevoStyle.paperSecondary)
                }
            } else {
                LocalizedText(quota.error ?? "Loading daily limits…")
                    .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .foregroundStyle(SwevoStyle.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SwevoStyle.paper, in: RoundedRectangle(cornerRadius: 20))
    }

    private var allowanceTitle: some View {
        LocalizedText("Today’s video allowance").font(.capture(.title3, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }

    private var moreAllowance: some View {
        Button { paywall = true } label: {
            HStack(spacing: 6) {
                LocalizedText("Get more").font(.capture(.footnote, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Glyph(symbol: .back, size: 11, tint: SwevoStyle.paperSecondary).rotationEffect(.degrees(180))
            }.frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(SwevoStyle.paperSecondary)
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).disabled(unavailable)
            .accessibilityLabel("Get more daily views and downloads")
    }

    private func balance(_ kind: AllowanceKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if commerce.premium || quota.isUnlimited(kind) {
                LocalizedText("Unlimited").font(.capture(.title3, weight: .semibold))
            } else {
                Text(quota.remaining(kind), format: .number)
                    .font(.capture(.largeTitle, weight: .semibold)).monospacedDigit()
            }
            HStack(spacing: 6) {
                Glyph(symbol: kind == .watch ? .play : .download, size: 14, tint: SwevoStyle.paperSecondary)
                LocalizedText(kind == .watch ? "Views left" : "Downloads left")
                    .font(.capture(.footnote)).foregroundStyle(SwevoStyle.paperSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
