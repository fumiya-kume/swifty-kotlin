@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-PATH-FN-038: Validates that `kotlin.io.path.Path.useLines(charset, block)`
/// is exposed as an extension function in the `kotlin.io.path` package, type-checks
/// in user source, and is routed to the runtime entry points `kk_path_useLines`
/// (charset overload) and `kk_path_useLines_default` (no-charset overload).
///
/// The extension function is wired through the synthetic Path stub registry in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`,
/// and the runtime helpers are declared in `Sources/RuntimeABI/RuntimeABISpec.swift`.
final class PathUseLinesFunctionTests: XCTestCase {
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

    func testPathUseLinesResolvesWithBlockOnly() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines

        fun firstLine(path: Path): String? {
            return path.useLines { lines -> lines.firstOrNull() }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.useLines { block } should resolve with the no-charset overload, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathUseLinesResolvesWithCharsetAndBlock() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.text.Charsets

        fun lineCount(path: Path): Int {
            return path.useLines(Charsets.UTF_8) { lines -> lines.count() }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Path.useLines(charset) { block } should resolve, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathUseLinesFunctionSignaturesAndRuntimeLinks() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines

        fun noop(path: Path) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let pathSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            )
            let sequenceSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "sequences", "Sequence"].map(interner.intern))
            )
            let charsetSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern))
            )
            let pathType = types.make(
                .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
            )
            let sequenceOfStringType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(types.stringType)],
                nullability: .nonNull
            )))
            let charsetType = types.make(
                .classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull))
            )

            let useLinesSymbols = symbols.lookupAll(
                fqName: ["kotlin", "io", "path", "useLines"].map(interner.intern)
            )

            let fullUseLines = try XCTUnwrap(useLinesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID),
                      let typeParameterSymbol = signature.typeParameterSymbols.first
                else { return false }
                let typeParameterType = types.make(.typeParam(TypeParamType(
                    symbol: typeParameterSymbol,
                    nullability: .nonNull
                )))
                let blockType = types.make(.functionType(FunctionType(
                    params: [sequenceOfStringType],
                    returnType: typeParameterType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charsetType, blockType]
                    && signature.returnType == typeParameterType
            })

            let defaultUseLines = try XCTUnwrap(useLinesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID),
                      let typeParameterSymbol = signature.typeParameterSymbols.first
                else { return false }
                let typeParameterType = types.make(.typeParam(TypeParamType(
                    symbol: typeParameterSymbol,
                    nullability: .nonNull
                )))
                let blockType = types.make(.functionType(FunctionType(
                    params: [sequenceOfStringType],
                    returnType: typeParameterType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                return signature.receiverType == pathType
                    && signature.parameterTypes == [blockType]
                    && signature.returnType == typeParameterType
            })

            XCTAssertEqual(
                symbols.externalLinkName(for: fullUseLines),
                "kk_path_useLines",
                "Path.useLines(charset, block) should bind to runtime helper kk_path_useLines"
            )
            XCTAssertEqual(
                symbols.externalLinkName(for: defaultUseLines),
                "kk_path_useLines_default",
                "Path.useLines(block) should bind to runtime helper kk_path_useLines_default"
            )

            let fullSignature = try XCTUnwrap(symbols.functionSignature(for: fullUseLines))
            XCTAssertEqual(fullSignature.valueParameterHasDefaultValues, [true, false])
            XCTAssertEqual(fullSignature.valueParameterIsVararg, [false, false])
            XCTAssertEqual(fullSignature.typeParameterSymbols.count, 1)

            let defaultSignature = try XCTUnwrap(symbols.functionSignature(for: defaultUseLines))
            XCTAssertEqual(defaultSignature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(defaultSignature.valueParameterIsVararg, [false])
            XCTAssertEqual(defaultSignature.typeParameterSymbols.count, 1)
        }
    }

    func testPathUseLinesCallExpressionBindsToChosenCallee() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines
        import kotlin.text.Charsets

        fun total(path: Path): Int {
            val a = path.useLines { lines -> lines.count() }
            val b = path.useLines(Charsets.UTF_8) { lines -> lines.count() }
            return a + b
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.useLines() should resolve cleanly: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "useLines", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertNotNil(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Each Path.useLines() call expression must bind to a chosen callee"
                )
            }
        }
    }
}
