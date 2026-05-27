@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-022: Validates that `Path.getLastModifiedTime(vararg options: LinkOption): FileTime`
/// is exposed as an extension function in the `kotlin.io.path` package, type-checks
/// in user source, and is routed to the `kk_path_getLastModifiedTime` runtime entry point.
final class PathGetLastModifiedTimeFunctionTests: XCTestCase {
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

    func testPathGetLastModifiedTimeOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import java.nio.file.attribute.FileTime
        import kotlin.io.path.Path
        import kotlin.io.path.getLastModifiedTime

        fun modifiedTime(path: Path, option: LinkOption): FileTime {
            val first = path.getLastModifiedTime()
            val second = path.getLastModifiedTime(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.getLastModifiedTime(options) extension function in kotlin.io.path should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let fileTimeSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileTime"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let fileTimeType = types.make(.classType(ClassType(classSymbol: fileTimeSymbol, args: [], nullability: .nonNull)))
            let getLastModifiedTimeSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "getLastModifiedTime"].map(interner.intern))
            let getLastModifiedTime = try XCTUnwrap(getLastModifiedTimeSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == fileTimeType
            })
            XCTAssertEqual(symbols.externalLinkName(for: getLastModifiedTime), "kk_path_getLastModifiedTime")

            let signature = try XCTUnwrap(symbols.functionSignature(for: getLastModifiedTime))
            XCTAssertEqual(signature.valueParameterIsVararg, [true])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "getLastModifiedTime", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, getLastModifiedTime)
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], fileTimeType)
            }
        }
    }
}
