import SwiftUI

struct TaskListsView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var vm = TaskListsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.taskLists.isEmpty {
                    ProgressView()
                } else if vm.taskLists.isEmpty {
                    ContentUnavailableView("No Lists", systemImage: "checklist", description: Text("Create a list in Google Tasks to get started."))
                } else {
                    List(vm.taskLists) { list in
                        NavigationLink(destination: TasksView(taskList: list)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.title)
                                    .font(.headline)
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Lists")
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
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .alert("Error", isPresented: $vm.hasError) {
                Button("OK") {}
            } message: {
                Text(vm.errorMessage)
            }
        }
    }
}

@MainActor
class TaskListsViewModel: ObservableObject {
    @Published var taskLists: [GTTaskList] = []
    @Published var isLoading = false
    @Published var hasError = false
    var errorMessage = ""

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await AuthManager.shared.getAccessToken()
            taskLists = try await GoogleTasksService.shared.fetchTaskLists(token: token)
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }
}
