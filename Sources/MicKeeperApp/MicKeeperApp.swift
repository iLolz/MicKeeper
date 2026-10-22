import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        // `--snapshot <path.png> [--dark]` renders the window offscreen and exits (no Screen Recording permission needed).
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            SnapshotRenderer.run(path: args[index + 1], dark: args.contains("--dark"))
        } else {
            MicKeeperApp.main()
        }
    }
}

struct MicKeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("MicKeeper", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 460, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 480, height: 680)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare binary (`swift run`); harmless inside the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Step 3 replaces this with the menu bar mode.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
enum SnapshotRenderer {
    static func run(path: String, dark: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let model = AppModel()
        let size = NSSize(width: 480, height: 680)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: ContentView().environmentObject(model).frame(width: size.width, height: size.height))
        window.contentView = host

        // Let the enforcer deliver its first snapshot and the List lay out.
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
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
