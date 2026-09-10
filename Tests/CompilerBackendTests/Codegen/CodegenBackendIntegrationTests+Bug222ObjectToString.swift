#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendBug222ObjectToStringTests {
    @Test
    func testObjectOverrideIsUsedByPrintAndPrintln() throws {
        let source = """
        object Singleton {
            override fun toString(): String = "I am Singleton"
        }
        fun main() {
            println(Singleton)
            print(Singleton)
            println()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug222ObjectOverride",
            expected: "I am Singleton\nI am Singleton\n"
        )
    }

    @Test
    func testObjectCrossingAnyBoundaryKeepsRegisteredHandle() throws {
        let source = """
        object Plain
        fun main() {
            val erased: Any = Plain
            println(Plain)
            println(erased)
            println("prefix=$erased")
        }
        """

        let output = try runKotlinOutput(source, moduleName: "Bug222ObjectAnyBoundary")
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 4)
        #expect(lines[0] == "Plain")
        #expect(lines[1].hasPrefix("<object 0x"))
        #expect(lines[2].hasPrefix("prefix=<object 0x"))
        #expect(!output.contains("\n0\n"))
    }

    private func runKotlinOutput(_ source: String, moduleName: String) throws -> String {
        var output = ""
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            output = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
        }
        return output
    }
}
#endif
