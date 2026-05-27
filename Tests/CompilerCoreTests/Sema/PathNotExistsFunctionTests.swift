@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-027: Validates that `Path.notExists(vararg options: LinkOption): Boolean`
/// is exposed as an extension function in the `kotlin.io.path` package, type-checks
/// in user source, and is routed to the `kk_path_notExists` runtime entry point.
final class PathNotExistsFunctionTests: XCTestCase {
    private func memberCallExprIDs(named name: String, in ast: ASTModule, interner: StringInterner) -> [ExprID] {
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

    func testPathNotExistsOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.notExists

        fun absentPath(path: Path, option: LinkOption): Boolean {
            val first = path.notExists()
            val second = path.notExists(option)
            return first && second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.notExists(options) extension function in kotlin.io.path should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let notExistsSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "notExists"].map(interner.intern))
            let notExists = try XCTUnwrap(notExistsSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == types.booleanType
            })
            XCTAssertEqual(symbols.externalLinkName(for: notExists), "kk_path_notExists")

            let signature = try XCTUnwrap(symbols.functionSignature(for: notExists))
            XCTAssertEqual(signature.valueParameterIsVararg, [true])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "notExists", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, notExists)
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], types.booleanType)
            }
        }
    }
}
