@testable import CompilerCore
import Foundation
import XCTest

final class DeepRecursiveFunctionTests: XCTestCase {
    func testTopLevelDeepRecursiveInitializerParsesLambdaBeforeNextDeclaration() throws {
        let source = """
        val factorial = DeepRecursiveFunction<Int, Int>({ n ->
            if (n <= 1) 1 else n * callRecursive(n - 1)
        })

        fun main(): Int = factorial(5)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            let parsedInitializer = ast.arena.exprs.indices.contains { raw in
                let exprID = ExprID(rawValue: Int32(raw))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(calleeID, _, args, _) = expr,
                      args.count == 1,
                      let calleeExpr = ast.arena.expr(calleeID),
                      case let .nameRef(name, _) = calleeExpr
                else {
                    return false
                }
                return ctx.interner.resolve(name) == "DeepRecursiveFunction"
            }
            XCTAssertTrue(parsedInitializer, "Expected property initializer call to retain its lambda argument.")
        }
    }

    func testDeepRecursiveFunctionBasicRecursionCompilesToKIR() throws {
        try assertKotlinCompilesToKIR("""
        val factorial = DeepRecursiveFunction<Int, Int>({ n ->
            if (n <= 1) 1 else n * callRecursive(n - 1)
        })

        fun main(): Int = factorial(5)
        """)
    }

    func testDeepRecursiveFunctionExtensionCallRecursiveResolves() throws {
        let source = """
        fun wrapper(other: DeepRecursiveFunction<Int, Int>): DeepRecursiveFunction<Int, Int> =
            DeepRecursiveFunction<Int, Int>({ n ->
                if (n <= 0) 0 else other.callRecursive(n - 1)
            })
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let resolved = ast.arena.exprs.indices.contains(where: { raw in
            let exprID = ExprID(rawValue: Int32(raw))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr
            else {
                return false
            }
            guard ctx.interner.resolve(callee) == "callRecursive",
                  let callBinding = sema.bindings.callBinding(for: exprID),
                  let symbol = sema.symbols.symbol(callBinding.chosenCallee)
            else {
                return false
            }
            let fqName = symbol.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
            return sema.symbols.functionSignature(for: symbol.id)?.isSuspend == true
                && fqName == "kotlin.DeepRecursiveScope.callRecursive"
        })

        XCTAssertTrue(resolved, "Expected DeepRecursiveScope.callRecursive extension overload to resolve")
    }

    func testDeepRecursiveSymbolsExposeExpectedSignatures() throws {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }

        let (sema, interner) = try XCTUnwrap(result)
        let invokeFQName = ["kotlin", "DeepRecursiveFunction", "invoke"].map { interner.intern($0) }
        let scopeCallFQName = ["kotlin", "DeepRecursiveScope", "callRecursive"].map { interner.intern($0) }

        let invokeSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: invokeFQName).first(where: { symbolID in
                sema.symbols.symbol(symbolID)?.flags.contains(.operatorFunction) == true
            })
        )
        let invokeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: invokeSymbol))
        XCTAssertFalse(invokeSignature.isSuspend)

        let callRecursiveSymbols = sema.symbols.lookupAll(fqName: scopeCallFQName)
        XCTAssertEqual(callRecursiveSymbols.count, 2, "Expected plain and extension callRecursive overloads")
        XCTAssertTrue(callRecursiveSymbols.allSatisfy { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.isSuspend == true
        })
    }
}
