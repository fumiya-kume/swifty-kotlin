#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    /// KSP-1166: Base64 range and destination APIs resolve to bundled Kotlin
    /// source declarations instead of legacy runtime bridge symbols.
    @Test
    func testBase64RangeAndDestinationAPIsAreSourceBacked() throws {
        let source = """
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi
        import kotlin.text.Appendable

        @OptIn(ExperimentalEncodingApi::class)
        fun encodeRange(source: ByteArray): String = Base64.Default.encode(source, 1, 4)

        @OptIn(ExperimentalEncodingApi::class)
        fun encodeToByteArrayRange(source: ByteArray): ByteArray =
            Base64.Default.encodeToByteArray(source, 1, 4)

        @OptIn(ExperimentalEncodingApi::class)
        fun encodeIntoByteArrayRange(source: ByteArray, destination: ByteArray): Int =
            Base64.Default.encodeIntoByteArray(source, destination, 2, 1, 4)

        @OptIn(ExperimentalEncodingApi::class)
        fun encodeToAppendableRange(source: ByteArray, destination: Appendable): Appendable =
            Base64.Default.encodeToAppendable(source, destination, 1, 4)

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeByteArrayRange(source: ByteArray): ByteArray = Base64.Default.decode(source, 1, 5)

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeIntoByteArrayRange(source: ByteArray, destination: ByteArray): Int =
            Base64.Default.decodeIntoByteArray(source, destination, 2, 1, 5)

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeCharSequenceRange(source: CharSequence): ByteArray = Base64.Default.decode(source, 1, 5)

        @OptIn(ExperimentalEncodingApi::class)
        fun decodeIntoCharSequenceRange(source: CharSequence, destination: ByteArray): Int =
            Base64.Default.decodeIntoByteArray(source, destination, 2, 1, 5)
        """
        let expectedNames: Set<String> = [
            "encode",
            "encodeToByteArray",
            "encodeIntoByteArray",
            "encodeToAppendable",
            "decode",
            "decodeIntoByteArray",
        ]

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Base64 range APIs should lower without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let module = try #require(ctx.kir)
            let calls: [(String, SymbolID)] = findAllKIRFunctions(in: module).flatMap { function in
                function.body.compactMap { instruction -> (String, SymbolID)? in
                    switch instruction {
                    case let .call(symbol, callee, _, _, _, _, _, _),
                         let .virtualCall(symbol, callee, _, _, _, _, _, _):
                        guard let symbol, expectedNames.contains(ctx.interner.resolve(callee)) else {
                            return nil
                        }
                        return (ctx.interner.resolve(callee), symbol)
                    default:
                        return nil
                    }
                }
            }
            let names = Set(calls.map(\.0))
            #expect(
                calls.count == 8,
                "Expected one KIR call for each Base64 overload, got: \(calls)"
            )
            #expect(
                names == expectedNames,
                "Expected all Base64 API names in consumer KIR, got: \(names.sorted())"
            )

            let sema = try #require(ctx.sema)
            for (name, symbol) in calls {
                #expect(
                    sema.symbols.isSourceBackedSymbol(symbol),
                    "Base64.\(name) must resolve to a bundled Kotlin source declaration"
                )
                #expect(
                    sema.symbols.externalLinkName(for: symbol) == nil,
                    "Base64.\(name) must not carry a runtime bridge link"
                )
            }

            let calleeNames = findAllKIRFunctions(in: module).flatMap {
                extractCallees(from: $0.body, interner: ctx.interner)
            }
            #expect(
                calleeNames.allSatisfy { !$0.hasPrefix("kk_base64_") },
                "Base64 consumer KIR must not reference legacy runtime bridges: \(calleeNames)"
            )
        }
    }
}
#endif
