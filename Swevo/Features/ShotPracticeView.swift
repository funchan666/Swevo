import SwiftUI

@MainActor
struct ShotPracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @StateObject private var journal = ShotPracticeJournal()
    @State private var title = ""
    @State private var note = ""
    @State private var movement: ShotMovement
    @State private var seconds: Int
    @State private var lockedFocus: Bool
    @State private var history = false
    @State private var selectedSession: ShotPracticeSession?
    @State private var showingRemoval = false
    @State private var sharedExport: SharedFile?
    private var emptyHistory: Bool {
        history && journal.available && journal.completedSessions.isEmpty
    }

    init(initialMovement: ShotMovement = .pushIn, initialSeconds: Int = 6, initialFocusLock: Bool = false) {
        _movement = State(initialValue: initialMovement)
        _seconds = State(initialValue: initialSeconds)
        _lockedFocus = State(initialValue: initialFocusLock)
    }

    var body: some View {
        let practiceDepth: CGFloat = journal.activeSession == nil ? 116 : 84
        ScenePage(artwork: emptyHistory ? "EmptySessions" : "SceneJournal",
                  depth: emptyHistory ? 128 : practiceDepth, openingGap: 0, artworkOpacity: 0.45) { _ in
            SceneTitle(emptyHistory ? "No finished sessions" : "Shot log", size: 34).padding(.trailing, 50)
        } content: { _ in
            VStack(alignment: .leading, spacing: 18) {
                ChoiceStrip(values: ["Practice", "Sessions"], selected: history ? "Sessions" : "Practice") {
                    history = $0 == "Sessions"
                }
                if let message = journal.storageMessage { ErrorNote(message: message) }
                if history { sessions }
                else if let session = journal.activeSession { practice(session) }
                else { start }
            }
        }
            .scrollDismissesKeyboard(.interactively)
            .sceneDismiss { dismiss() }
            .sheet(item: $selectedSession) { session in sessionDetail(session) }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 16) {
            EmptyStateCopy(message: "Pick a camera move and log the result after each take.")
            TextField("Shot name (optional)", text: $title).submitLabel(.done).swevoField()
            EmptyStateAction(title: "Start session", symbol: .edit) {
                if journal.beginSession(title: title) { title = "" }
            }.disabled(!journal.available)
        }
    }

    private func practice(_ session: ShotPracticeSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sessionTitle(session).font(.capture(.title3, display: true))
            LocalizedText("Set the move and duration before filming. Review the take, then log the result.")
                .font(.capture(.subheadline))
                .foregroundStyle(SwevoStyle.secondary)
            LocalizedText("Camera move").font(.capture(.headline))
            ChoiceStrip(values: ShotMovement.allCases.map(\.label), selected: movement.label) { label in
                if let selection = ShotMovement.allCases.first(where: { $0.label == label }) { movement = selection }
            }
            LocalizedText("Target duration").font(.capture(.headline))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { amountControls }
                VStack(alignment: .leading, spacing: 8) { amountControls }
            }
            Button { lockedFocus.toggle() } label: {
                LocalizedText(lockedFocus ? "Focus locked" : "Autofocus")
            }.buttonStyle(CompactActionStyle())
                .accessibilityAddTraits(lockedFocus ? .isSelected : [])
            TextField("Take note (optional)", text: $note, axis: .vertical)
                .lineLimit(2...5).swevoField()
            LocalizedText("Take result").font(.capture(.headline))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 10)], spacing: 10) {
                ForEach(ShotResult.allCases) { result in
                    ActionButton(title: result.label, primary: result.countsAsSuccess) {
                        if journal.record(result, movement: movement, seconds: seconds, lockedFocus: lockedFocus, note: note) {
                            note = ""
                        }
                    }
                }
            }
            countSummary(session)
            if let last = session.takes.last { takeRow(last) }
            Button { journal.undoLastTake() } label: { LocalizedText("Undo last take") }
                .buttonStyle(CompactActionStyle()).disabled(session.takes.isEmpty)
            ActionButton(title: "Finish session", primary: false) {
                if journal.finishSession() {
                    note = ""
                    history = true
                }
            }.disabled(session.takes.isEmpty)
        }
    }

    @ViewBuilder private var amountControls: some View {
        Button { seconds -= 1 } label: { LocalizedText("Shorter") }
            .buttonStyle(CompactActionStyle()).disabled(seconds <= ShotPracticeJournal.amountRange.lowerBound)
        Text(verbatim: "\(seconds) s").font(.capture(.headline)).monospacedDigit()
            .frame(minWidth: 54).accessibilityAddTraits(.updatesFrequently)
        Button { seconds += 1 } label: { LocalizedText("Longer") }
            .buttonStyle(CompactActionStyle()).disabled(seconds >= ShotPracticeJournal.amountRange.upperBound)
    }

    @ViewBuilder private var sessions: some View {
        if emptyHistory {
            VStack(alignment: .leading, spacing: 14) {
                EmptyStateCopy(message: "Finish a practice session to review its takes here.")
                EmptyStateAction(title: "Back to practice", symbol: .edit) { history = false }
            }
        }
        ForEach(journal.completedSessions) { session in
            Button { selectedSession = session } label: {
                VStack(alignment: .leading, spacing: 8) {
                    sessionTitle(session).font(.capture(.headline))
                    Text(session.startedAt, format: .dateTime.month().day().hour().minute().locale(locale))
                        .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
                    countSummary(session)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background { CaptureSurface(tone: .plum) }
                    .contentShape(Rectangle())
            }.buttonStyle(PressStyle())
        }
    }

    private func sessionDetail(_ session: ShotPracticeSession) -> some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Session results") { selectedSession = nil }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sessionTitle(session).font(.capture(.title2, display: true))
                    countSummary(session)
                    ForEach(session.takes) { take in takeRow(take) }
                    if let message = journal.storageMessage { ErrorNote(message: message) }
                    ActionButton(title: "Export session CSV", primary: false) {
                        if let url = journal.exportSession(session) { sharedExport = SharedFile(url: url) }
                    }
                    Button { showingRemoval = true } label: { LocalizedText("Delete session") }
                        .buttonStyle(CompactActionStyle())
                }.swevoPage()
            }
        }.swevoScreenBackground()
            .sheet(item: $sharedExport) { ShareSheet(items: [$0.url]) }
            .fullScreenCover(isPresented: $showingRemoval) {
                AccountDecisionDialog(title: "Delete session?", message: "This removes the session and its take notes.",
                    confirmTitle: "Delete session", destructive: true, cancel: { showingRemoval = false }) {
                        showingRemoval = false
                        if journal.removeSession(session.id) { selectedSession = nil }
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
        let seconds = take.seconds
        return VStack(alignment: .leading, spacing: 6) {
            LocalizedText(take.movement.label).font(.capture(.headline))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(seconds) s").monospacedDigit()
                LocalizedText(take.result.label)
            }.font(.capture(.subheadline)).foregroundStyle(SwevoStyle.accent)
            LocalizedText(take.lockedFocus ? "Focus locked" : "Autofocus")
                .font(.capture(.caption)).foregroundStyle(SwevoStyle.secondary)
            if !take.note.isEmpty { Text(verbatim: take.note).font(.capture(.subheadline)) }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background { CaptureSurface(tone: .plum) }
    }
}
