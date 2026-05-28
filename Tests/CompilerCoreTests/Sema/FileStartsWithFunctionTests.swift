@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-FN-037: `fun java.io.File.startsWith(other: File): Boolean`
///                   `fun java.io.File.startsWith(other: String): Boolean`
///
/// Verifies that the synthetic `startsWith` overloads registered on the
/// `java.io.File` synthetic class (see
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticFileIOStubs.swift`)
/// resolve through Sema for plain File receivers and bind to the runtime
/// helpers `kk_file_startsWith_file` / `kk_file_startsWith_string` listed in
/// `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
final class FileStartsWithFunctionTests: XCTestCase {
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

    func testFileStartsWithFileOverloadResolves() throws {
        let source = """
        import java.io.File

        fun isChild(child: File, parent: File): Boolean {
            return child.startsWith(parent)
        }

        fun main() {
            println(isChild(File("/tmp/sub/file.txt"), File("/tmp")))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "File.startsWith(File) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - String overload resolves cleanly

    func testFileStartsWithStringOverloadResolves() throws {
        let source = """
        import java.io.File

        fun isUnderTmp(file: File): Boolean {
            return file.startsWith("/tmp")
        }

        fun main() {
            println(isUnderTmp(File("/tmp/sub/file.txt")))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "File.startsWith(String) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // MARK: - Both call expressions are typed as Boolean

    func testFileStartsWithCallExpressionsAreTypedAsBoolean() throws {
        let source = """
        import java.io.File

        fun decide(file: File, parent: File): Boolean {
            val a: Boolean = file.startsWith(parent)
            val b: Boolean = file.startsWith("/tmp")
            return a && b
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.startsWith call expressions should type cleanly as Boolean: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let booleanType = sema.types.booleanType

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "startsWith", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2, "expected two startsWith member calls")
            for callExpr in callExprs {
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    booleanType,
                    "Each File.startsWith(...) call expression must be typed as Boolean"
                )
            }
        }
    }

    // MARK: - Sema registers both overloads with the expected runtime link names

    func testFileStartsWithSignaturesAndRuntimeLinkNames() throws {
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
                fqName: ["java", "io", "File", "startsWith"].map(interner.intern)
            )

            let fileOverload = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == fileType
                    && signature.parameterTypes == [fileType]
                    && signature.returnType == types.booleanType
            })
            XCTAssertEqual(
                symbols.externalLinkName(for: fileOverload),
                "kk_file_startsWith_file",
                "File.startsWith(File) should bind to runtime helper kk_file_startsWith_file"
            )

            let stringOverload = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == fileType
                    && signature.parameterTypes == [types.stringType]
                    && signature.returnType == types.booleanType
            })
            XCTAssertEqual(
                symbols.externalLinkName(for: stringOverload),
                "kk_file_startsWith_string",
                "File.startsWith(String) should bind to runtime helper kk_file_startsWith_string"
            )
        }
    }
}
