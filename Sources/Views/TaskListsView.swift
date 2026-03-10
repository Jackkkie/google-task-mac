import SwiftUI

enum NavigationDestination: Hashable {
    case starred
    case list(GTTaskList)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .starred: hasher.combine("starred")
        case .list(let list): hasher.combine(list.id)
        }
    }

    static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case (.starred, .starred): return true
        case (.list(let a), .list(let b)): return a.id == b.id
        default: return false
        }
    }
}

struct TaskListsView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var vm = TaskListsViewModel()
    @State private var showCreateList = false
    @State private var newListTitle = ""
    @State private var navigationPath = NavigationPath()
    @State private var hasAutoNavigated = false

    private var starredCount: Int {
        StarredService.shared.starredIds.count
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if vm.isLoading && vm.taskLists.isEmpty {
                    ProgressView()
                } else if vm.taskLists.isEmpty {
                    ContentUnavailableView("No Lists", systemImage: "checklist", description: Text("Create a list to get started."))
                } else {
                    List {
                        // Starred row
                        NavigationLink(value: NavigationDestination.starred) {
                            Label {
                                HStack {
                                    Text("Starred")
                                    if starredCount > 0 {
                                        Text("\(starredCount)")
                                            .font(.caption)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.blue, in: Capsule())
                                    }
                                }
                            } icon: {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }

                        // Task lists
                        Section("My Lists") {
                            ForEach(vm.taskLists) { list in
                                NavigationLink(value: NavigationDestination.list(list)) {
                                    HStack {
                                        Text(list.title)
                                            .font(.headline)
                                        Spacer()
                                        if let count = vm.incompleteCounts[list.id], count > 0 {
                                            Text("\(count)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        // Create new list
                        Section {
                            Button {
                                showCreateList = true
                            } label: {
                                Label("Create new list", systemImage: "plus")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: NavigationDestination.self) { dest in
                switch dest {
                case .starred:
                    StarredView()
                case .list(let list):
                    TasksView(
                        taskList: list,
                        isDefaultList: list.id == vm.taskLists.first?.id,
                        onListDeleted: {
                            navigationPath = NavigationPath()
                            Task { await vm.load() }
                        }
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive, action: authManager.signOut) {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Label(authManager.userName ?? "Account", systemImage: "person.circle")
                    }
                }
            }
            .task {
                await vm.load()
                // Auto-navigate to first list with incomplete tasks
                if !hasAutoNavigated, !vm.taskLists.isEmpty {
                    hasAutoNavigated = true
                    let firstActive = vm.taskLists.first(where: { vm.incompleteCounts[$0.id, default: 0] > 0 }) ?? vm.taskLists.first!
                    navigationPath.append(NavigationDestination.list(firstActive))
                }
            }
            .refreshable { await vm.load() }
            .alert("Error", isPresented: $vm.hasError) {
                Button("OK") {}
            } message: {
                Text(vm.errorMessage)
            }
            .alert("New List", isPresented: $showCreateList) {
                TextField("List name", text: $newListTitle)
                Button("Cancel", role: .cancel) { newListTitle = "" }
                Button("Create") {
                    let title = newListTitle
                    newListTitle = ""
                    Task {
                        if let list = await vm.createList(title: title) {
                            navigationPath.append(NavigationDestination.list(list))
                        }
                    }
                }
            }
        }
    }
}

@MainActor
class TaskListsViewModel: ObservableObject {
    @Published var taskLists: [GTTaskList] = []
    @Published var incompleteCounts: [String: Int] = [:]
    @Published var isLoading = false
    @Published var hasError = false
    var errorMessage = ""

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await AuthManager.shared.getAccessToken()
            taskLists = try await GoogleTasksService.shared.fetchTaskLists(token: token)

            // Fetch incomplete counts for each list
            for list in taskLists {
                let tasks = try await GoogleTasksService.shared.fetchTasks(listId: list.id, token: token)
                incompleteCounts[list.id] = tasks.filter { !$0.isCompleted }.count
            }
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    func createList(title: String) async -> GTTaskList? {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            let list = try await GoogleTasksService.shared.createTaskList(title: title, token: token)
            taskLists.append(list)
            incompleteCounts[list.id] = 0
            return list
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
            return nil
        }
    }
}
