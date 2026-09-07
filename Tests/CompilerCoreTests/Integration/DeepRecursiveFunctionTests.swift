#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite struct DeepRecursiveFunctionTests {

    @Test func testDeepRecursiveFunctionSema() throws {
        let sources: [String] = [
            // testDeepRecursiveFunctionCallRecursiveResolves
            """
            package sample0
                    fun wrapper(other: DeepRecursiveFunction<Int, Int>): DeepRecursiveFunction<Int, Int> =
                        DeepRecursiveFunction<Int, Int>({ n ->
                            if (n <= 0) 0 else other.callRecursive(n - 1)
                        })

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testDeepRecursiveFunctionCallRecursiveResolves

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

                        let ast = try #require(ctx.ast)
                        let sema = try #require(ctx.sema)
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
                            return sema.symbols.externalLinkName(for: symbol.id) == "__kk_deep_recursive_function_callRecursive"
                                && fqName == "kotlin.DeepRecursiveFunction.callRecursive"
                        })

                        #expect(resolved, "Expected DeepRecursiveFunction.callRecursive member to resolve")

            }

        }
    }

    @Test func testTopLevelDeepRecursiveInitializerParsesLambdaBeforeNextDeclaration() throws {
        let source = """
        val factorial = DeepRecursiveFunction<Int, Int>({ n ->
            if (n <= 1) 1 else n * callRecursive(n - 1)
        })

        fun main(): Int = factorial(5)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try #require(ctx.ast)
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
            #expect(parsedInitializer, "Expected property initializer call to retain its lambda argument.")
        }
    }


    @Test func testDeepRecursiveFunctionBasicRecursionCompilesToKIR() throws {
        try assertKotlinCompilesToKIR("""
        val factorial = DeepRecursiveFunction<Int, Int>({ n ->
            if (n <= 1) 1 else n * callRecursive(n - 1)
        })

        fun main(): Int = factorial(5)
        """)
    }


    @Test func testDeepRecursiveSymbolsExposeExpectedSignatures() throws {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (ctx.sema!, ctx.interner)
        }

        let (sema, interner) = try #require(result)
        let invokeFQName = ["kotlin", "DeepRecursiveFunction", "invoke"].map { interner.intern($0) }
        let scopeCallFQName = ["kotlin", "DeepRecursiveScope", "callRecursive"].map { interner.intern($0) }

        let invokeSymbol = try #require(
            sema.symbols.lookupAll(fqName: invokeFQName).first(where: { symbolID in
                sema.symbols.symbol(symbolID)?.flags.contains(.operatorFunction) == true
            })
        )
        let invokeSignature = try #require(sema.symbols.functionSignature(for: invokeSymbol))
        #expect(!(invokeSignature.isSuspend))

        // The recursion trampoline lives in the runtime. The bundled Kotlin
        // source exposes both the scope member and the member extension.
        let callRecursiveSymbols = sema.symbols.lookupAll(fqName: scopeCallFQName)
        #expect(callRecursiveSymbols.count == 2)
        let callRecursiveSymbol = try #require(callRecursiveSymbols.first { symbolID in
            sema.symbols.externalLinkName(for: symbolID) == "__kk_deep_recursive_scope_callRecursive"
        })
        let callRecursiveSignature = try #require(sema.symbols.functionSignature(for: callRecursiveSymbol))
        #expect(callRecursiveSignature.parameterTypes.count == 1)
        #expect(!(callRecursiveSignature.isSuspend))

        let functionExtensionSymbol = try #require(callRecursiveSymbols.first { symbolID in
            sema.symbols.externalLinkName(for: symbolID) == "__kk_deep_recursive_function_callRecursive"
        })
        let functionExtensionSignature = try #require(
            sema.symbols.functionSignature(for: functionExtensionSymbol)
        )
        #expect(functionExtensionSignature.receiverType != nil)
        #expect(functionExtensionSignature.parameterTypes.count == 1)
        #expect(functionExtensionSignature.isSuspend)

        let scopedInvokeFQName = ["kotlin", "DeepRecursiveScope", "invoke"].map { interner.intern($0) }
        let scopedInvokeSymbol = try #require(
            sema.symbols.lookupAll(fqName: scopedInvokeFQName).first
        )
        let scopedInvokeSignature = try #require(sema.symbols.functionSignature(for: scopedInvokeSymbol))
        #expect(scopedInvokeSignature.receiverType != nil)
        #expect(scopedInvokeSignature.parameterTypes.count == 1)
        #expect(scopedInvokeSignature.returnType == sema.types.nothingType)
        #expect(!(scopedInvokeSignature.isSuspend))
        #expect(sema.symbols.externalLinkName(for: scopedInvokeSymbol) == nil)
        #expect(
            sema.symbols.annotations(for: scopedInvokeSymbol).contains {
                KnownCompilerAnnotation.deprecated.matches($0.annotationFQName)
            }
        )
    }

}
#endif
