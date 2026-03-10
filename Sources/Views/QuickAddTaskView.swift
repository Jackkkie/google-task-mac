import SwiftUI

struct QuickAddTaskView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var taskLists: [GTTaskList] = []
    @State private var selectedListId = ""
    @State private var isLoading = true
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView("Loading lists...")
                } else {
                    Section {
                        TextField("Task title", text: $title)
                    }
                    if taskLists.count > 1 {
                        Section {
                            Picker("List", selection: $selectedListId) {
                                ForEach(taskLists) { list in
                                    Text(list.title).tag(list.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            isAdding = true
                            do {
                                let token = try await AuthManager.shared.getAccessToken()
                                _ = try await GoogleTasksService.shared.createTask(
                                    listId: selectedListId,
                                    title: title,
                                    token: token
                                )
                                await AuthManager.shared.refreshWidgetCache()
                            } catch {
                                print("Quick add error: \(error)")
                            }
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selectedListId.isEmpty || isAdding || isLoading)
                }
            }
            .task {
                do {
                    let token = try await AuthManager.shared.getAccessToken()
                    taskLists = try await GoogleTasksService.shared.fetchTaskLists(token: token)
                    if let first = taskLists.first {
                        selectedListId = first.id
                    }
                } catch {}
                isLoading = false
            }
        }
    }
}
