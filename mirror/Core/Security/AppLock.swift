import Foundation
import LocalAuthentication
import Observation

/// App Lock (iOS and Mac, off by default): Face ID / Touch ID, falling back to the device passcode
/// or Mac password, when MirrorNotes opens and after five minutes away. The journal stays in
/// memory behind the lock (drafts survive); covers are drawn by `AppLockCovers`.
///
/// "Away" starts when the app goes to the background (iOS), stops being the active app (Mac), or
/// the Mac's screen locks or it sleeps, and never while the system's own Face ID / Touch ID /
/// password prompt is up: that prompt makes the app inactive (iOS) or resign active (Mac), and
/// finishing an unlock must not count as having been away.
@Observable
@MainActor
final class AppLock {
    static let shared = AppLock()

    static let enabledKey = "appLockEnabled"
    static let awayLimit: TimeInterval = 5 * 60

    enum Method {
        case faceID, touchID, opticID, passcode, unavailable
    }

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    /// iOS: the app isn't active (app switcher snapshot, Control Center), so content is hidden
    /// without asking to unlock.
    private(set) var privacyCover = false
    /// Why the last attempt couldn't run (no passcode set); nil after a plain cancel.
    private(set) var unavailableReason: String?

    var hidesContent: Bool { isLocked || privacyCover }

    private var awaySince: Date?
    /// One automatic prompt per return; cancelling it leaves the Unlock button, not a loop.
    private var autoPromptArmed = true

    /// UI tests, the Mac snapshot harness and perf runs never lock.
    static var isHarnessRun: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--uitesting") || args.contains("--macSnapshot")
            || args.contains { $0.hasPrefix("--perfSeed=") }
    }

    private init() {
        let enabled = !Self.isHarnessRun && UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    // MARK: Method

    /// What unlocking will use on this device, for labels.
    static var method: Method {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .unavailable }
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            switch context.biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            case .opticID: return .opticID
            default: break
            }
        }
        return .passcode
    }

    // MARK: Settings

    /// Turning it on or off asks first, so it can't be turned off by someone else and is known to
    /// work before it's relied on. False when that check didn't pass.
    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isEnabled else { return true }
        let reason = enabled
            ? String(localized: "Turn on App Lock for your journal.")
            : String(localized: "Turn off App Lock for your journal.")
        guard await authenticate(reason: reason) else { return false }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if !enabled { isLocked = false }
        awaySince = nil
        return true
    }

    // MARK: Unlock

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        if await authenticate(reason: String(localized: "Unlock your journal.")) {
            isLocked = false
            awaySince = nil
        }
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unavailableReason = Self.unavailableText
            return false
        }
        unavailableReason = nil
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            #if DEBUG
            print("[AppLock] evaluatePolicy failed: LAError \((error as? LAError)?.code.rawValue ?? 0)")
            #endif
            return false
        }
    }

    static var unavailableText: String {
        #if os(macOS)
        String(localized: "Set a login password for this Mac to use App Lock.")
        #else
        String(localized: "Set a passcode for this device to use App Lock.")
        #endif
    }

    // MARK: Away

    /// The app went to the background (iOS), stopped being the active app (Mac), or the Mac's
    /// screen locked or it went to sleep.
    func didLeave() {
        guard isEnabled, !isAuthenticating else { return }
        if awaySince == nil { awaySince = Date() }
        autoPromptArmed = true
    }

    /// Back in the app: locks if it was away long enough, then asks once.
    func didReturn() {
        guard isEnabled else { return }
        if let since = awaySince, Date().timeIntervalSince(since) >= Self.awayLimit {
            isLocked = true
        }
        awaySince = nil
        if isLocked, autoPromptArmed, !isAuthenticating {
            autoPromptArmed = false
            Task { await unlock() }
        }
    }

    func setPrivacyCover(_ on: Bool) {
        privacyCover = on && isEnabled
    }

    #if DEBUG
    /// Tests: drive the away timer without waiting five minutes.
    func setAwaySinceForTesting(_ date: Date?) { awaySince = date }
    func setStateForTesting(enabled: Bool, locked: Bool) {
        isEnabled = enabled
        isLocked = locked
        autoPromptArmed = false
    }
    #endif
}
