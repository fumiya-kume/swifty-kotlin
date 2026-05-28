@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-020: Validates that `kotlin.io.path.Path.forEachLine(charset, action)`
/// is exposed as an extension function in the `kotlin.io.path` package, type-checks
/// in user source, and is routed to the runtime entry points `kk_path_forEachLine`
/// (charset overload) and `kk_path_forEachLine_default` (UTF-8 default overload).
///
/// The Sema stubs live in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`
/// and the runtime exports live in `Sources/Runtime/RuntimePath.swift`. The
/// matching ABI spec entries are declared in
/// `Sources/RuntimeABI/RuntimeABISpec.swift`.
final class PathForEachLineFunctionTests: XCTestCase {
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

    func testPathForEachLineDefaultOverloadResolvesWithoutCharset() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.forEachLine

        fun visitLines(path: Path) {
            path.forEachLine { line ->
                val text = line
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.forEachLine { action } should resolve via the UTF-8 default overload, got: "
                    + errors.map { "\($0.code): \($0.message)" }.joined(separator: ", ")
            )
        }
    }

    func testPathForEachLineWithExplicitCharsetResolves() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.forEachLine
        import kotlin.text.Charsets

        fun visitLines(path: Path) {
            path.forEachLine(Charsets.UTF_8) { line ->
                val text = line
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.forEachLine(Charsets.UTF_8) { action } should resolve via the charset overload, got: "
                    + errors.map { "\($0.code): \($0.message)" }.joined(separator: ", ")
            )
        }
    }

    func testPathForEachLineSignaturesAndRuntimeLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let pathSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            )
            let charsetSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let charsetType = types.make(
                .classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull))
            )
            let stringActionType = types.make(.functionType(FunctionType(
                params: [types.stringType],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "forEachLine"].map(interner.intern)
            )

            let charsetOverload = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charsetType, stringActionType]
                    && signature.returnType == types.unitType
            })
            let defaultOverload = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [stringActionType]
                    && signature.returnType == types.unitType
            })

            XCTAssertEqual(
                symbols.externalLinkName(for: charsetOverload),
                "kk_path_forEachLine",
                "Charset overload of Path.forEachLine should bind to the kk_path_forEachLine runtime helper"
            )
            XCTAssertEqual(
                symbols.externalLinkName(for: defaultOverload),
                "kk_path_forEachLine_default",
                "Default-charset overload of Path.forEachLine should bind to the kk_path_forEachLine_default runtime helper"
            )

            let charsetSignature = try XCTUnwrap(symbols.functionSignature(for: charsetOverload))
            XCTAssertEqual(charsetSignature.valueParameterHasDefaultValues, [true, false])
            XCTAssertEqual(charsetSignature.valueParameterIsVararg, [false, false])
            XCTAssertEqual(charsetSignature.returnType, types.unitType)
            XCTAssertEqual(charsetSignature.receiverType, pathType)

            let defaultSignature = try XCTUnwrap(symbols.functionSignature(for: defaultOverload))
            XCTAssertEqual(defaultSignature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(defaultSignature.valueParameterIsVararg, [false])
            XCTAssertEqual(defaultSignature.returnType, types.unitType)
            XCTAssertEqual(defaultSignature.receiverType, pathType)
        }
    }

    func testPathForEachLineCallExpressionsTypedAsUnit() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.forEachLine
        import kotlin.text.Charsets

        fun visitLines(path: Path) {
            path.forEachLine { line ->
                val first = line
            }
            path.forEachLine(Charsets.UTF_8) { line ->
                val second = line
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.forEachLine variants should resolve cleanly: "
                    + ctx.diagnostics.diagnostics.map(\.message).joined(separator: ", ")
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let types = sema.types

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "forEachLine", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    types.unitType,
                    "Each Path.forEachLine call expression must be typed as Unit"
                )
            }
        }
    }
}
