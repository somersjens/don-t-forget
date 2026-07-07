import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct HistoryCSVRow {
    let content: String
    let kind: String
    let category: String
    let dateTime: Date
    let isDeleted: Bool
}

struct HistoryCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    private let data: Data

    init(rows: [HistoryCSVRow], locale: Locale = AppCalendar.locale) {
        var lines = [[
            locale.localized("csv.header.content"),
            locale.localized("csv.header.type"),
            locale.localized("csv.header.category"),
            locale.localized("csv.header.dateTime"),
            locale.localized("csv.header.deleted")
        ].joined(separator: ",")]
        lines.append(contentsOf: rows.map { row in
            [
                Self.escape(row.content),
                Self.escape(row.kind),
                Self.escape(row.category),
                Self.escape(Self.iso8601Formatter.string(from: row.dateTime)),
                row.isDeleted ? "1" : "0"
            ].joined(separator: ",")
        })

        // The UTF-8 BOM lets Excel recognize accented characters without import settings.
        data = Data((["\u{FEFF}", lines.joined(separator: "\r\n")].joined()).utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static func uniqueFilename(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return "Dont-forget_historie_\(formatter.string(from: date))"
    }

    static func recurringCategoryNames(from encodedCategories: String) -> [String: String] {
        struct Category: Decodable {
            let id: String
            let title: String
        }

        guard let data = encodedCategories.data(using: .utf8),
              let categories = try? JSONDecoder().decode([Category].self, from: data) else {
            return [:]
        }

        return categories.reduce(into: [:]) { names, category in
            names[category.id] = category.title
        }
    }

    static func fallbackRecurringCategoryName(for id: String, locale: Locale) -> String {
        return switch id {
        case "birthday": locale.localized("category.recurring.birthdays")
        case "holidays": locale.localized("category.recurring.holidays")
        case "general": locale.localized("category.recurring.general")
        case "personal": locale.localized("Persoonlijk")
        default:
            id
        }
    }

    private static func escape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
