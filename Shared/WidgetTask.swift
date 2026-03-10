import Foundation

/// Lightweight task model shared between the main app and the widget extension.
/// Stored in App Group UserDefaults so the widget can read it without network calls.
struct WidgetTask: Identifiable, Codable {
    let id: String
    let listId: String
    let title: String
    let dueDate: Date?
    let isOverdue: Bool
}
