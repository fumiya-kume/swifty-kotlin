import XCTest
@testable import CompilerCore

final class CommandRunnerTests: XCTestCase {

    // MARK: - resolveExecutable

    func testResolveExecutableFindsExistingCommand() {
        let resolved = CommandRunner.resolveExecutable("ls", fallback: "/nonexistent/ls")
        XCTAssertTrue(resolved.hasSuffix("/ls"), "Expected resolved path to end with /ls, got: \(resolved)")
        XCTAssertNotEqual(resolved, "/nonexistent/ls", "Should have found ls in PATH")
    }

    func testResolveExecutableFallsBackForMissingCommand() {
        let fallback = "/this/path/does/not/exist/in/PATH"
        let resolved = CommandRunner.resolveExecutable("__command_that_definitely_does_not_exist__", fallback: fallback)
        XCTAssertEqual(resolved, fallback)
    }

    func testResolveExecutableReturnsFullPath() {
        let resolved = CommandRunner.resolveExecutable("echo", fallback: "/bin/echo")
        XCTAssertTrue(resolved.hasPrefix("/"), "Resolved path should be absolute, got: \(resolved)")
    }

    // MARK: - run: stdout / exit code

    func testRunSuccessfulCommandReturnsZeroExitCode() throws {
        let result = try CommandRunner.run(executable: "/bin/echo", arguments: [])
        XCTAssertEqual(result.exitCode, 0)
    }

    func testRunCommandCapturesStdout() throws {
        let result = try CommandRunner.run(executable: "/bin/echo", arguments: ["hello world"])
        XCTAssertTrue(result.stdout.contains("hello world"),
                      "Expected stdout to contain 'hello world', got: \(result.stdout)")
    }

    func testRunCommandCapturesMultipleArguments() throws {
        let result = try CommandRunner.run(executable: "/bin/echo", arguments: ["foo", "bar"])
        XCTAssertTrue(result.stdout.contains("foo"), "Expected stdout to contain 'foo'")
        XCTAssertTrue(result.stdout.contains("bar"), "Expected stdout to contain 'bar'")
    }

    // MARK: - run: nonzero exit

    func testRunNonZeroExitThrowsNonZeroExitError() {
        XCTAssertThrowsError(try CommandRunner.run(executable: "/usr/bin/false", arguments: [])) { error in
            guard case CommandRunnerError.nonZeroExit(let result) = error else {
                XCTFail("Expected nonZeroExit error, got: \(error)")
                return
            }
            XCTAssertNotEqual(result.exitCode, 0)
        }
    }

    func testNonZeroExitErrorContainsCommandResult() {
        do {
            _ = try CommandRunner.run(executable: "/usr/bin/false", arguments: [])
            XCTFail("Expected nonZeroExit to be thrown")
        } catch CommandRunnerError.nonZeroExit(let result) {
            XCTAssertNotEqual(result.exitCode, 0)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - run: launch failure

    func testRunNonexistentExecutableThrowsLaunchFailed() {
        XCTAssertThrowsError(
            try CommandRunner.run(executable: "/nonexistent/binary/path", arguments: [])
        ) { error in
            guard case CommandRunnerError.launchFailed = error else {
                XCTFail("Expected launchFailed error, got: \(error)")
                return
            }
        }
    }

    // MARK: - run: stderr capture

    func testRunCommandCapturesStderr() throws {
        // /bin/sh -c "echo errormsg >&2" writes to stderr
        let result = try CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo errormsg >&2"]
        )
        XCTAssertTrue(result.stderr.contains("errormsg"),
                      "stderr should contain the error message")
    }

    func testRunLargeOutputDoesNotDeadlock() throws {
        let result = try CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "yes x | head -c 131072"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, 131072)
    }

    func testRunLargeStderrDoesNotDeadlock() throws {
        let result = try CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "yes e | head -c 131072 1>&2"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr.count, 131072)
    }

    // MARK: - run: currentDirectoryPath

    func testRunCurrentDirectoryPathSetsWorkingDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory.path
        let result = try CommandRunner.run(
            executable: "/bin/pwd",
            arguments: [],
            currentDirectoryPath: tmpDir
        )
        let normalized = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // On macOS, /var/folders may be a symlink to /private/var/folders.
        // Accept either the original or resolved path.
        let resolvedTmp = (try? FileManager.default.destinationOfSymbolicLink(atPath: tmpDir)) ?? tmpDir
        XCTAssertTrue(
            normalized == tmpDir || normalized == resolvedTmp || normalized.hasPrefix("/private"),
            "Expected pwd output to match tmpDir, got: \(normalized)"
        )
    }
}
