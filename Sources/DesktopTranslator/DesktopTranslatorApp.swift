import AppKit
import CoreGraphics

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

    private var desktopWidgetLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupControlShortcuts()
        setupStatusItem()
        HistorySync.shared.start()
        putOnDesktop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        putOnDesktop()
        return true
    }

    @objc
    func showTranslator() {
        guard let window = translatorWindow() else { return }
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    func putOnDesktop() {
        guard let window = translatorWindow() else { return }
        window.level = desktopWidgetLevel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.orderFrontRegardless()
        window.makeKey()
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
        appMenu.addItem(withTitle: "Put on Desktop", action: #selector(putOnDesktop), keyEquivalent: "d")
        appMenu.addItem(withTitle: "Open as Window", action: #selector(showTranslator), keyEquivalent: "n")
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
        menu.addItem(NSMenuItem(title: "Put on Desktop", action: #selector(putOnDesktop), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open as Window", action: #selector(showTranslator), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func makeWindowController() -> NSWindowController {
        let viewController = TranslatorViewController()
        let window = NSWindow(contentViewController: viewController)
        window.title = "Desktop Translator"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.paper
        window.setContentSize(NSSize(width: 480, height: 840))
        window.center()
        window.level = desktopWidgetLevel

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        return controller
    }
}
