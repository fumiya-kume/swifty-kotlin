@testable import CompilerCore
import Foundation
import XCTest

final class DeepRecursiveSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testDeepRecursiveSyntheticTypesAndMembersAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let functionFQName = ["kotlin", "DeepRecursiveFunction"].map { interner.intern($0) }
        let scopeFQName = ["kotlin", "DeepRecursiveScope"].map { interner.intern($0) }

        let functionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: functionFQName))
        let scopeSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: scopeFQName))

        XCTAssertEqual(sema.symbols.symbol(functionSymbol)?.kind, .class)
        XCTAssertEqual(sema.symbols.symbol(scopeSymbol)?.kind, .class)
        XCTAssertEqual(sema.types.nominalTypeParameterSymbols(for: functionSymbol).count, 2)
        XCTAssertEqual(sema.types.nominalTypeParameterSymbols(for: scopeSymbol).count, 2)

        let functionInit = try XCTUnwrap(sema.symbols.lookup(fqName: functionFQName + [interner.intern("<init>")]))
        XCTAssertEqual(sema.symbols.externalLinkName(for: functionInit), "kk_deep_recursive_function_new")

        let invokeSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: functionFQName + [interner.intern("invoke")]))
        XCTAssertEqual(sema.symbols.externalLinkName(for: invokeSymbol), "kk_deep_recursive_function_invoke")
        XCTAssertTrue(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)

        let functionCallRecursive = try XCTUnwrap(
            sema.symbols.lookup(fqName: functionFQName + [interner.intern("callRecursive")])
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: functionCallRecursive),
            "kk_deep_recursive_function_callRecursive"
        )

        let scopeCallRecursive = try XCTUnwrap(
            sema.symbols.lookup(fqName: scopeFQName + [interner.intern("callRecursive")])
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: scopeCallRecursive),
            "kk_deep_recursive_scope_callRecursive"
        )
    }

    func testDeepRecursiveFunctionResolvesInSource() throws {
        let source = """
        class Node(val next: Node?)

        fun makeDepth(): DeepRecursiveFunction<Node?, Int> {
            val depth: DeepRecursiveFunction<Node?, Int> = DeepRecursiveFunction<Node?, Int> {
                if (it == null) 0 else callRecursive(it.next) + 1
            }
            return depth
        }

        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let constructorCall = try XCTUnwrap(firstExprID(in: ast) { exprID, _ in
                guard let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee else {
                    return false
                }
                return sema.symbols.externalLinkName(for: chosen) == "kk_deep_recursive_function_new"
            })
            let constructorCallee = try XCTUnwrap(sema.bindings.callBinding(for: constructorCall)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: constructorCallee), "kk_deep_recursive_function_new")

        }
    }
}
