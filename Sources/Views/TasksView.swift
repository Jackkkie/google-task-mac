import SwiftUI

// MARK: - Sort Option

enum TaskSortOption: String, CaseIterable {
    case myOrder = "My order"
    case date = "Date"
    case starredRecently = "Starred recently"
}

// MARK: - Drag State

/// Tracks state for the custom drag-to-reorder / drag-to-indent system.
@MainActor
class DragState: ObservableObject {
    @Published var draggedTaskId: String?
    @Published var dragOffset: CGSize = .zero
    @Published var isDragging = false
    /// If x-offset > threshold during drag, we enter "indent" mode
    @Published var isIndentMode = false
    /// If x-offset < -threshold during drag on a subtask, we enter "outdent" mode
    @Published var isOutdentMode = false
    /// The task ID that would become parent (the one right above the drop spot)
    @Published var indentTargetId: String?
    /// The index where the dragged item would be inserted (for reorder)
    @Published var hoverIndex: Int?

    static let indentThreshold: CGFloat = 50

    func reset() {
        draggedTaskId = nil
        dragOffset = .zero
        isDragging = false
        isIndentMode = false
        isOutdentMode = false
        indentTargetId = nil
        hoverIndex = nil
    }
}

// MARK: - Row Heights

/// Stores measured row heights for hit-testing during drag
@MainActor
class RowGeometry: ObservableObject {
    @Published var frames: [String: CGRect] = [:]
}

// MARK: - TasksView

struct TasksView: View {
    let taskList: GTTaskList
    let isDefaultList: Bool
    let onListDeleted: (() -> Void)?

    @StateObject private var vm: TasksViewModel
    @StateObject private var drag = DragState()
    @StateObject private var rowGeo = RowGeometry()
    @State private var showingAdd = false
    @State private var showingAddSubtask: GTTask?
    @State private var sortOption: TaskSortOption = .myOrder
    @State private var showCompletedSection = true
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showClearCompletedConfirm = false
    @State private var listTitle: String

    init(taskList: GTTaskList, isDefaultList: Bool = false, onListDeleted: (() -> Void)? = nil) {
        self.taskList = taskList
        self.isDefaultList = isDefaultList
        self.onListDeleted = onListDeleted
        _vm = StateObject(wrappedValue: TasksViewModel(listId: taskList.id))
        _listTitle = State(initialValue: taskList.title)
    }

    /// Flattened pending tasks: parent followed by its children, in order
    private var flatPending: [GTTask] {
        let topLevel = sortTasks(vm.tasks.filter { !$0.isCompleted && $0.parent == nil })
        var result: [GTTask] = []
        for task in topLevel {
            result.append(task)
            let children = vm.tasks.filter { $0.parent == task.id && !$0.isCompleted }
            result.append(contentsOf: children)
        }
        return result
    }

    private var done: [GTTask] {
        vm.tasks.filter { $0.isCompleted && $0.parent == nil }
    }

