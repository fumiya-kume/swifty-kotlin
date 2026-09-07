#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendMatchNamedGroupCollectionTests {
    @Test func testNamedAccessorPreservesOptionalAndMissingGroupBehavior() throws {
        let source = """
        fun main() {
            val optional = Regex("(?<name>a)?").find("")
            println(optional?.groups?.get("name")?.value ?: "null")

            val matched = Regex("(?<name>a)").find("a")
            println(matched?.groups?.get("name")?.value ?: "null")

            try {
                matched?.groups?.get("missing")
                println("no-error")
            } catch (e: IllegalArgumentException) {
                println("invalid-name")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchNamedGroupCollectionBehavior",
            expected:
                """
                null
                a
                invalid-name
                """ + "\n"
        )
    }
}
#endif
