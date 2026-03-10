import SwiftUI

struct TasksView: View {
    let taskList: GTTaskList
    @StateObject private var vm: TasksViewModel
    @State private var showingAdd = false

    init(taskList: GTTaskList) {
        self.taskList = taskList
        _vm = StateObject(wrappedValue: TasksViewModel(listId: taskList.id))
    }

    var pending: [GTTask] { vm.tasks.filter { !$0.isCompleted } }
    var done: [GTTask] { vm.tasks.filter { $0.isCompleted } }

    var body: some View {
        Group {
            if vm.isLoading && vm.tasks.isEmpty {
                ProgressView()
            } else if vm.tasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "checkmark.circle", description: Text("Tap + to add your first task."))
            } else {
                List {
                    Section {
                        ForEach(pending) { task in
                            TaskRowView(task: task) { await vm.toggle(task) }
                        }
                        .onDelete { offsets in
                            Task { await vm.delete(at: offsets, in: pending) }
                        }
                        .onMove { source, destination in
                            Task { await vm.movePending(from: source, to: destination) }
                        }
                    }

                    if !done.isEmpty {
                        Section("Completed") {
                            ForEach(done) { task in
                                TaskRowView(task: task) { await vm.toggle(task) }
                            }
                            .onDelete { offsets in
                                Task { await vm.delete(at: offsets, in: done) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(taskList.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddTaskView { title, notes, due in
                await vm.add(title: title, notes: notes, due: due)
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

struct TaskRowView: View {
    let task: GTTask
    let onToggle: () async -> Void
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                isAnimating = true
                Task {
                    await onToggle()
                    isAnimating = false
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                    .symbolEffect(.bounce, value: isAnimating)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let due = task.dueDate {
                    Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(task.isOverdue ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
class TasksViewModel: ObservableObject {
    @Published var tasks: [GTTask] = []
    @Published var isLoading = false
    @Published var hasError = false
    var errorMessage = ""

    let listId: String

    init(listId: String) { self.listId = listId }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await AuthManager.shared.getAccessToken()
            tasks = try await GoogleTasksService.shared.fetchTasks(listId: listId, token: token)
            WidgetDataService.shared.update(tasks: tasks.map { ($0, listId) }, isSignedIn: true)
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    func toggle(_ task: GTTask) async {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            let updated = try await GoogleTasksService.shared.toggleComplete(listId: listId, task: task, token: token)
            if let i = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[i] = updated
            }
            WidgetDataService.shared.update(tasks: tasks.map { ($0, listId) }, isSignedIn: true)
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    func add(title: String, notes: String?, due: String?) async {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            let task = try await GoogleTasksService.shared.createTask(listId: listId, title: title, notes: notes, due: due, token: token)
            tasks.insert(task, at: 0)
            WidgetDataService.shared.update(tasks: tasks.map { ($0, listId) }, isSignedIn: true)
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    func movePending(from source: IndexSet, to destination: Int) async {
        var pending = tasks.filter { !$0.isCompleted }
        let done = tasks.filter { $0.isCompleted }
        pending.move(fromOffsets: source, toOffset: destination)
        tasks = pending + done

        guard let sourceIndex = source.first else { return }
        let targetIndex = destination > sourceIndex ? destination - 1 : destination
        let movedTask = pending[targetIndex]
        let previousTask = targetIndex > 0 ? pending[targetIndex - 1] : nil

        do {
            let token = try await AuthManager.shared.getAccessToken()
            try await GoogleTasksService.shared.moveTask(
                listId: listId,
                taskId: movedTask.id,
                previousTaskId: previousTask?.id,
                token: token
            )
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
            await load()
        }
    }

    func delete(at offsets: IndexSet, in subset: [GTTask]) async {
        let toDelete = offsets.map { subset[$0] }
        do {
            let token = try await AuthManager.shared.getAccessToken()
            for task in toDelete {
                try await GoogleTasksService.shared.deleteTask(listId: listId, taskId: task.id, token: token)
                tasks.removeAll { $0.id == task.id }
            }
            WidgetDataService.shared.update(tasks: tasks.map { ($0, listId) }, isSignedIn: true)
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }
}
