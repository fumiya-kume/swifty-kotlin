@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-FN-036: `fun java.io.File.resolveSibling(relative: File): File`
///                   `fun java.io.File.resolveSibling(relative: String): File`
///
/// Verifies that the synthetic `resolveSibling` overloads registered on the
/// `java.io.File` synthetic class (see
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticFileIOStubs.swift`)
/// resolve through Sema for plain File receivers and bind to the runtime
/// helpers `kk_file_resolveSibling_file` / `kk_file_resolveSibling_string` listed
/// in `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
final class FileResolveSiblingFunctionTests: XCTestCase {
    private func memberCallExprIDs(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

    // MARK: - File overload resolves cleanly

    func testFileResolveSiblingFileOverloadResolves() throws {
        let source = """
        import java.io.File

        fun getSibling(file: File, sibling: File): File {
            return file.resolveSibling(sibling)
        }

        fun main() {
            val f = File("/tmp/a/b.txt")
            val sibling = File("c.txt")
            println(getSibling(f, sibling).path)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "File.resolveSibling(File) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - String overload resolves cleanly

    func testFileResolveSiblingStringOverloadResolves() throws {
        let source = """
        import java.io.File

        fun getSiblingByName(file: File): File {
            return file.resolveSibling("other.txt")
        }

        fun main() {
            println(getSiblingByName(File("/tmp/a/b.txt")).path)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "File.resolveSibling(String) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - Both call expressions are typed as File

    func testFileResolveSiblingCallExpressionsAreTypedAsFile() throws {
        let source = """
        import java.io.File

        fun decide(file: File, other: File): File {
            val a: File = file.resolveSibling(other)
            val b: File = file.resolveSibling("sibling.txt")
            return a
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.resolveSibling call expressions should type cleanly as File: \(ctx.diagnostics.diagnostics.map(\.message))"
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
            let callExprs = memberCallExprIDs(named: "resolveSibling", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2, "expected two resolveSibling member calls")
            for callExpr in callExprs {
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    fileType,
                    "Each File.resolveSibling(...) call expression must be typed as File"
                )
            }
        }
    }

    // MARK: - Sema registers both overloads with the expected runtime link names

    func testFileResolveSiblingSignaturesAndRuntimeLinkNames() throws {
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
                fqName: ["java", "io", "File", "resolveSibling"].map(interner.intern)
            )

            let fileOverload = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == fileType
                    && signature.parameterTypes == [fileType]
                    && signature.returnType == fileType
            })
            XCTAssertEqual(
                symbols.externalLinkName(for: fileOverload),
                "kk_file_resolveSibling_file",
                "File.resolveSibling(File) should bind to runtime helper kk_file_resolveSibling_file"
            )

            let stringOverload = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == fileType
                    && signature.parameterTypes == [types.stringType]
                    && signature.returnType == fileType
            })
            XCTAssertEqual(
                symbols.externalLinkName(for: stringOverload),
                "kk_file_resolveSibling_string",
                "File.resolveSibling(String) should bind to runtime helper kk_file_resolveSibling_string"
            )
        }
    }
}
