#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite(.serialized)
struct CodegenBackendIterableContainsTests {
    @Test
    func iterableContainsUsesCanonicalDiffCaseAtRuntime() throws {
        let source = try diffCaseSource("stdlib_kotlin_collections_Iterable_contains.kt")
        try assertKotlinOutput(
            source,
            moduleName: "IterableContainsRuntime",
            expected: """
            true
            direct-iterators=1
            true
            operator-iterators=1
            false
            missing-iterators=1
            true
            empty-iterators=1
            true
            true
            true
            true

            """
        )
    }
}
#endif
