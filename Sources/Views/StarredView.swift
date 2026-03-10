import SwiftUI

struct StarredView: View {
    @StateObject private var vm = StarredViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.starredTasks.isEmpty {
                ProgressView()
            } else if vm.starredTasks.isEmpty {
                ContentUnavailableView("No Starred Tasks", systemImage: "star", description: Text("Star tasks to see them here."))
            } else {
                List {
                    ForEach(vm.starredTasks) { item in
                        TaskRowView(
                            task: item.task,
                            onToggle: { await vm.toggle(item) },
                            onToggleStar: { vm.toggleStar(item) }
                        )
                    }
                }
            }
        }
        .navigationTitle("Starred")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: $vm.hasError) {
            Button("OK") {}
        } message: {
            Text(vm.errorMessage)
        }
    }
}

struct StarredTaskItem: Identifiable {
    var id: String { task.id }
    let task: GTTask
    let listId: String
}

@MainActor
class StarredViewModel: ObservableObject {
    @Published var starredTasks: [StarredTaskItem] = []
    @Published var isLoading = false
    @Published var hasError = false
    var errorMessage = ""

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await AuthManager.shared.getAccessToken()
            let lists = try await GoogleTasksService.shared.fetchTaskLists(token: token)
            let starredIds = StarredService.shared.starredIds

            var items: [StarredTaskItem] = []
            for list in lists {
                let tasks = try await GoogleTasksService.shared.fetchTasks(listId: list.id, token: token)
                for task in tasks where starredIds.contains(task.id) && !task.isCompleted {
                    items.append(StarredTaskItem(task: task, listId: list.id))
                }
            }

            // Sort by starred date (most recent first)
            let timestamps = StarredService.shared.starredTimestamps
            starredTasks = items.sorted {
                let a = timestamps[$0.task.id] ?? .distantPast
                let b = timestamps[$1.task.id] ?? .distantPast
                return a > b
            }
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    func toggle(_ item: StarredTaskItem) async {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            _ = try await GoogleTasksService.shared.toggleComplete(listId: item.listId, task: item.task, token: token)
            starredTasks.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    func toggleStar(_ item: StarredTaskItem) {
        StarredService.shared.toggleStar(item.task.id)
        starredTasks.removeAll { $0.id == item.id }
    }
}
