import CoreLocation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    @AppStorage(SettingsKeys.weekStart)
    private var weekStart = WeekStartOption.monday.rawValue

    @AppStorage(SettingsKeys.weekNumberRule)
    private var weekNumberRule = WeekNumberRule.iso8601.rawValue

    @AppStorage(SettingsKeys.dateFormat)
    private var dateFormat = DateFormatOption.system.rawValue

    @AppStorage(SettingsKeys.language)
    private var language = AppLanguage.system.rawValue

    @AppStorage(SettingsKeys.historyShowsDeletedItems)
    private var historyShowsDeletedItems = true

    @AppStorage(SettingsKeys.historyRetention)
    private var historyRetention = HistoryRetentionOption.default.rawValue

    @AppStorage(SettingsKeys.recurringHorizon)
    private var recurringHorizon = RecurringHorizonOption.threeMonths.rawValue

    @AppStorage(SettingsKeys.recurringExtendedThrough)
    private var recurringExtendedThrough = 0.0

    @AppStorage(SettingsKeys.recurringLastSyncSignature)
    private var recurringLastSyncSignature = ""

    @AppStorage(SettingsKeys.iCloudSyncEnabled)
    private var iCloudSyncEnabled = true

    @AppStorage(SettingsKeys.endOfDayReminderEnabled)
    private var endOfDayReminderEnabled = false

    @AppStorage(SettingsKeys.endOfDayReminderMinutes)
    private var endOfDayReminderMinutes = EndOfDayReminderService.defaultMinutes

    @AppStorage(SettingsKeys.recurringCategories)
    private var recurringCategoriesData = ""

    @AppStorage(SettingsKeys.todoGroups)
    private var todoGroupsData = ""

    @AppStorage(SettingsKeys.calendarSyncEnabled)
    private var calendarSyncEnabled = false

    @AppStorage(SettingsKeys.calendarLastSyncDate)
    private var calendarLastSyncDate = 0.0

    @AppStorage(SettingsKeys.weatherInAgendaEnabled)
    private var weatherInAgendaEnabled = false

    @AppStorage(SettingsKeys.weatherLocationName)
    private var weatherLocationName = ""

    @AppStorage(SettingsKeys.weatherLatitude)
    private var weatherLatitude = 0.0

    @AppStorage(SettingsKeys.weatherLongitude)
    private var weatherLongitude = 0.0

    @AppStorage(SettingsKeys.weatherLastError)
    private var weatherLastError = ""

    @AppStorage(SettingsKeys.weatherReloadToken)
    private var weatherReloadToken = 0

    @State private var calendarError: String?
    @State private var isRequestingCalendarAccess = false
    @State private var historyExportDocument: HistoryCSVDocument?
    @State private var historyExportFilename = ""
    @State private var isExportingHistory = false
    @State private var historyExportError: String?
    @State private var backupError: String?
    @State private var isConfirmingHistoryDeletion = false
    @State private var historyDeletionError: String?
    @State private var pendingHistoryRetention: String?
    @State private var isConfirmingRetentionChange = false
    @State private var isShowingStorageRestartNotice = false
    @State private var isRevertingICloudChange = false
    @State private var iCloudStatusText: String?
    @State private var isConfirmingAppReset = false
    @State private var appResetError: String?
    @State private var didTriggerResetLongPress = false
    @State private var reminderError: String?
    @State private var isSendingTestReminder = false
    @State private var testReminderCountdown: Int?
    @State private var testReminderCountdownTask: Task<Void, Never>?
    @State private var isShowingWeatherSetup = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ActionButtonCaptureSettingsView()
                    } label: {
                        Label {
                            Text("Actieknop configureren")
                        } icon: {
                            PulsingActionButtonIcon()
                        }
                    }

                    NavigationLink {
                        ActionButtonSettingsView()
                    } label: {
                        Label("Lockscreen-widget configureren", systemImage: "rectangle.on.rectangle")
                    }

                    NavigationLink {
                        HomeWidgetSettingsView()
                    } label: {
                        Label("Beginscherm-widget configureren", systemImage: "rectangle.split.2x1")
                    }

                }

                Section {
                    Picker("Systeemtaal", selection: $language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title(for: locale)).tag(language.rawValue)
                        }
                    }
                    .tint(.primary)

                    Picker("Week begint op", selection: $weekStart) {
                        ForEach(WeekStartOption.allCases) { option in
                            Text(option.title(for: locale)).tag(option.rawValue)
                        }
                    }
                    .tint(.primary)

                    Picker("Weeknummering", selection: $weekNumberRule) {
                        ForEach(WeekNumberRule.allCases) { rule in
                            Text(rule.title(for: locale)).tag(rule.rawValue)
                        }
                    }
                    .tint(.primary)

                    Picker(locale.localized("Datum formattering"), selection: $dateFormat) {
                        let localeDefault = DateFormatOption.localeDefault(for: locale)
                        ForEach(DateFormatOption.allCases) { option in
                            Text(option.title(for: locale, localeDefault: localeDefault))
                                .tag(option.rawValue)
                        }
                    }
                    .tint(.primary)

                    Picker(
                        locale.localized("Afgerond opschonen"),
                        selection: historyRetentionSelection
                    ) {
                        ForEach(HistoryRetentionOption.allCases) { option in
                            Text(option.title(for: locale)).tag(option.rawValue)
                        }
                    }
                    .tint(.primary)

                    Picker(
                        locale.localized("Agenda vooruit laden"),
                        selection: $recurringHorizon
                    ) {
                        ForEach(RecurringHorizonOption.allCases) { option in
                            Text(option.title(for: locale)).tag(option.rawValue)
                        }
                    }
                    .tint(.primary)
                    .onChange(of: recurringHorizon) { _, _ in
                        recurringExtendedThrough = 0
                        recurringLastSyncSignature = ""
                    }

                }

                Section {
                    Toggle(
                        locale.localized("Einde-dagherinnering"),
                        isOn: $endOfDayReminderEnabled
                    )
                    .onChange(of: endOfDayReminderEnabled) { _, enabled in
                        updateEndOfDayReminder(enabled: enabled)
                    }

                    HStack {
                        Text(locale.localized("Tijd"))
                        Spacer()
                        DatePicker(
                            "",
                            selection: endOfDayReminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .controlSize(.small)
                        .frame(height: 24)
                    }
                    .frame(height: 44)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

                    Button(action: sendTestReminder) {
                        if let testReminderCountdown {
                            HStack(spacing: 8) {
                                Image(systemName: "timer")
                                Text(locale.localizedFormat(
                                    "settings.testAgainInSeconds",
                                    testReminderCountdown
                                ))
                                .contentTransition(.numericText(countsDown: true))
                            }
                        } else if isSendingTestReminder {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(locale.localized("Testmelding versturen…"))
                            }
                        } else {
                            Label(
                                locale.localized("Testmelding versturen"),
                                systemImage: "paperplane"
                            )
                        }
                    }
                    .disabled(isSendingTestReminder || testReminderCountdown != nil)
                    .animation(.smooth(duration: 0.35), value: testReminderCountdown)
                } footer: {
                    Text(locale.localized("Je krijgt een overzicht van de openstaande taken van vandaag. Zijn er geen openstaande taken, dan wordt op de geplande tijd niets verstuurd. De melding is mogelijk niet zichtbaar als je telefoon in slaap- of nachtmodus staat."))
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $iCloudSyncEnabled) {
                            Text(locale.localized("iCloud-synchronisatie"))
                        }
                        .onChange(of: iCloudSyncEnabled) { _, enabled in
                            if isRevertingICloudChange {
                                isRevertingICloudChange = false
                                return
                            }
                            do {
                                try AppBackupService.createAutomaticSnapshot(
                                    from: modelContext,
                                    reason: "before-icloud-mode-change"
                                )
                            } catch {
                                isRevertingICloudChange = true
                                iCloudSyncEnabled = !enabled
                                backupError = locale.localizedFormat(
                                    "iCloud-instelling niet gewijzigd: %@",
                                    error.localizedDescription
                                )
                                return
                            }
                            if enabled {
                                CloudSettingsSynchronizer.shared.start()
                                Task { await refreshICloudStatus() }
                            } else {
                                CloudSettingsSynchronizer.shared.stop()
                                iCloudStatusText = nil
                            }
                            isShowingStorageRestartNotice = true
                        }

                        if !iCloudSyncEnabled {
                            Text(locale.localized("Als je apparaat kwijt raakt, zijn je gegevens niet terug te halen."))
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else if let iCloudStatusText {
                            Label(
                                iCloudStatusText,
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: iCloudSyncEnabled)

                    Toggle("Verwijderde items tonen", isOn: $historyShowsDeletedItems)

                    Toggle("Synchroniseer met iPhone Kalender", isOn: $calendarSyncEnabled)
                        .disabled(isRequestingCalendarAccess)
                        .onChange(of: calendarSyncEnabled) { _, enabled in
                            guard enabled else { return }
                            requestCalendarAccess()
                        }

                    Toggle(
                        locale.localized("Weer bij toekomstige dagen"),
                        isOn: weatherAgendaSelection
                    )

                    if weatherInAgendaEnabled {
                        Button {
                            isShowingWeatherSetup = true
                        } label: {
                            HStack {
                                Label(
                                    locale.localized("Weerlocatie"),
                                    systemImage: "location"
                                )
                                Spacer()
                                Text(weatherLocationName)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        if !weatherLastError.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(
                                    weatherErrorText,
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.footnote)
                                .foregroundStyle(.orange)

                                if weatherLastError == AppleWeatherForecastStore.authenticationError,
                                   let helpURL = URL(string: "https://developer.apple.com/help/account/services/weatherkit") {
                                    Link(
                                        locale.localized("Bekijk WeatherKit-instellingen bij Apple"),
                                        destination: helpURL
                                    )
                                    .font(.footnote.weight(.semibold))
                                }

                                Button(locale.localized("Probeer weer opnieuw")) {
                                    weatherLastError = ""
                                    weatherReloadToken += 1
                                }
                                .font(.footnote.weight(.semibold))
                            }
                        }
                    }

                    if isRequestingCalendarAccess {
                        ProgressView("Kalender synchroniseren…")
                    }

                    if let calendarError {
                        Label(calendarError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if calendarSyncEnabled {
                        Button {
                            syncCalendarNow()
                        } label: {
                            Label("Synchroniseer nu", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isRequestingCalendarAccess)
                    }

                }

                Section {
                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        Label(
                            locale.localized("Backup en herstel"),
                            systemImage: "externaldrive.badge.timemachine"
                        )
                    }

                    Button(action: exportHistory) {
                        Label(
                            locale.localized("Afgeronde items downloaden als CSV"),
                            systemImage: "arrow.down.doc"
                        )
                    }
                } footer: {
                    Text(locale.localized("Een volledige backup bevat actieve en afgeronde items, herhalingen en instellingen. CSV is alleen bedoeld als leesbaar historie-overzicht."))
                }

                Section {
                    Label {
                        Text(locale.localized("Verwijder alle afgeronde taken"))
                    } icon: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !didTriggerResetLongPress else {
                            didTriggerResetLongPress = false
                            return
                        }
                        isConfirmingHistoryDeletion = true
                    }
                    .onLongPressGesture(minimumDuration: 3, maximumDistance: 30) {
                        didTriggerResetLongPress = true
                        isConfirmingAppReset = true
                    } onPressingChanged: { isPressing in
                        guard !isPressing, didTriggerResetLongPress else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            didTriggerResetLongPress = false
                        }
                    }
                    .accessibilityHint(locale.localized("Houd 3 seconden ingedrukt om de hele app te resetten."))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        isConfirmingHistoryDeletion = true
                    }
                    .accessibilityAction(named: locale.localized("Hele app resetten")) {
                        isConfirmingAppReset = true
                    }
                }
            }
            .tint(.brandHardBlue)
            .onAppear {
                language = AppLanguage.resolved(from: language).rawValue
            }
            .task {
                if iCloudSyncEnabled {
                    await refreshICloudStatus()
                }
            }
            .navigationTitle("Instellingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") {
                        dismiss()
                    }
                }
            }
            .fileExporter(
                isPresented: $isExportingHistory,
                document: historyExportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: historyExportFilename
            ) { result in
                if case .failure(let error) = result {
                    historyExportError = error.localizedDescription
                }
            }
            .sheet(isPresented: $isShowingWeatherSetup) {
                WeatherAgendaSetupView { location, name in
                    weatherLatitude = location.coordinate.latitude
                    weatherLongitude = location.coordinate.longitude
                    weatherLocationName = name
                    weatherLastError = ""
                    weatherInAgendaEnabled = true
                    weatherReloadToken += 1
                }
            }
            .alert(
                locale.localized("Backup mislukt"),
                isPresented: Binding(
                    get: { backupError != nil },
                    set: { if !$0 { backupError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupError ?? "")
            }
            .alert(
                locale.localized("Heropen de app"),
                isPresented: $isShowingStorageRestartNotice
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(locale.localized("De wijziging wordt actief nadat je de app volledig hebt afgesloten en opnieuw hebt geopend."))
            }
            .alert(
                locale.localized("Exporteren mislukt"),
                isPresented: Binding(
                    get: { historyExportError != nil },
                    set: { if !$0 { historyExportError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(historyExportError ?? "")
            }
            .alert(
                locale.localized("Meldingen niet beschikbaar"),
                isPresented: Binding(
                    get: { reminderError != nil },
                    set: { if !$0 { reminderError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(reminderError ?? "")
            }
            .alert(
                locale.localized("Oude geschiedenis opruimen?"),
                isPresented: $isConfirmingRetentionChange
            ) {
                Button(locale.localized("Annuleer"), role: .cancel) {
                    pendingHistoryRetention = nil
                }
                Button(locale.localized("Wijzig en ruim op"), role: .destructive) {
                    applyPendingHistoryRetention()
                }
            } message: {
                Text(locale.localized("Items ouder dan de gekozen periode worden verwijderd. Eerst wordt automatisch een volledige veiligheidskopie gemaakt."))
            }
            .alert(
                locale.localized("Afgerond verwijderen?"),
                isPresented: $isConfirmingHistoryDeletion
            ) {
                Button(locale.localized("Annuleer"), role: .cancel) {}
                Button(locale.localized("Verwijder"), role: .destructive) {
                    deleteAllHistory()
                }
            } message: {
                Text(locale.localized("Alle afgeronde en verwijderde items worden definitief verwijderd. Dit kan niet ongedaan worden gemaakt."))
            }
            .alert(
                locale.localized("Verwijderen mislukt"),
                isPresented: Binding(
                    get: { historyDeletionError != nil },
                    set: { if !$0 { historyDeletionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(historyDeletionError ?? "")
            }
            .alert(
                locale.localized("Hele app resetten?"),
                isPresented: $isConfirmingAppReset
            ) {
                Button(locale.localized("Annuleer"), role: .cancel) {}
                Button(locale.localized("Reset alles"), role: .destructive) {
                    resetEntireApp()
                }
            } message: {
                Text(locale.localized("Alle agenda-items, taken, herhalingen, afgeronde items en instellingen worden definitief verwijderd. De app start daarna alsof je hem voor het eerst hebt gedownload."))
            }
            .alert(
                locale.localized("Resetten mislukt"),
                isPresented: Binding(
                    get: { appResetError != nil },
                    set: { if !$0 { appResetError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(appResetError ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickTodoCaptureRequested)) { _ in
                dismiss()
            }
            .onDisappear {
                testReminderCountdownTask?.cancel()
            }
        }
    }

    private var weatherAgendaSelection: Binding<Bool> {
        Binding(
            get: { weatherInAgendaEnabled },
            set: { enabled in
                if enabled {
                    isShowingWeatherSetup = true
                } else {
                    weatherInAgendaEnabled = false
                    weatherLastError = ""
                }
            }
        )
    }

    private var weatherErrorText: String {
        if weatherLastError == AppleWeatherForecastStore.authenticationError {
            return locale.localized("Apple kon deze app niet aanmelden bij WeatherKit. Controleer of WeatherKit voor deze App ID bij zowel App Services als App Capabilities aanstaat. Staat dat al goed, probeer dan later opnieuw; Apple heeft mogelijk een tijdelijke authenticatiestoring.")
        }
        return locale.localizedFormat("Weer kon niet worden geladen: %@", weatherLastError)
    }

    private var historyRetentionSelection: Binding<String> {
        Binding(
            get: { historyRetention },
            set: { newValue in
                guard newValue != historyRetention else { return }
                if newValue == HistoryRetentionOption.never.rawValue {
                    historyRetention = newValue
                } else {
                    pendingHistoryRetention = newValue
                    isConfirmingRetentionChange = true
                }
            }
        )
    }

    private func applyPendingHistoryRetention() {
        guard let rawValue = pendingHistoryRetention,
              let retention = HistoryRetentionOption(rawValue: rawValue) else { return }
        do {
            try HistoryCleanupService.removeExpiredHistory(
                retention: retention,
                from: modelContext
            )
            historyRetention = rawValue
            pendingHistoryRetention = nil
        } catch {
            historyDeletionError = error.localizedDescription
            pendingHistoryRetention = nil
        }
    }

    private func refreshICloudStatus() async {
        let status = await ICloudStatusService.accountStatus()
        iCloudStatusText = ICloudStatusService.warningDescription(for: status, locale: locale)
    }

    private var endOfDayReminderTime: Binding<Date> {
        Binding(
            get: {
                let hour = endOfDayReminderMinutes / 60
                let minute = endOfDayReminderMinutes % 60
                return Calendar.current.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                endOfDayReminderMinutes = (components.hour ?? 21) * 60 + (components.minute ?? 50)
            }
        )
    }

    private func updateEndOfDayReminder(enabled: Bool) {
        guard enabled else {
            EndOfDayReminderService.cancelPendingReminders()
            return
        }

        Task { @MainActor in
            do {
                let granted = try await EndOfDayReminderService.requestAuthorization()
                guard granted else {
                    endOfDayReminderEnabled = false
                    reminderError = locale.localizedFormat("notifications.permission.settings", locale.appDisplayName)
                    return
                }
                rescheduleEndOfDayReminder()
            } catch {
                endOfDayReminderEnabled = false
                reminderError = error.localizedDescription
            }
        }
    }

    private func rescheduleEndOfDayReminder() {
        let entries = (try? modelContext.fetch(FetchDescriptor<DayEntry>(
            predicate: #Predicate { entry in
                !entry.isDone && !entry.isRemoved
            }
        ))) ?? []
        let minutes = endOfDayReminderMinutes

        Task { @MainActor in
            try? await EndOfDayReminderService.reschedule(entries: entries, minutes: minutes)
        }
    }

    private func sendTestReminder() {
        isSendingTestReminder = true
        let entries = (try? modelContext.fetch(FetchDescriptor<DayEntry>(
            predicate: #Predicate { entry in
                !entry.isDone && !entry.isRemoved
            }
        ))) ?? []
        let emptyText = locale.localized("Geen openstaande taken voor vandaag")

        Task { @MainActor in
            defer { isSendingTestReminder = false }
            do {
                let granted = try await EndOfDayReminderService.requestAuthorization()
                guard granted else {
                    reminderError = locale.localizedFormat("notifications.permission.settings", locale.appDisplayName)
                    return
                }
                try await EndOfDayReminderService.sendTestNotification(
                    entries: entries,
                    emptyText: emptyText
                )
                startTestReminderCooldown()
            } catch {
                reminderError = error.localizedDescription
            }
        }
    }

    private func startTestReminderCooldown() {
        testReminderCountdownTask?.cancel()
        withAnimation(.smooth(duration: 0.35)) {
            testReminderCountdown = 5
        }

        testReminderCountdownTask = Task { @MainActor in
            for remaining in stride(from: 4, through: 1, by: -1) {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                withAnimation(.smooth(duration: 0.35)) {
                    testReminderCountdown = remaining
                }
            }

            try? await Task.sleep(for: .seconds(1))
            withAnimation(.smooth(duration: 0.35)) {
                testReminderCountdown = nil
            }
            testReminderCountdownTask = nil
        }
    }

    private func requestCalendarAccess() {
        isRequestingCalendarAccess = true
        calendarError = nil

        Task { @MainActor in
            do {
                let granted = try await CalendarSyncService.requestAccess()
                calendarSyncEnabled = granted

                if !granted {
                    calendarError = locale.localized("Geen toegang. Je kunt dit later wijzigen in iOS-instellingen.")
                }
            } catch {
                calendarSyncEnabled = false
                calendarError = locale.localizedFormat("error.syncFailed", error.localizedDescription)
            }

            isRequestingCalendarAccess = false
        }
    }

    private func syncCalendarNow() {
        isRequestingCalendarAccess = true
        calendarError = nil

        Task { @MainActor in
            do {
                let entries = try modelContext.fetch(FetchDescriptor<DayEntry>())
                let granted = try await CalendarSyncService.requestAccessAndSync(entries: entries)
                calendarSyncEnabled = granted

                if granted {
                    try modelContext.save()
                    calendarLastSyncDate = Date.now.timeIntervalSinceReferenceDate
                } else {
                    calendarError = locale.localized("Geen toegang. Je kunt dit later wijzigen in iOS-instellingen.")
                }
            } catch {
                calendarError = locale.localizedFormat("error.syncFailed", error.localizedDescription)
            }

            isRequestingCalendarAccess = false
        }
    }

    private func exportHistory() {
        let entryDescriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { entry in
                entry.isDone || entry.isRemoved
            },
            sortBy: [SortDescriptor(\DayEntry.date, order: .reverse)]
        )
        let todoDescriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { todo in
                todo.isDone || todo.isRemoved
            },
            sortBy: [SortDescriptor(\TodoItem.createdAt, order: .reverse)]
        )
        let recurringDescriptor = FetchDescriptor<RecurringItem>(
            predicate: #Predicate { item in
                item.isRemoved
            },
            sortBy: [SortDescriptor(\RecurringItem.createdAt, order: .reverse)]
        )
        let entries: [DayEntry]
        let todos: [TodoItem]
        let removedRecurringItems: [RecurringItem]
        do {
            entries = try modelContext.fetch(entryDescriptor)
            todos = try modelContext.fetch(todoDescriptor)
            removedRecurringItems = try modelContext.fetch(recurringDescriptor)
        } catch {
            historyExportError = error.localizedDescription
            return
        }
        let recurringCategoryNames = HistoryCSVDocument.recurringCategoryNames(from: recurringCategoriesData)
        let todoCategoryNames = Dictionary(uniqueKeysWithValues: TodoGroupStore.decode(todoGroupsData).map {
            ($0.id, $0.title)
        })

        let rows = entries.compactMap { entry -> HistoryCSVRow? in
            guard entry.isDone || entry.isRemoved else { return nil }
            let kind: String
            let category: String
            switch entry.source {
            case .recurring:
                kind = AppSection.recurring.title(for: locale)
                let categoryID = entry.accentRawValue == "birthdayReminder"
                    ? RecurringTheme.birthday.rawValue
                    : entry.accentRawValue
                category = recurringCategoryNames[categoryID]
                    ?? HistoryCSVDocument.fallbackRecurringCategoryName(for: categoryID, locale: locale)
            case .manual, .todo:
                kind = AppSection.agenda.title(for: locale)
                category = AppSection.agenda.title(for: locale)
            }
            return HistoryCSVRow(
                content: entry.rawText,
                kind: kind,
                category: category,
                dateTime: entry.completedAt ?? entry.date,
                isDeleted: entry.isRemoved
            )
        } + todos.compactMap { todo -> HistoryCSVRow? in
            guard todo.isDone || todo.isRemoved else { return nil }
            return HistoryCSVRow(
                content: todo.text,
                kind: AppSection.todo.title(for: locale),
                category: todoCategoryNames[todo.bucketRawValue] ?? todo.bucketRawValue,
                dateTime: todo.completedAt ?? todo.createdAt,
                isDeleted: todo.isRemoved
            )
        } + removedRecurringItems.map { item in
            HistoryCSVRow(
                content: item.title,
                kind: AppSection.recurring.title(for: locale),
                category: recurringCategoryNames[item.themeRawValue]
                    ?? HistoryCSVDocument.fallbackRecurringCategoryName(
                        for: item.themeRawValue,
                        locale: locale
                    ),
                dateTime: item.completedAt ?? item.createdAt,
                isDeleted: true
            )
        }

        historyExportDocument = HistoryCSVDocument(rows: rows.sorted { $0.dateTime > $1.dateTime })
        historyExportFilename = HistoryCSVDocument.uniqueFilename(at: .now)
        isExportingHistory = true
    }

    private func deleteAllHistory() {
        do {
            try HistoryCleanupService.removeAllHistory(from: modelContext)
        } catch {
            historyDeletionError = error.localizedDescription
        }
    }

    private func resetEntireApp() {
        do {
            try AppResetService.reset(modelContext: modelContext)
        } catch {
            appResetError = error.localizedDescription
        }
    }
}

private struct WeatherAgendaSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var resolver = WeatherLocationResolver()
    @State private var place = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    let completed: (CLLocation, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(locale.localizedFormat("weather.location.explanation", locale.appDisplayName))
                        .foregroundStyle(.secondary)

                    Button(action: useCurrentLocation) {
                        Label(
                            locale.localized("Gebruik mijn huidige locatie"),
                            systemImage: "location.fill"
                        )
                    }
                    .disabled(isWorking)
                } footer: {
                    Text(locale.localized("Je locatie wordt alleen gebruikt om het weer op te halen. De gekozen plaats wordt op dit apparaat bewaard."))
                }

                Section(locale.localized("Of stel zelf een plaats in")) {
                    TextField(
                        locale.localized("Plaats, bijvoorbeeld Amsterdam"),
                        text: $place
                    )
                    .textContentType(.addressCity)
                    .submitLabel(.done)
                    .onSubmit(useEnteredPlace)

                    Button(action: useEnteredPlace) {
                        Label(locale.localized("Gebruik deze plaats"), systemImage: "magnifyingglass")
                    }
                    .disabled(isWorking || place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if isWorking {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(locale.localized("Locatie bepalen…"))
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(locale.localized("Weerlocatie"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(locale.localized("Annuleer")) { dismiss() }
                        .disabled(isWorking)
                }
            }
        }
    }

    private func useCurrentLocation() {
        perform {
            let location = try await resolver.requestCurrentLocation()
            let name = await resolver.name(for: location)
            finish(location: location, name: name)
        }
    }

    private func useEnteredPlace() {
        perform {
            let result = try await resolver.geocode(place: place)
            finish(location: result.location, name: result.name)
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func finish(location: CLLocation, name: String) {
        completed(location, name)
        dismiss()
    }
}

private struct PulsingActionButtonIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        Image(systemName: "button.programmable")
            .foregroundStyle(Color.brandHardBlue)
            .scaleEffect(reduceMotion ? 1 : (isExpanded ? 1.14 : 0.94))
            .opacity(reduceMotion ? 1 : (isExpanded ? 1 : 0.68))
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.15).repeatForever(autoreverses: true),
                value: isExpanded
            )
            .onAppear {
                isExpanded = !reduceMotion
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                isExpanded = !shouldReduceMotion
            }
            .accessibilityHidden(true)
    }
}

private struct ActionButtonSettingsView: View {
    @Environment(\.locale)
    private var locale

    @AppStorage(SettingsKeys.actionButtonContent)
    private var content = ActionButtonContentOption.today.rawValue

    @AppStorage(SettingsKeys.actionButtonDatePrefix)
    private var datePrefix = ActionButtonDatePrefixOption.date.rawValue

    @AppStorage(SettingsKeys.actionButtonItemCount)
    private var itemCount = 3

    @AppStorage(SettingsKeys.lockScreenWordTruncation)
    private var wordTruncation = LockScreenWordTruncationOption.ellipsis.rawValue

    private var selectedContent: ActionButtonContentOption {
        ActionButtonContentOption(rawValue: content) ?? .today
    }

    private var selectedDatePrefix: ActionButtonDatePrefixOption {
        ActionButtonDatePrefixOption(rawValue: datePrefix) ?? .date
    }

    private var selectedWordTruncation: LockScreenWordTruncationOption {
        LockScreenWordTruncationOption(rawValue: wordTruncation) ?? .ellipsis
    }

    var body: some View {
        Form {
            Section {
                Text(locale.localizedFormat("lockscreen.widget.instructions", locale.appDisplayName))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Aantal weergeven") {
                Picker("Aantal", selection: $itemCount) {
                    ForEach([3, 4, 5], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Weergave") {
                Picker("Inhoud", selection: $content) {
                    ForEach(ActionButtonContentOption.allCases) { option in
                        Text(option.title(for: locale)).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .tint(.primary)
            }

            Section("Tekst") {
                HStack {
                    Text("Woorden afsnijden")
                        .foregroundStyle(.primary)

                    Spacer()

                    Menu {
                        ForEach(LockScreenWordTruncationOption.allCases) { option in
                            Button {
                                wordTruncation = option.rawValue
                            } label: {
                                if option == selectedWordTruncation {
                                    Label(option.title(for: locale), systemImage: "checkmark")
                                } else {
                                    Text(option.title(for: locale))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(selectedWordTruncation.title(for: locale))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                }

                if selectedContent == .todayAndTomorrow {
                    HStack {
                        Text("Voorvoegsel")
                            .foregroundStyle(.primary)

                        Spacer()

                        Menu {
                            ForEach(ActionButtonDatePrefixOption.allCases) { option in
                                Button {
                                    datePrefix = option.rawValue
                                } label: {
                                    if option == selectedDatePrefix {
                                        Label(option.title(for: locale), systemImage: "checkmark")
                                    } else {
                                        Text(option.title(for: locale))
                                    }
                                }
                            }
                        } label: {
                            Text(selectedDatePrefix.selectionTitle(for: locale))
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .navigationTitle("Lockscreen-widget")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if ActionButtonContentOption(rawValue: content) == nil {
                content = ActionButtonContentOption.today.rawValue
            }
        }
    }
}

private struct HomeWidgetSettingsView: View {
    @Environment(\.locale) private var locale

    @AppStorage(SettingsKeys.homeWidgetContent)
    private var content = HomeWidgetContentOption.combined.rawValue
    @AppStorage(SettingsKeys.homeWidgetCalendarRange)
    private var calendarRange = HomeWidgetCalendarRangeOption.today.rawValue
    @AppStorage(SettingsKeys.homeWidgetDatePrefix)
    private var datePrefix = ActionButtonDatePrefixOption.date.rawValue
    @AppStorage(SettingsKeys.homeWidgetTextFlow)
    private var textFlow = HomeWidgetTextFlowOption.truncate.rawValue
    @AppStorage(SettingsKeys.homeWidgetShowsTitle)
    private var showsTitle = true
    @AppStorage(SettingsKeys.homeWidgetBackground)
    private var background = HomeWidgetBackgroundOption.brandLightBlue.rawValue
    @AppStorage(SettingsKeys.homeWidgetShowsOtherWhenEmpty)
    private var showsOtherWhenEmpty = true
    @AppStorage(SettingsKeys.homeWidgetTodoCategoryID)
    private var todoCategoryID = ""
    @AppStorage(SettingsKeys.todoGroups)
    private var todoGroupsData = ""

    private var todoGroups: [TodoGroup] {
        TodoGroupStore.decode(todoGroupsData)
    }

    private var usesLightBlueBackground: Binding<Bool> {
        Binding(
            get: { background != HomeWidgetBackgroundOption.white.rawValue },
            set: { background = $0
                ? HomeWidgetBackgroundOption.brandLightBlue.rawValue
                : HomeWidgetBackgroundOption.white.rawValue
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Inhoud", selection: $content) {
                    ForEach(HomeWidgetContentOption.allCases) { option in
                        Text(option.title(for: locale))
                            .foregroundStyle(.primary)
                            .tag(option.rawValue)
                    }
                }
                .tint(.primary)

                Picker("Kalenderperiode", selection: $calendarRange) {
                    ForEach(HomeWidgetCalendarRangeOption.allCases) { option in
                        Text(option.title(for: locale))
                            .foregroundStyle(.primary)
                            .tag(option.rawValue)
                    }
                }
                .tint(.primary)

                Picker("Datumweergave", selection: $datePrefix) {
                    Text("0 = vandaag, 1 = morgen")
                        .foregroundStyle(.primary)
                        .tag(ActionButtonDatePrefixOption.dayCount.rawValue)
                    Text("Datum (dd/mm)")
                        .foregroundStyle(.primary)
                        .tag(ActionButtonDatePrefixOption.date.rawValue)
                }
                .tint(.primary)

                Picker("Takenweergave", selection: $todoCategoryID) {
                    Text("Bovenste taken")
                        .foregroundStyle(.primary)
                        .tag("")
                    ForEach(todoGroups) { group in
                        Text(group.title)
                            .foregroundStyle(.primary)
                            .tag(group.id)
                    }
                }
                .tint(.primary)

                Picker("Lange tekst", selection: $textFlow) {
                    ForEach([HomeWidgetTextFlowOption.wrap, .truncate]) { option in
                        Text(option.title(for: locale))
                            .foregroundStyle(.primary)
                            .tag(option.rawValue)
                    }
                }
                .tint(.primary)

                Toggle("Titel laten zien", isOn: $showsTitle)
                Toggle("Lichtblauwe widgetkleur", isOn: usesLightBlueBackground)
                Toggle("Slimme weergave", isOn: $showsOtherWhenEmpty)
            } footer: {
                Text("Bij slimme weergave worden Taken over de volledige breedte getoond als er geen kalenderitems zijn, en andersom. Zo wordt er minder snel tekst afgesneden.")

            }
        }
        .navigationTitle("Beginscherm-widget")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ActionButtonCaptureSettingsView: View {
    private static let calendarDestinationID = "__actionButtonCalendarToday"

    @Environment(\.locale)
    private var locale

    @AppStorage(SettingsKeys.actionButtonDefaultDestination)
    private var destination = ActionButtonDefaultDestination.topTodoCategory.rawValue

    @AppStorage(SettingsKeys.actionButtonTaskCategoryID)
    private var taskCategoryID = ""

    @AppStorage(SettingsKeys.todoGroups)
    private var todoGroupsData = ""

    @AppStorage(SettingsKeys.actionButtonStartsVoiceRecording)
    private var startsVoiceRecording = false

    @AppStorage(SettingsKeys.actionButtonLaunchMode)
    private var launchMode = ActionButtonLaunchMode.quickField.rawValue

    private var selectedLaunchMode: ActionButtonLaunchMode {
        ActionButtonLaunchMode(rawValue: launchMode) ?? .quickField
    }

    private var groups: [TodoGroup] {
        TodoGroupStore.decode(todoGroupsData)
    }

    private var destinationBinding: Binding<String> {
        Binding(
            get: {
                if destination == ActionButtonDefaultDestination.calendarToday.rawValue {
                    return Self.calendarDestinationID
                }
                if groups.contains(where: { $0.id == taskCategoryID }) {
                    return taskCategoryID
                }
                return groups.first?.id ?? TodoGroupStore.defaults[0].id
            },
            set: { selectedID in
                if selectedID == Self.calendarDestinationID {
                    destination = ActionButtonDefaultDestination.calendarToday.rawValue
                } else {
                    destination = ActionButtonDefaultDestination.topTodoCategory.rawValue
                    taskCategoryID = selectedID
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Text(locale.localized("De Actieknop is alleen beschikbaar op iPhone 15 Pro en nieuwere modellen. Stel op je iPhone bij Instellingen › Actieknop › Opdracht de opdracht ‘Nieuwe taak’ in."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Bij indrukken") {
                Picker("Openen", selection: $launchMode) {
                    ForEach(ActionButtonLaunchMode.allCases) { option in
                        Text(option.title(for: locale)).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .tint(.primary)
            }

            Section("Standaardbestemming") {
                Picker("Bestemming", selection: destinationBinding) {
                    ForEach(groups) { group in
                        Label(group.title, systemImage: group.icon)
                            .tag(group.id)
                    }

                    Label("Kalender vandaag", systemImage: "calendar")
                        .tag(Self.calendarDestinationID)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .tint(.primary)
            }

            if selectedLaunchMode == .fullApp {
                Section("Spraakinvoer") {
                    Toggle("Direct spraak opnemen", isOn: $startsVoiceRecording)
                }
            }
        }
        .navigationTitle("Actieknop")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            _ = AppModelStore.load()
            QuickCapturePreparation.prepareConfirmation()
        }
        .onChange(of: destination) { _, _ in
            QuickCapturePreparation.prepareConfirmation()
        }
        .onChange(of: taskCategoryID) { _, _ in
            QuickCapturePreparation.prepareConfirmation()
        }
        .onChange(of: todoGroupsData) { _, _ in
            QuickCapturePreparation.prepareConfirmation()
        }
        .onChange(of: locale.identifier) { _, _ in
            QuickCapturePreparation.prepareConfirmation()
        }
    }
}
