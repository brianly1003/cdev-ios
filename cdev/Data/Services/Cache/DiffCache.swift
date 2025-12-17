import Foundation

/// In-memory cache for diff entries
actor DiffCache {
    private var diffs: [String: DiffEntry] = [:] // keyed by file path
    private var orderedPaths: [String] = []
    private let maxSize: Int

    init(maxSize: Int = 100) {
        self.maxSize = maxSize
    }

    /// Add or update diff entry
    func add(_ entry: DiffEntry) {
        let path = entry.filePath

        if diffs[path] == nil {
            orderedPaths.append(path)
        }

        diffs[path] = entry

        // Trim if over limit
        while orderedPaths.count > maxSize {
            let oldPath = orderedPaths.removeFirst()
            diffs.removeValue(forKey: oldPath)
        }
    }

    /// Get diff for file
    func get(path: String) -> DiffEntry? {
        diffs[path]
    }

    /// Get all diffs (most recent first)
    func getAll() -> [DiffEntry] {
        orderedPaths.reversed().compactMap { diffs[$0] }
    }

    /// Get recent diffs
    func getRecent(_ count: Int) -> [DiffEntry] {
        Array(getAll().prefix(count))
    }

    /// Clear all diffs
    func clear() {
        diffs.removeAll()
        orderedPaths.removeAll()
    }

    /// Remove diff for file
    func remove(path: String) {
        diffs.removeValue(forKey: path)
        orderedPaths.removeAll { $0 == path }
    }

    /// Count
    var count: Int {
        diffs.count
    }
}
