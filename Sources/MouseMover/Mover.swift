import AppKit
import ApplicationServices
import CoreGraphics
import IOKit
import OSLog
import ServiceManagement

/// The interval choices shown in the menu, in seconds.
let intervalChoices: [Int] = [30, 60, 120, 300]

/// Mover owns the on/off state and the timer that nudges the cursor.
///
/// While it is enabled, every `intervalSeconds` it posts two real
/// `mouseMoved` events to the HID event tap: 1 px to the side and back.
/// A posted HID event resets the system idle timer (a plain
/// `CGWarpMouseCursorPosition` does not). It never clicks and never types.
/// While it is disabled, no timer runs and no events are posted.
///
/// Usage:
///
///     let mover = Mover()
///     mover.setInterval(60)
///     mover.setEnabled(true)   // nudges every 60 s
///     mover.setEnabled(false)  // stops at once
@MainActor
final class Mover: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let interval = "intervalSeconds"
    }

    /// The default interval when nothing valid is stored.
    static let defaultInterval = 60
    /// A tick is skipped when real input happened less than this many seconds ago.
    static let activeUserThreshold: Double = 5

    @Published private(set) var isEnabled: Bool
    @Published private(set) var intervalSeconds: Int
    @Published private(set) var hasAccess: Bool
    @Published private(set) var lastMove: Date?
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var loginItemMessage: String?

    private let defaults: UserDefaults
    private var timer: Timer?
    private var accessPoll: Timer?
    private var activity: NSObjectProtocol?
    private let log = Logger(subsystem: "local.MouseMover", category: "mover")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: Key.interval)
        intervalSeconds = intervalChoices.contains(stored) ? stored : Self.defaultInterval
        isEnabled = defaults.bool(forKey: Key.enabled)
        hasAccess = Self.checkAccess(prompt: false)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        log.notice("launch: enabled=\(self.isEnabled) interval=\(self.intervalSeconds)s access=\(self.hasAccess)")
        if isEnabled {
            if !hasAccess { hasAccess = Self.checkAccess(prompt: true) }
            start()
        }
    }

    // MARK: State shown in the menu

    /// A short status line, for example "On, every 1 min".
    var statusText: String {
        if !isEnabled { return "Off" }
        if !hasAccess { return "On, needs Accessibility permission" }
        return "On, every \(Self.label(for: intervalSeconds))"
    }

    /// The SF Symbol for the menu bar: filled while on, outline while off,
    /// and a warning triangle while on without permission.
    var iconName: String {
        if !isEnabled { return "computermouse" }
        return hasAccess ? "computermouse.fill" : "exclamationmark.triangle.fill"
    }

    /// A human label for an interval, for example "30 s" or "2 min".
    static func label(for seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 { return "\(seconds / 60) min" }
        return "\(seconds) s"
    }

    // MARK: Actions

    /// Turns the mover on or off and remembers the choice.
    /// On enable, it asks for Accessibility permission if it is missing.
    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        defaults.set(on, forKey: Key.enabled)
        if on {
            hasAccess = Self.checkAccess(prompt: true)
            start()
        } else {
            stop()
        }
    }

    /// Sets the nudge interval (one of `intervalChoices`) and remembers it.
    func setInterval(_ seconds: Int) {
        guard intervalChoices.contains(seconds), seconds != intervalSeconds else { return }
        intervalSeconds = seconds
        defaults.set(seconds, forKey: Key.interval)
        log.notice("interval set to \(seconds)s")
        if isEnabled { start() }
    }

    /// Shows the system prompt and opens
    /// System Settings > Privacy & Security > Accessibility.
    func requestAccess() {
        hasAccess = Self.checkAccess(prompt: true)
        guard !hasAccess,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Adds or removes the app as a login item.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemMessage = nil
        } catch {
            loginItemMessage = "Login item: \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginItemMessage = "Approve it in System Settings > General > Login Items"
        }
    }

    // MARK: Timer

    private func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: TimeInterval(intervalSeconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        if activity == nil {
            // Keeps App Nap from delaying the timer. Idle system sleep stays allowed.
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Mouse Mover nudge timer"
            )
        }
        updateAccessPoll()
        log.notice("enabled: every \(self.intervalSeconds)s")
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        accessPoll?.invalidate()
        accessPoll = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        log.notice("disabled")
    }

    /// While enabled without permission, checks every 2 s so the icon
    /// changes as soon as the user grants it.
    private func updateAccessPoll() {
        if isEnabled && !hasAccess {
            guard accessPoll == nil else { return }
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hasAccess = Self.checkAccess(prompt: false)
                    if self.hasAccess { self.updateAccessPoll() }
                }
            }
            RunLoop.main.add(t, forMode: .common)
            accessPoll = t
        } else {
            accessPoll?.invalidate()
            accessPoll = nil
        }
    }

    private func tick() {
        hasAccess = Self.checkAccess(prompt: false)
        updateAccessPoll()
        guard hasAccess else {
            log.notice("skip: no Accessibility permission")
            return
        }
        if Self.isScreenLocked() {
            log.notice("skip: screen is locked")
            return
        }
        if Self.anyMouseButtonDown() {
            log.notice("skip: a mouse button is down")
            return
        }
        if let idle = Self.hidIdleSeconds(), idle < Self.activeUserThreshold {
            log.notice("skip: user is active (idle \(idle, format: .fixed(precision: 1))s)")
            return
        }
        nudge()
    }

    /// Posts a real 1 px mouse move and a move back to the start point.
    private func nudge() {
        guard let start = CGEvent(source: nil)?.location else {
            log.error("skip: cannot read the cursor position")
            return
        }
        let idleBefore = Self.hidIdleSeconds() ?? -1
        let source = CGEventSource(stateID: .hidSystemState)
        let dx: CGFloat = start.x >= 1 ? -1 : 1
        Self.postMove(to: CGPoint(x: start.x + dx, y: start.y), dx: Int64(dx), source: source)
        usleep(30_000)
        Self.postMove(to: start, dx: Int64(-dx), source: source)
        lastMove = Date()
        log.notice("moved: idle before \(idleBefore, format: .fixed(precision: 1))s")
    }

    private static func postMove(to point: CGPoint, dx: Int64, source: CGEventSource?) {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: dx)
        event.setIntegerValueField(.mouseEventDeltaY, value: 0)
        event.post(tap: .cghidEventTap)
    }

    // MARK: System checks

    /// Reports whether the app may post events. With `prompt`, macOS shows
    /// its Accessibility dialog when the permission is missing.
    static func checkAccess(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        return trusted || CGPreflightPostEventAccess()
    }

    /// The same value as `ioreg -c IOHIDSystem` HIDIdleTime, in seconds.
    static func hidIdleSeconds() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? NSNumber else { return nil }
        return value.doubleValue / 1_000_000_000
    }

    private static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    private static func anyMouseButtonDown() -> Bool {
        [CGMouseButton.left, .right, .center].contains {
            CGEventSource.buttonState(.hidSystemState, button: $0)
        }
    }
}
