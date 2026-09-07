#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DeepRecursiveSourceMigrationTests {
    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private static let sharedSources: [String] = [
        """
        fun noop() {}
        """,
        """
        class Node(val next: Node?)

        fun makeDepth(): DeepRecursiveFunction<Node?, Int> {
            val depth: DeepRecursiveFunction<Node?, Int> = DeepRecursiveFunction<Node?, Int> {
                if (it == null) 0 else callRecursive(it.next) + 1
            }
            return depth
        }

        fun useDepth(node: Node?): Int = makeDepth()(node)
        """,
    ]

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }

    @Test func testDeepRecursiveAPISymbolsComeFromBundledKotlinSource() throws {
        let ctx = try sharedCtx()

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected bundled DeepRecursive.kt to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        let functionFQName = ["kotlin", "DeepRecursiveFunction"].map(ctx.interner.intern)
        let scopeFQName = ["kotlin", "DeepRecursiveScope"].map(ctx.interner.intern)

        for fqName in [functionFQName, scopeFQName] {
            let classSymbol = try #require(sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .class
            })
            let info = try #require(sema.symbols.symbol(classSymbol))
            #expect(!info.flags.contains(.synthetic), "DeepRecursive types should be backed by bundled source")
            #expect(sema.types.nominalTypeParameterSymbols(for: classSymbol).count == 2)
            #expect(bundledSourcePath(for: classSymbol, sema: sema, ctx: ctx) == true)
        }

        let constructorFQName = functionFQName + [ctx.interner.intern("<init>")]
        let constructorSymbol = try #require(sema.symbols.lookupAll(fqName: constructorFQName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .constructor
        })
        #expect(sema.symbols.externalLinkName(for: constructorSymbol) == "__kk_deep_recursive_function_new")
        #expect(
            bundledSourcePath(for: constructorSymbol, sema: sema, ctx: ctx) == true,
            "constructor source path: \(sourcePath(for: constructorSymbol, sema: sema, ctx: ctx) ?? "<none>")"
        )

        let functionClassSymbol = try #require(classSymbol(named: "DeepRecursiveFunction", sema: sema, ctx: ctx))
        let functionTypeParameterSymbols = sema.types.nominalTypeParameterSymbols(for: functionClassSymbol)
        let scopeClassSymbol = try #require(classSymbol(named: "DeepRecursiveScope", sema: sema, ctx: ctx))
        let constructorSignature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
        #expect(constructorSignature.parameterTypes.count == 1)
        guard case let .functionType(blockType) = sema.types.kind(of: constructorSignature.parameterTypes[0]) else {
            Issue.record("DeepRecursiveFunction constructor should take a function type")
            return
        }
        #expect(blockType.isSuspend)
        guard let receiver = blockType.receiver,
              case let .classType(receiverClass) = sema.types.kind(of: receiver)
        else {
            Issue.record("DeepRecursiveFunction constructor block should have a DeepRecursiveScope receiver")
            return
        }
        #expect(receiverClass.classSymbol == scopeClassSymbol)
        let receiverTypeParameterSymbols = receiverClass.args.compactMap { argument -> SymbolID? in
            guard case let .invariant(type) = argument,
                  case let .typeParam(typeParameter) = sema.types.kind(of: type)
            else {
                return nil
            }
            return typeParameter.symbol
        }
        #expect(receiverTypeParameterSymbols == functionTypeParameterSymbols)
        #expect(blockType.params.count == 1)
        guard case let .typeParam(valueType) = sema.types.kind(of: blockType.params[0]),
              case let .typeParam(returnType) = sema.types.kind(of: blockType.returnType)
        else {
            Issue.record("DeepRecursiveFunction constructor block should use the class type parameters")
            return
        }
        #expect(valueType.symbol == functionTypeParameterSymbols[0])
        #expect(returnType.symbol == functionTypeParameterSymbols[1])

        let invokeSymbol = try #require(member("invoke", of: functionFQName, sema: sema, ctx: ctx))
        #expect(sema.symbols.externalLinkName(for: invokeSymbol) == "__kk_deep_recursive_function_invoke")
        #expect(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)

        let functionCallRecursive = try #require(member("callRecursive", of: functionFQName, sema: sema, ctx: ctx))
        #expect(
            sema.symbols.externalLinkName(for: functionCallRecursive)
                == "__kk_deep_recursive_function_callRecursive"
        )

        let scopeCallRecursive = try #require(
            sema.symbols.lookupAll(fqName: scopeFQName + [ctx.interner.intern("callRecursive")]).first { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == "__kk_deep_recursive_scope_callRecursive"
            }
        )
        #expect(
            sema.symbols.externalLinkName(for: scopeCallRecursive) == "__kk_deep_recursive_scope_callRecursive"
        )
        #expect(bundledSourcePath(for: scopeCallRecursive, sema: sema, ctx: ctx) == true)

        let functionExtension = try #require(
            sema.symbols.lookupAll(fqName: scopeFQName + [ctx.interner.intern("callRecursive")]).first { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == "__kk_deep_recursive_function_callRecursive"
            }
        )
        let functionExtensionSignature = try #require(sema.symbols.functionSignature(for: functionExtension))
        #expect(functionExtensionSignature.receiverType != nil)
        #expect(functionExtensionSignature.isSuspend)
        #expect(bundledSourcePath(for: functionExtension, sema: sema, ctx: ctx) == true)

        let scopedInvoke = try #require(
            sema.symbols.lookupAll(fqName: scopeFQName + [ctx.interner.intern("invoke")]).first
        )
        let scopedInvokeSignature = try #require(sema.symbols.functionSignature(for: scopedInvoke))
        #expect(scopedInvokeSignature.receiverType != nil)
        #expect(scopedInvokeSignature.returnType == sema.types.nothingType)
        #expect(bundledSourcePath(for: scopedInvoke, sema: sema, ctx: ctx) == true)
    }

    @Test func testDeepRecursiveCallsResolveToBundledKotlinSourceSymbols() throws {
        let ctx = try sharedCtx()

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected DeepRecursive source calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let factoryCall = try #require(firstExprID(in: ast) { exprID, _ in
            guard let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee else { return false }
            return sema.symbols.externalLinkName(for: chosen) == "__kk_deep_recursive_function_new"
        })
        let constructorCallee = try #require(sema.bindings.callBinding(for: factoryCall)?.chosenCallee)
        #expect(sema.symbols.symbol(constructorCallee)?.kind == .constructor)
        #expect(
            bundledSourcePath(for: constructorCallee, sema: sema, ctx: ctx) == true,
            "constructor source path: \(sourcePath(for: constructorCallee, sema: sema, ctx: ctx) ?? "<none>")"
        )

        // `callRecursive(...)` inside the block resolves through ordinary
        // member lookup on the DeepRecursiveScope receiver, not a Sema special case.
        let callRecursiveCall = try #require(firstExprID(in: ast) { exprID, expr in
            guard case let .call(calleeID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeID),
                  case let .nameRef(name, _) = calleeExpr,
                  ctx.interner.resolve(name) == "callRecursive"
            else { return false }
            return sema.bindings.callBinding(for: exprID) != nil
        })
        let callRecursiveCallee = try #require(sema.bindings.callBinding(for: callRecursiveCall)?.chosenCallee)
        let calleeFQName = try #require(sema.symbols.symbol(callRecursiveCallee)?.fqName)
            .map { ctx.interner.resolve($0) }
            .joined(separator: ".")
        #expect(calleeFQName == "kotlin.DeepRecursiveScope.callRecursive")
        #expect(
            sema.symbols.externalLinkName(for: callRecursiveCallee) == "__kk_deep_recursive_scope_callRecursive"
        )
        #expect(bundledSourcePath(for: callRecursiveCallee, sema: sema, ctx: ctx) == true)
    }

    private func member(
        _ name: String,
        of ownerFQName: [InternedString],
        sema: SemaModule,
        ctx: CompilationContext
    ) -> SymbolID? {
        sema.symbols.lookupAll(fqName: ownerFQName + [ctx.interner.intern(name)]).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .function
        }
    }

    private func classSymbol(
        named name: String,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> SymbolID? {
        let fqName = ["kotlin", name].map { ctx.interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fqName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .class
        }
    }

    private func bundledSourcePath(
        for symbol: SymbolID,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> Bool {
        sourcePath(for: symbol, sema: sema, ctx: ctx)?.contains("__bundled_kotlin/DeepRecursive.kt") == true
    }

    private func sourcePath(
        for symbol: SymbolID,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> String? {
        // Constructors use their declaration range for source ownership while
        // the containing class carries the explicit source file ID.
        let fileID = sema.symbols.sourceFileID(for: symbol)
            ?? sema.symbols.symbol(symbol)?.declSite?.start.file
            ?? sema.symbols.parentSymbol(for: symbol).flatMap { sema.symbols.sourceFileID(for: $0) }
        guard let fileID else { return nil }
        return ctx.sourceManager.path(of: fileID)
    }
}
#endif
