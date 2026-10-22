import Foundation
import MicPriorityCore

let usage = """
Usage: micpriority-cli <command>

Commands:
  list                    Input devices and the priority order
  watch                   Enforce the priority order and print events until Ctrl+C
  move <uid> <position>   Move a device to a position (1 = highest priority)
  disable <uid>           Never use this microphone
  enable <uid>            Allow this microphone again
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let system = AudioDeviceService()
let store = ConfigStore()

func loadConfig() -> PriorityConfig {
    do { return try store.load() } catch { fail("Could not read \(store.url.path): \(error)") }
}

func saveConfig(_ config: PriorityConfig) {
    do { try store.save(config) } catch { fail("Could not write \(store.url.path): \(error)") }
}

/// Loads the config and registers currently connected devices, saving if anything was added.
func loadRegisteredConfig() -> PriorityConfig {
    var config = loadConfig()
    if !config.register(system.listInputDevices()).isEmpty { saveConfig(config) }
    return config
}

func printList() {
    let devices = system.listInputDevices()
    let defaultUID = system.currentDefaultInput()?.uid
    let config = loadRegisteredConfig()
    let connected = Set(devices.map(\.uid))

    print("Input devices:")
    for device in devices {
        let mark = device.uid == defaultUID ? "*" : " "
        let alive = device.isAlive ? "" : " (not alive)"
        print(" \(mark) \(device.name) [\(device.transportType.displayName)]\(alive)")
        print("     uid: \(device.uid)")
    }
    print("   (* = current default)")
    print("")
    print("Priority order (\(store.url.path)):")
    for (index, known) in config.devices.enumerated() {
        let state = config.isEnabled(uid: known.uid) ? "enabled " : "disabled"
        let presence = connected.contains(known.uid) ? "connected" : "offline"
        print("  \(index + 1). [\(state)] \(known.name) [\(known.transportType.displayName), \(presence)]")
        print("     uid: \(known.uid)")
    }
    let chosen = PriorityEngine.chooseDevice(available: devices, config: config)
    print("")
    print("Auto-disable new Bluetooth mics: \(config.autoDisableBluetoothMics ? "on" : "off")")
    print("Preferred device right now: \(chosen?.name ?? "none (system left alone)")")
}

func requireKnown(_ uid: String, in config: PriorityConfig) {
    if config.position(of: uid) == nil { fail("Unknown uid \(uid). Run `list` to see known devices.") }
}

func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "list":
    printList()

case "watch":
    let enforcer = PriorityEnforcer(system: system, config: loadConfig(), store: store)
    enforcer.onEvent = { print("[\(timestamp())] event: \($0)") }
    enforcer.onDecision = { print("[\(timestamp())] decision: \($0)") }
    enforcer.onConfigChange = { config in
        print("[\(timestamp())] config saved (\(config.devices.count) known devices)")
    }
    // Pick up changes made by the app (or another CLI command) to the shared config.json.
    let watcher = ConfigFileWatcher(store: store) { enforcer.reloadConfig($0) }
    watcher.start()
    signal(SIGINT, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler {
        watcher.stop()
        enforcer.stop()
        print("\nStopped.")
        exit(0)
    }
    sigint.resume()
    setvbuf(stdout, nil, _IOLBF, 0)
    print("Watching audio devices. Press Ctrl+C to stop.")
    enforcer.start()
    dispatchMain()

case "move":
    guard args.count == 3, let position = Int(args[2]), position >= 1 else { fail(usage) }
    var config = loadRegisteredConfig()
    requireKnown(args[1], in: config)
    config.move(uid: args[1], to: position - 1)
    saveConfig(config)
    printList()

case "disable", "enable":
    guard args.count == 2 else { fail(usage) }
    var config = loadRegisteredConfig()
    requireKnown(args[1], in: config)
    config.setEnabled(args[0] == "enable", uid: args[1])
    saveConfig(config)
    printList()

default:
    print(usage)
    exit(args.isEmpty || args.first == "help" ? 0 : 1)
}
