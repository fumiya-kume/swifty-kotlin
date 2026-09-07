/// Synthetic-stdlib dispatch helpers used by `inferCallExpr` to detect
/// user-shadowing or qualified-call paths.
///
/// Split out from `CallTypeChecker.swift`.
extension CallTypeChecker {
    /// Returns true when `exprID` is a lambda literal or callable reference.
    func isLambdaOrCallableRefArg(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let argExpr = ast.arena.expr(exprID) else { return false }
        switch argExpr {
        case .lambdaLiteral, .callableRef:
            return true
        default:
            return false
        }
    }

    func shouldUseBuiltinFlowFactorySpecialHandling(
        calleeName: InternedString,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        if locals[calleeName] != nil {
            return false
        }
        let visibleCandidates = ctx.cachedScopeLookup(calleeName)
        if visibleCandidates.isEmpty {
            return true
        }
        // KSP-674: defer to any real (non-synthetic) declaration — the bundled
        // Kotlin `flowOf`/`emptyFlow` implementations (kotlinx.coroutines.flow)
        // or a user override. Only keep the builtin factory special handling
        // while a synthetic stub is the only visible candidate.
        let hasRealCandidate = visibleCandidates.contains { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function
            else {
                return false
            }
            return !symbol.flags.contains(.synthetic)
        }
        return !hasRealCandidate
    }

    /// Returns true when `name` is shadowed by a non-synthetic (user-defined) symbol,
    /// either as a local variable binding or as a scope-visible declaration.
    /// Used to guard stdlib special-call paths (measureTimeMillis, measureNanoTime, etc.)
    /// so that user-defined functions with the same name are not misidentified as stdlib intrinsics.
    func isShadowedByNonSyntheticSymbol(
        _ name: InternedString,
        locals: LocalBindings,
        ctx: TypeInferenceContext,
        argumentCount: Int? = nil
    ) -> Bool {
        if locals[name] != nil { return true }
        return ctx.cachedScopeLookup(name).contains { candidate in
            guard let sym = ctx.cachedSymbol(candidate) else { return false }
            if let argumentCount {
                guard sym.kind == .function,
                      let signature = ctx.sema.symbols.functionSignature(for: candidate),
                      signature.receiverType == nil,
                      signature.parameterTypes.count == argumentCount
                else {
                    return false
                }
            }
            return !sym.flags.contains(.synthetic)
        }
    }

    func topLevelStdlibSpecialCallKind(
        calleeName: InternedString,
        argCount: Int,
        locals: LocalBindings,
        ctx: TypeInferenceContext,
        rejectNonSyntheticShadow: Bool
    ) -> StdlibSpecialCallKind? {
        if locals[calleeName] != nil {
            return nil
        }
        if rejectNonSyntheticShadow,
           isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            return nil
        }
        let visibleCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        for candidate in visibleCandidates {
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  symbol.flags.contains(.synthetic),
                  let signature = ctx.sema.symbols.functionSignature(for: candidate),
                  signature.receiverType == nil,
                  signature.parameterTypes.count == argCount
            else {
                continue
            }
            if let kind = ctx.sema.symbols.stdlibSpecialCallKind(forSymbol: candidate) {
                return kind
            }
        }
        return nil
    }

    /// Returns true when there is a synthetic symbol visible under `name` whose
    /// fully-qualified name matches `fqComponents`.  Used to guard stdlib
    /// special-call paths so that identically-named user or third-party
    /// functions are not misclassified as stdlib intrinsics.
    func isSyntheticStdlibSymbol(
        _ name: InternedString,
        fqComponents: [String],
        ctx: TypeInferenceContext
    ) -> Bool {
        let interner = ctx.interner
        let internedFQ = fqComponents.map { interner.intern($0) }
        return ctx.cachedScopeLookup(name).contains { candidate in
            guard let sym = ctx.cachedSymbol(candidate),
                  sym.flags.contains(.synthetic)
            else { return false }
            return sym.fqName == internedFQ
        }
    }

    /// Resolves a synthetic `AtomicIntArray` / `AtomicLongArray` class symbol
    /// visible under `name`, accepting either the legacy `kotlin.concurrent`
    /// package or the newer `kotlin.concurrent.atomics` package.
    func syntheticAtomicArrayClassSymbol(
        _ name: InternedString,
        className: String,
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        let interner = ctx.interner
        let kotlin = interner.intern("kotlin")
        let concurrent = interner.intern("concurrent")
        let atomics = interner.intern("atomics")
        let classNameStr = interner.intern(className)
        let legacyFQ = [kotlin, concurrent, classNameStr]
        let atomicsFQ = [kotlin, concurrent, atomics, classNameStr]
        return ctx.cachedScopeLookup(name).first { candidate in
            guard let sym = ctx.cachedSymbol(candidate),
                  sym.kind == .class,
                  sym.flags.contains(.synthetic)
            else { return false }
            return sym.fqName == legacyFQ || sym.fqName == atomicsFQ
        }
    }

    /// Returns the visible stdlib function symbol for source-backed stdlib
    /// declarations that still need compiler special-casing.
    ///
    /// A migrated bundled function is no longer synthetic, so the generic
    /// shadowing guard would otherwise treat the stdlib declaration itself as a
    /// user shadow.  We allow the exact stdlib FQN and reject any other
    /// non-synthetic candidate with the same simple name.
    func sourceOrSyntheticStdlibFunctionSymbol(
        _ name: InternedString,
        fqComponents: [String],
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        let internedFQ = fqComponents.map { ctx.interner.intern($0) }
        var stdlibSymbol: SymbolID?
        for candidate in ctx.cachedScopeLookup(name) {
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function
            else {
                continue
            }
            if symbol.fqName == internedFQ {
                if symbol.flags.contains(.synthetic) {
                    return candidate
                }
                stdlibSymbol = stdlibSymbol ?? candidate
                continue
            }
            if !symbol.flags.contains(.synthetic) {
                return nil
            }
        }
        return stdlibSymbol
    }

    /// Returns the fully qualified path of a callee expression when it is
    /// composed of dotted names like `kotlin.coroutines.foo`.
    func qualifiedCalleePath(for exprID: ExprID, ast: ASTModule) -> [InternedString]? {
        guard let expr = ast.arena.expr(exprID) else {
            return nil
        }
        switch expr {
        case let .nameRef(name, _):
            return [name]
        case let .memberCall(receiver, member, _, _, _):
            guard let receiverPath = qualifiedCalleePath(for: receiver, ast: ast) else {
                return nil
            }
            return receiverPath + [member]
        case let .callableRef(receiver, member, _):
            if let receiver {
                guard let receiverPath = qualifiedCalleePath(for: receiver, ast: ast) else {
                    return nil
                }
                return receiverPath + [member]
            }
            return [member]
        default:
            return nil
        }
    }
}
