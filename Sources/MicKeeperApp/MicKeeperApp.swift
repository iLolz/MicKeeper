import AppKit
import Combine
import os
import SwiftUI

@main
enum Entry {
    // NSApplication keeps only a weak reference to its delegate.
    private static var delegate: AppDelegate?

    static func main() {
        // `--snapshot <path.png> [--dark] [--popover]` renders offscreen and exits
        // (no Screen Recording permission needed).
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            SnapshotRenderer.run(path: args[index + 1], dark: args.contains("--dark"), popover: args.contains("--popover"))
        } else {
            let app = NSApplication.shared
            let delegate = AppDelegate(startHidden: args.contains("--hidden"))
            Self.delegate = delegate
            app.delegate = delegate
            app.run()
        }
    }
}

/// Owns the menu bar item and the main window.
/// The app lives in the menu bar; the Dock icon shows only while the window is open.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger = Logger(subsystem: "com.alencar.mickeeper", category: "App")
    private let startHidden: Bool
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(startHidden: Bool) {
        self.startHidden = startHidden
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        setUpMainMenu()
        setUpStatusItem()

        if startHidden || Self.launchedAsLoginItem() {
            logger.info("Started hidden (menu bar only)")
            NSApp.setActivationPolicy(.accessory)
        } else {
            showWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Opening the app again (Finder, Spotlight, Dock) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: Window

    @objc func showWindow() {
        popover.performClose(nil)
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        logger.info("Window shown")
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "MicKeeper"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ContentView().environmentObject(model))
        // The window takes exactly the content's size (480 wide, height follows the list).
        host.sizingOptions = [.minSize, .maxSize, .intrinsicContentSize]
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.center()
        // Remember only the position; the size always comes from the content.
        window.setFrameAutosaveName("MainWindowPosition")
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Keep running in the menu bar; hide the Dock icon.
        NSApp.setActivationPolicy(.accessory)
        logger.info("Window closed; still running in the menu bar")
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.setAccessibilityLabel("MicKeeper")

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView:
            MenuBarView(openWindow: { [weak self] in self?.showWindow() },
                        quit: { NSApp.terminate(nil) })
                .environmentObject(model))

        model.$autoSwitch
            .sink { [weak self] on in self?.updateStatusIcon(autoSwitch: on) }
            .store(in: &cancellables)
        logger.info("Status item created")
    }

    private func updateStatusIcon(autoSwitch: Bool) {
        let name = autoSwitch ? "mic.fill" : "mic.slash.fill"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: autoSwitch ? "MicKeeper ativo" : "MicKeeper pausado")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = autoSwitch ? "MicKeeper: troca automática ativa" : "MicKeeper: pausado"
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: Main menu (visible while the window is open)

    private func setUpMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Sobre o MicKeeper", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar MicKeeper", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sair do MicKeeper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Janela")
        windowMenu.addItem(withTitle: "Fechar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    /// True when macOS opened the app as a login item.
    private static func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

@MainActor
enum SnapshotRenderer {
    static func run(path: String, dark: Bool, popover: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let model = AppModel()
        let root: AnyView = popover
            ? AnyView(MenuBarView(openWindow: {}, quit: {}).environmentObject(model))
            : AnyView(ContentView().environmentObject(model))
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
                              styleMask: popover ? [.borderless] : [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host

        // Let the enforcer deliver its first snapshot and the views lay out.
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("Wrote \(path)")
            exit(0)
        } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}
