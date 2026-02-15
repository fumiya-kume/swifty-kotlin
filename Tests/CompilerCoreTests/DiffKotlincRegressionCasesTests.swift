import Foundation
import XCTest

final class DiffKotlincRegressionCasesTests: XCTestCase {
    func testDiffKotlincRegressionCasesAreTracked() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let casesDir = root.appendingPathComponent("Scripts/diff_cases", isDirectory: true)
        let readmePath = casesDir.appendingPathComponent("README.md").path

        XCTAssertTrue(FileManager.default.fileExists(atPath: readmePath))

        let files = try FileManager.default.contentsOfDirectory(at: casesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "kt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThanOrEqual(files.count, 7)

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty case file: \(file.lastPathComponent)")
            XCTAssertTrue(contents.contains("fun "), "Regression case should include a function: \(file.lastPathComponent)")
        }
    }
}
