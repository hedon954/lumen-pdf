import XCTest
@testable import LumenPDF

final class AppDataDirectoryTests: XCTestCase {
    private let xctest = ["XCTestConfigurationFilePath": "/tmp/fake.xctestconfiguration"]

    func testUnderXCTestTheDataDirectoryIsATemporaryFolder() {
        let url = AppDataDirectory.url(environment: xctest)
        XCTAssertTrue(url.path.hasPrefix(FileManager.default.temporaryDirectory.path), url.path)
        XCTAssertFalse(url.path.contains("Application Support"), url.path)
    }

    func testOverrideIsHonoredOnlyUnderXCTest() {
        var environment = xctest
        environment[AppDataDirectory.testOverrideKey] = "/tmp/lumenpdf-fake-data"
        XCTAssertEqual(AppDataDirectory.url(environment: environment).path, "/tmp/lumenpdf-fake-data")

        let normal = AppDataDirectory.url(environment: [AppDataDirectory.testOverrideKey: "/tmp/lumenpdf-fake-data"])
        XCTAssertTrue(normal.path.hasSuffix("Application Support/LumenPDF"), normal.path)
    }

    func testThisTestRunNeverUsesTheRealLibrary() {
        XCTAssertTrue(AppDataDirectory.isRunningTests)
        XCTAssertFalse(AppDataDirectory.current.path.contains("Application Support/LumenPDF"), AppDataDirectory.current.path)
    }
}
