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

    // One unified daily reminder (replaces the old separate writing reminder).
    // On by default; tapping the notification opens the mood check-in sheet.
    @AppStorage("moodCheckInEnabled") private var moodCheckInEnabled: Bool = true
    @AppStorage("moodCheckInHour") private var moodCheckInHour: Int = 9
    @AppStorage("moodCheckInMinute") private var moodCheckInMinute: Int = 0
    @AppStorage("moodCheckInTimeUserSet") private var moodCheckInTimeUserSet: Bool = false
    @State private var showMoodCheckInPicker = false

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

    private var moodCheckInTime: Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = moodCheckInHour
        c.minute = moodCheckInMinute
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
                        .sheet(isPresented: $showSubscription) { SubscriptionView().environment(\.appDisplayMode, displayMode) }
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

                    // Unified daily reminder — all tiers, opens the mood check-in
                    Button { withAnimation { showMoodCheckInPicker.toggle() } } label: {
                        HStack {
                            SettingsRowLabel(title: "Daily check-in reminder", systemImage: "face.smiling.fill", iconColor: .pink)
                            Spacer()
                            SettingsValueText(text: moodCheckInEnabled
                                ? moodCheckInTime.formatted(date: .omitted, time: .shortened)
                                : String(localized: "Off"))
                            SettingsChevron()
                                .rotationEffect(.degrees(showMoodCheckInPicker ? 90 : 0))
                                .animation(.easeInOut(duration: 0.2), value: showMoodCheckInPicker)
                        }
                    }
                    .buttonStyle(.plain)

                    if showMoodCheckInPicker {
                        VStack(spacing: 12) {
                            Toggle("Remind me to check in once a day", isOn: $moodCheckInEnabled)
                                .font(.system(size: 14))
                                .onChange(of: moodCheckInEnabled) { _, enabled in
                                    Task {
                                        if enabled {
                                            await NotificationService.scheduleMoodCheckIn(
                                                hour: moodCheckInHour,
                                                minute: moodCheckInMinute
                                            )
                                        } else {
                                            NotificationService.cancelMoodCheckIn()
                                        }
                                    }
                                }
                            if moodCheckInEnabled {
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: { moodCheckInTime },
                                        set: { date in
                                            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                                            moodCheckInHour = c.hour ?? 9
                                            moodCheckInMinute = c.minute ?? 0
                                            moodCheckInTimeUserSet = true
                                            Task {
                                                await NotificationService.scheduleMoodCheckIn(
                                                    hour: moodCheckInHour,
                                                    minute: moodCheckInMinute
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
                            .environment(\.appDisplayMode, displayMode)
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
