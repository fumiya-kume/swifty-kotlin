#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendMapFilterDestinationTests {

    @Test
    func testCodegenMapFilterFamilyUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/stdlib_kotlin_collections_Map_filter.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "MapFilterFamilyDestination",
            expected:
                """
                filterTo identity=true value={a=99, seed=0, b=2, c=3}
                filterNotTo identity=true value={seed=0, a=1}
                empty identity=true value={seed=0}
                nullable identity=true value={seed=0, value=2}
                exception=stop partial={seed=0, a=1}
                """ + "\n"
        )
    }
}
#endif
