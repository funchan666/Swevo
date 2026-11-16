import SwiftUI
import StoreKit

struct MembershipView: View {
    var rewardKind: AllowanceKind? = nil
    var exportRequired = false
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var pairedMinimumWidth: CGFloat = 316
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
        }
    }
    private var selectedPlan: SKProduct? {
        plans.first(where: { $0.productIdentifier == selectedID }) ?? plans.first
    }
    private var purchasing: Bool { commerce.preparingPurchase || commerce.busy || purchaseTask != nil }
    private var interactionLocked: Bool { purchasing || commerce.loadingPlans || ads.busy || ads.isPresenting }

    var body: some View {
        ScenePage(artwork: "ScenePlusCover", depth: 140, openingGap: 0, artworkOpacity: 0.58) { _ in
            SceneTitle("Swevo Plus", size: 42)
                .padding(.top, 54)
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
        let paired = allowsColumns && width >= pairedMinimumWidth && !wide
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 32))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))

        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                restoreLink
                if purchaseAction == .restore { purchaseFeedback }
            }
            layout {
                benefits(paired: paired)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    if commerce.premium {
                        activeMembership
                        renewalDisclosure
                    } else {
                        checkout(paired: paired)
                    }
                    if purchaseAction == .subscribe { purchaseFeedback }
                    PolicyLinks(compact: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !exportRequired, !commerce.premium, api.session != nil { rewardOption }
        }
    }

    private func benefits(paired: Bool) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .topLeading), count: paired ? 2 : 1)
        return VStack(alignment: .leading, spacing: 12) {
            if exportRequired {
                LocalizedText("Export is included with Plus.")
                    .font(.capture(.subheadline, weight: .semibold)).foregroundStyle(SwevoStyle.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            benefit(.edit, "MP4 video export", "Up to 1080p")
            benefit(.sound, "M4A audio export", "Extract audio from video.")
            Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                benefit(.play, "Unlimited lesson views")
                benefit(.download, "Unlimited offline downloads")
                benefit(.home, "Skip opening ads")
                benefit(.bookmark, "Shot presets")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LocalizedStringKey("Plus benefits"))
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

    private func checkout(paired: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if api.session == nil { ConnectionPanel() }
            if !plans.isEmpty { planPicker(paired: paired) }
            if let error = commerce.plansError {
                ErrorNote(message: error)
                ActionButton(title: "Retry", primary: false) { Task { await commerce.loadPlans() } }
                    .disabled(interactionLocked)
            }
            if selectedPlan != nil { renewalDisclosure }
            if selectedPlan != nil || commerce.loadingPlans || purchasing { subscribeButton }
        }
    }

    private var purchaseButtonTitle: String {
        if commerce.preparingPurchase { return "Preparing purchase…" }
        if commerce.busy { return "Checking purchases…" }
        if commerce.loadingPlans { return "Loading plans…" }
        return "Subscribe"
    }

    private func planPicker(paired: Bool) -> some View {
        let sideBySide = paired && plans.count == 2
        let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 4))
                                : AnyLayout(VStackLayout(spacing: 4))
        return layout {
            ForEach(plans, id: \.productIdentifier) { plan in
                planOption(plan, sideBySide: sideBySide)
            }
        }
        .padding(4)
        .swevoGlass(cornerRadius: 18)
    }

    private func planOption(_ product: SKProduct, sideBySide: Bool) -> some View {
        let selected = selectedPlan?.productIdentifier == product.productIdentifier
        let price = commerce.price(product)
        let period = commerce.period(product, locale: locale)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button { selectedID = product.productIdentifier } label: {
            Group {
                if sideBySide {
                    VStack(alignment: .leading, spacing: 4) {
                        planName(product, selected: selected)
                        planPrice(price, selected: selected)
                        planPeriod(period)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                planName(product, selected: selected)
                                planPeriod(period)
                            }.fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 0)
                            planPrice(price, selected: selected).fixedSize(horizontal: true, vertical: false)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            planName(product, selected: selected)
                            planPrice(price, selected: selected)
                            planPeriod(period)
                        }
                    }
                }
            }.padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .foregroundStyle(SwevoStyle.paper)
                .background(selected ? SwevoStyle.accent.opacity(0.12) : Color.clear, in: shape)
                .overlay { shape.strokeBorder(selected ? SwevoStyle.accent.opacity(0.75) : Color.clear).allowsHitTesting(false) }
                .contentShape(shape)
        }.buttonStyle(PressStyle()).disabled(interactionLocked)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("membership.plan.\(product.productIdentifier)")
    }

    private func planName(_ product: SKProduct, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(selected ? SwevoStyle.accent : SwevoStyle.secondary, lineWidth: selected ? 4 : 1)
                .frame(width: 12, height: 12).accessibilityHidden(true)
            Group {
                if let period = product.subscriptionPeriod, period.numberOfUnits == 1, period.unit == .month {
                    LocalizedText("Monthly")
                } else if let period = product.subscriptionPeriod, period.numberOfUnits == 1, period.unit == .year {
                    LocalizedText("Yearly")
                } else {
                    Text(verbatim: product.localizedTitle)
                }
            }.font(.capture(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
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

    private var renewalDisclosure: some View {
        LocalizedText("Renews automatically. Cancel in your Apple account at least 24 hours before renewal.")
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
                    loadingMark(width: 30, tint: SwevoStyle.ink)
                } else if selectedPlan != nil {
                    Glyph(symbol: .back, size: 16, tint: SwevoStyle.ink).rotationEffect(.degrees(180))
                }
            }.padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 54)
                .foregroundStyle(SwevoStyle.ink)
                .background { CaptureSurface(tone: .accent) }
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
        ScenePage(artwork: nil, depth: 48, openingGap: 0) { _ in
            SceneTitle("Account", size: 38)
        } content: { container in
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
                Group {
                    if api.session != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            accountDetails
                            membershipEntry
                            allowance
                        }
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
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(title: "Account details").accessibilityAddTraits(.isHeader)
                LocalizedText("ID · %@", id).monospacedDigit().textSelection(.enabled)
                    .font(.capture(.footnote)).foregroundStyle(SwevoStyle.secondary)
            }.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var membershipEntry: some View {
        Button { paywall = true } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText(commerce.premium ? "Plus active" : "Free plan")
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
        LocalizedText("Today’s lesson limits").font(.capture(.title3, weight: .semibold))
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
