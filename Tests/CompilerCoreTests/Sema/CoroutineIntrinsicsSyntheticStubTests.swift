#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct CoroutineIntrinsicsSyntheticStubTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema {
            return cached
        }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    @Test
    func testCoroutineIntrinsicsStubsAreRegisteredWithExpectedShapes() throws {
        let (sema, interner) = try sharedSema()

        let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
        let continuationSymbol = try #require(
            sema.symbols.lookup(fqName: continuationFQName),
            "Expected kotlin.coroutines.Continuation to be registered"
        )
        #expect(sema.symbols.symbol(continuationSymbol)?.kind == .interface)
        let continuationTypeParams = sema.types.nominalTypeParameterSymbols(for: continuationSymbol)
        #expect(continuationTypeParams.count == 1)

        let coroutineSuspendedFQName = ["kotlin", "coroutines", "intrinsics", "COROUTINE_SUSPENDED"].map { interner.intern($0) }
        let coroutineSuspendedSymbol = try #require(
            sema.symbols.lookup(fqName: coroutineSuspendedFQName),
            "Expected COROUTINE_SUSPENDED to be registered"
        )
        #expect(sema.symbols.symbol(coroutineSuspendedSymbol)?.kind == .property)
        #expect(sema.symbols.externalLinkName(for: coroutineSuspendedSymbol) == "kk_coroutine_suspended")
        #expect(sema.symbols.propertyType(for: coroutineSuspendedSymbol) == sema.types.nullableAnyType)

        let suspendIntrinsicFQName = ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"].map { interner.intern($0) }
        let suspendIntrinsicSymbol = try #require(
            sema.symbols.lookup(fqName: suspendIntrinsicFQName),
            "Expected suspendCoroutineUninterceptedOrReturn to be registered"
        )
        #expect(sema.symbols.symbol(suspendIntrinsicSymbol)?.kind == .function)
        #expect(sema.symbols.externalLinkName(for: suspendIntrinsicSymbol) == nil)

        let signature = try #require(sema.symbols.functionSignature(for: suspendIntrinsicSymbol))
        #expect(signature.isSuspend == true)
        #expect(signature.parameterTypes.count == 1)
        #expect(signature.typeParameterSymbols.count == 1)

        let functionTypeParam = try #require(signature.typeParameterSymbols.first)
        let functionTypeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: functionTypeParam,
            nullability: .nonNull
        )))
        let functionContinuationType = sema.types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(functionTypeParamType)],
            nullability: .nonNull
        )))
        let blockType = sema.types.make(.functionType(FunctionType(
            params: [functionContinuationType],
            returnType: sema.types.nullableAnyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        #expect(signature.parameterTypes == [blockType])
        #expect(signature.returnType == functionTypeParamType)
    }

    @Test
    func testSourceBackedCoroutineIntrinsicsReplaceResidualStubs() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: true,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let package = [
                interner.intern("kotlin"),
                interner.intern("coroutines"),
                interner.intern("intrinsics"),
            ]

            func symbols(named name: String) -> [SymbolID] {
                sema.symbols.lookupAll(fqName: package + [interner.intern(name)])
            }

            let suspendedName = interner.intern("COROUTINE_SUSPENDED")
            #expect(sema.bundledIndex.contains(ownerFQName: package, name: suspendedName, arity: 0))
            let suspendedSymbols = symbols(named: "COROUTINE_SUSPENDED")
            #expect(suspendedSymbols.count == 1)
            #expect(suspendedSymbols.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.synthetic) == false })

            let singletonSymbols = symbols(named: "CoroutineSingletons")
            #expect(singletonSymbols.count == 1)
            let singletonSymbol = try #require(singletonSymbols.first)
            #expect(sema.symbols.symbol(singletonSymbol)?.kind == .enumClass)

            let fallbackSymbols = symbols(named: "startCoroutineUninterceptedOrReturnFallback")
            #expect(fallbackSymbols.count == 2)
            #expect(fallbackSymbols.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.synthetic) == false })

            let suspendName = interner.intern("suspendCoroutineUninterceptedOrReturn")
            #expect(sema.bundledIndex.contains(ownerFQName: package, name: suspendName, arity: 1))
            let suspendSymbols = symbols(named: "suspendCoroutineUninterceptedOrReturn")
            #expect(suspendSymbols.count == 1)
            #expect(suspendSymbols.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.synthetic) == false })

            let wrapperSymbols = symbols(named: "wrapWithContinuationImpl")
            #expect(wrapperSymbols.count == 1)
            #expect(wrapperSymbols.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.synthetic) == false })
        }
    }

    // MARK: - Shared context for call-site tests

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?
    private static nonisolated(unsafe) var _sharedPaths: [String]?

    private func sharedCtx() throws -> (CompilationContext, [String]) {
        if let cached = Self._sharedCtx, let paths = Self._sharedPaths {
            return (cached, paths)
        }
        var result: CompilationContext?
        var paths: [String] = []
        try withTemporaryFiles(contents: Self.sharedSources) { p in
            paths = p
            let ctx = makeCompilationContext(
                inputs: paths,
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        Self._sharedPaths = paths
        return (ctx, paths)
    }

    private static let sharedSources: [String] = [
        """
        package sample0
        import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
        import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

        suspend fun probe(): Int {
            return suspendCoroutineUninterceptedOrReturn { continuation ->
                COROUTINE_SUSPENDED
            }
        }
        """,
        """
        package sample1
        import kotlin.coroutines.RestrictsSuspension

        @RestrictsSuspension
        class Scope

        @RestrictsSuspension
        interface ScopeInterface
        """,
        """
        package sample2
        import kotlin.coroutines.RestrictsSuspension

        @RestrictsSuspension
        fun bad() {}
        """,
        """
        package sample3
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn

        fun probe(block: suspend () -> Int, completion: Continuation<Int>): Any? {
            return block.startCoroutineUninterceptedOrReturn(completion)
        }
        """
    ]

    private func errorDiagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID && $0.severity == .error }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID && $0.code == code }
    }

    private func firstExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    @Test
    func testSuspendCoroutineIntrinsicsResolveInSource() throws {
        let (ctx, paths) = try sharedCtx()
        let path = paths[0]
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        #expect(errorDiagnosticsForPath(path, in: ctx).isEmpty)

        let callExpr = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .call(calleeExpr, _, _, _) = expr,
                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
            else {
                return false
            }
            return ctx.interner.resolve(calleeName) == "suspendCoroutineUninterceptedOrReturn"
        })

        #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .suspendCoroutineUninterceptedOrReturn)
        let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
        #expect(
            sema.symbols.externalLinkName(for: chosenCallee) ==
            nil
        )
        #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)
    }

    @Test
    func testStartCoroutineUninterceptedOrReturnOverloadsAreRegistered() throws {
        let (sema, interner) = try sharedSema()

        let fqName = ["kotlin", "coroutines", "intrinsics", "startCoroutineUninterceptedOrReturn"].map {
            interner.intern($0)
        }
        let symbols = sema.symbols.lookupAll(fqName: fqName)
        #expect(symbols.count == 2)

        let signatures = symbols.compactMap { sema.symbols.functionSignature(for: $0) }
        #expect(signatures.count == 2)
        #expect(symbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        #expect(symbols.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.inlineFunction) == true })
        #expect(signatures.allSatisfy { $0.receiverType != nil })
        #expect(signatures.allSatisfy { $0.returnType == sema.types.nullableAnyType })
        #expect(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
        #expect(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))
    }

    @Test
    func testRestrictsSuspensionAnnotationIsRegisteredWithClassTarget() throws {
        let (sema, interner) = try sharedSema()

        let fqName = ["kotlin", "coroutines", "RestrictsSuspension"].map {
            interner.intern($0)
        }
        let symbolID = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.RestrictsSuspension to be registered"
        )
        let symbol = try #require(sema.symbols.symbol(symbolID))
        #expect(symbol.kind == .annotationClass)
        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))

        let constructorFQName = fqName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        #expect(constructors.count == 1)
        let constructor = try #require(
            constructors.first,
            "Expected kotlin.coroutines.RestrictsSuspension to expose its implicit no-arg constructor"
        )
        let constructorSymbol = try #require(sema.symbols.symbol(constructor))
        #expect(constructorSymbol.visibility == .public)
        #expect(constructorSymbol.flags.contains(.synthetic))
        let constructorSignature = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(constructorSignature.parameterTypes.isEmpty)
        #expect(constructorSignature.returnType == sema.types.make(.classType(ClassType(
            classSymbol: symbolID,
            args: [],
            nullability: .nonNull
        ))))

        let annotations = sema.symbols.annotations(for: symbolID)
        #expect(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.CLASS"]
            },
            "RestrictsSuspension should target class-like declarations, got: \(annotations)"
        )
        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.BINARY"]
            },
            "RestrictsSuspension should use binary retention, got: \(annotations)"
        )
        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.SinceKotlin"
                    && $0.arguments == ["1.3"]
            },
            "RestrictsSuspension should be available since Kotlin 1.3, got: \(annotations)"
        )
    }

    @Test
    func testRestrictsSuspensionAnnotationTargetsClassLikeDeclarationsOnly() throws {
        let (ctx, paths) = try sharedCtx()
        let acceptedPath = paths[1]
        let rejectedPath = paths[2]

        let acceptedDiagnostics = diagnosticsForPath(
            acceptedPath,
            withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET",
            in: ctx
        )
        #expect(
            acceptedDiagnostics.isEmpty,
            "Expected RestrictsSuspension to accept class-like declarations, got: \(ctx.diagnostics.diagnostics)"
        )

        let rejectedDiagnostics = diagnosticsForPath(
            rejectedPath,
            withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET",
            in: ctx
        )
        #expect(
            rejectedDiagnostics.count == 1,
            "Expected RestrictsSuspension to reject function declarations, got: \(ctx.diagnostics.diagnostics)"
        )
        #expect(rejectedDiagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    @Test
    func testStartCoroutineUninterceptedOrReturnResolvesInSource() throws {
        let (ctx, paths) = try sharedCtx()
        let path = paths[3]
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        #expect(errorDiagnosticsForPath(path, in: ctx).isEmpty, "\(ctx.diagnostics.diagnostics)")

        let callExpr = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .memberCall(_, memberName, _, _, _) = expr else { return false }
            return ctx.interner.resolve(memberName) == "startCoroutineUninterceptedOrReturn"
        })

        let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
        #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        #expect(sema.bindings.exprTypes[callExpr] == sema.types.nullableAnyType)
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    private func isError(_ diagnostic: Diagnostic) -> Bool {
        diagnostic.severity == .error
    }
}
#endif
