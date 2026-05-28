@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-FN-024: `fun java.io.File.normalize(): File`
///
/// Verifies that the synthetic `normalize` member registered on the
/// `java.io.File` synthetic class (see
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticFileIOStubs.swift`)
/// resolves through Sema and binds to the runtime helper `kk_file_normalize`
/// listed in `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
final class FileNormalizeFunctionTests: XCTestCase {

    // MARK: - Basic resolution

    func testFileNormalizeResolves() throws {
        let source = """
        import java.io.File

        fun normalize(file: File): File {
            return file.normalize()
        }

        fun main() {
            println(normalize(File("/tmp/./sub/../file.txt")).path)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "File.normalize() should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - Return type is File

    func testFileNormalizeCallExpressionIsTypedAsFile() throws {
        let source = """
        import java.io.File

        fun normalized(file: File): File {
            val result: File = file.normalize()
            return result
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.normalize() should type-check as File: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let fileSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
            )
            let fileType = sema.types.make(
                .classType(ClassType(classSymbol: fileSymbol, args: [], nullability: .nonNull))
            )

            let ast = try XCTUnwrap(ctx.ast)
            let normalizeCallExprs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      interner.resolve(callee) == "normalize"
                else {
                    return nil
                }
                return exprID
            }
            XCTAssertFalse(normalizeCallExprs.isEmpty, "Expected at least one normalize call expression")
            for callExpr in normalizeCallExprs {
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    fileType,
                    "File.normalize() call expression must be typed as File"
                )
            }
        }
    }

    // MARK: - Symbol registration and runtime link name

    func testFileNormalizeSignatureAndRuntimeLinkName() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let fileSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
            )
            let fileType = types.make(
                .classType(ClassType(classSymbol: fileSymbol, args: [], nullability: .nonNull))
            )

            let candidates = symbols.lookupAll(
                fqName: ["java", "io", "File", "normalize"].map(interner.intern)
            )

            let normalizeOverload = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == fileType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == fileType
            }, "Expected a normalize overload with () -> File signature")

            XCTAssertEqual(
                symbols.externalLinkName(for: normalizeOverload),
                "kk_file_normalize",
                "File.normalize() should bind to runtime helper kk_file_normalize"
            )
        }
    }
}
