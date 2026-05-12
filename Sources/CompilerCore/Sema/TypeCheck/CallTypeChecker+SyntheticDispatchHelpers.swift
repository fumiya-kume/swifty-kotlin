/// Synthetic-stdlib dispatch helpers used by `inferCallExpr` to
/// recognize the kotlin.stdlib `run` / `let` / `also` / `apply` / `with`
/// scope-function family and to detect user-shadowing or qualified-call
/// paths.
///
/// Split out from `CallTypeChecker.swift`.
extension CallTypeChecker {
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
        let hasConflictingUserDefinedCandidate = visibleCandidates.contains { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function
            else {
                return false
            }
            let flowPkgPrefix = [
                ctx.interner.intern("kotlinx"),
                ctx.interner.intern("coroutines"),
                ctx.interner.intern("flow"),
            ]
            return !symbol.fqName.starts(with: flowPkgPrefix)
        }
        return !hasConflictingUserDefinedCandidate
    }

    // MARK: - Top-level run helpers (STDLIB-401)

    /// Returns true when the call site looks like a top-level `run { ... }` or
    /// `run(::ref)` that should be intercepted by the scope-function path.
    func isTopLevelRunCandidate(
        calleeName: InternedString?,
        args: [CallArgument],
        knownNames: KnownCompilerNames,
        ast: ASTModule,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        guard let calleeName, args.count == 1,
              calleeName == knownNames.run,
              locals[calleeName] == nil
        else {
            return false
        }
        return isLambdaOrCallableRefArg(args[0].expr, ast: ast)
            && !isShadowedByUserDefinedRun(calleeName, ctx: ctx)
    }

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

    /// Returns true when a non-synthetic (user-defined) `run` shadows the
    /// synthetic stdlib helper.
    /// KNOWN LIMITATION: This treats any non-synthetic symbol named `run` as
    /// shadowing, regardless of whether it is a top-level or extension overload.
    /// A more precise check would compare signatures/receiver types.
    func isShadowedByUserDefinedRun(
        _ calleeName: InternedString,
        ctx: TypeInferenceContext
    ) -> Bool {
        ctx.cachedScopeLookup(calleeName).contains { candidate in
            guard let sym = ctx.cachedSymbol(candidate) else { return false }
            return !sym.flags.contains(.synthetic)
        }
    }

    /// Returns true when `name` is shadowed by a non-synthetic (user-defined) symbol,
    /// either as a local variable binding or as a scope-visible declaration.
    /// Used to guard stdlib special-call paths (measureTimeMillis, measureNanoTime, etc.)
    /// so that user-defined functions with the same name are not misidentified as stdlib intrinsics.
    func isShadowedByNonSyntheticSymbol(
        _ name: InternedString,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> Bool {
        if locals[name] != nil { return true }
        return ctx.cachedScopeLookup(name).contains { candidate in
            guard let sym = ctx.cachedSymbol(candidate) else { return false }
            return !sym.flags.contains(.synthetic)
        }
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
