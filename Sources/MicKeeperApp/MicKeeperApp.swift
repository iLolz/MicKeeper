import AppKit
import Combine
import MicKeeperCore
import os
import SwiftUI

@main
enum Entry {
    // NSApplication keeps only a weak reference to its delegate.
    private static var delegate: AppDelegate?

    static func main() {
        // `--snapshot <path.png> [--dark] [--popover | --settings] [--lang pt-BR|en|es]` renders offscreen
        // and exits (no Screen Recording permission needed).
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            let language = args.firstIndex(of: "--lang").flatMap { $0 + 1 < args.count ? AppLanguage(rawValue: args[$0 + 1]) : nil }
            let kind: SnapshotRenderer.Kind = args.contains("--popover") ? .popover
                : args.contains("--settings") ? .settings
                : args.contains("--status-icon") ? .statusIcon : .window
            SnapshotRenderer.run(path: args[index + 1], dark: args.contains("--dark"), kind: kind, language: language)
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
    private var settingsWindow: NSWindow?
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
        let host = NSHostingView(rootView: LocalizedRoot { [weak self] in
            ContentView(openSettings: { self?.showSettings() })
        }.environmentObject(model))
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
        let closing = notification.object as? NSWindow
        // Keep running in the menu bar; hide the Dock icon once no window is left.
        let otherVisible = [window, settingsWindow].contains { $0 != nil && $0 !== closing && $0!.isVisible }
        guard !otherVisible else { return }
        NSApp.setActivationPolicy(.accessory)
        logger.info("Window closed; still running in the menu bar")
    }

    // MARK: Settings

    @objc func showSettings() {
        popover.performClose(nil)
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        window.title = tr("settings.title")
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 120),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: LocalizedRoot { SettingsView() }.environmentObject(model))
        host.sizingOptions = [.minSize, .maxSize, .intrinsicContentSize]
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.center()
        window.setFrameAutosaveName("SettingsWindowPosition")
        window.delegate = self
        return window
    }

    /// Updates the AppKit parts (menus, titles, tooltips) after a language change; SwiftUI views rebuild themselves.
    private func applyLanguage() {
        setUpMainMenu()
        settingsWindow?.title = tr("settings.title")
        updateStatusIcon(autoSwitch: model.autoSwitch)
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.setAccessibilityLabel("MicKeeper")

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: LocalizedRoot { [weak self] in
            MenuBarView(openWindow: { self?.showWindow() },
                        openSettings: { self?.showSettings() },
                        quit: { NSApp.terminate(nil) })
        }.environmentObject(model))

        model.$autoSwitch
            .sink { [weak self] on in self?.updateStatusIcon(autoSwitch: on) }
            .store(in: &cancellables)
        model.$languageChoice
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyLanguage() }
            .store(in: &cancellables)
        logger.info("Status item created")
    }

    private func updateStatusIcon(autoSwitch: Bool) {
        let tooltip = autoSwitch ? tr("statusItem.active") : tr("statusItem.paused")
        let image = Logo.menuBarImage(paused: !autoSwitch)
        image.accessibilityDescription = tooltip
        statusItem.button?.image = image
        statusItem.button?.toolTip = tooltip
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
        appMenu.addItem(withTitle: tr("mainMenu.about"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: tr("mainMenu.settings"), action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("mainMenu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("mainMenu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: tr("mainMenu.window"))
        windowMenu.addItem(withTitle: tr("mainMenu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: tr("mainMenu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
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
    enum Kind { case window, popover, settings, statusIcon }

    static func run(path: String, dark: Bool, kind: Kind, language: AppLanguage?) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let model = AppModel(languageOverride: language)
        let root: AnyView
        switch kind {
        case .window: root = AnyView(ContentView(openSettings: {}).environmentObject(model))
        case .popover: root = AnyView(MenuBarView(openWindow: {}, openSettings: {}, quit: {}).environmentObject(model))
        case .settings: root = AnyView(SettingsView().environmentObject(model))
        case .statusIcon:
            // Both menu bar variants at 4x, black on white, to check the template artwork.
            root = AnyView(HStack(spacing: 24) {
                ForEach([false, true], id: \.self) { paused in
                    Image(nsImage: Logo.menuBarImage(paused: paused)).resizable().frame(width: 72, height: 72)
                }
            }.padding(16).background(Color.white).foregroundStyle(.black))
        }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
                              styleMask: kind == .popover || kind == .statusIcon ? [.borderless] : [.titled, .fullSizeContentView],
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
