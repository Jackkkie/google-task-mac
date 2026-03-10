import AppIntents
import WidgetKit

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"

    @Parameter(title: "Task ID")
    var taskId: String

    @Parameter(title: "List ID")
    var listId: String

    init() {}

    init(taskId: String, listId: String) {
        self.taskId = taskId
        self.listId = listId
    }

    func perform() async throws -> some IntentResult {
        let suite = "group.com.jk.googletaskonmac"
        guard
            let defaults = UserDefaults(suiteName: suite),
            let token = defaults.string(forKey: "accessToken")
        else { return .result() }

        let urlString = "https://tasks.googleapis.com/tasks/v1/lists/\(listId)/tasks/\(taskId)"
        guard let url = URL(string: urlString) else { return .result() }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["status": "completed"])

        _ = try? await URLSession.shared.data(for: request)

        if let data = defaults.data(forKey: "widgetTasks"),
           var tasks = try? JSONDecoder().decode([WidgetTask].self, from: data) {
            tasks.removeAll { $0.id == taskId }
            if let encoded = try? JSONEncoder().encode(tasks) {
                defaults.set(encoded, forKey: "widgetTasks")
            }
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
