#if canImport(Testing)
import Foundation
import Testing

/// Guards BUG-135: Swift Testing suites share one process and run
/// concurrently, so calling a process-global runtime reset / GC from one
/// suite deallocates live handles owned by other suites and crashes the test
/// process with a KSWIFTK-RUNTIME-0001 invalid-handle panic — but only
/// probabilistically, depending on scheduling.
///
/// This lint scans Swift Testing test sources for un-isolated calls to those
/// APIs so the mistake fails deterministically in the offending PR instead of
/// crashing unrelated CI runs. Tests that genuinely need these APIs must use
/// `.runtimeIsolation(...)` (or `RuntimeTestIsolationLease`) to serialize and
/// reset runtime state before/after each test.
@Suite
struct RuntimeSwiftTestingIsolationLintTests {
    private static let forbiddenCalls = [
        "kk_runtime_force_reset",
        "kk_runtime_reset_gc",
        "kk_runtime_reset_metadata",
        "kk_runtime_reset_flow",
        "kk_runtime_reset_thread_local",
        "kk_runtime_reset_delegate",
        "__kk_system_gc",
        "kk_gc_collect",
        "kk_gc_schedule",
    ]

    // Split so this file's own source never matches the marker.
    private static let swiftTestingMarker = "canImport(" + "Testing)"

    @Test
    func testSwiftTestingSuitesDoNotResetGlobalRuntimeState() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let testsRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
        var violations: [String] = []
        var scannedSwiftTestingFiles = 0

        for target in ["RuntimeTests", "RuntimeTestsParallel"] {
            let dir = testsRoot.appendingPathComponent(target)
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            for file in files.sorted(by: { $0.path < $1.path }) where file.pathExtension == "swift" {
                if file.lastPathComponent == thisFile.lastPathComponent { continue }
                let source = try String(contentsOf: file, encoding: .utf8)
                guard source.contains(Self.swiftTestingMarker) else { continue }
                // Isolated suites/leases acquire process-wide runtime locks and reset
                // state around each test, so calling reset/GC inside them is safe.
                let isIsolated = source.contains(".runtimeIsolation(")
                    || source.contains("RuntimeTestIsolationLease(")
                guard !isIsolated else { continue }
                scannedSwiftTestingFiles += 1

                for (index, rawLine) in source.components(separatedBy: "\n").enumerated() {
                    let line = rawLine.trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("//") { continue }
                    for call in Self.forbiddenCalls {
                        guard let range = line.range(of: call) else { continue }
                        let rest = line[range.upperBound...].drop { $0 == " " }
                        guard rest.first == "(" else { continue }
                        violations.append("\(target)/\(file.lastPathComponent):\(index + 1): \(call)()")
                    }
                }
            }
        }

        #expect(
            scannedSwiftTestingFiles > 0,
            "Lint scanned no Swift Testing files — the source layout changed and this lint needs updating"
        )
        #expect(
            violations.isEmpty,
            """
            Swift Testing suites must not mutate process-global runtime state without \
            `.runtimeIsolation(...)`: they run concurrently in one process, and a global \
            reset/GC deallocates handles owned by other suites (TODO.md BUG-135). Either \
            add `.runtimeIsolation(...)` to the suite or use `RuntimeTestIsolationLease`.
            \(violations.joined(separator: "\n"))
            """
        )
    }
}
#endif
