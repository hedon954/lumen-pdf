import XCTest
@testable import LumenPDF

final class AppUpdatePolicyTests: XCTestCase {
    func testInstallLocationBlocksReadOnlyTranslocatedAndUnwritableCopies() {
        XCTAssertEqual(
            AppInstallLocationPolicy.decide(facts(path: "/Applications/LumenPDF.app", readOnly: false, writable: true)),
            .replaceInPlace
        )
        XCTAssertEqual(
            AppInstallLocationPolicy.decide(facts(path: "/Volumes/LumenPDF/LumenPDF.app", readOnly: true, writable: true)),
            .blocked(.diskImage)
        )
        XCTAssertEqual(
            AppInstallLocationPolicy.decide(
                facts(path: "/private/var/folders/xx/AppTranslocation/yy/d/LumenPDF.app", readOnly: true, writable: false)
            ),
            .blocked(.translocated)
        )
        XCTAssertEqual(
            AppInstallLocationPolicy.decide(facts(path: "/Applications/LumenPDF.app", readOnly: false, writable: false)),
            .blocked(.notWritable)
        )
        XCTAssertEqual(
            AppInstallLocationPolicy.decide(facts(path: "", readOnly: false, writable: true)),
            .blocked(.notWritable)
        )
    }

    func testAutomaticCheckWaitsAfterSuccessAndRetriesAfterFailureBackoff() {
        let now: TimeInterval = 1_000_000
        XCTAssertFalse(AutomaticUpdateCheck.shouldRun(
            enabled: false, suppressed: false, now: now, lastSuccess: nil, lastFailure: nil
        ))
        XCTAssertFalse(AutomaticUpdateCheck.shouldRun(
            enabled: true, suppressed: true, now: now, lastSuccess: nil, lastFailure: nil
        ))
        XCTAssertFalse(AutomaticUpdateCheck.shouldRun(
            enabled: true, suppressed: false, now: now,
            lastSuccess: now - AutomaticUpdateCheck.successInterval + 1, lastFailure: nil
        ))
        XCTAssertTrue(AutomaticUpdateCheck.shouldRun(
            enabled: true, suppressed: false, now: now,
            lastSuccess: now - AutomaticUpdateCheck.successInterval, lastFailure: nil
        ))
        XCTAssertFalse(AutomaticUpdateCheck.shouldRun(
            enabled: true, suppressed: false, now: now,
            lastSuccess: nil, lastFailure: now - AutomaticUpdateCheck.failureBackoff + 1
        ))
        XCTAssertTrue(AutomaticUpdateCheck.shouldRun(
            enabled: true, suppressed: false, now: now, lastSuccess: nil, lastFailure: nil
        ))
    }

    func testDiskImageMountPointUsesTheFirstMountedEntity() {
        let plist: [String: Any] = [
            "system-entities": [
                ["dev-entry": "/dev/disk4"],
                ["mount-point": "/Volumes/LumenPDF 1.0.34", "dev-entry": "/dev/disk4s1"]
            ]
        ]

        XCTAssertEqual(DiskImageAttach.mountPoint(in: plist), "/Volumes/LumenPDF 1.0.34")
        XCTAssertNil(DiskImageAttach.mountPoint(in: ["system-entities": [["dev-entry": "/dev/disk4"]]]))
    }

    private func facts(path: String, readOnly: Bool, writable: Bool) -> BundleLocationFacts {
        BundleLocationFacts(bundlePath: path, volumeIsReadOnly: readOnly, parentIsWritable: writable)
    }
}
