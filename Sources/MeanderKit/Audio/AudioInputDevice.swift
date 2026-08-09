import AVFoundation
import CoreAudio
import Foundation

public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public static let systemDefaultID = "system-default"

    public let id: String
    public let name: String
    public let isSystemDefault: Bool

    public init(id: String, name: String, isSystemDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isSystemDefault = isSystemDefault
    }
}

public enum AudioInputDevices {
    public static func available(includeSystemDefault: Bool = true) -> [AudioInputDevice] {
        var devices: [AudioInputDevice] = []

        if includeSystemDefault {
            let name = defaultInputDeviceName().map { "System Default (\($0))" }
                ?? "System Default Input"
            devices.append(AudioInputDevice(
                id: AudioInputDevice.systemDefaultID,
                name: name,
                isSystemDefault: true
            ))
        }

        let hardwareDevices = allDeviceIDs()
            .filter(hasInputChannels)
            .compactMap { deviceID -> AudioInputDevice? in
                guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, for: deviceID),
                      let name = stringProperty(kAudioObjectPropertyName, for: deviceID) else {
                    return nil
                }
                return AudioInputDevice(id: uid, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        devices.append(contentsOf: hardwareDevices)
        return devices
    }

    public static func displayName(for selectionID: String, in devices: [AudioInputDevice]? = nil) -> String {
        let knownDevices = devices ?? available()
        if let device = knownDevices.first(where: { $0.id == selectionID }) {
            return device.name
        }
        if selectionID == AudioInputDevice.systemDefaultID {
            return defaultInputDeviceName().map { "System Default (\($0))" } ?? "System Default Input"
        }
        return "System Default Input"
    }

    static func deviceID(for selectionID: String) -> AudioDeviceID? {
        guard selectionID != AudioInputDevice.systemDefaultID else { return nil }
        return allDeviceIDs().first { deviceID in
            stringProperty(kAudioDevicePropertyDeviceUID, for: deviceID) == selectionID
        }
    }

    private static func defaultInputDeviceName() -> String? {
        guard let deviceID = defaultInputDeviceID() else {
            return AVCaptureDevice.default(for: .audio)?.localizedName
        }
        return stringProperty(kAudioObjectPropertyName, for: deviceID)
            ?? AVCaptureDevice.default(for: .audio)?.localizedName
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        ) == noErr else {
            return []
        }

        return ids
    }

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else {
            return false
        }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr else {
            return false
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString>.size)
        let valuePointer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<CFString>.size,
            alignment: MemoryLayout<CFString>.alignment
        )
        defer { valuePointer.deallocate() }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, valuePointer)
        guard status == noErr else { return nil }
        let string = valuePointer.load(as: CFString.self) as String
        return string.isEmpty ? nil : string
    }
}
