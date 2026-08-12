import XCTest
@testable import LyrinotchCore

final class MacHardwareInfoProviderTests: XCTestCase {
    func testReturnsTrimmedMachineNameFromValidSystemProfilerJSON() async {
        let provider = MacHardwareInfoProvider(loader: {
            ProcessResult(
                exitCode: 0,
                stdout: #"{"SPHardwareDataType":[{"machine_name":"  MacBook Pro  "}]}"#,
                stderr: ""
            )
        })

        let name = await provider.modelName()

        XCTAssertEqual(name, "MacBook Pro")
    }

    func testReturnsNilForMalformedMissingOrEmptyMachineName() async {
        let malformed = MacHardwareInfoProvider(loader: {
            ProcessResult(exitCode: 0, stdout: "not json", stderr: "")
        })
        let missing = MacHardwareInfoProvider(loader: {
            ProcessResult(exitCode: 0, stdout: #"{"SPHardwareDataType":[{}]}"#, stderr: "")
        })
        let empty = MacHardwareInfoProvider(loader: {
            ProcessResult(exitCode: 0, stdout: #"{"SPHardwareDataType":[{"machine_name":"   "}]}"#, stderr: "")
        })

        let malformedName = await malformed.modelName()
        let missingName = await missing.modelName()
        let emptyName = await empty.modelName()

        XCTAssertNil(malformedName)
        XCTAssertNil(missingName)
        XCTAssertNil(emptyName)
    }

    func testReturnsNilForUnsuccessfulProcess() async {
        let provider = MacHardwareInfoProvider(loader: {
            ProcessResult(exitCode: 1, stdout: #"{"SPHardwareDataType":[{"machine_name":"MacBook Pro"}]}"#, stderr: "failed")
        })

        let name = await provider.modelName()

        XCTAssertNil(name)
    }

    func testCachesFailureForTheSession() async {
        let counter = ProviderInvocationCounter()
        let provider = MacHardwareInfoProvider(loader: {
            await counter.increment()
            throw ProcessRunnerError.timedOut(seconds: 2)
        })

        let first = await provider.modelName()
        let second = await provider.modelName()
        let callCount = await counter.value

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(callCount, 1)
    }

    func testCachesSuccessfulNameForTheSession() async {
        let counter = ProviderInvocationCounter()
        let provider = MacHardwareInfoProvider(loader: {
            await counter.increment()
            return ProcessResult(
                exitCode: 0,
                stdout: #"{"SPHardwareDataType":[{"machine_name":"MacBook Pro"}]}"#,
                stderr: ""
            )
        })

        let first = await provider.modelName()
        let second = await provider.modelName()
        let callCount = await counter.value

        XCTAssertEqual(first, "MacBook Pro")
        XCTAssertEqual(second, "MacBook Pro")
        XCTAssertEqual(callCount, 1)
    }
}

private actor ProviderInvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
