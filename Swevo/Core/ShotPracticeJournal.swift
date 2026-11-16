import Foundation
import Combine

enum ShotMovement: String, Codable, CaseIterable, Identifiable {
    case pushIn, track, reveal, parallax, orbit, tilt
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pushIn: "Push in"
        case .track: "Follow"
        case .reveal: "Reveal"
        case .parallax: "Parallax"
        case .orbit: "Orbit"
        case .tilt: "Tilt"
        }
    }
}

enum ShotResult: String, Codable, CaseIterable, Identifiable {
    case usable, shaky, tilted, lostFocus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .usable: "Keep this take"
        case .shaky: "Camera shake"
        case .tilted: "Horizon drift"
        case .lostFocus: "Lost focus"
        }
    }
    var countsAsSuccess: Bool { self == .usable }
}

struct ShotTake: Codable, Identifiable {
    let id: UUID
    let recordedAt: Date
    let movement: ShotMovement
    let seconds: Int
    let lockedFocus: Bool
    let result: ShotResult
    let note: String
}

struct ShotPracticeSession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    let title: String
    var finishedAt: Date?
    var takes: [ShotTake]
    var reviewMovieID: UUID? = nil
    var successfulTakes: Int { takes.filter { $0.result.countsAsSuccess }.count }
}

private struct ShotJournalArchive: Codable {
    var activeSession: ShotPracticeSession?
    var completedSessions: [ShotPracticeSession] = []
}

@MainActor
final class ShotPracticeJournal: ObservableObject {
    static let amountRange = 2...30
    @Published private var archive = ShotJournalArchive()
    @Published private(set) var storageMessage: String?
    private let archiveURL: URL
    private(set) var available = true
    var activeSession: ShotPracticeSession? { archive.activeSession }
    var completedSessions: [ShotPracticeSession] { archive.completedSessions }

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShotPractice", isDirectory: true)
        archiveURL = folder.appendingPathComponent("sessions.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                archive = try JSONDecoder().decode(ShotJournalArchive.self, from: Data(contentsOf: archiveURL))
            }
        } catch {
            available = false
            storageMessage = "Practice records could not be opened. Existing records are preserved."
        }
    }

    @discardableResult
    func beginSession(title: String) -> Bool {
        guard activeSession == nil else { return false }
        var next = archive
        next.activeSession = ShotPracticeSession(id: UUID(), startedAt: Date(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), takes: [])
        return commit(next)
    }

    @discardableResult
    func record(_ result: ShotResult, movement: ShotMovement, seconds: Int, lockedFocus: Bool, note: String) -> Bool {
        guard var session = activeSession, Self.amountRange.contains(seconds) else { return false }
        session.takes.append(ShotTake(id: UUID(), recordedAt: Date(), movement: movement,
            seconds: seconds, lockedFocus: lockedFocus, result: result,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        var next = archive
        next.activeSession = session
        return commit(next)
    }

    func undoLastTake() {
        guard var session = activeSession, !session.takes.isEmpty else { return }
        session.takes.removeLast()
        var next = archive
        next.activeSession = session
        commit(next)
    }

    func finishSession() -> ShotPracticeSession? {
        guard var session = activeSession, !session.takes.isEmpty else { return nil }
        session.finishedAt = Date()
        var next = archive
        next.completedSessions.insert(session, at: 0)
        next.activeSession = nil
        return commit(next) ? session : nil
    }

    func attachReviewVideo(_ movieID: UUID, to sessionID: UUID) {
        guard let index = archive.completedSessions.firstIndex(where: { $0.id == sessionID }),
              archive.completedSessions[index].reviewMovieID != movieID else { return }
        var next = archive
        next.completedSessions[index].reviewMovieID = movieID
        commit(next)
    }

    @discardableResult
    func removeSession(_ id: UUID) -> Bool {
        var next = archive
        next.completedSessions.removeAll { $0.id == id }
        return commit(next)
    }

    func exportSession(_ session: ShotPracticeSession) -> URL? {
        let dates = ISO8601DateFormatter()
        let title = Self.csvField(session.title)
        let header = "recorded_at_utc,title,movement,target_seconds,locked_focus,result,note"
        let rows = session.takes.map { take in
            [dates.string(from: take.recordedAt), title, take.movement.rawValue, String(take.seconds),
             String(take.lockedFocus), take.result.rawValue, Self.csvField(take.note)].joined(separator: ",")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShotExports", isDirectory: true)
        let url = folder.appendingPathComponent("swevo-session-\(session.id.uuidString).csv")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(([header] + rows).joined(separator: "\r\n").appending("\r\n").utf8)
                .write(to: url, options: .atomic)
            storageMessage = nil
            return url
        } catch {
            storageMessage = "The practice export could not be created. Please try again."
            return nil
        }
    }

    private static func csvField(_ value: String) -> String {
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let text = first.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    @discardableResult
    private func commit(_ next: ShotJournalArchive) -> Bool {
        guard available else { return false }
        do {
            try JSONEncoder().encode(next)
                .write(to: archiveURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            archive = next
            storageMessage = nil
            return true
        } catch {
            storageMessage = "This change could not be saved. Please try again."
            return false
        }
    }
}
