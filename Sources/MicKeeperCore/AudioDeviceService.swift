import CoreAudio
import Foundation
import os

/// CoreAudio implementation of `AudioSystem`.
public final class AudioDeviceService: AudioSystem {
    private let logger = Logger(subsystem: Log.subsystem, category: "AudioDeviceService")
    private let listenerQueue = DispatchQueue(label: "com.alencar.mickeeper.coreaudio-listener")
    private var handler: ((AudioChangeEvent) -> Void)?
    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?

    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    public init() {}

    deinit { stopListening() }

    // MARK: Queries

    public func listInputDevices() -> [AudioDevice] {
        allDeviceIDs().compactMap { id in
            guard inputChannelCount(id) > 0 else { return nil }
            return makeDevice(id)
        }
    }

    public func currentDefaultInput() -> AudioDevice? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.defaultInputAddress
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return makeDevice(id)
    }

    public func setDefaultInput(uid: String) throws {
        guard let device = listInputDevices().first(where: { $0.uid == uid }) else {
            throw AudioSystemError.deviceNotFound(uid: uid)
        }
        var id = device.id
        var address = Self.defaultInputAddress
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        guard status == noErr else {
            throw AudioSystemError.coreAudio(status: status, operation: "Set default input")
        }
    }

    // MARK: Listening

    public func startListening(_ handler: @escaping (AudioChangeEvent) -> Void) {
        stopListening()
        self.handler = handler

        let devices: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handler?(.devicesChanged)
        }
        let defaultInput: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handler?(.defaultInputChanged)
        }
        let system = AudioObjectID(kAudioObjectSystemObject)

        var status = AudioObjectAddPropertyListenerBlock(system, &Self.devicesAddress, listenerQueue, devices)
        if status == noErr { devicesListener = devices } else {
            logger.error("Failed to add devices listener: \(status)")
        }
        status = AudioObjectAddPropertyListenerBlock(system, &Self.defaultInputAddress, listenerQueue, defaultInput)
        if status == noErr { defaultInputListener = defaultInput } else {
            logger.error("Failed to add default input listener: \(status)")
        }
    }

    public func stopListening() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if let block = devicesListener {
            AudioObjectRemovePropertyListenerBlock(system, &Self.devicesAddress, listenerQueue, block)
            devicesListener = nil
        }
        if let block = defaultInputListener {
            AudioObjectRemovePropertyListenerBlock(system, &Self.defaultInputAddress, listenerQueue, block)
            defaultInputListener = nil
        }
        handler = nil
    }

    // MARK: CoreAudio helpers

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = Self.devicesAddress
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func makeDevice(_ id: AudioDeviceID) -> AudioDevice? {
        guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let name = stringProperty(id, kAudioObjectPropertyName) ?? uid
        let transport = uint32Property(id, kAudioDevicePropertyTransportType).map(TransportType.init(coreAudioValue:)) ?? .other
        let alive = (uint32Property(id, kAudioDevicePropertyDeviceIsAlive) ?? 1) != 0
        return AudioDevice(id: id, uid: uid, name: name, transportType: transport, isAlive: alive)
    }

    private func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let listPointer = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, listPointer) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(listPointer).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() else { return nil }
        return string as String
    }

    private func uint32Property(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}

enum Log {
    static let subsystem = "com.alencar.mickeeper"
}
