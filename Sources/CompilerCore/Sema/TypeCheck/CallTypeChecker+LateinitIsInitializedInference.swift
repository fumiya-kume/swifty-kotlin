/// Inference for `prop::isInitialized` lateinit-property reference accesses.
///
/// Split out from `CallTypeChecker+MemberCallInference.swift`.
extension CallTypeChecker {
    /// Handles `prop::isInitialized` on lateinit property references.
    /// Returns the inferred type, or `nil` when the call is not a lateinit
    /// `isInitialized` access (the dispatcher should continue with other checks).
    func tryInferLateinitIsInitializedCall(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        guard args.isEmpty,
              case .callableRef = ast.arena.expr(receiverID),
              calleeName == knownNames.isInitialized
        else {
            return nil
        }

        _ = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
        if let propertySymbol = sema.bindings.identifierSymbol(for: receiverID),
           let propertyInfo = sema.symbols.symbol(propertySymbol),
           propertyInfo.kind == .property,
           propertyInfo.flags.contains(.lateinitProperty)
        {
            let boolType = sema.types.make(.primitive(.boolean, .nonNull))
            if let isInitializedProperty = ctx.cachedScopeLookup(calleeName).first(where: { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .property
                else {
                    return false
                }
                return sema.symbols.extensionPropertyReceiverType(for: candidate) != nil
            }) {
                sema.bindings.bindIdentifier(id, symbol: isInitializedProperty)
            }
            sema.bindings.bindExprType(id, type: boolType)
            return boolType
        }

        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-LATEINIT",
            "'isInitialized' is only available on lateinit property references.",
            range: range
        )
        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
    }
}
