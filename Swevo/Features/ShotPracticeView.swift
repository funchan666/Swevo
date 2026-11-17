import SwiftUI

@MainActor
struct ShotPracticeView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var journal = ShotPracticeJournal()
    @State private var title = ""
    @State private var note = ""
    @FocusState private var noteFocused: Bool
    @State private var movement: ShotMovement
    @State private var seconds: Int
    @State private var lockedFocus: Bool
    @State private var history: Bool
    @State private var historyMovement: ShotMovement?
    @State private var pendingImportOnly = false
    @State private var destination: SessionDestination?
    @State private var preparingReviewVideo = false
    @State private var showingRemoval = false
    @State private var sharedExport: SharedFile?
    private let showsBackButton: Bool

    private enum SessionDestination: Identifiable {
        case details(ShotPracticeSession)
        case importVideo(ShotPracticeSession)
        case review(ShotReviewTarget)

        var id: String {
            switch self {
            case .details(let session): "details-\(session.id)"
            case .importVideo(let session): "import-\(session.id)"
            case .review(let target): "review-\(target.id)"
            }
        }
    }

    private var emptyHistory: Bool {
        history && journal.available && journal.completedSessions.isEmpty
    }
    private var canFinish: Bool { !history && journal.activeSession?.takes.isEmpty == false }

    init(initialMovement: ShotMovement = .pushIn, initialSeconds: Int = 6, initialFocusLock: Bool = false,
         startInHistory: Bool = false, showsBackButton: Bool = false) {
        _movement = State(initialValue: initialMovement)
        _seconds = State(initialValue: min(max(initialSeconds, ShotPracticeJournal.amountRange.lowerBound),
                                          ShotPracticeJournal.amountRange.upperBound))
        _lockedFocus = State(initialValue: initialFocusLock)
        _history = State(initialValue: startInHistory)
        self.showsBackButton = showsBackButton
    }

    var body: some View {
        let artwork = history ? "SceneJournal" : "SceneShot"
        GeometryReader { viewport in
            let docked = canPinFinish(in: viewport)
            ScenePage(artwork: emptyHistory ? nil : artwork, depth: emptyHistory ? 44 : (history ? 144 : 246),
                      openingGap: 0, artworkOpacity: 0.97) { _ in
                if !emptyHistory {
                    SceneTitle(history ? "Sessions" : movement.label, size: 42)
                        .foregroundStyle(SwevoStyle.paper)
                        .padding(.top, 48)
                }
            } content: { container in
                let bounds = CGRect(origin: .zero, size: container.size)
                let wide = typeSize <= .xLarge && SwevoStyle.pageContentWidth(in: container) >= 590
                    && !SwevoStyle.intersectsReservedRegion(bounds, in: container)
                VStack(alignment: .leading, spacing: 22) {
                    sectionPicker(stacked: typeSize > .xLarge || SwevoStyle.pageContentWidth(in: container) < 280)
                    if let message = journal.storageMessage { ErrorNote(message: message) }
                    if history {
                        sessions(in: container)
                    } else {
                        practice(wide: wide)
                        if canFinish && !docked { finishButton }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if canFinish && docked && !noteFocused {
                    finishDock
                }
            }
        }
        .sceneDismiss(symbol: showsBackButton ? .back : .close, label: showsBackButton ? "Back" : "Close",
                      edge: showsBackButton ? .leading : .trailing) { dismiss() }
        .sheet(item: $destination) { destination in
            switch destination {
            case .details(let session): sessionDetail(session)
            case .importVideo(let session): ShotPracticeImport(journal: journal, session: session)
            case .review(let target): target.editor(journal: journal)
            }
        }
    }

    private func canPinFinish(in viewport: GeometryProxy) -> Bool {
        let width = SwevoStyle.pageContentWidth(in: viewport)
        guard typeSize <= .xLarge, width >= 300, viewport.size.height >= 400 else { return false }
        let dockWidth = min(width, 680)
        let dockArea = CGRect(x: (viewport.size.width - dockWidth) / 2, y: viewport.size.height - 96,
                              width: dockWidth, height: 96)
        return !SwevoStyle.intersectsReservedRegion(dockArea, in: viewport)
    }

    private func sectionPicker(stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            sectionButton("Practice", showsHistory: false)
            sectionButton("Sessions", showsHistory: true)
        }
        .padding(4)
        .swevoGlass(cornerRadius: 14)
    }

    private func sectionButton(_ label: String, showsHistory: Bool) -> some View {
        let selected = history == showsHistory
        return Button {
            noteFocused = false
            history = showsHistory
        } label: {
            LocalizedText(label).font(.capture(.subheadline, weight: .semibold))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? SwevoStyle.ink : SwevoStyle.paper)
                .background(selected ? SwevoStyle.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func practice(wide: Bool) -> some View {
        let session = journal.activeSession
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 22))
        return VStack(alignment: .leading, spacing: 22) {
            if let session, let title = session.title.nilIfBlank {
                Text(verbatim: title).font(.capture(.title2, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            layout {
                setup(starting: session == nil)
                if let session { takeLog(session) }
            }
        }
    }

    private var finishButton: some View {
        ActionButton(title: "Finish and review") {
            guard let finished = journal.finishSession() else { return }
            note = ""
            history = true
            destination = .details(finished)
        }
        .accessibilityIdentifier("practice.finishAndReview")
    }

    private var finishDock: some View {
        finishButton
            .padding(6)
            .swevoGlass(cornerRadius: 16)
            .pageHorizontalMargins()
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(SwevoStyle.background)
    }

    private func setup(starting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeading(1, title: "Set up the shot")
            ChoiceStrip(values: ShotMovement.allCases.map(\.label), selected: movement.label) { label in
                if let selection = ShotMovement.allCases.first(where: { $0.label == label }) { movement = selection }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 10) {
                    durationSetting.fixedSize(horizontal: true, vertical: false)
                    focusSetting.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 8) {
                    durationSetting
                    focusSetting
                }
            }
            if starting {
                TextField("Shot name (optional)", text: $title,
                          prompt: Text("Shot name (optional)").foregroundStyle(SwevoStyle.secondary))
                    .submitLabel(.done).swevoField()
                ActionButton(title: "Start session") {
                    if journal.beginSession(title: title) { title = "" }
                }.disabled(!journal.available)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func takeLog(_ session: ShotPracticeSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeading(2, title: "Film and log a take")
            LocalizedText("Film with your camera app, then log what you noticed.")
                .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Take note (optional)", text: $note,
                      prompt: Text("Take note (optional)").foregroundStyle(SwevoStyle.secondary), axis: .vertical)
                .lineLimit(2...5).swevoField().focused($noteFocused)
            VStack(spacing: 0) {
                ForEach(ShotResult.allCases) { result in
                    Button {
                        if journal.record(result, movement: movement, seconds: seconds, lockedFocus: lockedFocus, note: note) {
                            note = ""
                            noteFocused = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            LocalizedText(result.label).font(.capture(.subheadline, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if result.countsAsSuccess {
                                Glyph(symbol: .bookmark, size: 17, tint: SwevoStyle.accent)
                            }
                        }.padding(.horizontal, 12).padding(.vertical, 6)
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(PressStyle())
                    if result != .lostFocus { Divider().overlay(SwevoStyle.line).accessibilityHidden(true) }
                }
            }.swevoGlass(cornerRadius: 15)
            if let last = session.takes.last {
                countSummary(session)
                takeRow(last)
                Button { journal.undoLastTake() } label: { LocalizedText("Undo last take") }
                    .buttonStyle(PressStyle()).foregroundStyle(SwevoStyle.accent)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepHeading(_ number: Int, title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(number, format: .number).monospacedDigit()
                .font(.capture(.headline)).foregroundStyle(SwevoStyle.accent)
            LocalizedText(title).font(.capture(.title3, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var durationSetting: some View {
        VStack(alignment: .leading, spacing: 4) {
            LocalizedText("Target duration").font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                durationButton("−", label: "Shorter", delta: -1)
                Text(verbatim: "\(seconds) s").font(.capture(.headline)).monospacedDigit()
                    .padding(.horizontal, 4)
                durationButton("+", label: "Longer", delta: 1)
            }
            .environment(\.layoutDirection, .leftToRight)
            .swevoGlass(cornerRadius: 12)
        }
    }

    private func durationButton(_ sign: String, label: String, delta: Int) -> some View {
        Button { seconds += delta } label: {
            Text(verbatim: sign).font(.capture(.title3, weight: .semibold))
                .foregroundStyle(SwevoStyle.accent)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .disabled(!ShotPracticeJournal.amountRange.contains(seconds + delta))
            .accessibilityLabel(LocalizedStringKey(label))
    }

    private var focusSetting: some View {
        Button { lockedFocus.toggle() } label: {
            LocalizedText(lockedFocus ? "Focus locked" : "Autofocus")
                .font(.capture(.footnote, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(lockedFocus ? SwevoStyle.accent : SwevoStyle.paper)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(minHeight: 44)
                .swevoGlass(cornerRadius: 12).contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityAddTraits(lockedFocus ? .isSelected : [])
    }

    @ViewBuilder private func sessions(in container: GeometryProxy) -> some View {
        if emptyHistory {
            VStack(alignment: .leading, spacing: 14) {
                EmptyStateScene(artwork: "EmptySessions", title: "No finished sessions",
                                message: "Finish a practice session to review its takes here.", container: container)
                EmptyStateAction(title: "Back to practice", symbol: .edit, primary: true) { history = false }
            }
        } else if !journal.completedSessions.isEmpty {
            let bounds = CGRect(origin: .zero, size: container.size)
            let stacked = typeSize > .xLarge || SwevoStyle.pageContentWidth(in: container) < 320
                || SwevoStyle.intersectsReservedRegion(bounds, in: container)
            let matches = journal.completedSessions.filter { session in
                if pendingImportOnly, session.reviewMovieID != nil { return false }
                guard let historyMovement else { return true }
                return session.takes.contains { $0.movement == historyMovement }
            }
            VStack(alignment: .leading, spacing: 16) {
                sessionFilters
                if matches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        LocalizedText(pendingImportOnly && historyMovement == nil
                                      ? "No sessions awaiting video" : "No matching sessions")
                            .font(.capture(.headline))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        EmptyStateAction(title: "Clear filters", symbol: .close) {
                            historyMovement = nil
                            pendingImportOnly = false
                        }
                    }
                    .padding(.vertical, 10)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(matches) { session in
                            sessionRow(session, stacked: stacked)
                        }
                    }
                }
            }
        }
    }

    private var sessionFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { pendingImportOnly.toggle() } label: {
                HStack(spacing: 8) {
                    Glyph(symbol: .folder, size: 16, tint: SwevoStyle.accent)
                    LocalizedText("Pending import").font(.capture(.subheadline, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if pendingImportOnly {
                        Glyph(symbol: .close, size: 12, tint: SwevoStyle.accent)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(minHeight: 44)
                .foregroundStyle(pendingImportOnly ? SwevoStyle.accent : SwevoStyle.paper)
                .background(pendingImportOnly ? SwevoStyle.accent.opacity(0.14) : SwevoStyle.surface,
                            in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityAddTraits(pendingImportOnly ? .isSelected : [])
            .accessibilityIdentifier("practice.sessions.pendingImport")

            ScrollViewReader { scroll in
                ChoiceStrip(values: ["All movements"] + ShotMovement.allCases.map(\.label),
                            selected: historyMovement?.label ?? "All movements") { label in
                    historyMovement = ShotMovement.allCases.first { $0.label == label }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(LocalizedStringKey("Movement"))
                .accessibilityIdentifier("practice.sessions.movementFilter")
                .onChange(of: historyMovement) { _, selection in
                    if selection == nil { scroll.scrollTo("All movements", anchor: .leading) }
                }
            }
        }
    }

    private func sessionRow(_ session: ShotPracticeSession, stacked: Bool) -> some View {
        let movie = library.reviewMovie(attachedTo: session.reviewMovieID)
        let marks = (movie?.rangeMarks ?? []).filter { $0.timeRange != nil }
        let language = AppLanguage.from(locale)
        let title = session.title.nilIfBlank
        var seen = Set<ShotMovement>()
        let movements = session.takes.compactMap { take in
            seen.insert(take.movement).inserted ? L10n.text(take.movement.label, language: language) : nil
        }.joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 12) {
            Button { destination = .details(session) } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: title ?? movements.nilIfBlank ?? L10n.text("Untitled shot", language: language))
                            .font(.capture(.headline)).foregroundStyle(SwevoStyle.paper)
                            .fixedSize(horizontal: false, vertical: true)
                        if title != nil, !movements.isEmpty {
                            Text(verbatim: movements).font(.capture(.subheadline, weight: .semibold))
                                .foregroundStyle(SwevoStyle.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(session.startedAt, format: .dateTime.year().month().day().hour().minute().locale(locale))
                            .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                        countSummary(session)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Glyph(symbol: .back, size: 13, tint: SwevoStyle.secondary).rotationEffect(.degrees(180))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHint(LocalizedStringKey("Session results"))

            if let movie {
                sessionVideo(session, movie: movie, mark: marks.first, stacked: stacked)
                if !marks.isEmpty {
                    LocalizedText("Saved ranges").font(.capture(.footnote, weight: .semibold))
                        .foregroundStyle(SwevoStyle.secondary)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 2) {
                        ForEach(marks) { mark in
                            sessionRange(session, movie: movie, mark: mark, stacked: stacked)
                        }
                    }
                }
            } else {
                if session.reviewMovieID != nil {
                    LocalizedText("Video unavailable").font(.capture(.footnote))
                        .foregroundStyle(SwevoStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                EmptyStateAction(title: "Import video", symbol: .folder, primary: true) {
                    destination = .importVideo(session)
                }
                .accessibilityIdentifier("practice.session.import.\(session.id.uuidString)")
            }

            Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
        }
    }

    private func sessionVideo(_ session: ShotPracticeSession, movie: PracticeRecording, mark: VideoRangeMark?,
                              stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                             : AnyLayout(HStackLayout(spacing: 12))
        return Button {
            destination = .review(ShotReviewTarget(sessionID: session.id, movie: movie, mark: mark))
        } label: {
            layout {
                VideoFileThumbnail(url: library.url(for: movie), maximumSize: 480)
                    .aspectRatio(16.0 / 9, contentMode: .fit)
                    .frame(maxWidth: stacked ? 240 : 118)
                    .clipShape(.rect(cornerRadius: 9))
                    .overlay(alignment: .bottomTrailing) {
                        Glyph(symbol: .play, size: 13, tint: SwevoStyle.paper)
                            .frame(width: 30, height: 30)
                            .background(SwevoStyle.ink.opacity(0.88), in: RoundedRectangle(cornerRadius: 7))
                            .padding(5)
                            .allowsHitTesting(false)
                    }
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: movie.displayFilename).font(.capture(.subheadline, weight: .semibold))
                        .foregroundStyle(SwevoStyle.paper)
                        .fixedSize(horizontal: false, vertical: true)
                    LocalizedText(mark == nil ? "Mark a range" : "Continue review")
                        .font(.capture(.footnote, weight: .semibold)).foregroundStyle(SwevoStyle.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(SwevoStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("practice.session.review.\(session.id.uuidString)")
    }

    private func sessionRange(_ session: ShotPracticeSession, movie: PracticeRecording, mark: VideoRangeMark,
                              stacked: Bool) -> some View {
        let name = mark.name.nilIfBlank ?? L10n.text("Unnamed range", language: AppLanguage.from(locale))
        let start = durationLabel(mark.start, fractional: true)
        let end = durationLabel(mark.end, fractional: true)
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
        return Button {
            destination = .review(ShotReviewTarget(sessionID: session.id, movie: movie, mark: mark))
        } label: {
            HStack(spacing: 9) {
                Glyph(symbol: .play, size: 14, tint: SwevoStyle.accent)
                    .frame(width: 24)
                layout {
                    Text(verbatim: name).font(.capture(.subheadline, weight: .semibold))
                        .foregroundStyle(SwevoStyle.paper)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: "\(start) – \(end)").font(.capture(.footnote)).monospacedDigit()
                        .foregroundStyle(SwevoStyle.secondary)
                        .environment(\.layoutDirection, .leftToRight)
                        .fixedSize(horizontal: !stacked, vertical: true)
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityHint(LocalizedStringKey("Loop range"))
        .accessibilityIdentifier("practice.session.loop.\(session.id.uuidString).\(mark.id.uuidString)")
    }

    private func sessionDetail(_ session: ShotPracticeSession) -> some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Review your footage") { destination = nil }
                .disabled(preparingReviewVideo)
            ScenePage { container in
                let bounds = CGRect(origin: .zero, size: container.size)
                let stacked = typeSize > .xLarge || SwevoStyle.pageContentWidth(in: container) < 310
                    || SwevoStyle.intersectsReservedRegion(bounds, in: container)
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        sessionTitle(session).font(.capture(.title2, display: true))
                            .fixedSize(horizontal: false, vertical: true)
                        countSummary(session)
                    }
                    ShotPracticeReview(journal: journal, sessionID: session.id, busy: $preparingReviewVideo, stacked: stacked)
                    if let message = journal.storageMessage { ErrorNote(message: message) }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(session.takes) { take in takeRow(take) }
                    }
                    ActionButton(title: "Export session CSV", primary: false) {
                        if let url = journal.exportSession(session) { sharedExport = SharedFile(url: url) }
                    }.disabled(preparingReviewVideo)
                    Button { showingRemoval = true } label: { LocalizedText("Delete session") }
                        .buttonStyle(CompactActionStyle()).disabled(preparingReviewVideo)
                }
            }
        }.swevoScreenBackground()
            .interactiveDismissDisabled(preparingReviewVideo)
            .sheet(item: $sharedExport) { ShareSheet(items: [$0.url]) }
            .fullScreenCover(isPresented: $showingRemoval) {
                AccountDecisionDialog(title: "Delete session?", message: "This removes the session and its take notes.",
                    confirmTitle: "Delete session", destructive: true, cancel: { showingRemoval = false }) {
                        showingRemoval = false
                        if journal.removeSession(session.id) { destination = nil }
                    }.presentationBackground(.clear)
            }
    }

    @ViewBuilder private func sessionTitle(_ session: ShotPracticeSession) -> some View {
        if let title = session.title.nilIfBlank { Text(verbatim: title) }
        else { LocalizedText("Untitled shot") }
    }

    private func countSummary(_ session: ShotPracticeSession) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(session.successfulTakes) / \(session.takes.count)").font(.capture(.headline)).monospacedDigit()
            LocalizedText("Kept takes").font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
        }.accessibilityElement(children: .combine)
    }

    private func takeRow(_ take: ShotTake) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(verbatim: "\(take.seconds) s")
                    .font(.capture(.headline)).monospacedDigit()
                    .foregroundStyle(SwevoStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    LocalizedText(take.movement.label).font(.capture(.headline))
                    LocalizedText(take.result.label).font(.capture(.subheadline))
                    LocalizedText(take.lockedFocus ? "Focus locked" : "Autofocus")
                        .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                }.fixedSize(horizontal: false, vertical: true)
            }
            if !take.note.isEmpty {
                Text(verbatim: take.note).font(.capture(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(SwevoStyle.line).accessibilityHidden(true)
        }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private struct ShotPracticeImport: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var journal: ShotPracticeJournal
    let session: ShotPracticeSession
    @State private var importing = false
    @State private var movieToAttach: PracticeRecording?
    @State private var review: ShotReviewTarget?
    @State private var detent = PresentationDetent.medium

    var body: some View {
        Group {
            if let review {
                review.editor(journal: journal)
            } else {
                VStack(spacing: 0) {
                    SheetHeading(title: "Import video") { dismiss() }
                        .disabled(importing)
                    ScenePage { container in
                        let bounds = CGRect(origin: .zero, size: container.size)
                        let stacked = SwevoStyle.pageContentWidth(in: container) < 310
                            || SwevoStyle.intersectsReservedRegion(bounds, in: container)
                        VStack(alignment: .leading, spacing: 12) {
                            if let title = session.title.nilIfBlank {
                                Text(verbatim: title).font(.capture(.subheadline))
                                    .foregroundStyle(SwevoStyle.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let movieToAttach {
                                ErrorNote(message: journal.storageMessage ?? "This change could not be saved. Please try again.")
                                ActionButton(title: "Retry") { attach(movieToAttach) }
                            } else {
                                VideoImportActions(onImported: attach, importing: $importing,
                                                   presentation: .library(stacked: stacked, photosFirst: true))
                            }
                        }
                    }
                }
                .swevoScreenBackground()
                .interactiveDismissDisabled(importing)
            }
        }
        .presentationDetents(review == nil ? [.medium, .large] : [.large], selection: $detent)
    }

    private func attach(_ movie: PracticeRecording) {
        guard journal.attachReviewVideo(movie.id, to: session.id) else {
            movieToAttach = movie
            return
        }
        detent = .large
        review = ShotReviewTarget(sessionID: session.id, movie: movie)
    }
}

private struct ShotReviewTarget: Identifiable {
    let id = UUID()
    let sessionID: UUID
    let movie: PracticeRecording
    var mark: VideoRangeMark? = nil

    @MainActor
    func editor(journal: ShotPracticeJournal) -> EditorSheet {
        EditorSheet(initialMovie: movie, initialTool: .ranges, initialLoop: mark, onVideoOpened: { opened in
            journal.attachReviewVideo(opened.id, to: sessionID)
        })
    }
}

private extension LibraryStore {
    func reviewMovie(attachedTo movieID: UUID?) -> PracticeRecording? {
        guard let movieID,
              let movie = movies.first(where: { $0.id == movieID && !$0.isExport && !$0.isAudio }),
              FileManager.default.isReadableFile(atPath: url(for: movie).path)
        else { return nil }
        return movie
    }
}

@MainActor
private struct ShotPracticeReview: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.layoutDirection) private var direction
    @ObservedObject var journal: ShotPracticeJournal
    let sessionID: UUID
    @Binding var busy: Bool
    let stacked: Bool
    @State private var target: ShotReviewTarget?
    @State private var showsImports = false

    private var reviewMovieID: UUID? {
        journal.completedSessions.first(where: { $0.id == sessionID })?.reviewMovieID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let reviewMovie = library.reviewMovie(attachedTo: reviewMovieID) {
                let url = library.url(for: reviewMovie)
                let marks = (reviewMovie.rangeMarks ?? []).filter { $0.timeRange != nil }
                let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                     : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    VideoFileThumbnail(url: url)
                        .frame(width: 84, height: 56)
                        .clipShape(.rect(cornerRadius: 8))
                    Text(verbatim: reviewMovie.displayFilename).font(.capture(.headline))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                EmptyStateAction(title: "Mark a range", symbol: .bookmark, primary: marks.isEmpty) {
                    target = ShotReviewTarget(sessionID: sessionID, movie: reviewMovie)
                }.disabled(busy).accessibilityIdentifier("practice.review.openVideo")
                if !marks.isEmpty {
                    RangeShareActions(context: .practice(source: url, marks: marks, stacked: stacked, loop: { mark in
                        target = ShotReviewTarget(sessionID: sessionID, movie: reviewMovie, mark: mark)
                    }), busy: $busy)
                }
            } else {
                if reviewMovieID != nil {
                    ErrorNote(message: "Video unavailable")
                }
                LocalizedText("Import a video to mark a range, loop it, and compare frames.")
                    .font(.capture(.subheadline)).foregroundStyle(SwevoStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VideoImportActions(onImported: { movie in
                    journal.attachReviewVideo(movie.id, to: sessionID)
                    target = ShotReviewTarget(sessionID: sessionID, movie: movie)
                }, importing: $busy, presentation: .library(stacked: stacked, photosFirst: true))
                recentImports
            }
        }
        .sheet(item: $target) { target in target.editor(journal: journal) }
    }

    @ViewBuilder private var recentImports: some View {
        let movies = library.importedMovies.filter { !$0.isAudio }
        let expandedAngle: Double = direction == .rightToLeft ? 90 : 270
        if !movies.isEmpty {
            Button { showsImports.toggle() } label: {
                HStack(spacing: 10) {
                    Glyph(symbol: .folder, size: 16, tint: SwevoStyle.accent)
                    LocalizedText("Recent imports").font(.capture(.subheadline, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Glyph(symbol: .back, size: 12, tint: SwevoStyle.accent)
                        .rotationEffect(.degrees(showsImports ? expandedAngle : 180))
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityAddTraits(showsImports ? .isSelected : [])
            .accessibilityIdentifier("practice.review.recentImports")
            .disabled(busy)

            if showsImports {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(movies) { movie in
                        VideoFileButton(url: library.url(for: movie), filename: movie.displayFilename, date: movie.date) {
                            target = ShotReviewTarget(sessionID: sessionID, movie: movie)
                        }
                    }
                }.disabled(busy)
            }
        }
    }
}
