@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-030: Validates that the `readAttributes` extension functions
/// on `kotlin.io.path.Path` are wired through Sema for both overloads:
/// - `Path.readAttributes(attributes: String, vararg options: LinkOption): Map<String, Any?>`
///   resolves to `kk_path_readAttributes_string`.
/// - `Path.readAttributes<A : BasicFileAttributes>(vararg options: LinkOption): A`
///   resolves to `kk_path_readAttributes`.
final class PathReadAttributesFunctionTests: XCTestCase {
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

    func testPathReadAttributesStringOverloadResolvesToRuntimeEntry() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.readAttributes

        fun attributes(path: Path, option: LinkOption): Map<String, Any?> {
            val first: Map<String, Any?> = path.readAttributes("basic:*")
            val second: Map<String, Any?> = path.readAttributes("basic:*", option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.readAttributes(attributes, options) extension function in kotlin.io.path should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let mapSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "collections", "Map"].map(interner.intern)))
            let linkOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let mapOfStringToNullableAnyType = types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.invariant(types.stringType), .out(types.nullableAnyType)],
                nullability: .nonNull
            )))
            let readAttributesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "readAttributes"].map(interner.intern))
            let readAttributes = try XCTUnwrap(readAttributesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [types.stringType, linkOptionType]
                    && signature.returnType == mapOfStringToNullableAnyType
            })
            XCTAssertEqual(symbols.externalLinkName(for: readAttributes), "kk_path_readAttributes_string")

            let signature = try XCTUnwrap(symbols.functionSignature(for: readAttributes))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, true])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "readAttributes", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, readAttributes)
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], mapOfStringToNullableAnyType)
            }
        }
    }

    func testPathReadAttributesGenericOverloadResolvesToRuntimeEntry() throws {
        let source = """
        import java.nio.file.LinkOption
        import java.nio.file.attribute.BasicFileAttributes
        import kotlin.io.path.Path
        import kotlin.io.path.readAttributes

        fun attributes(path: Path, option: LinkOption): BasicFileAttributes {
            val first: BasicFileAttributes = path.readAttributes<BasicFileAttributes>()
            val second: BasicFileAttributes = path.readAttributes<BasicFileAttributes>(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.readAttributes<A>(options) extension function in kotlin.io.path should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let basicFileAttributesSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "BasicFileAttributes"].map(interner.intern)))
            let linkOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let basicFileAttributesType = types.make(.classType(ClassType(classSymbol: basicFileAttributesSymbol, args: [], nullability: .nonNull)))
            let readAttributesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "readAttributes"].map(interner.intern))
            let readAttributes = try XCTUnwrap(readAttributesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID),
                      let typeParameterSymbol = signature.typeParameterSymbols.first
                else {
                    return false
                }
                let returnType = types.make(.typeParam(TypeParamType(
                    symbol: typeParameterSymbol,
                    nullability: .nonNull
                )))
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == returnType
            })
            XCTAssertEqual(symbols.externalLinkName(for: readAttributes), "kk_path_readAttributes")

            let signature = try XCTUnwrap(symbols.functionSignature(for: readAttributes))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [true])
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)
            XCTAssertEqual(signature.reifiedTypeParameterIndices, [0])
            XCTAssertEqual(signature.typeParameterUpperBoundsList, [[basicFileAttributesType]])
            let typeParameterSymbol = try XCTUnwrap(signature.typeParameterSymbols.first)
            XCTAssertTrue(symbols.symbol(typeParameterSymbol)?.flags.contains(.reifiedTypeParameter) == true)
            XCTAssertEqual(symbols.typeParameterUpperBounds(for: typeParameterSymbol), [basicFileAttributesType])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "readAttributes", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, readAttributes)
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], basicFileAttributesType)
            }
        }
    }
}
