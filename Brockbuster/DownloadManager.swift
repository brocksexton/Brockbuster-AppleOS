import Foundation
import Combine

/// Represents the lifecycle state of an offline download.
enum DownloadState: String, Codable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

/// A persisted record for a single downloaded item.
struct DownloadRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let itemId: String
    let itemName: String
    let mediaType: String?
    let seriesName: String?
    let seasonNumber: Int?
    let episodeNumber: Int?

    let serverKey: String
    let userId: String?

    var state: DownloadState
    var progress: Double
    var errorDescription: String?

    var bytesWritten: Int64?
    var bytesExpected: Int64?

    var localRelativePath: String?
    var createdAt: Date
    var updatedAt: Date
}

/// Manages offline downloads.
///
/// - iOS/iPadOS: uses a background URLSession so downloads can continue when the app backgrounds.
/// - tvOS: uses a default session (background sessions are restricted), but still provides queuing and progress.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var records: [DownloadRecord] = []

    private var session: URLSession!
    private var taskToRecord: [Int: UUID] = [:]

    private let persistenceURL: URL
    private let downloadsRootURL: URL

    // MARK: - Static Path Helpers

    /// Compute the Brockbuster Application Support root directory.
    ///
    /// URLSession download delegate callbacks may be invoked off the main actor. For
    /// file moves, the file at the temporary `location` provided by the system can be
    /// deleted once the delegate method returns. To avoid races, we compute paths and
    /// move/copy synchronously inside the delegate method using these static helpers.
    nonisolated private static func brockbusterAppSupportRoot() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory

        let root = appSupport.appendingPathComponent("Brockbuster", isDirectory: true)
        if !fm.fileExists(atPath: root.path) {
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    nonisolated private static func brockbusterDownloadsRoot() -> URL {
        let fm = FileManager.default
        let root = brockbusterAppSupportRoot()
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        if !fm.fileExists(atPath: downloads.path) {
            try? fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        }
        return downloads
    }

    override init() {
        let fm = FileManager.default

        // App Support/Brockbuster
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory

        let root = appSupport.appendingPathComponent("Brockbuster", isDirectory: true)
        if !fm.fileExists(atPath: root.path) {
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }

        self.persistenceURL = root.appendingPathComponent("downloads.json")
        self.downloadsRootURL = root.appendingPathComponent("Downloads", isDirectory: true)
        if !fm.fileExists(atPath: downloadsRootURL.path) {
            try? fm.createDirectory(at: downloadsRootURL, withIntermediateDirectories: true)
        }

        super.init()

        loadPersisted()
        configureSession()
        restorePendingTasks()
    }

    // MARK: - Public API

    func record(for itemId: String, serverKey: String, userId: String?) -> DownloadRecord? {
        records.first(where: { $0.itemId == itemId && $0.serverKey == serverKey && $0.userId == userId })
    }

    func isDownloaded(itemId: String, serverKey: String, userId: String?) -> Bool {
        guard let rec = record(for: itemId, serverKey: serverKey, userId: userId) else { return false }
        return rec.state == .completed && rec.localRelativePath != nil
    }

    func localFileURL(for record: DownloadRecord) -> URL? {
        guard let rel = record.localRelativePath else { return nil }
        return downloadsRootURL.appendingPathComponent(rel)
    }

    /// Enqueue a download for a given Jellyfin item.
    func enqueue(item: JellyfinClient.LibraryItem, sessionStore: SessionStore, entryPoint: String = "unknown") {
        guard let serverKey = sessionStore.serverURL.host ?? sessionStore.serverURL.absoluteString as String? else { return }
        let userId = sessionStore.currentUser?.id

        if let existing = record(for: item.id, serverKey: serverKey, userId: userId), existing.state == .completed {
            return
        }

        let now = Date()
        var record = DownloadRecord(
            id: UUID(),
            itemId: item.id,
            itemName: item.name ?? "Untitled",
            mediaType: item.mediaType ?? item.type,
            seriesName: item.seriesName,
            seasonNumber: item.parentIndexNumber,
            episodeNumber: item.indexNumber,
            serverKey: serverKey,
            userId: userId,
            state: .queued,
            progress: 0,
            errorDescription: nil,
            bytesWritten: nil,
            bytesExpected: nil,
            // Pre-compute the final destination relative path up-front.
            // This makes background delegate file moves race-free because the
            // delegate can parse the path from the taskDescription without needing
            // main-actor access to the records.
            localRelativePath: nil,
            createdAt: now,
            updatedAt: now
        )

        // Plan the destination path now.
        let plannedRel = destinationRelativePath(for: record, fileExtension: "mp4")
        record.localRelativePath = plannedRel

        // Upsert and persist first so UI updates immediately.
        upsert(record)

        Task {
            await startDownload(recordId: record.id, itemId: item.id, sessionStore: sessionStore)
        }
    }

    func remove(record: DownloadRecord) {
        // Cancel any in-flight task
        cancel(record: record)

        // Delete file on disk
        if let url = localFileURL(for: record) {
            try? FileManager.default.removeItem(at: url)
        }

        records.removeAll(where: { $0.id == record.id })
        persist()
    }

    func cancel(record: DownloadRecord) {
        // Find URLSession task and cancel.
        let recordId = record.id
        let taskIds = taskToRecord.filter { $0.value == recordId }.map { $0.key }
        guard !taskIds.isEmpty else { return }
        session.getAllTasks { tasks in
            let match = tasks.first(where: { taskIds.contains($0.taskIdentifier) })
            match?.cancel()
        }
        update(recordId: recordId) { rec in
            rec.state = .failed
            rec.errorDescription = "Cancelled"
            rec.updatedAt = Date()
        }
    }

    /// Retry a failed download record.
    ///
    /// This keeps the same record id (and therefore preserves UI bindings)
    /// while re-creating the underlying URLSession download task.
    func retry(record: DownloadRecord, sessionStore: SessionStore) {
        guard record.state == .failed else { return }

        update(recordId: record.id) { rec in
            rec.state = .downloading
            rec.progress = 0
            // Clear any previous error message on retry.
            rec.errorDescription = nil
            rec.updatedAt = Date()
        }

        Task { [weak self] in
            guard let self else { return }
            await self.startDownload(recordId: record.id, itemId: record.itemId, sessionStore: sessionStore)
        }
    }

    // MARK: - Internals

    private func configureSession() {
        #if os(tvOS)
        let config = URLSessionConfiguration.default
        #else
        let config = URLSessionConfiguration.background(withIdentifier: "lol.brockbuster.downloads")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        #endif
        config.waitsForConnectivity = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    private func restorePendingTasks() {
        // Re-associate existing tasks to persisted records when the app relaunches.
        session.getAllTasks { tasks in
            Task { @MainActor in
                for task in tasks {
                    if let downloadTask = task as? URLSessionDownloadTask,
                       let desc = downloadTask.taskDescription {
                        let uuidPart = desc.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true).first
                        guard let uuidPart, let uuid = UUID(uuidString: String(uuidPart)) else { continue }
                        self.taskToRecord[task.taskIdentifier] = uuid
                    }
                }
            }
        }
    }

    private func startDownload(recordId: UUID, itemId: String, sessionStore: SessionStore) async {
        do {
            let url = try await sessionStore.downloadURL(for: itemId)

            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            request.setValue("Brockbuster", forHTTPHeaderField: "User-Agent")

            let task = session.downloadTask(with: request)

            // Encode both the record id and the pre-computed relative destination
            // path so URLSession delegate callbacks can synchronously move the file
            // without hopping to the main actor.
            let rel = records.first(where: { $0.id == recordId })?.localRelativePath
            if let rel {
                task.taskDescription = "\(recordId.uuidString)|\(rel)"
            } else {
                task.taskDescription = recordId.uuidString
            }
            taskToRecord[task.taskIdentifier] = recordId

            update(recordId: recordId) { rec in
                rec.state = .downloading
                rec.updatedAt = Date()
            }
            task.resume()
        } catch {
            update(recordId: recordId) { rec in
                rec.state = .failed
                rec.errorDescription = error.localizedDescription
                rec.updatedAt = Date()
            }
        }
    }

    private func destinationRelativePath(for record: DownloadRecord, fileExtension: String) -> String {
        // Server/User scoping prevents collisions across accounts.
        let safeServer = sanitizePathComponent(record.serverKey)
        let safeUser = sanitizePathComponent(record.userId ?? "anonymous")
        let safeName = sanitizeFilename(record.itemName)
        return "\(safeServer)/\(safeUser)/\(record.itemId)_\(safeName).\(fileExtension)"
    }

    private func ensureParentDirectory(for fileURL: URL) {
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func sanitizeFilename(_ string: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return string.components(separatedBy: illegal).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizePathComponent(_ string: String) -> String {
        sanitizeFilename(string).replacingOccurrences(of: ".", with: "-")
    }

    // MARK: - Persistence

    private func loadPersisted() {
        guard let data = try? Data(contentsOf: persistenceURL) else { return }
        guard let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) else { return }
        self.records = decoded
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: persistenceURL, options: [.atomic])
        } catch {
            // Non-fatal.
        }
    }

    private func upsert(_ record: DownloadRecord) {
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx] = record
        } else {
            records.insert(record, at: 0)
        }
        persist()
    }

    private func update(recordId: UUID, mutate: (inout DownloadRecord) -> Void) {
        guard let idx = records.firstIndex(where: { $0.id == recordId }) else { return }
        var rec = records[idx]
        mutate(&rec)
        records[idx] = rec
        persist()
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let desc = downloadTask.taskDescription else { return }
        let uuidPart = desc.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true).first
        guard let uuidPart, let recordId = UUID(uuidString: String(uuidPart)) else { return }
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in
            self.update(recordId: recordId) { rec in
                rec.state = .downloading
                rec.progress = progress
                rec.bytesWritten = totalBytesWritten
                rec.bytesExpected = totalBytesExpectedToWrite
                rec.updatedAt = Date()
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let desc = downloadTask.taskDescription else { return }

        // taskDescription format:
        //   "<uuid>|<relativePath>"  (preferred)
        //   "<uuid>"                (fallback)
        let parts = desc.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true)
        guard let uuidPart = parts.first, let recordId = UUID(uuidString: String(uuidPart)) else { return }
        let relFromTask = (parts.count == 2) ? String(parts[1]) : nil

        let fm = FileManager.default
        let downloadsRoot = Self.brockbusterDownloadsRoot()

        func ensureParentDirectory(for fileURL: URL) {
            let dir = fileURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }

        // If the relative path is missing for some reason, fall back to a conservative
        // destination in a per-item folder.
        let rel = relFromTask ?? "unknown/anonymous/\(recordId.uuidString).mp4"
        let dest = downloadsRoot.appendingPathComponent(rel)
        ensureParentDirectory(for: dest)

        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            // IMPORTANT: move the file synchronously before returning.
            try fm.moveItem(at: location, to: dest)

            Task { @MainActor in
                self.update(recordId: recordId) { rec in
                    rec.state = .completed
                    rec.progress = 1
                    // Persist the final path (already planned during enqueue).
                    rec.localRelativePath = rel
                    rec.errorDescription = nil
                    rec.updatedAt = Date()
                }
            }
        } catch {
            Task { @MainActor in
                self.update(recordId: recordId) { rec in
                    rec.state = .failed
                    rec.errorDescription = error.localizedDescription
                    rec.updatedAt = Date()
                }
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let desc = task.taskDescription else { return }
        let uuidPart = desc.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: true).first
        guard let uuidPart, let recordId = UUID(uuidString: String(uuidPart)) else { return }
        guard let error = error else { return }
        Task { @MainActor in
            self.update(recordId: recordId) { rec in
                // If already completed, ignore.
                if rec.state != .completed {
                    rec.state = .failed
                    rec.errorDescription = error.localizedDescription
                    rec.updatedAt = Date()
                }
            }
        }
    }
}
