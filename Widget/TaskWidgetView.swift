import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Definition

struct TaskWidget: Widget {
    let kind = "TaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskWidgetProvider()) { entry in
            TaskWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Google Tasks")
        .description("Shows your upcoming tasks.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

// MARK: - Root View

struct TaskWidgetView: View {
    let entry: TaskEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if !entry.isSignedIn {
            notSignedIn
        } else if entry.tasks.isEmpty {
            empty
        } else {
            switch family {
            case .systemSmall:          SmallView(tasks: entry.tasks)
            case .systemMedium:         MediumView(tasks: entry.tasks)
            case .systemLarge:          LargeView(tasks: entry.tasks)
            case .accessoryCircular:    CircularView(count: entry.tasks.count)
            case .accessoryRectangular: RectangularView(tasks: entry.tasks)
            case .accessoryInline:      Text("\(entry.tasks.count) tasks left")
            default:                    SmallView(tasks: entry.tasks)
            }
        }
    }

    private var notSignedIn: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
            Text("Open app to sign in")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }

    private var empty: some View {
        Label("All done!", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .font(.subheadline)
    }
}

// MARK: - System Small

struct SmallView: View {
    let tasks: [WidgetTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Tasks", systemImage: "checklist")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: URL(string: "googletask://add")!) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }

            ForEach(tasks.prefix(4)) { task in
                HStack(spacing: 6) {
                    Button(intent: CompleteTaskIntent(taskId: task.id, listId: task.listId)) {
                        Image(systemName: "circle")
                            .font(.caption)
                            .foregroundStyle(task.isOverdue ? Color.red : Color.blue)
                    }
                    .buttonStyle(.plain)
                    Text(task.title)
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            if tasks.count > 4 {
                Text("+\(tasks.count - 4) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

// MARK: - System Medium

struct MediumView: View {
    let tasks: [WidgetTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Google Tasks", systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                Spacer()
                Link(destination: URL(string: "googletask://add")!) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
            }

            ForEach(tasks.prefix(3)) { task in
                HStack(spacing: 8) {
                    Button(intent: CompleteTaskIntent(taskId: task.id, listId: task.listId)) {
                        Image(systemName: "circle")
                            .font(.caption)
                            .foregroundStyle(task.isOverdue ? .red : .blue)
                    }
                    .buttonStyle(.plain)
                    Text(task.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    if let due = task.dueDate {
                        Text(due, style: .date)
                            .font(.caption2)
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

// MARK: - System Large

struct LargeView: View {
    let tasks: [WidgetTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Google Tasks", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Link(destination: URL(string: "googletask://add")!) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }

            Divider()

            ForEach(tasks.prefix(8)) { task in
                HStack(spacing: 10) {
                    Button(intent: CompleteTaskIntent(taskId: task.id, listId: task.listId)) {
                        Image(systemName: "circle")
                            .foregroundStyle(task.isOverdue ? .red : .blue)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        if let due = task.dueDate {
                            Text(due, style: .date)
                                .font(.caption2)
                                .foregroundStyle(task.isOverdue ? .red : .secondary)
                        }
                    }
                    Spacer()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

// MARK: - Lock Screen

struct CircularView: View {
    let count: Int

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("\(count)")
                    .font(.title2.bold())
                Text("tasks")
                    .font(.caption2)
            }
        }
    }
}

struct RectangularView: View {
    let tasks: [WidgetTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(tasks.prefix(3)) { task in
                Label(task.title, systemImage: task.isOverdue ? "exclamationmark.circle" : "circle")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(task.isOverdue ? .red : .primary)
            }
        }
    }
}
