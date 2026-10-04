import Foundation

/// LumenPDF 的数据目录（`data.db`、书库、阅读日志、调用日志）。
/// 在 XCTest 宿主里运行时改用临时目录（可用 `LUMENPDF_TEST_DATA_DIR` 指定），测试绝不碰真实文库。
/// 这个环境变量只在 XCTest 下生效，正常启动时忽略。
enum AppDataDirectory {
    static let testOverrideKey = "LUMENPDF_TEST_DATA_DIR"

    static let current = url(environment: ProcessInfo.processInfo.environment)

    static var isRunningTests: Bool {
        isRunningTests(environment: ProcessInfo.processInfo.environment)
    }

    static func isRunningTests(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }

    static func url(environment: [String: String]) -> URL {
        if isRunningTests(environment: environment) {
            if let override = environment[testOverrideKey], !override.isEmpty {
                return URL(fileURLWithPath: override, isDirectory: true)
            }
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("LumenPDFTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LumenPDF", isDirectory: true)
    }
}