    private func sortTasks(_ tasks: [GTTask]) -> [GTTask] {
        switch sortOption {
        case .myOrder:
            return tasks
        case .date:
            return tasks.sorted {
                switch ($0.dueDate, $1.dueDate) {
                case (let a?, let b?): return a < b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return false
                }
            }
        case .starredRecently:
            let starred = StarredService.shared
            return tasks.sorted {
                let aStarred = starred.isStarred($0.id)
                let bStarred = starred.isStarred($1.id)
                if aStarred != bStarred { return aStarred }
                if aStarred, let aDate = starred.starredDate(for: $0.id),
                   let bDate = starred.starredDate(for: $1.id) {
                    return aDate > bDate
                }
                return false
            }
        }
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.tasks.isEmpty {
                ProgressView()
            } else if vm.tasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "checkmark.circle", description: Text("Tap + to add your first task."))
            } else {
                taskListContent
            }
        }
        .navigationTitle(listTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    listOptionsMenu
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddTaskView(
                onAdd: { title, notes, due in
                    await vm.add(title: title, notes: notes, due: due)
                },
                onCancel: { showingAdd = false }
            )
        }
        .sheet(item: $showingAddSubtask) { parentTask in
            AddTaskView(
                onAdd: { title, notes, due in
                    await vm.addSubtask(parentId: parentTask.id, title: title, notes: notes, due: due)
                },
                onCancel: { showingAddSubtask = nil }
            )
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: $vm.hasError) {
            Button("OK") {}
        } message: {
            Text(vm.errorMessage)
        }
        .alert("Rename List", isPresented: $showRenameAlert) {
            TextField("List name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                Task {
                    if let updated = await vm.renameList(title: renameText) {
                        listTitle = updated.title
                    }
                }
            }
        }
        .confirmationDialog("Delete this list?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await vm.deleteList()
                    onListDeleted?()
                }
            }
        } message: {
            Text("All tasks in this list will be permanently deleted.")
        }
        .confirmationDialog("Delete all completed tasks?", isPresented: $showClearCompletedConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await vm.clearCompleted() }
            }
        }
    }

    // MARK: - Task List Content (Custom Drag)

    private var taskListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Pending tasks with custom drag
                ForEach(Array(flatPending.enumerated()), id: \.element.id) { index, task in
                    let isChild = task.parent != nil
                    let isDragged = drag.draggedTaskId == task.id
                    let isIndentTarget = drag.isIndentMode && drag.indentTargetId == task.id

                    // Show insertion indicator above this row
                    if let hoverIdx = drag.hoverIndex, hoverIdx == index, !drag.isIndentMode, drag.draggedTaskId != task.id {
                        insertionIndicator
                    }

                    ZStack {
                        taskRowContent(task: task, isChild: isChild)
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: RowFrameKey.self, value: [task.id: geo.frame(in: .named("dragArea"))])
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .opacity(isIndentTarget ? 1 : 0)
                    )
                    .opacity(isDragged ? 0.3 : 1.0)
                    .zIndex(isDragged ? 10 : 0)
                    .offset(isDragged ? drag.dragOffset : .zero)
                    .scaleEffect(isDragged ? 1.03 : 1.0)
                    .shadow(color: isDragged ? .black.opacity(0.2) : .clear, radius: isDragged ? 8 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isDragged)
                    .animation(.easeInOut(duration: 0.15), value: isIndentTarget)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 15, coordinateSpace: .named("dragArea"))
                            .onChanged { value in
                                // Only start drag on mostly-vertical or intentional movement
                                if !drag.isDragging {
                                    drag.isDragging = true
                                    drag.draggedTaskId = task.id
                                }
                                drag.dragOffset = value.translation
                                updateDragTarget(at: value.location, xOffset: value.translation.width, draggedTask: task)
                            }
                            .onEnded { _ in
                                handleDrop(task: task, index: index)
                            }
                    )

                    Divider().padding(.leading, isChild ? 52 : 16)
                }

                // Show insertion indicator at end
                if let hoverIdx = drag.hoverIndex, hoverIdx >= flatPending.count, !drag.isIndentMode {
                    insertionIndicator
                }

                // Completed section
                if !done.isEmpty {
                    completedSection
                }
            }
            .padding(.horizontal)
        }
        .scrollDisabled(drag.isDragging)
        .coordinateSpace(name: "dragArea")
        .onPreferenceChange(RowFrameKey.self) { frames in
            rowGeo.frames = frames
        }
        .onTapGesture {
            // Safety: reset stuck drag state
            if drag.isDragging {
                drag.reset()
            }
        }
    }

    private var insertionIndicator: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 3)
            .padding(.horizontal, 4)
            .transition(.opacity)
    }

    // MARK: - Drag Logic

    /// The left indent width for subtasks (matches Spacer in taskRowContent)
    private static let childIndent: CGFloat = 24

    private func updateDragTarget(at location: CGPoint, xOffset: CGFloat, draggedTask: GTTask) {
        let flat = flatPending

        // Visual position: where the task appears based on starting indent + drag offset
        let startX: CGFloat = draggedTask.parent != nil ? Self.childIndent : 0
        let visualX = startX + xOffset

        // Find which row the cursor is over
        var closestIndex = 0
        var closestDistance: CGFloat = .infinity
        for (i, task) in flat.enumerated() {
            guard task.id != draggedTask.id, let frame = rowGeo.frames[task.id] else { continue }
            let midY = frame.midY
            let dist = abs(location.y - midY)
            if dist < closestDistance {
                closestDistance = dist
                closestIndex = i
                // If below midpoint, insert after
                if location.y > midY {
                    closestIndex = i + 1
                }
            }
        }

        drag.hoverIndex = closestIndex

        // Determine mode based on visual position of the dragged task:
        // - Task visually at left (< childIndent/2) → top-level / outdent
        // - Task visually at right (> childIndent) → subtask / indent
        let isOutdent = draggedTask.parent != nil && visualX < Self.childIndent * 0.5
        let isIndent = draggedTask.parent == nil && visualX > Self.childIndent

        if isOutdent {
            drag.isOutdentMode = true
            drag.isIndentMode = false
            drag.indentTargetId = nil
        } else if isIndent {
            drag.isOutdentMode = false
            drag.isIndentMode = true
            // Find the top-level task at or above the hover position that can be a parent
            let insertAt = min(closestIndex, flat.count - 1)
            // Look backwards from insertAt for a top-level task
            for i in stride(from: max(insertAt, 0), through: 0, by: -1) {
                if i < flat.count && flat[i].parent == nil && flat[i].id != draggedTask.id {
                    drag.indentTargetId = flat[i].id
                    return
                }
            }
            drag.indentTargetId = nil
        } else {
            drag.isOutdentMode = false
            drag.isIndentMode = false
            drag.indentTargetId = nil
        }
    }

    private func handleDrop(task: GTTask, index: Int) {
        let flat = flatPending

        #if DEBUG
        print("[DROP] task=\(task.title) index=\(index) hoverIdx=\(drag.hoverIndex ?? -1) indent=\(drag.isIndentMode) outdent=\(drag.isOutdentMode) parent=\(task.parent ?? "nil")")
        #endif

        if drag.isOutdentMode, task.parent != nil {
            // Move subtask to top level
            let hoverIdx = drag.hoverIndex ?? index
            let prevTopLevel = findPreviousTopLevel(hoverIdx: hoverIdx, flat: flat, draggedId: task.id)
            #if DEBUG
            print("[DROP] outdent: previousTopLevel=\(prevTopLevel?.title ?? "nil")")
            #endif
            drag.reset()
            vm.performUnparentAt(task, previousTaskId: prevTopLevel?.id)
        } else if drag.isIndentMode, let parentId = drag.indentTargetId {
            // Make subtask
            drag.reset()
            vm.performMakeSubtask(task, parentId: parentId)
        } else if let hoverIdx = drag.hoverIndex, hoverIdx != index {
            drag.reset()

            if task.parent != nil {
                // Dragging a subtask → reorder among siblings under same parent
                let parentId = task.parent!
                let targetSibling = findPreviousSibling(hoverIdx: hoverIdx, parentId: parentId, flat: flat, draggedId: task.id)
                #if DEBUG
                print("[DROP] subtask reorder: previousSibling=\(targetSibling?.title ?? "nil")")
                #endif
                vm.performReorderSubtask(task, parentId: parentId, previousTaskId: targetSibling?.id)
            } else {
                // Dragging a top-level task → reorder among top-level only
                let prevTopLevel = findPreviousTopLevel(hoverIdx: hoverIdx, flat: flat, draggedId: task.id)
                #if DEBUG
                print("[DROP] top-level reorder: previousTopLevel=\(prevTopLevel?.title ?? "nil")")
                #endif
                vm.performReorder(task, previousTaskId: prevTopLevel?.id)
            }
        } else {
            #if DEBUG
            print("[DROP] no change")
            #endif
            drag.reset()
        }
    }

    /// Find the top-level task that should be "previous" when inserting at hoverIdx
    private func findPreviousTopLevel(hoverIdx: Int, flat: [GTTask], draggedId: String) -> GTTask? {
        // Look backwards from hoverIdx for a top-level task that isn't the dragged one
        let searchEnd = min(hoverIdx, flat.count)
        for i in stride(from: searchEnd - 1, through: 0, by: -1) {
            let t = flat[i]
            if t.parent == nil && t.id != draggedId {
                return t
            }
        }
        return nil // Move to top
    }

    /// Find the subtask that should be "previous" when reordering among siblings
    private func findPreviousSibling(hoverIdx: Int, parentId: String, flat: [GTTask], draggedId: String) -> GTTask? {
        let searchEnd = min(hoverIdx, flat.count)
        for i in stride(from: searchEnd - 1, through: 0, by: -1) {
            let t = flat[i]
            if t.parent == parentId && t.id != draggedId {
                return t
            }
            // If we hit the parent itself, no previous sibling
            if t.id == parentId {
                return nil
            }
        }
        return nil
    }

    // MARK: - Task Row Content

    @ViewBuilder
    private func taskRowContent(task: GTTask, isChild: Bool) -> some View {
        let parents = isChild ? [] : vm.tasks.filter { !$0.isCompleted && $0.parent == nil && $0.id != task.id }
        HStack(spacing: 12) {
            if isChild {
                Spacer().frame(width: 24)
            }

            Button {
                Task { await vm.toggle(task) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
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

            Spacer()

            Button {
                vm.toggleStar(task)
            } label: {
                Image(systemName: StarredService.shared.isStarred(task.id) ? "star.fill" : "star")
                    .foregroundStyle(StarredService.shared.isStarred(task.id) ? .blue : .secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            if !isChild, !task.isCompleted {
                Button {
                    showingAddSubtask = task
                } label: {
                    Label("Add subtask", systemImage: "text.badge.plus")
                }
            }
            if !isChild, !task.isCompleted, !parents.isEmpty {
                Menu {
                    ForEach(parents) { parent in
                        Button(parent.title) {
                            vm.performMakeSubtask(task, parentId: parent.id)
                        }
                    }
                } label: {
                    Label("Make subtask of...", systemImage: "arrow.right.to.line")
                }
            }
            if isChild {
                Button {
                    vm.performUnparent(task)
                } label: {
                    Label("Move to top level", systemImage: "arrow.left.to.line")
                }
            }
            Button {
                vm.toggleStar(task)
            } label: {
                Label(
                    StarredService.shared.isStarred(task.id) ? "Remove star" : "Add star",
                    systemImage: StarredService.shared.isStarred(task.id) ? "star.slash" : "star"
                )
            }
            Divider()
            Button(role: .destructive) {
                vm.performDelete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Completed Section

    private var completedSection: some View {
        VStack(spacing: 0) {
            Divider().padding(.vertical, 8)

            Button {
                withAnimation { showCompletedSection.toggle() }
            } label: {
                HStack {
                    Text("Completed (\(done.count))")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showCompletedSection ? 0 : -90))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if showCompletedSection {
                ForEach(done) { task in
                    VStack(spacing: 0) {
                        taskRowContent(task: task, isChild: false)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: - Options Menu

    private var listOptionsMenu: some View {
        Menu {
            Section("Sort by") {
                ForEach(TaskSortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    renameText = listTitle
                    showRenameAlert = true
                } label: {
                    Label("Rename list", systemImage: "pencil")
                }

                if !isDefaultList {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete list", systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) {} label: {
                        Label("Delete list", systemImage: "trash")
                    }
                    .disabled(true)
                }

                if !done.isEmpty {
                    Button(role: .destructive) {
                        showClearCompletedConfirm = true
                    } label: {
                        Label("Delete all completed tasks", systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

// MARK: - Row Frame Preference Key

struct RowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - TaskRowView (simplified, used only by StarredView)

struct TaskRowView: View {
    let task: GTTask
    let onToggle: () async -> Void
    var onToggleStar: (() -> Void)?
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

            Spacer()

            if let onToggleStar {
                Button {
                    onToggleStar()
                } label: {
                    Image(systemName: StarredService.shared.isStarred(task.id) ? "star.fill" : "star")
                        .foregroundStyle(StarredService.shared.isStarred(task.id) ? .blue : .secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ViewModel

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
            #if DEBUG
            print("[LOAD] \(tasks.filter { !$0.isCompleted }.map { "\($0.title)(p=\($0.parent ?? "nil"))" }.joined(separator: ", "))")
            #endif
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

    func toggleStar(_ task: GTTask) {
        StarredService.shared.toggleStar(task.id)
        objectWillChange.send()
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

    func addSubtask(parentId: String, title: String, notes: String?, due: String?) async {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            let task = try await GoogleTasksService.shared.createTask(listId: listId, title: title, notes: notes, due: due, token: token)
            try await GoogleTasksService.shared.moveTask(listId: listId, taskId: task.id, previousTaskId: nil, parentId: parentId, token: token)
            await load()
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    func makeSubtask(_ task: GTTask, parentId: String) async {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            try await GoogleTasksService.shared.moveTask(
                listId: listId,
                taskId: task.id,
                previousTaskId: nil,
                parentId: parentId,
                token: token
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    func reorderTask(_ task: GTTask, previousTaskId: String?) async {
        #if DEBUG
        print("[REORDER] \(task.title) prev=\(previousTaskId ?? "nil")")
        #endif
        do {
            let token = try await AuthManager.shared.getAccessToken()
            try await GoogleTasksService.shared.moveTask(
                listId: listId,
                taskId: task.id,
                previousTaskId: previousTaskId,
                token: token
            )
            await load()
        } catch {
            #if DEBUG
            print("[REORDER] ERROR: \(error)")
            #endif
            errorMessage = error.localizedDescription
            hasError = true
            await load()
        }
    }

    func unparentTask(_ task: GTTask, previousTaskId: String? = nil) async {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            // If no previousTaskId specified, place after the last top-level task
            let prevId = previousTaskId ?? tasks.filter({ !$0.isCompleted && $0.parent == nil }).last?.id
            #if DEBUG
            print("[UNPARENT] \(task.title) prev=\(prevId ?? "nil")")
            #endif
            try await GoogleTasksService.shared.moveTask(
                listId: listId,
                taskId: task.id,
                previousTaskId: prevId,
                token: token
            )
            await load()
        } catch {
            #if DEBUG
            print("[UNPARENT] ERROR: \(error)")
            #endif
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    func performDelete(_ task: GTTask) {
        Task { await deleteSingle(task) }
    }

    func performUnparent(_ task: GTTask) {
        Task { await unparentTask(task) }
    }

    func performUnparentAt(_ task: GTTask, previousTaskId: String?) {
        Task { await unparentTask(task, previousTaskId: previousTaskId) }
    }

    func performMakeSubtask(_ task: GTTask, parentId: String) {
        Task { await makeSubtask(task, parentId: parentId) }
    }

    func performReorder(_ task: GTTask, previousTaskId: String?) {
        Task { await reorderTask(task, previousTaskId: previousTaskId) }
    }

    func performReorderSubtask(_ task: GTTask, parentId: String, previousTaskId: String?) {
        Task { await reorderSubtask(task, parentId: parentId, previousTaskId: previousTaskId) }
    }

    func reorderSubtask(_ task: GTTask, parentId: String, previousTaskId: String?) async {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            try await GoogleTasksService.shared.moveTask(
                listId: listId,
                taskId: task.id,
                previousTaskId: previousTaskId,
                parentId: parentId,
                token: token
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
            await load()
        }
    }

    func deleteSingle(_ task: GTTask) async {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            try await GoogleTasksService.shared.deleteTask(listId: listId, taskId: task.id, token: token)
            tasks.removeAll { $0.id == task.id }
            WidgetDataService.shared.update(tasks: tasks.map { ($0, listId) }, isSignedIn: true)
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
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

    func renameList(title: String) async -> GTTaskList? {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            return try await GoogleTasksService.shared.updateTaskList(listId: listId, title: title, token: token)
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
            return nil
        }
    }

    func deleteList() async {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            try await GoogleTasksService.shared.deleteTaskList(listId: listId, token: token)
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }

    func clearCompleted() async {
        do {
            let token = try await AuthManager.shared.getAccessToken()
            try await GoogleTasksService.shared.clearCompleted(listId: listId, token: token)
            tasks.removeAll { $0.isCompleted }
            WidgetDataService.shared.update(tasks: tasks.map { ($0, listId) }, isSignedIn: true)
        } catch {
            errorMessage = error.localizedDescription
            hasError = true
        }
    }
}
