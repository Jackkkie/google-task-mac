import Foundation

class GoogleTasksService {
    static let shared = GoogleTasksService()
    private let base = "https://tasks.googleapis.com/tasks/v1"

    private init() {}

    // MARK: - Task Lists

    func fetchTaskLists(token: String) async throws -> [GTTaskList] {
        let url = URL(string: "\(base)/users/@me/lists")!
        let data = try await fetch(url, token: token)
        return (try decode(GTTaskListResponse.self, from: data).items) ?? []
    }

    // MARK: - Tasks

    func fetchTasks(listId: String, token: String) async throws -> [GTTask] {
        var comps = URLComponents(string: "\(base)/lists/\(listId)/tasks")!
        comps.queryItems = [
            URLQueryItem(name: "showCompleted", value: "true"),
            URLQueryItem(name: "showHidden", value: "true"),
            URLQueryItem(name: "maxResults", value: "100")
        ]
        let data = try await fetch(comps.url!, token: token)
        let tasks = (try decode(TaskListResponse.self, from: data).items) ?? []
        // Sort by position to reflect move operations
        return tasks.sorted { ($0.position ?? "") < ($1.position ?? "") }
    }

    func createTask(listId: String, title: String, notes: String? = nil, due: String? = nil, token: String) async throws -> GTTask {
        let url = URL(string: "\(base)/lists/\(listId)/tasks")!
        var body: [String: Any] = ["title": title]
        if let notes { body["notes"] = notes }
        if let due { body["due"] = due }
        let data = try await fetch(url, method: "POST", body: body, token: token)
        return try decode(GTTask.self, from: data)
    }

    func updateTask(listId: String, task: GTTask, token: String) async throws -> GTTask {
        let url = URL(string: "\(base)/lists/\(listId)/tasks/\(task.id)")!
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as! [String: Any]
        let data = try await fetch(url, method: "PUT", body: body, token: token)
        return try decode(GTTask.self, from: data)
    }

    func toggleComplete(listId: String, task: GTTask, token: String) async throws -> GTTask {
        var t = task
        t.status = task.isCompleted ? .needsAction : .completed
        if !task.isCompleted {
            t.completed = ISO8601DateFormatter().string(from: Date())
        }
        return try await updateTask(listId: listId, task: t, token: token)
    }

    func deleteTask(listId: String, taskId: String, token: String) async throws {
        let url = URL(string: "\(base)/lists/\(listId)/tasks/\(taskId)")!
        _ = try await fetch(url, method: "DELETE", token: token)
    }

    func moveTask(listId: String, taskId: String, previousTaskId: String?, parentId: String? = nil, token: String) async throws {
        var comps = URLComponents(string: "\(base)/lists/\(listId)/tasks/\(taskId)/move")!
        var queryItems: [URLQueryItem] = []
        if let prev = previousTaskId {
            queryItems.append(URLQueryItem(name: "previous", value: prev))
        }
        if let parentId {
            queryItems.append(URLQueryItem(name: "parent", value: parentId))
        }
        if !queryItems.isEmpty { comps.queryItems = queryItems }
        #if DEBUG
        print("[MOVE API] \(comps.url!.absoluteString)")
        #endif
        _ = try await fetch(comps.url!, method: "POST", token: token)
    }

    // MARK: - Task List CRUD

    func createTaskList(title: String, token: String) async throws -> GTTaskList {
        let url = URL(string: "\(base)/users/@me/lists")!
        let body: [String: Any] = ["title": title]
        let data = try await fetch(url, method: "POST", body: body, token: token)
        return try decode(GTTaskList.self, from: data)
    }

    func updateTaskList(listId: String, title: String, token: String) async throws -> GTTaskList {
        let url = URL(string: "\(base)/users/@me/lists/\(listId)")!
        let body: [String: Any] = ["title": title]
        let data = try await fetch(url, method: "PATCH", body: body, token: token)
        return try decode(GTTaskList.self, from: data)
    }

    func deleteTaskList(listId: String, token: String) async throws {
        let url = URL(string: "\(base)/users/@me/lists/\(listId)")!
        _ = try await fetch(url, method: "DELETE", token: token)
    }

    // MARK: - Clear Completed

    func clearCompleted(listId: String, token: String) async throws {
        let url = URL(string: "\(base)/lists/\(listId)/clear")!
        _ = try await fetch(url, method: "POST", token: token)
    }

    // MARK: - Private

    private func fetch(_ url: URL, method: String = "GET", body: [String: Any]? = nil, token: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[API ERROR] \(method) \(url) → \(code): \(body)")
            #endif
            throw APIError.badResponse(code)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}

enum APIError: LocalizedError {
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "API error \(code)"
        }
    }
}
