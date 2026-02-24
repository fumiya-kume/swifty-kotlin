import Foundation
import XCTest

final class JscpdConfigTests: XCTestCase {

    private func projectRootURL() -> URL {
        // Tests run from the package directory; walk up from the test file location
        // to find the project root by locating Package.swift.
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        // Fallback: current working directory
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    // MARK: - .jscpd.json validation

    func testJscpdConfigFileExists() {
        let configPath = projectRootURL().appendingPathComponent(".jscpd.json").path
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: configPath),
            ".jscpd.json should exist at the project root"
        )
    }

    func testJscpdConfigIsValidJSON() throws {
        let configURL = projectRootURL().appendingPathComponent(".jscpd.json")
        let data = try Data(contentsOf: configURL)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [String: Any], ".jscpd.json should be a JSON object")
    }

    func testJscpdConfigHasExpectedThreshold() throws {
        let config = try loadJscpdConfig()
        let threshold = try XCTUnwrap(config["threshold"] as? Int, "threshold key should be an integer")
        XCTAssertEqual(threshold, 5, "Duplication threshold should be 5%")
    }

    func testJscpdConfigHasSwiftFormat() throws {
        let config = try loadJscpdConfig()
        let format = try XCTUnwrap(config["format"] as? [String], "format key should be a string array")
        XCTAssertTrue(format.contains("swift"), "format should include 'swift'")
    }

    func testJscpdConfigTargetsSourcesDirectory() throws {
        let config = try loadJscpdConfig()
        let path = try XCTUnwrap(config["path"] as? [String], "path key should be a string array")
        XCTAssertTrue(path.contains("Sources/"), "path should include 'Sources/'")
    }

    func testJscpdConfigHasGitignoreEnabled() throws {
        let config = try loadJscpdConfig()
        let gitignore = try XCTUnwrap(config["gitignore"] as? Bool, "gitignore key should be a boolean")
        XCTAssertTrue(gitignore, "gitignore should be enabled")
    }

    func testJscpdConfigUsesRelativePaths() throws {
        let config = try loadJscpdConfig()
        let absolute = try XCTUnwrap(config["absolute"] as? Bool, "absolute key should be a boolean")
        XCTAssertFalse(absolute, "absolute should be false for relative paths")
    }

    func testJscpdConfigHasConsoleReporter() throws {
        let config = try loadJscpdConfig()
        let reporters = try XCTUnwrap(config["reporters"] as? [String], "reporters key should be a string array")
        XCTAssertTrue(reporters.contains("console"), "reporters should include 'console'")
    }

    func testJscpdConfigHasMinLinesAndMinTokens() throws {
        let config = try loadJscpdConfig()
        let minLines = try XCTUnwrap(config["minLines"] as? Int, "minLines key should be an integer")
        let minTokens = try XCTUnwrap(config["minTokens"] as? Int, "minTokens key should be an integer")
        XCTAssertGreaterThan(minLines, 0, "minLines should be positive")
        XCTAssertGreaterThan(minTokens, 0, "minTokens should be positive")
    }

    // MARK: - CI workflow validation

    func testCIWorkflowContainsJscpdCheckJob() throws {
        let ciURL = projectRootURL()
            .appendingPathComponent(".github")
            .appendingPathComponent("workflows")
            .appendingPathComponent("ci.yml")
        let contents = try String(contentsOf: ciURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("jscpd-check:"), "ci.yml should contain a jscpd-check job")
    }

    func testCIWorkflowJscpdJobRunsOnUbuntu() throws {
        let ciURL = projectRootURL()
            .appendingPathComponent(".github")
            .appendingPathComponent("workflows")
            .appendingPathComponent("ci.yml")
        let contents = try String(contentsOf: ciURL, encoding: .utf8)

        // Find the jscpd-check section and verify it uses ubuntu-latest
        guard let jscpdRange = contents.range(of: "jscpd-check:") else {
            XCTFail("ci.yml should contain jscpd-check job")
            return
        }
        let afterJscpd = String(contents[jscpdRange.upperBound...])
        // Look within the next few lines for runs-on
        let lines = afterJscpd.components(separatedBy: "\n").prefix(10)
        let runsOnLine = lines.first { $0.contains("runs-on:") }
        XCTAssertNotNil(runsOnLine, "jscpd-check job should have a runs-on key")
        XCTAssertTrue(
            runsOnLine?.contains("ubuntu-latest") == true,
            "jscpd-check job should run on ubuntu-latest"
        )
    }

    func testCIWorkflowJscpdJobInstallsJscpd() throws {
        let ciURL = projectRootURL()
            .appendingPathComponent(".github")
            .appendingPathComponent("workflows")
            .appendingPathComponent("ci.yml")
        let contents = try String(contentsOf: ciURL, encoding: .utf8)
        XCTAssertTrue(
            contents.contains("npm install -g jscpd"),
            "ci.yml should install jscpd via npm"
        )
    }

    func testCIWorkflowJscpdJobUsesThresholdFlag() throws {
        let ciURL = projectRootURL()
            .appendingPathComponent(".github")
            .appendingPathComponent("workflows")
            .appendingPathComponent("ci.yml")
        let contents = try String(contentsOf: ciURL, encoding: .utf8)
        XCTAssertTrue(
            contents.contains("--threshold 5"),
            "ci.yml jscpd invocation should include --threshold 5"
        )
    }

    func testCIWorkflowJscpdJobTargetsSources() throws {
        let ciURL = projectRootURL()
            .appendingPathComponent(".github")
            .appendingPathComponent("workflows")
            .appendingPathComponent("ci.yml")
        let contents = try String(contentsOf: ciURL, encoding: .utf8)

        // Find jscpd run command line
        guard let runRange = contents.range(of: "run: jscpd") else {
            XCTFail("ci.yml should contain a 'run: jscpd' step")
            return
        }
        let line = String(contents[runRange.lowerBound...])
            .components(separatedBy: "\n")
            .first ?? ""
        XCTAssertTrue(
            line.contains("Sources/"),
            "jscpd run command should target Sources/ directory"
        )
    }

    // MARK: - Helpers

    private func loadJscpdConfig() throws -> [String: Any] {
        let configURL = projectRootURL().appendingPathComponent(".jscpd.json")
        let data = try Data(contentsOf: configURL)
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
    }
}
