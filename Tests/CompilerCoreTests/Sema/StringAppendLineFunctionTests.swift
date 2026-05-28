@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-004: Validates that `StringBuilder.appendLine` overloads resolve
/// through Sema, dispatching to the runtime link names
/// `kk_string_builder_append_line_obj` (value overload) and
/// `kk_string_builder_append_line_noarg_obj` (no-arg overload).
final class StringAppendLineFunctionTests: XCTestCase {

    // MARK: - appendLine(value) overload

    func testAppendLineWithValueResolvesWithoutErrors() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine("hello")
            sb.appendLine("world")
            println(sb.toString())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected appendLine(String) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - appendLine() no-arg overload

    func testAppendLineNoArgResolvesWithoutErrors() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine()
            println(sb.toString())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected appendLine() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - appendLine returns StringBuilder (chaining)

    func testAppendLineChainingResolvesWithoutErrors() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val result = StringBuilder()
                .appendLine("first")
                .appendLine("second")
                .appendLine()
                .toString()
            println(result)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected chained appendLine calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Runtime link name registration

    func testAppendLineWithValueLinksToCorrectRuntimeSymbol() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine("test")
        }
        """)
        try runSema(ctx)
        let interner = ctx.interner
        let sema = ctx.sema!
        let sbSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("StringBuilder"),
            interner.intern("appendLine"),
        ])
        let valueOverload = sbSymbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.count == 1
        }
        XCTAssertNotNil(valueOverload, "appendLine(value) overload should be registered")
        if let sym = valueOverload {
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: sym),
                "kk_string_builder_append_line_obj",
                "appendLine(value) should link to kk_string_builder_append_line_obj"
            )
        }
    }

    func testAppendLineNoArgLinksToCorrectRuntimeSymbol() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine()
        }
        """)
        try runSema(ctx)
        let interner = ctx.interner
        let sema = ctx.sema!
        let sbSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("StringBuilder"),
            interner.intern("appendLine"),
        ])
        let noArgOverload = sbSymbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.isEmpty
        }
        XCTAssertNotNil(noArgOverload, "appendLine() no-arg overload should be registered")
        if let sym = noArgOverload {
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: sym),
                "kk_string_builder_append_line_noarg_obj",
                "appendLine() should link to kk_string_builder_append_line_noarg_obj"
            )
        }
    }
}
