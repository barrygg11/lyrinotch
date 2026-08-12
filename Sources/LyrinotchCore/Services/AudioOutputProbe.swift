import CoreAudio
import Foundation

/// Best-effort detection of whether the default output is headphones / Bluetooth
/// (mic calibration is usually useless in those cases).
public enum AudioOutputProbe {
    public enum Route: String, Sendable, Equatable {
        case speakers
        case headphones
        case bluetooth
        case unknown
    }

    public static func defaultOutputRoute() -> Route {
        guard let deviceID = defaultOutputDeviceID() else { return .unknown }
        return outputRoute(for: deviceID)
    }

    /// A stable identity for the current default output device.
    ///
    /// CoreAudio's device UID distinguishes devices that share the same broad
    /// route (for example, two different Bluetooth speakers). The route prefix
    /// also distinguishes data-source changes on one device, such as switching
    /// a Mac's built-in output between speakers and its headphone jack. When
    /// CoreAudio cannot provide a UID, this falls back to the existing route
    /// value so callers always receive a non-empty, persistable identity.
    public static func defaultOutputIdentity() -> String {
        guard let deviceID = defaultOutputDeviceID() else {
            return Route.unknown.rawValue
        }

        return outputIdentity(
            deviceUID: deviceUID(for: deviceID),
            fallbackRoute: outputRoute(for: deviceID)
        )
    }

    /// A stable identity for the current default input device used by mic
    /// calibration. Falling back to a fixed value intentionally invalidates a
    /// device-specific result if CoreAudio can no longer identify that input.
    public static func defaultInputIdentity() -> String {
        guard let deviceID = defaultInputDeviceID() else {
            return inputIdentity(deviceUID: nil)
        }
        return inputIdentity(deviceUID: deviceUID(for: deviceID))
    }

    /// The complete acoustic environment for an automatic calibration result.
    /// Both ends matter: changing either the playback device or the microphone
    /// can change the measured latency.
    public static func defaultCalibrationEnvironmentIdentity() -> String {
        calibrationEnvironmentIdentity(
            outputIdentity: defaultOutputIdentity(),
            inputIdentity: defaultInputIdentity()
        )
    }

    static func outputIdentity(deviceUID: String?, fallbackRoute: Route) -> String {
        if let deviceUID {
            let normalizedUID = deviceUID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedUID.isEmpty {
                return "\(fallbackRoute.rawValue)|\(normalizedUID)"
            }
        }
        return fallbackRoute.rawValue
    }

    static func inputIdentity(deviceUID: String?) -> String {
        guard let deviceUID else { return "unknown-input" }
        let normalizedUID = deviceUID.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedUID.isEmpty ? "unknown-input" : normalizedUID
    }

    static func calibrationEnvironmentIdentity(
        outputIdentity: String,
        inputIdentity: String
    ) -> String {
        "audio-environment-v1|output=\(outputIdentity)|input=\(inputIdentity)"
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    private static func defaultDeviceID(
        selector: AudioObjectPropertySelector
    ) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
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

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedUID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &unmanagedUID
        )
        guard status == noErr, let unmanagedUID else { return nil }
        let uid = unmanagedUID.takeRetainedValue()
        return uid as String
    }

    private static func outputRoute(for deviceID: AudioDeviceID) -> Route {
        // Transport type (built-in / headphone / Bluetooth / USB …)
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transport) == noErr {
            switch transport {
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                return .bluetooth
            case kAudioDeviceTransportTypeUSB:
                // USB DAC / headset — treat like headphones for mic purposes.
                return .headphones
            case kAudioDeviceTransportTypeBuiltIn:
                break
            default:
                break
            }
        }

        // Data source on output: often "Internal Speakers" vs "Headphones".
        var sourceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var sourceID: UInt32 = 0
        var sourceSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(deviceID, &sourceAddress, 0, nil, &sourceSize, &sourceID) == noErr {
            // FourCC 'hdpn' = headphones on many Macs.
            let headphonesCode: UInt32 = 0x6864_706E // 'hdpn'
            if sourceID == headphonesCode {
                return .headphones
            }
        }

        if transport == kAudioDeviceTransportTypeBuiltIn {
            return .speakers
        }
        return .unknown
    }

    /// Mic onset calibration is only reliable with open speakers.
    public static var micCalibrationLikelyUseful: Bool {
        switch defaultOutputRoute() {
        case .speakers, .unknown:
            // unknown: allow attempt; quiet gate will skip if no bleed.
            return true
        case .headphones, .bluetooth:
            return false
        }
    }
}
