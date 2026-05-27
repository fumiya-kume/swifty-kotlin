@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-042: Validates that `String.padStart(length, padChar)` resolves
/// through Sema both with an explicit pad character and via the default-space
/// single-argument overload, mirroring `kotlin.text.padStart`.
///
/// Runtime link names involved:
///   - `kk_string_padStart_default` (1-arg, default pad char `' '`)
///   - `kk_string_padStart`         (2-arg, explicit pad char)
///
/// The implementation is wired through
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticStringStubs.swift`
/// and backed by `Sources/Runtime/RuntimeStringStdlib.swift`.
final class StringPadStartFunctionTests: XCTestCase {
    func testPadStartFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun zeroPad(value: String): String {
            return value.padStart(5, '0')
        }

        fun spacePadDefault(value: String): String {
            return value.padStart(8)
        }

        fun padLiteral(): String {
            return "42".padStart(5, '0')
        }

        fun padTooShortNoChange(value: String): String {
            return value.padStart(1, '*')
        }

        fun padInPipeline(value: String): String {
            return value
                .padStart(4, '0')
                .padStart(6, ' ')
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.padStart to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testPadStartFunctionResolvesToRuntimeLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let fq = ["kotlin", "text", "padStart"].map { interner.intern($0) }
            let symbols = sema.symbols.lookupAll(fqName: fq)
            XCTAssertEqual(
                symbols.count, 2,
                "kotlin.text.padStart should expose 2 overloads (default pad char + explicit pad char)"
            )

            let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            XCTAssertTrue(
                links.contains("kk_string_padStart_default"),
                "padStart should expose the 1-arg default-pad overload (kk_string_padStart_default)"
            )
            XCTAssertTrue(
                links.contains("kk_string_padStart"),
                "padStart should expose the 2-arg explicit-pad overload (kk_string_padStart)"
            )

            for symbolID in symbols {
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                XCTAssertEqual(
                    signature.receiverType,
                    sema.types.stringType,
                    "padStart overloads must be String extensions"
                )
                XCTAssertEqual(
                    signature.returnType,
                    sema.types.stringType,
                    "padStart overloads must return String"
                )
            }
        }
    }
}
