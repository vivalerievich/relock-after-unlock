import AppKit
import Darwin
import Foundation
import IOKit
import OSLog

private let label = "local.relock-after-unlock"
private let log = Logger(subsystem: label, category: "timer")
private let unlocked = Notification.Name("com.apple.screenIsUnlocked")
private let locked = Notification.Name("com.apple.screenIsLocked")

private struct SystemScreenLock {
    private typealias LockFunction = @convention(c) () -> Int32
    private let lock: LockFunction

    init?() {
        // Use macOS's immediate screen lock, without simulated keys or permission changes.
        guard let library = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/A/login",
                                   RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let symbol = dlsym(library, "SACLockScreenImmediate") else {
            dlclose(library)
            return nil
        }
        // Keep the system framework loaded for the lifetime of the agent.
        lock = unsafeBitCast(symbol, to: LockFunction.self)
    }

    static var isUnlockedConsoleSession: Bool {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(root) }
        guard let sessions = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString,
                                                             kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return false }
        return sessions.contains { session in
            session["kCGSSessionUserIDKey"] as? UInt32 == geteuid() &&
            session["kCGSSessionOnConsoleKey"] as? Bool == true &&
            session["kCGSessionLoginDoneKey"] as? Bool == true &&
            session["CGSSessionScreenIsLocked"] as? Bool != true
        }
    }

    func lockNow() -> Int32 { lock() }
}

private enum LockDelay: Int, CaseIterable {
    case thirty = 30
    case sixty = 60

    static let preferenceKey = "LockDelayMinutes"

    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    var menuTitle: String { String(format: NSLocalizedString("delay.minutes", comment: "Delay option"), rawValue) }
}

private final class RelockAgent: NSObject, NSApplicationDelegate {
    private let screenLock: SystemScreenLock
    private var lockDelay = LockDelay(rawValue: UserDefaults.standard.integer(forKey: LockDelay.preferenceKey))
        ?? .thirty
    private var unlockedAt: Date?
    private var deadlineTimer: Timer?
    private var displayTimer: Timer?
    private var statusItem: NSStatusItem?
    private var delayItems: [LockDelay: NSMenuItem] = [:]
    private let details = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(screenLock: SystemScreenLock) {
        self.screenLock = screenLock
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "RelockAfterUnlock"
        let image = NSImage(systemSymbolName: "lock", accessibilityDescription: NSLocalizedString("app.name", comment: "Menu bar icon"))
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.addItem(details)
        menu.addItem(.separator())
        for delay in LockDelay.allCases {
            let item = NSMenuItem(title: delay.menuTitle, action: #selector(changeLockDelay(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = delay.rawValue
            menu.addItem(item)
            delayItems[delay] = item
        }
        updateDelaySelection()
        statusItem.menu = menu
        self.statusItem = statusItem

        let notifications = DistributedNotificationCenter.default()
        notifications.addObserver(self, selector: #selector(screenDidUnlock(_:)),
                                  name: unlocked, object: nil, suspensionBehavior: .deliverImmediately)
        notifications.addObserver(self, selector: #selector(screenDidLock(_:)),
                                  name: locked, object: nil, suspensionBehavior: .deliverImmediately)
        updateCountdownDisplay()
        if statusItem.button == nil {
            log.error("macOS did not provide a menu bar button.")
        } else {
            log.notice("Menu bar item initialized; visible: \(statusItem.isVisible, privacy: .public).")
        }
    }

    @objc private func changeLockDelay(_ item: NSMenuItem) {
        guard let delay = LockDelay(rawValue: item.tag), delay != lockDelay else { return }
        lockDelay = delay
        UserDefaults.standard.set(delay.rawValue, forKey: LockDelay.preferenceKey)
        updateDelaySelection()
        if let unlockedAt {
            startCountdown(from: unlockedAt)
        }
        log.notice("Lock delay set to \(delay.rawValue, privacy: .public) minutes.")
    }

    private func updateDelaySelection() {
        for (delay, item) in delayItems {
            item.state = delay == lockDelay ? .on : .off
        }
    }

    @objc private func screenDidUnlock(_ notification: Notification) {
        startCountdown(from: Date())
        log.notice("Screen unlocked; \(self.lockDelay.rawValue, privacy: .public)-minute timer started.")
    }

    @objc private func screenDidLock(_ notification: Notification) {
        guard deadlineTimer != nil else { return }
        clearCountdown()
        log.notice("Screen locked; timer cancelled.")
    }

    private func startCountdown(from unlockedAt: Date) {
        self.unlockedAt = unlockedAt
        deadlineTimer?.invalidate()
        displayTimer?.invalidate()

        let deadline = unlockedAt.addingTimeInterval(lockDelay.seconds)
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            self?.deadlineReached()
        }
        deadlineTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        let refresh = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateCountdownDisplay()
        }
        displayTimer = refresh
        RunLoop.main.add(refresh, forMode: .common)
        updateCountdownDisplay()
    }

    private func clearCountdown() {
        unlockedAt = nil
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        displayTimer?.invalidate()
        displayTimer = nil
        updateCountdownDisplay()
    }

    private func updateCountdownDisplay() {
        guard let button = statusItem?.button else { return }
        guard let deadline = deadlineTimer?.fireDate else {
            button.attributedTitle = NSAttributedString(string: "")
            let message = NSLocalizedString("status.waiting", comment: "Inactive timer")
            button.toolTip = message
            button.setAccessibilityLabel(message)
            details.title = message
            return
        }

        let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        let countdown = String(format: "%02d:%02d", remaining / 60, remaining % 60)
        button.attributedTitle = NSAttributedString(
            string: countdown,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)]
        )
        let message = String(format: NSLocalizedString("status.remaining", comment: "Countdown"), countdown)
        button.toolTip = message
        button.setAccessibilityLabel(message)
        let time = DateFormatter.localizedString(from: deadline, dateStyle: .none, timeStyle: .medium)
        details.title = String(format: NSLocalizedString("status.deadline", comment: "Scheduled lock time"), time)
    }

    private func deadlineReached() {
        clearCountdown()
        guard SystemScreenLock.isUnlockedConsoleSession else {
            log.notice("Deadline reached without an unlocked console session.")
            return
        }
        let status = screenLock.lockNow()
        if status == 0 {
            log.notice("Screen lock requested after \(self.lockDelay.rawValue, privacy: .public) minutes.")
        } else {
            log.error("macOS screen lock failed: OSStatus \(status).")
        }
    }
}

guard let screenLock = SystemScreenLock() else {
    log.error("The macOS screen lock function is unavailable.")
    exit(EX_UNAVAILABLE)
}
if CommandLine.arguments == [CommandLine.arguments[0], "--probe"] {
    print("Native lock available; unlocked console session: \(SystemScreenLock.isUnlockedConsoleSession)")
    exit(EX_OK)
}
private let agent = RelockAgent(screenLock: screenLock)
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.delegate = agent
withExtendedLifetime(agent) { application.run() }
