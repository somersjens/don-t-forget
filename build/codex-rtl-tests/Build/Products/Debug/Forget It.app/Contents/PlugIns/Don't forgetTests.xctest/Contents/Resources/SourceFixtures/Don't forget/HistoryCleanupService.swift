import Foundation
import SwiftData

enum HistoryCleanupService {
    @discardableResult
    static func removeExpiredHistory(
        retention: HistoryRetentionOption,
        from modelContext: ModelContext,
        now: Date = .now
    ) throws -> Int {
        guard let cutoff = retention.cutoffDate(from: now) else { return 0 }

        let entries = try modelContext.fetch(historyEntriesDescriptor())
        let todos = try modelContext.fetch(historyTodosDescriptor())
        let recurringItems = try modelContext.fetch(historyRecurringItemsDescriptor())
        let expiredEntries = entries.filter { historyDate(for: $0) < cutoff }
        let expiredTodos = todos.filter { historyDate(for: $0) < cutoff }
        let expiredRecurringItems = recurringItems.filter { historyDate(for: $0) < cutoff }
        let deletedCount = expiredEntries.count + expiredTodos.count + expiredRecurringItems.count
        guard deletedCount > 0 else { return 0 }

        try AppBackupService.createAutomaticSnapshot(
            from: modelContext,
            reason: "before-history-cleanup"
        )

        for entry in expiredEntries {
            modelContext.delete(entry)
        }

        for todo in expiredTodos {
            modelContext.delete(todo)
        }

        for item in expiredRecurringItems {
            modelContext.delete(item)
        }

        try modelContext.save()
        return deletedCount
    }

    @discardableResult
    static func removeAllHistory(from modelContext: ModelContext) throws -> Int {
        let entries = try modelContext.fetch(historyEntriesDescriptor())
        let todos = try modelContext.fetch(historyTodosDescriptor())
        let recurringItems = try modelContext.fetch(historyRecurringItemsDescriptor())
        var deletedCount = 0

        guard !entries.isEmpty || !todos.isEmpty || !recurringItems.isEmpty else { return 0 }
        try AppBackupService.createAutomaticSnapshot(
            from: modelContext,
            reason: "before-delete-all-history"
        )

        for entry in entries {
            modelContext.delete(entry)
            deletedCount += 1
        }

        for todo in todos {
            modelContext.delete(todo)
            deletedCount += 1
        }


        for item in recurringItems {
            modelContext.delete(item)
            deletedCount += 1
        }

        if deletedCount > 0 {
            try modelContext.save()
        }
        return deletedCount
    }

    private static func historyEntriesDescriptor() -> FetchDescriptor<DayEntry> {
        FetchDescriptor(predicate: #Predicate<DayEntry> { entry in
            entry.isDone || entry.isRemoved
        })
    }

    private static func historyTodosDescriptor() -> FetchDescriptor<TodoItem> {
        FetchDescriptor(predicate: #Predicate<TodoItem> { todo in
            todo.isDone || todo.isRemoved
        })
    }

    private static func historyRecurringItemsDescriptor() -> FetchDescriptor<RecurringItem> {
        FetchDescriptor(predicate: #Predicate<RecurringItem> { item in
            item.isRemoved
        })
    }

    private static func historyDate(for entry: DayEntry) -> Date {
        entry.completedAt ?? entry.date
    }

    private static func historyDate(for todo: TodoItem) -> Date {
        todo.completedAt ?? todo.createdAt
    }

    private static func historyDate(for item: RecurringItem) -> Date {
        item.completedAt ?? item.createdAt
    }
}
