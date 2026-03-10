import Foundation
import WidgetKit

class WidgetDataService {
    static let shared = WidgetDataService()
    private let suite = "group.com.jk.googletaskonmac"

    private init() {}

    func update(tasks: [(task: GTTask, listId: String)], isSignedIn: Bool) {
        let defaults = UserDefaults(suiteName: suite)
        defaults?.set(isSignedIn, forKey: "isSignedIn")

        let widgetTasks = tasks
            .filter { !$0.task.isCompleted }
            .sorted {
                switch ($0.task.dueDate, $1.task.dueDate) {
                case (let a?, let b?): return a < b
                case (_?, nil): return true
                default: return false
                }
            }
            .map { WidgetTask(id: $0.task.id, listId: $0.listId, title: $0.task.title, dueDate: $0.task.dueDate, isOverdue: $0.task.isOverdue) }

        if let data = try? JSONEncoder().encode(widgetTasks) {
            defaults?.set(data, forKey: "widgetTasks")
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    func clear() {
        let defaults = UserDefaults(suiteName: suite)
        defaults?.set(false, forKey: "isSignedIn")
        defaults?.removeObject(forKey: "widgetTasks")
        defaults?.removeObject(forKey: "accessToken")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
