import Foundation
import XCTest

final class JscpdConfigTests: XCTestCase {
    /// Walks up from the test source file to locate the project root (the
    /// directory containing Package.swift).
    private func projectRootURL() -> URL {
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
        let contents = try loadCIWorkflowContents()
        XCTAssertTrue(contents.contains("jscpd-check:"), "ci.yml should contain a jscpd-check job")
    }

    func testCIWorkflowJscpdJobRunsOnUbuntu() throws {
        let jobBlock = try extractJscpdJobBlock()
        let runsOnLine = jobBlock.components(separatedBy: "\n").first { $0.contains("runs-on:") }
        XCTAssertNotNil(runsOnLine, "jscpd-check job should have a runs-on key")
        XCTAssertTrue(
            runsOnLine?.contains("ubuntu-latest") == true,
            "jscpd-check job should run on ubuntu-latest"
        )
    }

    func testCIWorkflowJscpdJobInstallsPinnedVersion() throws {
        let jobBlock = try extractJscpdJobBlock()
        XCTAssertTrue(
            jobBlock.contains("npm install -g jscpd@"),
            "ci.yml should install a pinned version of jscpd via npm"
        )
    }

    func testCIWorkflowJscpdJobUsesThresholdFlag() throws {
        let jobBlock = try extractJscpdJobBlock()
        XCTAssertTrue(
            jobBlock.contains("--threshold 5"),
            "ci.yml jscpd invocation should include --threshold 5"
        )
    }

    func testCIWorkflowJscpdJobTargetsSources() throws {
        let jobBlock = try extractJscpdJobBlock()
        XCTAssertTrue(jobBlock.contains("jscpd"), "jscpd-check job should invoke jscpd")
        XCTAssertTrue(
            jobBlock.contains("Sources/"),
            "jscpd run command should target Sources/ directory"
        )
    }

    // MARK: - Helpers

    /// Loads and parses the `.jscpd.json` configuration as a dictionary.
    private func loadJscpdConfig() throws -> [String: Any] {
        let configURL = projectRootURL().appendingPathComponent(".jscpd.json")
        let data = try Data(contentsOf: configURL)
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
    }

    /// Reads the CI workflow YAML file contents.
    private func loadCIWorkflowContents() throws -> String {
        let ciURL = projectRootURL()
            .appendingPathComponent(".github")
            .appendingPathComponent("workflows")
            .appendingPathComponent("ci.yml")
        return try String(contentsOf: ciURL, encoding: .utf8)
    }

    /// Extracts the `jscpd-check` job block from the CI workflow.
    /// The block spans from the `jscpd-check:` key to the next top-level
    /// job key (a line with two-space indent followed by a key) or EOF.
    private func extractJscpdJobBlock() throws -> String {
        let contents = try loadCIWorkflowContents()
        guard let startRange = contents.range(of: "jscpd-check:") else {
            throw XCTSkip("ci.yml does not contain jscpd-check job — skipping dependent test")
        }
        let afterStart = String(contents[startRange.upperBound...])
        let lines = afterStart.components(separatedBy: "\n")

        // Collect lines until we hit the next top-level job header
        // (a non-empty line with exactly 2-space indent ending with a colon)
        var blockLines: [String] = []
        for line in lines {
            if !line.isEmpty,
               line.hasPrefix("  "),
               !line.hasPrefix("    "),
               line.trimmingCharacters(in: .whitespaces).hasSuffix(":")
            {
                break
            }
            blockLines.append(line)
        }
        return blockLines.joined(separator: "\n")
    }
}
