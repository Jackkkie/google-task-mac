import WidgetKit
import SwiftUI

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
    let isSignedIn: Bool
}

struct TaskWidgetProvider: TimelineProvider {
    private let suite = "group.com.jk.googletaskonmac"

    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: .now, tasks: preview, isSignedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(TaskEntry(date: .now, tasks: load(), isSignedIn: signedIn()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = TaskEntry(date: .now, tasks: load(), isSignedIn: signedIn())
        // Refresh every 30 min; the main app also triggers a reload after fetching
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> [WidgetTask] {
        guard
            let defaults = UserDefaults(suiteName: suite),
            let data = defaults.data(forKey: "widgetTasks"),
            let tasks = try? JSONDecoder().decode([WidgetTask].self, from: data)
        else { return [] }
        return tasks
    }

    private func signedIn() -> Bool {
        UserDefaults(suiteName: suite)?.bool(forKey: "isSignedIn") ?? false
    }

    private var preview: [WidgetTask] {
        [
            WidgetTask(id: "1", listId: "", title: "Review pull requests", dueDate: .now, isOverdue: false),
            WidgetTask(id: "2", listId: "", title: "Team standup", dueDate: nil, isOverdue: false),
            WidgetTask(id: "3", listId: "", title: "Submit report", dueDate: Calendar.current.date(byAdding: .day, value: -1, to: .now), isOverdue: true)
        ]
    }
}
