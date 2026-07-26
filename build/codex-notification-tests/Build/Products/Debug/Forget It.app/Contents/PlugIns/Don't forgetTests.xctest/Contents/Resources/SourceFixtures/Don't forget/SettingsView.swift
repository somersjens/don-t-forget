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

    @AppStorage(SettingsKeys.weekdayLabelLength)
    private var weekdayLabelLength = WeekdayLabelLengthOption.one.rawValue

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

    @AppStorage(SettingsKeys.defaultColorCombinationEnabled)
    private var defaultColorCombinationEnabled = true

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

    @AppStorage(SettingsKeys.weatherLastErrorDetails)
    private var weatherLastErrorDetails = ""

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
    @State private var appActivityState = AppActivityState.shared

    private var hasCalendarRowsAfterWeather: Bool {
        isRequestingCalendarAccess || calendarError != nil || calendarSyncEnabled
    }

    private var settingsIntegrationTailPosition: SettingsCardRowPosition {
        !weatherInAgendaEnabled && !hasCalendarRowsAfterWeather ? .last : .middle
    }

    private var weatherLocationTailPosition: SettingsCardRowPosition {
        weatherLastError.isEmpty && !hasCalendarRowsAfterWeather ? .last : .middle
    }

    private var weatherErrorTailPosition: SettingsCardRowPosition {
        !hasCalendarRowsAfterWeather ? .last : .middle
    }

    private var calendarProgressTailPosition: SettingsCardRowPosition {
        calendarError == nil && !calendarSyncEnabled ? .last : .middle
    }

    private var calendarErrorTailPosition: SettingsCardRowPosition {
        calendarSyncEnabled ? .middle : .last
    }

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
                    .settingsCardRow(.first)

                    NavigationLink {
                        ActionButtonSettingsView()
                    } label: {
                        Label("Lockscreen-widget configureren", systemImage: "rectangle.on.rectangle")
                    }
                    .settingsCardRow(.middle)

                    NavigationLink {
                        HomeWidgetSettingsView()
                    } label: {
                        Label("Beginscherm-widget configureren", systemImage: "rectangle.split.2x1")
                    }
                    .settingsCardRow(.last)

                }

                Section {
                    Picker(languagePickerTitle, selection: $language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title(for: locale)).tag(language.rawValue)
                        }
                    }
                    .tint(Color.appPrimaryText)
                    .settingsCardRow(.first)

                    Picker(
                        locale.localized("App Color"),
                        selection: $defaultColorCombinationEnabled
                    ) {
                        Text(locale.localized("Light blue")).tag(true)
                        Text(locale.localized("Grey")).tag(false)
                    }
                    .tint(Color.appPrimaryText)
                    .settingsCardRow(.middle)

                    Picker("Week begint op", selection: $weekStart) {
                        ForEach(WeekStartOption.allCases) { option in
                            Text(option.title(for: locale)).tag(option.rawValue)
                        }
                    }
                    .tint(Color.appPrimaryText)
                    .settingsCardRow(.middle)

                    Picker(weekdayFormattingPickerTitle, selection: $weekdayLabelLength) {
                        ForEach(WeekdayLabelLengthOption.allCases) { option in
                            Text(option.title(for: locale)).tag(option.rawValue)
                        }
                    }
                    .tint(Color.appPrimaryText)
                    .onAppear(perform: normalizeWeekdayLabelLength)
                    .settingsCardRow(.middle)

                    Picker("Weeknummering", selection: $weekNumberRule) {
                        ForEach(WeekNumberRule.allCases) { rule in
                            Text(rule.title(for: locale)).tag(rule.rawValue)
                        }
                    }
                    .tint(Color.appPrimaryText)
                    .settingsCardRow(.middle)

                    Picker(locale.localized("Datum formattering"), selection: $dateFormat) {
                        let localeDefault = DateFormatOption.localeDefault(for: locale)
                        ForEach(DateFormatOption.allCases) { option in
                            Text(option.title(for: locale, localeDefault: localeDefault))
                                .tag(option.rawValue)
                        }
                    }
                    .tint(Color.appPrimaryText)
                    .settingsCardRow(.middle)

                    Picker(
                        locale.localized("Afgerond opschonen"),
                        selection: historyRetentionSelection
                    ) {
                        ForEach(HistoryRetentionOption.allCases) { option in
                            Text(option.title(for: locale)).tag(option.rawValue)
                        }
                    }
                    .tint(Color.appPrimaryText)
                    .settingsCardRow(.middle)

                    Picker(
                        locale.localized("Agenda vooruit laden"),
                        selection: $recurringHorizon
                    ) {
                        ForEach(RecurringHorizonOption.allCases) { option in
                            Text(option.title(for: locale)).tag(option.rawValue)
                        }
                    }
                    .tint(Color.appPrimaryText)
                    .onChange(of: recurringHorizon) { _, _ in
                        recurringExtendedThrough = 0
                        recurringLastSyncSignature = ""
                    }
                    .settingsCardRow(.last)

                }

                Section {
                    Toggle(
                        locale.localized("Einde-dagherinnering"),
                        isOn: $endOfDayReminderEnabled
                    )
                    .onChange(of: endOfDayReminderEnabled) { _, enabled in
                        updateEndOfDayReminder(enabled: enabled)
                    }
                    .settingsCardRow(.first)

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
                    .settingsCardRow(.middle)

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
                    .settingsCardRow(.last)
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
                    .settingsCardRow(.first)

                    Toggle("Verwijderde items tonen", isOn: $historyShowsDeletedItems)
                        .settingsCardRow(.middle)

                    Toggle("Synchroniseer met iPhone Kalender", isOn: $calendarSyncEnabled)
                        .disabled(isRequestingCalendarAccess)
                        .onChange(of: calendarSyncEnabled) { _, enabled in
                            guard enabled else { return }
                            requestCalendarAccess()
                        }
                        .settingsCardRow(.middle)

                    Toggle(
                        locale.localized("Weer bij toekomstige dagen"),
                        isOn: weatherAgendaSelection
                    )
                    .settingsCardRow(settingsIntegrationTailPosition)

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
                        .settingsCardRow(weatherLocationTailPosition)

                        if !weatherLastError.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(
                                    weatherErrorText,
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.footnote)
                                .foregroundStyle(.orange)

                                if !weatherLastErrorDetails.isEmpty {
                                    Text(weatherLastErrorDetails)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

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
                                    weatherLastErrorDetails = ""
                                    weatherReloadToken += 1
                                }
                                .font(.footnote.weight(.semibold))
                            }
                            .settingsCardRow(weatherErrorTailPosition)
                        }
                    }

                    if isRequestingCalendarAccess {
                        ProgressView("Kalender synchroniseren…")
                            .settingsCardRow(calendarProgressTailPosition)
                    }

                    if let calendarError {
                        Label(calendarError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .settingsCardRow(calendarErrorTailPosition)
                    }

                    if calendarSyncEnabled {
                        Button {
                            syncCalendarNow()
                        } label: {
                            Label("Synchroniseer nu", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isRequestingCalendarAccess)
                        .settingsCardRow(.last)
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
                    .settingsCardRow(.first)

                    Button(action: exportHistory) {
                        Label(
                            locale.localized("Afgeronde items downloaden als CSV"),
                            systemImage: "arrow.down.doc"
                        )
                    }
                    .settingsCardRow(.last)
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
                    .settingsCardRow(.single)
                }
            }
            .appFormBackground(lightBlueEnabled: defaultColorCombinationEnabled)
            .tint(.brandHardBlue)
            .onChange(of: defaultColorCombinationEnabled) { _, _ in
                appActivityState.begin(.themeChange)
                appActivityState.finish(.themeChange, after: .milliseconds(900))
            }
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
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        AppActivityIndicator()
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        AppActivityIndicator()
                    }
                }
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
                    weatherLastErrorDetails = ""
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

    private func normalizeWeekdayLabelLength() {
        guard WeekdayLabelLengthOption(rawValue: weekdayLabelLength) == nil else { return }
        weekdayLabelLength = WeekdayLabelLengthOption.one.rawValue
    }

    private var languagePickerTitle: String {
        locale.localized("settings.language")
    }

    private var weekdayFormattingPickerTitle: String {
        locale.localized("settings.weekdayFormatting")
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
                    weatherLastErrorDetails = ""
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
        appActivityState.begin(.calendarSync)
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
            appActivityState.finish(.calendarSync)
        }
    }

    private func syncCalendarNow() {
        isRequestingCalendarAccess = true
        appActivityState.begin(.calendarSync)
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
            appActivityState.finish(.calendarSync)
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
                        .settingsCardRow(.first)

                    Button(action: useCurrentLocation) {
                        Label(
                            locale.localized("Gebruik mijn huidige locatie"),
                            systemImage: "location.fill"
                        )
                    }
                    .disabled(isWorking)
                    .settingsCardRow(.last)
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
                    .settingsCardRow(.first)

                    Button(action: useEnteredPlace) {
                        Label(locale.localized("Gebruik deze plaats"), systemImage: "magnifyingglass")
                    }
                    .disabled(isWorking || place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .settingsCardRow(.last)
                }

                if isWorking {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(locale.localized("Locatie bepalen…"))
                        }
                        .settingsCardRow(.single)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .settingsCardRow(.single)
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

    @AppStorage(SettingsKeys.dateFormat)
    private var dateFormat = DateFormatOption.system.rawValue

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

    private var selectedDateFormatTitle: String {
        let localeDefault = DateFormatOption.localeDefault(for: locale)
        let option = DateFormatOption.resolved(from: dateFormat)
        return option == .system ? localeDefault.displayTitle : option.displayTitle
    }

    private var datePrefixTitle: String {
        "\(locale.localized("Datum")) (\(selectedDateFormatTitle))"
    }

    var body: some View {
        Form {
            Section {
                Text(locale.localizedFormat("lockscreen.widget.instructions", locale.appDisplayName))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .settingsCardRow(.single)
            }

            Section("Aantal weergeven") {
                Picker("Aantal", selection: $itemCount) {
                    ForEach([3, 4, 5], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .settingsCardRow(.single)
            }

            Section("Voorbeeld") {
                LockScreenWidgetSettingsPreview(
                    content: selectedContent,
                    datePrefix: selectedDatePrefix,
                    itemCount: itemCount,
                    wordTruncation: selectedWordTruncation,
                    dateFormat: DateFormatOption.resolved(from: dateFormat),
                    locale: locale
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .settingsCardRow(.single)
            }

            Section("Weergave") {
                let options = ActionButtonContentOption.allCases
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button {
                        content = option.rawValue
                    } label: {
                        HStack {
                            Text(option.title(for: locale))
                            Spacer()
                            if option == selectedContent {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.brandHardBlue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appPrimaryText)
                    .settingsCardRow(.row(at: index, count: options.count))
                }
            }

            Section("Tekst") {
                HStack {
                    Text("Woorden afsnijden")
                        .foregroundStyle(Color.appPrimaryText)

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
                    .tint(Color.appPrimaryText)
                }
                .settingsCardRow(selectedContent == .todayAndTomorrow ? .first : .single)

                if selectedContent == .todayAndTomorrow {
                    HStack {
                        Text("Voorvoegsel")
                            .foregroundStyle(Color.appPrimaryText)

                        Spacer()

                        Menu {
                            ForEach(ActionButtonDatePrefixOption.allCases) { option in
                                Button {
                                    datePrefix = option.rawValue
                                } label: {
                                    if option == selectedDatePrefix {
                                        Label(
                                            option == .date ? datePrefixTitle : option.title(for: locale),
                                            systemImage: "checkmark"
                                        )
                                    } else {
                                        Text(option == .date ? datePrefixTitle : option.title(for: locale))
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(selectedDatePrefix == .date
                                     ? datePrefixTitle
                                     : selectedDatePrefix.title(for: locale))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(Color.appPrimaryText)
                    }
                    .settingsCardRow(.last)
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

private enum WidgetPreviewData {
    struct CalendarItem: Identifiable {
        let id: Int
        let titleKey: String
        let dayOffset: Int
        let color: Color
    }

    struct TaskItem: Identifiable {
        let id: Int
        let titleKey: String
        let ageInDays: Int
        let categoryIndex: Int
        let color: Color
    }

    static let calendar: [CalendarItem] = [
        CalendarItem(id: 1, titleKey: "widget.preview.calendar.jobInterview", dayOffset: 0, color: .blue),
        CalendarItem(id: 2, titleKey: "widget.preview.calendar.dinnerWithFriends", dayOffset: 0, color: .pink),
        CalendarItem(id: 3, titleKey: "widget.preview.calendar.tattooAppointment", dayOffset: 1, color: .orange),
        CalendarItem(id: 4, titleKey: "widget.preview.calendar.justinBieber", dayOffset: 1, color: .indigo),
        CalendarItem(id: 5, titleKey: "widget.preview.calendar.blindDate", dayOffset: 2, color: .purple),
        CalendarItem(id: 6, titleKey: "widget.preview.calendar.gymSession", dayOffset: 2, color: .green),
        CalendarItem(id: 7, titleKey: "widget.preview.calendar.karaokeBattle", dayOffset: 3, color: .pink),
        CalendarItem(id: 8, titleKey: "widget.preview.calendar.bungeeJumping", dayOffset: 3, color: .orange),
        CalendarItem(id: 9, titleKey: "widget.preview.calendar.rooftopParty", dayOffset: 4, color: .indigo),
        CalendarItem(id: 10, titleKey: "widget.preview.calendar.pizzaTasting", dayOffset: 4, color: .red)
    ]

    static let tasks: [TaskItem] = [
        TaskItem(id: 1, titleKey: "widget.preview.task.cleanHouse", ageInDays: 0, categoryIndex: 0, color: .orange),
        TaskItem(id: 2, titleKey: "widget.preview.task.deleteSocialMedia", ageInDays: 4, categoryIndex: 0, color: .orange),
        TaskItem(id: 3, titleKey: "widget.preview.task.annualShower", ageInDays: 7, categoryIndex: 0, color: .orange),
        TaskItem(id: 4, titleKey: "widget.preview.task.printPhotos", ageInDays: 8, categoryIndex: 0, color: .orange),
        TaskItem(id: 5, titleKey: "widget.preview.task.finishPlaylist", ageInDays: 14, categoryIndex: 1, color: .indigo),
        TaskItem(id: 6, titleKey: "widget.preview.task.replyFanMail", ageInDays: 22, categoryIndex: 1, color: .indigo),
        TaskItem(id: 7, titleKey: "widget.preview.task.planRoadTrip", ageInDays: 34, categoryIndex: 1, color: .indigo),
        TaskItem(id: 8, titleKey: "widget.preview.task.newRecipe", ageInDays: 34, categoryIndex: 1, color: .indigo),
        TaskItem(id: 9, titleKey: "widget.preview.task.newHobby", ageInDays: 40, categoryIndex: 1, color: .indigo),
        TaskItem(id: 10, titleKey: "widget.preview.task.sellClothes", ageInDays: 80, categoryIndex: 1, color: .indigo)
    ]
}

private enum HomeWidgetPreviewFamily: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    func title(for locale: Locale) -> String {
        switch self {
        case .small: locale.localized("Klein")
        case .medium: locale.localized("Rechthoek")
        case .large: locale.localized("Groot")
        }
    }

    var size: CGSize {
        switch self {
        case .small: CGSize(width: 148, height: 148)
        case .medium: CGSize(width: 310, height: 145)
        case .large: CGSize(width: 300, height: 300)
        }
    }

    var rowCount: Int { self == .large ? 9 : (self == .small ? 2 : 5) }
}

private struct HomeWidgetSettingsPreview: View {
    @Environment(\.colorScheme) private var colorScheme

    let family: HomeWidgetPreviewFamily
    let content: HomeWidgetContentOption
    let calendarRange: HomeWidgetCalendarRangeOption
    let datePrefix: ActionButtonDatePrefixOption
    let dateFormat: DateFormatOption
    let todoCategoryID: String
    let todoGroups: [TodoGroup]
    let locale: Locale
    let wrapsText: Bool
    let showsTitle: Bool
    let usesLightBlueBackground: Bool
    let showsOtherWhenEmpty: Bool

    private var calendarItems: [(String, String, Color)] {
        let maximumOffset = calendarRange == .today ? 0 : (calendarRange == .todayAndTomorrow ? 1 : Int.max)
        return WidgetPreviewData.calendar.filter { $0.dayOffset <= maximumOffset }.map {
            (calendarPrefix(dayOffset: $0.dayOffset), locale.localized($0.titleKey), $0.color)
        }
    }

    private var todoItems: [(String, String, Color)] {
        let selectedIndex = todoGroups.firstIndex { $0.id == todoCategoryID }
        return WidgetPreviewData.tasks.filter { selectedIndex == nil || $0.categoryIndex == selectedIndex }.map {
            ("\($0.ageInDays)d", locale.localized($0.titleKey), $0.color)
        }
    }

    var body: some View {
        Group {
            if family == .large {
                largePreviewContent
            } else if showsOtherWhenEmpty, todoItems.isEmpty, content != .calendar, !calendarItems.isEmpty {
                previewColumn(
                    title: locale.localized("Geen open taken ✓"),
                    items: calendarItems,
                    maximum: previewRowCount,
                    calendar: true
                )
            } else if family == .small && content == .combined {
                VStack(alignment: .leading, spacing: 7) {
                    previewColumn(title: "Kalender", items: calendarItems, maximum: wrapsText ? 1 : 2, calendar: true)
                    Divider().opacity(0.45)
                    previewColumn(title: "Taken", items: todoItems, maximum: wrapsText ? 1 : 2, calendar: false)
                }
            } else if content == .combined {
                HStack(spacing: 10) {
                    previewColumn(title: "Kalender", items: calendarItems, maximum: previewRowCount, calendar: true)
                    Divider()
                    previewColumn(title: "Taken", items: todoItems, maximum: previewRowCount, calendar: false)
                }
            } else if content == .calendar {
                previewColumn(title: "Kalender", items: calendarItems, maximum: previewRowCount, calendar: true)
            } else {
                previewColumn(title: "Taken", items: todoItems, maximum: previewRowCount, calendar: false)
            }
        }
        .foregroundStyle(previewPrimaryTextColor)
        .padding(14)
        .frame(width: family.size.width, height: family.size.height, alignment: .topLeading)
        .background {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 35 / 255, green: 38 / 255, blue: 44 / 255),
                        Color(red: 10 / 255, green: 11 / 255, blue: 14 / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                usesLightBlueBackground
                    ? Color(red: 207 / 255, green: 224 / 255, blue: 247 / 255)
                    : Color.white
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
        .id(family)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var previewRowCount: Int {
        if wrapsText {
            return family == .large ? 7 : 3
        }
        return family.rowCount
    }

    private var previewPrimaryTextColor: Color {
        colorScheme == .dark && usesLightBlueBackground
            ? Color.brandDarkModeTextBlue
            : Color.primary
    }

    private var largePreviewContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            if showsTitle {
                HomeWidgetPreviewHeader(locale: locale)
                    .frame(height: (family.size.height - 28) * 0.12)

                Rectangle()
                    .fill(.secondary.opacity(0.16))
                    .frame(height: 1)
            }

            Group {
                if content == .combined {
                    HStack(alignment: .top, spacing: 10) {
                        previewColumn(
                            title: "Kalender",
                            items: calendarItems,
                            maximum: previewRowCount,
                            calendar: true,
                            showsAddButton: true
                        )
                        Rectangle()
                            .fill(.secondary.opacity(0.18))
                            .frame(width: 1)
                        previewColumn(
                            title: "Taken",
                            items: todoItems,
                            maximum: previewRowCount,
                            calendar: false,
                            showsAddButton: true
                        )
                    }
                } else if content == .calendar {
                    previewColumn(
                        title: "Kalender",
                        items: calendarItems,
                        maximum: previewRowCount,
                        calendar: true,
                        showsAddButton: true
                    )
                } else {
                    previewColumn(
                        title: "Taken",
                        items: todoItems,
                        maximum: previewRowCount,
                        calendar: false,
                        showsAddButton: true
                    )
                }
            }
        }
    }

    private func previewColumn(
        title: String,
        items: [(String, String, Color)],
        maximum: Int,
        calendar: Bool,
        showsAddButton: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsTitle {
                HStack(spacing: 5) {
                    Text(locale.localized(title))
                        .font(.system(size: showsAddButton ? 15 : 12, weight: .bold))
                    if showsAddButton && showsTitle {
                        Spacer(minLength: 4)
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 20, height: 20)
                    }
                }
                .foregroundStyle(Color(red: 59 / 255, green: 134 / 255, blue: 247 / 255))
            }
            ForEach(Array(items.prefix(maximum).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    PreviewDatePrefixText(
                        text: item.0,
                        visiblePrefixes: Array(items.prefix(maximum).map(\.0)),
                        color: calendar ? .secondary : item.2
                    )
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .fixedSize()
                    Text(item.1)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(wrapsText ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: wrapsText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func calendarPrefix(dayOffset: Int) -> String {
        guard datePrefix == .date else { return "\(dayOffset)" }
        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = dateFormat.dateFormat ?? DateFormatOption.localeDefault(for: locale).dateFormat ?? "dd/MM"
        return formatter.string(from: date)
    }
}

private struct PreviewDatePrefixText: View {
    let text: String
    let visiblePrefixes: [String]
    let color: Color

    var body: some View {
        Group {
            if isTaskAge {
                HStack(spacing: 0) {
                    ZStack(alignment: .trailing) {
                        ForEach(Array(Set(visiblePrefixes.map { String($0.dropLast()) })), id: \.self) { value in
                            Text(value)
                                .monospacedDigit()
                                .foregroundStyle(color)
                                .opacity(0)
                        }
                        Text(String(text.dropLast()))
                            .monospacedDigit()
                            .foregroundStyle(color)
                    }
                    Text("d")
                        .foregroundStyle(color)
                }
            } else {
                ZStack(alignment: .trailing) {
                    ForEach(Array(Set(visiblePrefixes)), id: \.self) { prefix in
                        Text(prefix)
                            .foregroundStyle(color)
                            .opacity(0)
                    }
                    Text(text)
                        .foregroundStyle(color)
                }
            }
        }
        .accessibilityLabel(text)
    }

    private var isTaskAge: Bool {
        text.hasSuffix("d") && visiblePrefixes.allSatisfy { $0.hasSuffix("d") }
    }
}

private struct HomeWidgetPreviewHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let locale: Locale

    private let brandBlue = Color(red: 59 / 255, green: 134 / 255, blue: 247 / 255)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text(dateTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text(weekTitle.uppercased(with: locale))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5.5)
                    .background(brandBlue.opacity(colorScheme == .dark ? 0.22 : 0.12), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(brandBlue.opacity(0.10), lineWidth: 0.5)
                    }
            }

            Text("\(dateTitle), \(weekTitle)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(brandBlue)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel("\(dateTitle), \(weekTitle)")
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        let text = formatter.string(from: .now)
        return text.prefix(1).uppercased(with: locale) + String(text.dropFirst())
    }

    private var weekTitle: String {
        var calendar = Calendar.current
        calendar.locale = locale
        return "week \(calendar.component(.weekOfYear, from: .now))"
    }
}

private struct LockScreenWidgetSettingsPreview: View {
    let content: ActionButtonContentOption
    let datePrefix: ActionButtonDatePrefixOption
    let itemCount: Int
    let wordTruncation: LockScreenWordTruncationOption
    let dateFormat: DateFormatOption
    let locale: Locale

    private struct PreviewItem: Identifiable {
        let id = UUID()
        let title: String
        let dayOffset: Int
    }

    private var items: [PreviewItem] {
        let calendarItems = WidgetPreviewData.calendar.map {
            PreviewItem(title: locale.localized($0.titleKey), dayOffset: $0.dayOffset)
        }
        let todoItems = WidgetPreviewData.tasks.map {
            PreviewItem(title: locale.localized($0.titleKey), dayOffset: 0)
        }

        if content == .todo {
            return Array(todoItems.prefix(itemCount))
        }
        if content == .today {
            return Array(calendarItems.prefix(itemCount)).map {
                PreviewItem(title: $0.title, dayOffset: 0)
            }
        }
        return Array(calendarItems.filter { $0.dayOffset <= 1 }.prefix(itemCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(items) { item in
                HStack(alignment: .center, spacing: 2) {
                    if let prefix = prefix(for: item) {
                        Text(prefix)
                            .font(.system(size: prefixFontSize, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.blue)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text(displayedTitle(item.title))
                        .font(.system(size: fontSize, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.97)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var fontSize: CGFloat {
        switch itemCount {
        case 0...2: 14
        case 3: 13
        case 4: 11.5
        default: 9.5
        }
    }

    private var prefixFontSize: CGFloat {
        max(8.5, fontSize - 1)
    }

    private var rowSpacing: CGFloat {
        switch itemCount {
        case 0...3: 2
        case 4: 1
        default: 0
        }
    }

    private func prefix(for item: PreviewItem) -> String? {
        guard content == .todayAndTomorrow else { return nil }
        switch datePrefix {
        case .date:
            return formattedDate(dayOffset: item.dayOffset)
        case .dayCount:
            return "\(item.dayOffset)"
        }
    }

    private func formattedDate(dayOffset: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = resolvedDateFormat
        return formatter.string(from: date)
    }

    private var resolvedDateFormat: String {
        if let format = dateFormat.dateFormat {
            return format
        }
        return DateFormatOption.localeDefault(for: locale).dateFormat ?? "dd/MM"
    }

    private func displayedTitle(_ title: String) -> String {
        switch wordTruncation {
        case .ellipsis:
            return title
        case .hyphen:
            return title.count > 20 ? "\(title.prefix(19))-" : title
        case .none:
            return title
        }
    }
}

private struct HomeWidgetSettingsView: View {
    @Environment(\.locale) private var locale

    @AppStorage(SettingsKeys.dateFormat)
    private var dateFormat = DateFormatOption.system.rawValue
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
    @State private var previewFamily = HomeWidgetPreviewFamily.medium

    private var todoGroups: [TodoGroup] {
        TodoGroupStore.decode(todoGroupsData)
    }

    private var selectedDateFormatTitle: String {
        let localeDefault = DateFormatOption.localeDefault(for: locale)
        let option = DateFormatOption.resolved(from: dateFormat)
        return option == .system ? localeDefault.displayTitle : option.displayTitle
    }

    private var datePrefixTitle: String {
        "\(locale.localized("Datum")) (\(selectedDateFormatTitle))"
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
            Section("Voorbeeld") {
                Picker("Widgetformaat", selection: $previewFamily) {
                    ForEach(HomeWidgetPreviewFamily.allCases) { family in
                        Text(family.title(for: locale)).tag(family)
                    }
                }
                .pickerStyle(.segmented)
                .settingsCardRow(.first)

                HomeWidgetSettingsPreview(
                    family: previewFamily,
                    content: HomeWidgetContentOption(rawValue: content) ?? .combined,
                    calendarRange: HomeWidgetCalendarRangeOption(rawValue: calendarRange) ?? .today,
                    datePrefix: ActionButtonDatePrefixOption(rawValue: datePrefix) ?? .date,
                    dateFormat: DateFormatOption.resolved(from: dateFormat),
                    todoCategoryID: todoCategoryID,
                    todoGroups: todoGroups,
                    locale: locale,
                    wrapsText: textFlow == HomeWidgetTextFlowOption.wrap.rawValue,
                    showsTitle: showsTitle,
                    usesLightBlueBackground: background != HomeWidgetBackgroundOption.white.rawValue,
                    showsOtherWhenEmpty: showsOtherWhenEmpty
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.2), value: previewFamily)
                .settingsCardRow(.last)
            }

            Section {
                Picker("Inhoud", selection: $content) {
                    ForEach(HomeWidgetContentOption.allCases) { option in
                        Text(option.title(for: locale))
                            .foregroundStyle(Color.appPrimaryText)
                            .tag(option.rawValue)
                    }
                }
                .tint(Color.appPrimaryText)
                .settingsCardRow(.first)

                Picker("Kalenderperiode", selection: $calendarRange) {
                    ForEach(HomeWidgetCalendarRangeOption.allCases) { option in
                        Text(option.title(for: locale))
                            .foregroundStyle(Color.appPrimaryText)
                            .tag(option.rawValue)
                    }
                }
                .tint(Color.appPrimaryText)
                .settingsCardRow(.middle)

                Picker("Datumweergave", selection: $datePrefix) {
                    Text("0 = vandaag, 1 = morgen")
                        .foregroundStyle(Color.appPrimaryText)
                        .tag(ActionButtonDatePrefixOption.dayCount.rawValue)
                    Text(datePrefixTitle)
                        .foregroundStyle(Color.appPrimaryText)
                        .tag(ActionButtonDatePrefixOption.date.rawValue)
                }
                .tint(Color.appPrimaryText)
                .settingsCardRow(.middle)

                Picker("Takenweergave", selection: $todoCategoryID) {
                    Text("Bovenste taken")
                        .foregroundStyle(Color.appPrimaryText)
                        .tag("")
                    ForEach(todoGroups) { group in
                        Text(group.title)
                            .foregroundStyle(Color.appPrimaryText)
                            .tag(group.id)
                    }
                }
                .tint(Color.appPrimaryText)
                .settingsCardRow(.middle)

                Picker("Lange tekst", selection: $textFlow) {
                    ForEach([HomeWidgetTextFlowOption.wrap, .truncate]) { option in
                        Text(option.title(for: locale))
                            .foregroundStyle(Color.appPrimaryText)
                            .tag(option.rawValue)
                    }
                }
                .tint(Color.appPrimaryText)
                .settingsCardRow(.middle)

                Toggle("Titel laten zien", isOn: $showsTitle)
                    .settingsCardRow(.middle)
                Toggle("Lichtblauwe widgetkleur", isOn: usesLightBlueBackground)
                    .settingsCardRow(.middle)
                Toggle("Slimme weergave", isOn: $showsOtherWhenEmpty)
                    .settingsCardRow(.last)
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
                ActionButtonCapturePreview(
                    launchMode: selectedLaunchMode,
                    destination: destination,
                    taskCategoryID: taskCategoryID,
                    groups: groups,
                    startsVoiceRecording: startsVoiceRecording
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .settingsCardRow(.first)

                Text(locale.localized("De Actieknop is alleen beschikbaar op iPhone 15 Pro en nieuwere modellen. Stel op je iPhone bij Instellingen › Actieknop › Opdracht de opdracht ‘Nieuwe taak’ in."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .settingsCardRow(.last)
            }

            Section("Bij indrukken") {
                let options = ActionButtonLaunchMode.allCases
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button {
                        launchMode = option.rawValue
                    } label: {
                        HStack {
                            Text(option.title(for: locale))
                            Spacer()
                            if option == selectedLaunchMode {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.brandHardBlue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appPrimaryText)
                    .settingsCardRow(.row(at: index, count: options.count))
                }
            }

            Section("Standaardbestemming") {
                ForEach(groups.indices, id: \.self) { index in
                    let group = groups[index]
                    Button {
                        destinationBinding.wrappedValue = group.id
                    } label: {
                        HStack {
                            Label {
                                Text(group.title)
                            } icon: {
                                Image(systemName: group.icon)
                                    .foregroundStyle(Color.brandHardBlue)
                            }
                            Spacer()
                            if destinationBinding.wrappedValue == group.id {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.brandHardBlue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appPrimaryText)
                    .settingsCardRow(.row(at: index, count: groups.count + 1))
                }

                Button {
                    destinationBinding.wrappedValue = Self.calendarDestinationID
                } label: {
                    HStack {
                        Label {
                            Text("Kalender vandaag")
                        } icon: {
                            Image(systemName: "calendar")
                                .foregroundStyle(Color.brandHardBlue)
                        }
                        Spacer()
                        if destinationBinding.wrappedValue == Self.calendarDestinationID {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.brandHardBlue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appPrimaryText)
                .settingsCardRow(groups.isEmpty ? .single : .last)
            }

            if selectedLaunchMode == .fullApp {
                Section("Spraakinvoer") {
                    Toggle("Direct spraak opnemen", isOn: $startsVoiceRecording)
                        .settingsCardRow(.single)
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

private struct ActionButtonCapturePreview: View {
    private enum Phase: Int { case waiting, pressed, opened, typing, saving, saved }

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let launchMode: ActionButtonLaunchMode
    let destination: String
    let taskCategoryID: String
    let groups: [TodoGroup]
    let startsVoiceRecording: Bool
    @State private var phase = Phase.waiting
    @State private var typedText = ""
    @State private var loopTask: Task<Void, Never>?

    private var exampleText: String { locale.localized("Dit is een voorbeeld") }
    private var selectedGroup: TodoGroup {
        groups.first(where: { $0.id == taskCategoryID }) ?? groups.first ?? TodoGroupStore.defaults[0]
    }
    private var isCalendar: Bool { destination == ActionButtonDefaultDestination.calendarToday.rawValue }
    private var destinationTitle: String { isCalendar ? locale.localized("Kalender vandaag") : selectedGroup.title }
    private var destinationIcon: String { isCalendar ? "calendar" : selectedGroup.icon }
    private var destinationColor: Color { isCalendar ? .brandHardBlue : selectedGroup.color }
    private var savedText: String { locale.localizedFormat("quick.addedTo", destinationTitle) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035))
            phone

            if phase.rawValue < Phase.opened.rawValue {
                Image(systemName: "hand.point.right.fill")
                    .font(.system(size: 22)).foregroundStyle(Color.brandHardBlue)
                    .offset(x: phase == .pressed ? -155 : -164, y: 57)
                .animation(.easeInOut(duration: 0.35), value: phase)
            }
        }
        .frame(height: 202)
        .clipped()
        .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locale.localized("Voorbeeld van de Actieknop"))
        .onAppear { restart(at: .waiting) }
        .onDisappear { loopTask?.cancel() }
        .onChange(of: launchMode) { _, _ in restart(at: .pressed) }
        .onChange(of: destination) { _, _ in restart(at: .saving) }
        .onChange(of: taskCategoryID) { _, _ in restart(at: .saving) }
        .onChange(of: startsVoiceRecording) { _, _ in restart(at: .opened) }
        .onChange(of: locale.identifier) { _, _ in restart(at: .opened) }
    }

    private var phone: some View {
        ZStack(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 44,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 44
            )
            .fill(Color.primary.opacity(0.9))
            .frame(width: 292, height: 188)

            UnevenRoundedRectangle(
                topLeadingRadius: 39,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 39
            )
            .fill(Color(uiColor: .systemBackground))
            .frame(width: 282, height: 183)
            .offset(x: 5, y: 5)
            .overlay(alignment: .topLeading) {
                phoneScreen
                    .frame(width: 274, height: 175)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 35,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 35
                    ))
                    .offset(x: 9, y: 9)
            }

            Capsule()
                .fill(phase == .pressed ? Color.brandHardBlue : Color.primary.opacity(0.65))
                .frame(width: phase == .pressed ? 8 : 5, height: 38)
                .offset(x: -4, y: 57)
                .shadow(color: phase == .pressed ? Color.brandHardBlue.opacity(0.65) : .clear, radius: 6)
                .animation(.spring(response: 0.24, dampingFraction: 0.55), value: phase)
        }
        .frame(width: 300, height: 190)
    }

    @ViewBuilder private var phoneScreen: some View {
        ZStack(alignment: .top) {
            if launchMode == .fullApp && phase.rawValue >= Phase.opened.rawValue {
                appScreen
            } else {
                lockScreen
            }

            statusBar

            if phase.rawValue >= Phase.opened.rawValue
                && !(launchMode == .fullApp && phase == .saved) {
                capturePanel
                    .frame(width: 264)
                    .padding(.top, launchMode == .quickField ? 46 : 45)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.88, anchor: .top).combined(with: .opacity),
                        removal: .identity
                    ))
            }
        }
    }

    private var statusBar: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 5) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 8, weight: .semibold))
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: "cellularbars").font(.system(size: 7))
                Image(systemName: "wifi").font(.system(size: 7))
                Image(systemName: "battery.100percent").font(.system(size: 9))
            }
            .padding(.horizontal, 20)
            .padding(.top, 9)

            Capsule()
                .fill(Color.black)
                .frame(width: 74, height: 21)
                .padding(.top, 5)
                .overlay(alignment: .leading) {
                    if phase.rawValue >= Phase.opened.rawValue {
                        Image("OnboardingLogo")
                            .resizable().scaledToFit()
                            .frame(width: 15, height: 15)
                            .background(Color.brandLightBlue, in: RoundedRectangle(cornerRadius: 4))
                            .padding(.leading, 4)
                            .padding(.top, 5)
                    }
                }
                .overlay(alignment: .trailing) {
                    if launchMode == .fullApp && startsVoiceRecording && phase == .opened {
                        Circle().fill(.orange).frame(width: 5, height: 5)
                            .padding(.trailing, 10).padding(.top, 5)
                    }
                }
        }
        .foregroundStyle(Color.appPrimaryText)
    }

    private var appScreen: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 29)

            ZStack {
                Text(isCalendar ? locale.localized("Kalender") : locale.localized("Taken"))
                    .font(.system(size: 15, weight: .bold))
                HStack {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 27, height: 27)
                        .background(.ultraThinMaterial, in: Circle())
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 27, height: 27)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .frame(height: 38)
            .padding(.horizontal, 10)

            if isCalendar {
                calendarResult
            } else {
                todoResult
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var calendarResult: some View {
        VStack(spacing: 5) {
            Text(calendarWeekTitle)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 7) {
                Text(Date.now.formatted(.dateTime.day().month(.twoDigits)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(Date.now.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.55)).frame(width: 0.7, height: 31)
                Text(exampleText)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle().stroke(Color.primary, lineWidth: 1.4).frame(width: 14, height: 14)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(.horizontal, 10)
    }

    private var todoResult: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: destinationIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(destinationColor)
                    .frame(width: 27, height: 27)
                    .background(destinationColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 0) {
                    Text(destinationTitle).font(.system(size: 12, weight: .bold)).lineLimit(1)
                    Text(locale.localized("1 open")).font(.system(size: 8)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(destinationColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)

            Divider().padding(.leading, 44)

            HStack(spacing: 7) {
                Text(locale.localized("todo.age.now"))
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(destinationColor)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(destinationColor.opacity(0.14), in: Capsule())
                Text(exampleText).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 0)
                Circle().stroke(Color.primary, lineWidth: 1.4).frame(width: 14, height: 14)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
        }
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 10)
    }

    private var calendarWeekTitle: String {
        let calendar = AppCalendar.calendar
        let week = calendar.component(.weekOfYear, from: .now)
        return "week #\(week)"
    }

    private var lockScreen: some View {
            ZStack {
                Color.brandLightBlue.opacity(0.72)
                VStack(spacing: 0) {
                Color.clear.frame(height: 31)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 42, weight: .medium))
                        .monospacedDigit()
                }
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                }
            }
    }

    @ViewBuilder private var capturePanel: some View {
        if launchMode == .quickField {
            quickFieldPanel
        } else {
            fullAppPanel
        }
    }

    private var quickFieldPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            if phase == .saved {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.brandHardBlue)
                        .frame(width: 20, height: 20)
                        .background(Color.brandLightBlue, in: Circle())
                    Text(savedText).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(locale.localized("Wat wil je niet vergeten?"))
                    .font(.system(size: 12, weight: .semibold))
                previewInputField
            }

            HStack(spacing: 8) {
                if phase != .saved {
                    Text(locale.localized("Annuleer"))
                        .foregroundStyle(Color.appPrimaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                Text(locale.localized("Gereed"))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.brandHardBlue, in: Capsule())
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(11)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
    }

    private var fullAppPanel: some View {
        VStack(spacing: 9) {
            HStack {
                Text(locale.localized("Annuleer"))
                Spacer()
                Text(locale.localized("Snel toevoegen")).fontWeight(.bold)
                Spacer()
                Text(locale.localized("Voeg toe"))
                    .fontWeight(.semibold)
                    .foregroundStyle(typedText.isEmpty ? Color.secondary : Color.brandHardBlue)
                    .scaleEffect(phase == .saving ? 0.86 : 1)
                    .animation(.spring(response: 0.22, dampingFraction: 0.55), value: phase)
            }
            .font(.system(size: 9))

            HStack(spacing: 6) {
                previewInputField
                Image(systemName: startsVoiceRecording && phase == .opened ? "waveform.circle.fill" : "mic.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(startsVoiceRecording && phase == .opened ? .red : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }

            HStack(spacing: 7) {
                previewChoice(title: destinationTitle, icon: destinationIcon, selected: true)
                previewChoice(title: locale.localized("Datum"), icon: "calendar", selected: false)
            }
        }
        .padding(11)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }

    private var previewInputField: some View {
        HStack(spacing: 4) {
            Text(typedText.isEmpty ? locale.localized("Wat wil je niet vergeten?") : typedText)
                .foregroundStyle(typedText.isEmpty ? .secondary : .primary)
                .font(.system(size: 11)).lineLimit(1)
            if phase == .typing { Rectangle().fill(Color.brandHardBlue).frame(width: 1.5, height: 15) }
            Spacer(minLength: 0)
            if !typedText.isEmpty { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 35)
        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 11))
    }

    private func previewChoice(title: String, icon: String, selected: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold))
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(selected ? destinationColor : .primary)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 29)
        .background(selected ? destinationColor.opacity(0.13) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private func restart(at startPhase: Phase) {
        loopTask?.cancel()
        typedText = startPhase.rawValue >= Phase.saving.rawValue ? exampleText : ""
        phase = startPhase
        loopTask = Task { @MainActor in
            if startPhase == .waiting { await pause(875); phase = .pressed; await pause(563) }
            else if startPhase == .pressed { await pause(438) }
            guard !Task.isCancelled else { return }
            if startPhase.rawValue <= Phase.pressed.rawValue { phase = .opened; await pause(813) }
            if startPhase.rawValue <= Phase.opened.rawValue {
                phase = .typing; typedText = ""
                for character in exampleText {
                    guard !Task.isCancelled else { return }
                    typedText.append(character); await pause(reduceMotion ? 25 : 94)
                }
                await pause(625)
            }
            guard !Task.isCancelled else { return }
            phase = .saving; await pause(813); phase = .saved; await pause(3_000)
            guard !Task.isCancelled else { return }
            restart(at: .waiting)
        }
    }

    private func pause(_ milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}
