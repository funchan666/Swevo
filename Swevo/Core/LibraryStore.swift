import Foundation
import AVFoundation
import Combine
import CoreTransferable
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LessonLibrarySnapshot()
    @Published var error: String?
    @Published private(set) var downloadsRequest: UUID?
    func openDownloads() { downloadsRequest = UUID() }
    private let root: URL
    private let snapshotURL: URL
    private var readable = true

    init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("SwevoMedia", isDirectory: true)
        snapshotURL = root.appendingPathComponent("library.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: snapshotURL.path) {
                snapshot = try JSONDecoder().decode(LessonLibrarySnapshot.self, from: Data(contentsOf: snapshotURL))
            }
        } catch {
            readable = false
            self.error = "Your local library could not be read. Existing files have been preserved."
        }
    }
    var movies: [PracticeRecording] { snapshot.movies }
    var importedMovies: [PracticeRecording] { movies.filter { !$0.isExport } }
    var favorites: [LessonClip] { snapshot.favorites }
    var history: [LessonLinkVisit] { snapshot.history }
    func url(for movie: PracticeRecording) -> URL { root.appendingPathComponent(movie.filename) }

    func watchedVideos(for owner: String?) -> [WatchedVideo] {
        guard let owner else { return [] }
        return snapshot.watchedVideos?.filter { $0.owner == owner } ?? []
    }

    func recordWatch(_ clip: LessonClip, owner: String) {
        guard !clip.playbackURL.isFileURL else { return }
        var next = snapshot
        var history = next.watchedVideos ?? []
        history.removeAll { $0.owner == owner && $0.id == clip.id }
        history.insert(WatchedVideo(clip: clip, date: Date(), owner: owner), at: 0)
        next.watchedVideos = Array(history.prefix(100))
        save(next)
    }

    func removeWatch(_ visit: WatchedVideo) {
        var next = snapshot
        next.watchedVideos?.removeAll { $0.owner == visit.owner && $0.id == visit.id }
        save(next)
    }

    func markOpened(_ movie: PracticeRecording) {
        guard let index = snapshot.movies.firstIndex(where: { $0.id == movie.id }) else { return }
        var next = snapshot
        next.movies[index].lastOpenedAt = Date()
        save(next)
    }

    @discardableResult
    func addRange(_ range: ClosedRange<Double>, name: String, to movieID: UUID) throws -> VideoRangeMark {
        guard let index = movies.firstIndex(where: { $0.id == movieID && !$0.isAudio }) else { throw SwevoError.storage }
        let title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let mark = VideoRangeMark(id: UUID(), name: title, start: range.lowerBound, end: range.upperBound)
        guard mark.timeRange != nil else { throw SwevoError.service("Choose a start and end for the range.") }
        var next = snapshot
        var ranges = next.movies[index].rangeMarks ?? []
        if let existing = ranges.first(where: { $0.start == mark.start && $0.end == mark.end && $0.name == mark.name }) {
            return existing
        }
        ranges.insert(mark, at: 0)
        next.movies[index].rangeMarks = ranges
        try persist(next)
        return mark
    }

    func removeRange(_ mark: VideoRangeMark, from movieID: UUID) throws {
        guard let index = movies.firstIndex(where: { $0.id == movieID }) else { throw SwevoError.storage }
        var next = snapshot
        next.movies[index].rangeMarks?.removeAll { $0.id == mark.id }
        try persist(next)
    }
    // Internal IDs stay stable; only the user-facing shared copy gets a readable name.
    func shareFile(for movie: PracticeRecording, commerce: CommerceStore) async throws -> URL {
        try commerce.requireMediaExport()
        let exportOwner = commerce.api.session?.userId.value
        let source = url(for: movie)
        let title = movie.title
        let task = Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("SwevoSharedVideos", isDirectory: true)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            // Expired staged copies are disposable; never touch the media library.
            for old in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
                if let created = try? old.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   created < Date().addingTimeInterval(-7 * 86_400) { try? fm.removeItem(at: old) }
            }
            let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
            var name = title.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if ["mp4", "mov", "m4v", "m4a"].contains((name as NSString).pathExtension.lowercased()) {
                name = (name as NSString).deletingPathExtension
            }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            while name.utf8.count > 160 { name.removeLast() }
            if name.isEmpty { name = "Kstep video" }
            let destination = directory.appendingPathComponent(name).appendingPathExtension(source.pathExtension)
            do {
                try Task.checkCancellation()
                try fm.copyItem(at: source, to: destination)
                try Task.checkCancellation()
                return destination
            } catch { try? fm.removeItem(at: directory); throw error }
        }
        let destination = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        do {
            try Task.checkCancellation()
            try commerce.requireMediaExport()
            guard exportOwner == commerce.api.session?.userId.value else { throw SwevoError.unauthorized }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
            throw error
        }
    }
    func isSaved(_ clip: LessonClip) -> Bool { favorites.contains { $0.id == clip.id } }
    @discardableResult func toggle(_ clip: LessonClip) -> Bool {
        var next = snapshot
        if isSaved(clip) { next.favorites.removeAll { $0.id == clip.id } }
        else { next.favorites.insert(clip, at: 0) }
        do { try persist(next); return true }
        catch { self.error = "Favorites could not be updated. Please try again."; return false }
    }
    func clearHistory() {
        var next = snapshot
        next.history = []
        save(next)
    }
    func removeVisit(_ visit: LessonLinkVisit) {
        var next = snapshot
        next.history.removeAll { $0.id == visit.id }
        save(next)
    }
    func importMovie(_ source: URL, exported: Bool = false, title: String? = nil) async throws -> PracticeRecording {
        guard readable else { throw SwevoError.storage }
        let id = UUID()
        let ext = source.pathExtension.lowercased().nilIfBlank ?? "mov"
        let item = PracticeRecording(id: id, filename: id.uuidString + "." + ext,
                              title: title ?? source.deletingPathExtension().lastPathComponent,
                              date: Date(), isExport: exported)
        let destination = url(for: item)
        try await Task.detached(priority: .userInitiated) {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }.value
        do {
            if !exported {
                _ = try await editableVideoDuration(for: AVURLAsset(url: destination))
            }
            try Task.checkCancellation()
            var next = snapshot
            next.movies.insert(item, at: 0)
            try persist(next)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return item
    }
    func delete(_ movie: PracticeRecording) {
        // Commit index removal first; a failed file deletion leaves an orphan, not a broken library entry.
        var next = snapshot
        next.movies.removeAll { $0.id == movie.id }
        do {
            try persist(next)
            let file = url(for: movie)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        } catch { self.error = error.localizedDescription }
    }
    private func save(_ next: LessonLibrarySnapshot) {
        do { try persist(next) } catch { self.error = error.localizedDescription }
    }
    private func persist(_ next: LessonLibrarySnapshot) throws {
        guard readable else { throw SwevoError.storage }
        let data = try JSONEncoder().encode(next)
        try data.write(to: snapshotURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let saved = try Data(contentsOf: snapshotURL)
        guard saved == data else { throw SwevoError.storage }
        snapshot = next
    }
}

struct ImportedMovie: Transferable {
    let url: URL
    let suggestedTitle: String?
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in SentTransferredFile(movie.url) }
        importing: { received in
            let ext = received.file.pathExtension.nilIfBlank ?? "mov"
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            let name = received.file.deletingPathExtension().lastPathComponent
            return ImportedMovie(url: copy, suggestedTitle: UUID(uuidString: name) == nil ? name.nilIfBlank : nil)
        }
    }
}
