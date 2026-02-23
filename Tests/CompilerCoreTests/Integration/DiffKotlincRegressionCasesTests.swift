import Foundation
import XCTest

final class DiffKotlincRegressionCasesTests: XCTestCase {
    func testDiffKotlincRegressionCasesAreTracked() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Integration/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let casesDir = root.appendingPathComponent("Scripts/diff_cases", isDirectory: true)
        let readmePath = casesDir.appendingPathComponent("README.md").path

        XCTAssertTrue(FileManager.default.fileExists(atPath: readmePath))

        let files = try FileManager.default.contentsOfDirectory(at: casesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "kt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThanOrEqual(files.count, 13)

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty case file: \(file.lastPathComponent)")
            let isScript = file.lastPathComponent.hasPrefix("script_")
            if !isScript {
                XCTAssertTrue(contents.contains("fun "), "Regression case should include a function: \(file.lastPathComponent)")
            }
        }
    }
}
