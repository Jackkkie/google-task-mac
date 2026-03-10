import Foundation

struct GTTask: Identifiable, Codable {
    let id: String
    var title: String
    var notes: String?
    var status: Status
    var due: String?
    var completed: String?
    var updated: String

    enum Status: String, Codable {
        case needsAction = "needsAction"
        case completed = "completed"
    }

    var isCompleted: Bool { status == .completed }

    var dueDate: Date? {
        guard let due else { return nil }
        // Google Tasks API returns due dates as RFC 3339 with time zeroed out
        return ISO8601DateFormatter().date(from: due)
    }

    var isOverdue: Bool {
        guard !isCompleted, let due = dueDate else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }
}

struct TaskListResponse: Codable {
    let items: [GTTask]?
}
