import Foundation

struct GTTaskList: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var updated: String
}

struct GTTaskListResponse: Codable {
    let items: [GTTaskList]?
}
