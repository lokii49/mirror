import SwiftUI
import SwiftData
import UserNotifications

/// "Journal" in Classic, "Protocol" in Sentinel — schedule and behavior
/// settings for nudges, digests, transcription, and notifications. Pushed
/// from the root Config screen rather than living inline, since this was
/// the largest single group crowding the old single-screen Settings.
struct ProtocolSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDisplayMode) private var displayMode
    @State private var subscriptionService = SubscriptionService.shared

    @AppStorage("nudgeHour") private var nudgeHour: Int = 8
    @AppStorage("nudgeMinute") private var nudgeMinute: Int = 0
    @State private var showNudgeTimePicker = false

    @AppStorage("writingReminderEnabled") private var writingReminderEnabled: Bool = false
    @AppStorage("writingReminderHour") private var writingReminderHour: Int = 9
    @AppStorage("writingReminderMinute") private var writingReminderMinute: Int = 0
    @State private var showWritingReminderPicker = false

    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage: String = ""
    @State private var showLanguagePicker = false
    @State private var notificationPermission: UNAuthorizationStatus = .notDetermined
    @State private var showSubscription = false

    private var nudgeTime: Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = nudgeHour
        c.minute = nudgeMinute
        return Calendar.current.date(from: c) ?? Date()
    }

    private var writingReminderTime: Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = writingReminderHour
        c.minute = writingReminderMinute
        return Calendar.current.date(from: c) ?? Date()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsGroup(title: "Schedule") {
                    // Daily nudge time — Core only
                    if subscriptionService.isSubscribed {
                        Button { withAnimation { showNudgeTimePicker.toggle() } } label: {
                            HStack {
                                SettingsRowLabel(title: "Daily nudge time", systemImage: "bell.fill", iconColor: .orange)
                                Spacer()
                                SettingsValueText(text: nudgeTime.formatted(date: .omitted, time: .shortened))
                                SettingsChevron()
                                    .rotationEffect(.degrees(showNudgeTimePicker ? 90 : 0))
                                    .animation(.easeInOut(duration: 0.2), value: showNudgeTimePicker)
                            }
                        }
                        .buttonStyle(.plain)

                        if showNudgeTimePicker {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { nudgeTime },
                                    set: { date in
                                        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                                        nudgeHour = c.hour ?? 8
                                        nudgeMinute = c.minute ?? 0
                                        Task {
                                            let insightReady = mirrorApp.hasDailyNudgeForToday(context: modelContext)
                                            let hasWritten = mirrorApp.hasEntryToday(context: modelContext)
                                            await NotificationService.rescheduleContextualNudge(
                                                hasWrittenToday: hasWritten,
                                                insightReady: insightReady,
                                                hour: nudgeHour,
                                                minute: nudgeMinute
                                            )
                                        }
                                    }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    } else {
                        Button { showSubscription = true } label: {
                            HStack {
                                SettingsRowLabel(title: "Daily nudge time", systemImage: "bell.fill", iconColor: .orange)
                                    .opacity(0.45)
                                Spacer()
                                SettingsTierBadge(tier: "Core")
                            }
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showSubscription) { SubscriptionView() }
                    }

                    SettingsDivider()

                    HStack {
                        SettingsRowLabel(title: "Weekly digest day", systemImage: "calendar", iconColor: .blue)
                            .opacity(subscriptionService.isSubscribed ? 1 : 0.45)
                        Spacer()
                        if subscriptionService.isSubscribed {
                            SettingsValueText(text: String(localized: "Sunday"))
                        } else {
                            SettingsTierBadge(tier: "Core")
                        }
                    }

                    SettingsDivider()

                    // Writing reminder — all tiers
                    Button { withAnimation { showWritingReminderPicker.toggle() } } label: {
                        HStack {
                            SettingsRowLabel(title: "Writing reminder", systemImage: "pencil.circle.fill", iconColor: .teal)
                            Spacer()
                            SettingsValueText(text: writingReminderEnabled
                                ? writingReminderTime.formatted(date: .omitted, time: .shortened)
                                : String(localized: "Off"))
                            SettingsChevron()
                                .rotationEffect(.degrees(showWritingReminderPicker ? 90 : 0))
                                .animation(.easeInOut(duration: 0.2), value: showWritingReminderPicker)
                        }
                    }
                    .buttonStyle(.plain)

                    if showWritingReminderPicker {
                        VStack(spacing: 12) {
                            Toggle("Enable daily writing reminder", isOn: $writingReminderEnabled)
                                .font(.system(size: 14))
                                .onChange(of: writingReminderEnabled) { _, enabled in
                                    Task {
                                        if enabled {
                                            await NotificationService.scheduleWritingReminder(
                                                hour: writingReminderHour,
                                                minute: writingReminderMinute
                                            )
                                        } else {
                                            NotificationService.cancelWritingReminder()
                                        }
                                    }
                                }
                            if writingReminderEnabled {
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: { writingReminderTime },
                                        set: { date in
                                            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                                            writingReminderHour = c.hour ?? 9
                                            writingReminderMinute = c.minute ?? 0
                                            Task {
                                                await NotificationService.scheduleWritingReminder(
                                                    hour: writingReminderHour,
                                                    minute: writingReminderMinute
                                                )
                                            }
                                        }
                                    ),
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                SettingsGroup(title: "Input") {
                    Button { showLanguagePicker = true } label: {
                        HStack {
                            SettingsRowLabel(title: "Voice transcription language", systemImage: "mic.fill", iconColor: MirrorTheme.violet)
                            Spacer()
                            let langName = VoiceTranscriptionService.pickerLanguages.first(where: { $0.id == transcriptionLanguage })?.displayName ?? String(localized: "Automatic")
                            SettingsValueText(text: langName)
                            SettingsChevron()
                        }
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showLanguagePicker) {
                        TranscriptionLanguagePickerView(selected: $transcriptionLanguage)
                    }

                    SettingsDivider()

                    HStack {
                        SettingsRowLabel(title: "Notifications", systemImage: "bell.badge.fill", iconColor: MirrorTheme.primary)
                        Spacer()
                        if notificationPermission == .denied {
                            Text("Disabled in Settings")
                                .font(.system(size: 12))
                                .foregroundStyle(MirrorTheme.textSecondary)
                        } else {
                            Toggle("", isOn: $notificationsEnabled)
                                .labelsHidden()
                                .onChange(of: notificationsEnabled) { _, enabled in
                                    if enabled {
                                        requestNotificationPermission()
                                    } else {
                                        NotificationService.cancelAll()
                                    }
                                }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(MirrorTheme.bgBase)
        .navigationTitle(displayMode == .sentinel ? "Protocol" : "Journal")
        .navigationBarTitleDisplayMode(.large)
        .task { await checkNotificationPermission() }
    }

    private func checkNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermission = settings.authorizationStatus
        if settings.authorizationStatus == .denied {
            notificationsEnabled = false
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                notificationPermission = granted ? .authorized : .denied
                if !granted { notificationsEnabled = false }
            }
        }
    }
}
