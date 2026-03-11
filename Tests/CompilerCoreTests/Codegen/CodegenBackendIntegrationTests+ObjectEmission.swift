@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenDefaultObjectEmissionSmoke() throws {
        let source = """
        fun helper(v: Int) = v + 1
        fun main() = helper(41)
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory

            let outputBase = tempDir.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "DefaultObjectSmoke",
                inputs: [path],
                outputPath: outputBase,
                emit: .object,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
            let objectSize = (try? FileManager.default.attributesOfItem(atPath: objectPath)[.size] as? NSNumber)?.intValue ?? 0
            XCTAssertGreaterThan(objectSize, 0)
        }
    }
}
