import AppKit
import CoreGraphics
import ServiceManagement
import WidgetKit

@main
enum AppLauncher {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    private var pinnedToDesktop = true
    private let frameAutosaveName = "DesktopTranslator.desktopFrame"

    private var desktopWidgetLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.disableRelaunchOnLogin()
        try? SMAppService.mainApp.register()
        setupMainMenu()
        setupControlShortcuts()
        setupStatusItem()
        HistorySync.shared.start()
        registerWidgetExtension()
        putOnDesktop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringTranslatorForward()
        return true
    }

    @objc
    func showTranslator() {
        pinnedToDesktop = false
        guard let window = translatorWindow() as? DesktopWidgetWindow else { return }
        window.pinnedToDesktop = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        bringTranslatorForward()
    }

    @objc
    func putOnDesktop() {
        pinnedToDesktop = true
        guard let window = translatorWindow() as? DesktopWidgetWindow else { return }
        window.pinnedToDesktop = true
        window.desktopWidgetLevel = desktopWidgetLevel
        sinkToDesktop(window)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        bringTranslatorForward()
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard pinnedToDesktop, let window = translatorWindow() else { return }
        sinkToDesktop(window)
    }

    private func bringTranslatorForward() {
        guard let window = translatorWindow() as? DesktopWidgetWindow else { return }
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .moveToActiveSpace]
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.orderFrontRegardless()
    }

    private func sinkToDesktop(_ window: NSWindow) {
        window.hidesOnDeactivate = false
        window.level = desktopWidgetLevel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.orderFrontRegardless()
    }

    @objc
    func addDesktopWidget() {
        registerWidgetExtension()
        let alert = NSAlert()
        alert.messageText = "Add Desktop Translator as a Widget"
        alert.informativeText = """
        The translator is already pinned to the desktop. Drag it wherever you want — it stays there.

        You can also add the system widget:
        1. Right-click an empty area of the desktop.
        2. Choose Edit Widgets.
        3. Search for Desktop Translator.
        4. Tap Look up on the widget to translate without opening a window.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc
    func quitApp() {
        NSApp.terminate(nil)
    }

    private func translatorWindow() -> NSWindow? {
        if windowController == nil {
            windowController = makeWindowController()
        }
        return windowController?.window
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Pin to Desktop", action: #selector(putOnDesktop), keyEquivalent: "d")
        appMenu.addItem(withTitle: "Open as Window", action: #selector(showTranslator), keyEquivalent: "n")
        appMenu.addItem(withTitle: "Add System Widget…", action: #selector(addDesktopWidget), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Desktop Translator", action: #selector(quitApp), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupControlShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let usesControl = flags.contains(.control) && !flags.contains(.command)
            guard usesControl else { return event }
            switch event.charactersIgnoringModifiers {
            case "c":
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                return nil
            case "v":
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                return nil
            case "x":
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                return nil
            case "a":
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "Aa"
            button.font = .systemFont(ofSize: 13, weight: .semibold)
            button.toolTip = "Desktop Translator"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show on Desktop", action: #selector(putOnDesktop), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open as Window", action: #selector(showTranslator), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Add System Widget…", action: #selector(addDesktopWidget), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func makeWindowController() -> NSWindowController {
        let viewController = TranslatorViewController()
        let window = DesktopWidgetWindow(contentViewController: viewController)
        window.title = "Desktop Translator"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = true
        window.isOpaque = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.paper
        window.isRestorable = false
        window.contentMinSize = NSSize(width: 400, height: 560)
        window.hidesOnDeactivate = false
        window.pinnedToDesktop = true
        window.desktopWidgetLevel = desktopWidgetLevel
        window.setFrameAutosaveName(frameAutosaveName)
        if !window.setFrameUsingName(frameAutosaveName) {
            placeDefaultFrame(window)
        }
        var frame = window.frame
        if frame.width < 400 {
            frame.size.width = 400
            window.setFrame(frame, display: false)
        }
        window.level = desktopWidgetLevel

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [frameAutosaveName] note in
            guard let window = note.object as? NSWindow else { return }
            let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            if let visible, visible.intersects(window.frame) {
                window.saveFrame(usingName: frameAutosaveName)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { [frameAutosaveName] note in
            (note.object as? NSWindow)?.saveFrame(usingName: frameAutosaveName)
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            NSApp.terminate(nil)
        }

        let controller = NSWindowController(window: window)
        window.orderFrontRegardless()
        return controller
    }

    private func placeDefaultFrame(_ window: NSWindow) {
        let size = NSSize(width: 420, height: 640)
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: visible.maxX - size.width - 28,
            y: visible.maxY - size.height - 28
        )
        window.setContentSize(size)
        window.setFrameOrigin(origin)
    }

    private func registerWidgetExtension() {
        guard let appex = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("TranslatorWidget.appex") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-a", appex.path]
        try? process.run()
        process.waitUntilExit()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private final class DesktopWidgetWindow: NSWindow {
    var pinnedToDesktop = true
    var desktopWidgetLevel: NSWindow.Level = .normal

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        isMovable = true
        isMovableByWindowBackground = true
        if pinnedToDesktop {
            level = .normal
        }
    }

    override func resignKey() {
        super.resignKey()
        if pinnedToDesktop {
            hidesOnDeactivate = false
            level = desktopWidgetLevel
        }
    }
}
