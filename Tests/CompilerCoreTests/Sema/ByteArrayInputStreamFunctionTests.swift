@testable import CompilerCore
import Foundation
import XCTest

/// Verifies the synthetic stubs for `ByteArray.inputStream()` (STDLIB-IO-FN-020) and
/// `ByteArray.inputStream(offset, length)` (STDLIB-IO-FN-021).
///
/// Two overloads are exposed from `kotlin.io`:
///   - `ByteArray.inputStream(): ByteArrayInputStream` → `kk_bytearray_inputStream`
///   - `ByteArray.inputStream(offset: Int, length: Int): ByteArrayInputStream` → `kk_bytearray_inputStream_range`
///
/// Both return `java.io.ByteArrayInputStream`, which is registered as an
/// `InputStream` subtype so that resource-management surfaces (`.use {}`) work
/// out of the box.
final class ByteArrayInputStreamFunctionTests: XCTestCase {

    // MARK: - STDLIB-IO-FN-020: ByteArray.inputStream() (zero-arg)

    func testZeroArgByteArrayInputStreamResolvesCleanly() throws {
        let source = """
        fun wrap(bytes: ByteArray) = bytes.inputStream()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected ByteArray.inputStream() to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "inputStream"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_bytearray_inputStream"
            )

            // The function should live in kotlin.io
            let chosenInfo = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
            XCTAssertEqual(
                chosenInfo.fqName.map { ctx.interner.resolve($0) },
                ["kotlin", "io", "inputStream"]
            )

            // The overload must have zero value parameters
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: chosenCallee))
            XCTAssertTrue(signature.parameterTypes.isEmpty)

            // Return type must be java.io.ByteArrayInputStream
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected ByteArray.inputStream() to return a class type")
            }
            let returnInfo = try XCTUnwrap(sema.symbols.symbol(returnClassType.classSymbol))
            XCTAssertEqual(
                returnInfo.fqName.map { ctx.interner.resolve($0) },
                ["java", "io", "ByteArrayInputStream"]
            )
        }
    }

    // MARK: - STDLIB-IO-FN-021: ByteArray.inputStream(offset, length) (range)

    func testRangeByteArrayInputStreamResolvesCleanly() throws {
        let source = """
        fun wrapRange(bytes: ByteArray, off: Int, len: Int) = bytes.inputStream(off, len)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected ByteArray.inputStream(offset, length) to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "inputStream"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_bytearray_inputStream_range"
            )

            // The overload must have two Int parameters: offset and length
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: chosenCallee))
            XCTAssertEqual(signature.parameterTypes.count, 2)
            XCTAssertEqual(signature.parameterTypes[0], sema.types.intType)
            XCTAssertEqual(signature.parameterTypes[1], sema.types.intType)

            // Return type must be java.io.ByteArrayInputStream
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected ByteArray.inputStream(offset, length) to return a class type")
            }
            let returnInfo = try XCTUnwrap(sema.symbols.symbol(returnClassType.classSymbol))
            XCTAssertEqual(
                returnInfo.fqName.map { ctx.interner.resolve($0) },
                ["java", "io", "ByteArrayInputStream"]
            )
        }
    }

    func testBothOverloadsExistInKotlinIOPackage() throws {
        // Direct symbol lookup to verify both inputStream stubs live in kotlin.io.
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let fqName = ["kotlin", "io", "inputStream"].map { interner.intern($0) }
            let symbols = sema.symbols.lookupAll(fqName: fqName)

            // Expect at least the two ByteArray overloads (there may be others from File/Path)
            let byteArrayFQName = ["kotlin", "ByteArray"].map { interner.intern($0) }
            guard let byteArraySymbol = sema.symbols.lookup(fqName: byteArrayFQName) else {
                return XCTFail("kotlin.ByteArray symbol not found")
            }
            let byteArrayType = sema.types.make(.classType(ClassType(
                classSymbol: byteArraySymbol, args: [], nullability: .nonNull
            )))

            let byteArrayOverloads = symbols.filter { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == byteArrayType
            }
            XCTAssertGreaterThanOrEqual(
                byteArrayOverloads.count, 2,
                "Expected at least two ByteArray.inputStream overloads in kotlin.io"
            )

            let externalLinks = Set(byteArrayOverloads.compactMap { sema.symbols.externalLinkName(for: $0) })
            XCTAssertTrue(
                externalLinks.contains("kk_bytearray_inputStream"),
                "Zero-arg overload kk_bytearray_inputStream not found"
            )
            XCTAssertTrue(
                externalLinks.contains("kk_bytearray_inputStream_range"),
                "Range overload kk_bytearray_inputStream_range not found"
            )
        }
    }

    func testByteArrayInputStreamReturnTypeFlowsThroughInputStreamMembers() throws {
        // ByteArrayInputStream extends InputStream, so its member surfaces
        // (.read(), .close(), .available()) must resolve cleanly.
        let source = """
        fun consume(bytes: ByteArray): Int {
            val stream = bytes.inputStream()
            val available = stream.available()
            val first = stream.read()
            stream.close()
            return available + first
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected ByteArrayInputStream member usage to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }

    func testByteArrayRangeInputStreamReturnTypeFlowsThroughInputStreamMembers() throws {
        // ByteArrayInputStream(offset, length) should also provide InputStream members.
        let source = """
        fun consumeRange(bytes: ByteArray, off: Int, len: Int): Int {
            val stream = bytes.inputStream(off, len)
            return stream.read()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected ByteArrayInputStream(range) member usage to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }
}
