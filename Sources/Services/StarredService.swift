import Foundation

/// Manages starred (favorite) tasks locally via UserDefaults.
/// Google Tasks API doesn't expose a native star field, so we track it client-side.
class StarredService {
    static let shared = StarredService()
    private let key = "starredTaskIds"
    private let timestampKey = "starredTimestamps"
    private let defaults = UserDefaults.standard

    private init() {}

    var starredIds: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// Timestamps when each task was starred (for "Starred recently" sort)
    var starredTimestamps: [String: Date] {
        guard let data = defaults.data(forKey: timestampKey),
              let dict = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
        return dict
    }

    func isStarred(_ taskId: String) -> Bool {
        starredIds.contains(taskId)
    }

    func toggleStar(_ taskId: String) {
        var ids = starredIds
        var timestamps = starredTimestamps
        if ids.contains(taskId) {
            ids.remove(taskId)
            timestamps.removeValue(forKey: taskId)
        } else {
            ids.insert(taskId)
            timestamps[taskId] = Date()
        }
        defaults.set(Array(ids), forKey: key)
        if let data = try? JSONEncoder().encode(timestamps) {
            defaults.set(data, forKey: timestampKey)
        }
    }

    func starredDate(for taskId: String) -> Date? {
        starredTimestamps[taskId]
    }

    /// Count of starred tasks from a given set of task IDs
    func starredCount(in taskIds: [String]) -> Int {
        taskIds.filter { starredIds.contains($0) }.count
    }
}
