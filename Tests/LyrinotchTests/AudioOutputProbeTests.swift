import XCTest
@testable import LyrinotchCore

final class AudioOutputProbeTests: XCTestCase {
    func testOutputIdentityPrefersDeviceUID() {
        XCTAssertEqual(
            AudioOutputProbe.outputIdentity(
                deviceUID: "AppleUSBAudioEngine:Example Device:1,2:3",
                fallbackRoute: .headphones
            ),
            "headphones|AppleUSBAudioEngine:Example Device:1,2:3"
        )
    }

    func testOutputIdentityNormalizesUIDWhitespace() {
        XCTAssertEqual(
            AudioOutputProbe.outputIdentity(
                deviceUID: "  BuiltInSpeakerDevice  \n",
                fallbackRoute: .speakers
            ),
            "speakers|BuiltInSpeakerDevice"
        )
    }

    func testOutputIdentityIncludesRouteWhenUIDIsShared() {
        let speakerIdentity = AudioOutputProbe.outputIdentity(
            deviceUID: "BuiltInOutputDevice",
            fallbackRoute: .speakers
        )
        let headphoneIdentity = AudioOutputProbe.outputIdentity(
            deviceUID: "BuiltInOutputDevice",
            fallbackRoute: .headphones
        )

        XCTAssertNotEqual(speakerIdentity, headphoneIdentity)
    }

    func testOutputIdentityFallsBackToRouteForMissingUID() {
        XCTAssertEqual(
            AudioOutputProbe.outputIdentity(deviceUID: nil, fallbackRoute: .bluetooth),
            AudioOutputProbe.Route.bluetooth.rawValue
        )
        XCTAssertEqual(
            AudioOutputProbe.outputIdentity(deviceUID: " \n", fallbackRoute: .unknown),
            AudioOutputProbe.Route.unknown.rawValue
        )
    }

    func testDefaultOutputIdentityIsAlwaysPersistable() {
        XCTAssertFalse(AudioOutputProbe.defaultOutputIdentity().isEmpty)
    }

    func testInputIdentityPrefersNormalizedDeviceUID() {
        XCTAssertEqual(
            AudioOutputProbe.inputIdentity(deviceUID: "  BuiltInMicrophoneDevice \n"),
            "BuiltInMicrophoneDevice"
        )
    }

    func testInputIdentityHasStableFallback() {
        XCTAssertEqual(AudioOutputProbe.inputIdentity(deviceUID: nil), "unknown-input")
        XCTAssertEqual(AudioOutputProbe.inputIdentity(deviceUID: " \n"), "unknown-input")
    }

    func testCalibrationEnvironmentIncludesOutputAndInputIdentity() {
        XCTAssertEqual(
            AudioOutputProbe.calibrationEnvironmentIdentity(
                outputIdentity: "speakers|BuiltInOutputDevice",
                inputIdentity: "BuiltInMicrophoneDevice"
            ),
            "audio-environment-v1|output=speakers|BuiltInOutputDevice|input=BuiltInMicrophoneDevice"
        )
    }

    func testDefaultInputAndCalibrationEnvironmentAreAlwaysPersistable() {
        XCTAssertFalse(AudioOutputProbe.defaultInputIdentity().isEmpty)
        XCTAssertFalse(AudioOutputProbe.defaultCalibrationEnvironmentIdentity().isEmpty)
    }
}
