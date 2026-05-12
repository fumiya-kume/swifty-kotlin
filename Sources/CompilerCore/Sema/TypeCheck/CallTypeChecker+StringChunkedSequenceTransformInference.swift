/// Inference for `String.chunked(Sequence)` / `String.chunked(Sequence) { ... }`
/// transform overloads (STDLIB-CHUNKED).
///
/// Split out from `CallTypeChecker+MemberCallInference.swift` to keep
/// member-call inference helpers grouped by responsibility.
extension CallTypeChecker {
    func tryInferStringChunkedSequenceTransform(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        safeCall: Bool
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        guard args.count == 2,
              interner.resolve(calleeName) == "chunkedSequence",
              isSyntheticStringLikeType(receiverType, sema: sema)
        else {
            return nil
        }
        guard explicitTypeArgs.count <= 1 else {
            sema.bindings.bindExprType(id, type: sema.types.anyType)
            return sema.types.anyType
        }

        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
            sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
        }

        let expectedElementType: TypeID = {
            if let explicitType = explicitTypeArgs.first {
                return explicitType
            }
            guard let expectedType else {
                return sema.types.anyType
            }
            let elementType = extractIterableOrSequenceElementType(expectedType, sema: sema, interner: interner)
            return elementType == sema.types.anyType ? sema.types.anyType : elementType
        }()
        let charSequenceType = syntheticCharSequenceType(sema: sema) ?? sema.types.stringType
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            params: [charSequenceType],
            returnType: expectedElementType,
            isSuspend: false,
            nullability: .nonNull
        )))
        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)

        let inferredBodyType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
        let bodyType = explicitTypeArgs.first
            ?? (expectedElementType == sema.types.anyType ? inferredBodyType : expectedElementType)
        if let chosen = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            calleeName,
        ]).first(where: { candidate in
            isSyntheticStringMemberCandidate(
                candidate,
                named: calleeName,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            )
                && (sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == args.count
        }) {
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [bodyType],
                    parameterMapping: [0: 0, 1: 1]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        }

        let resultType = makeSyntheticSequenceType(
            symbols: sema.symbols,
            types: sema.types,
            interner: interner,
            elementType: bodyType
        )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    // MARK: - inferMemberCallImpl: KClass / lateinit-isInitialized sub-dispatchers
    //
    // These helpers were extracted from `inferMemberCallImpl` (which used to be a
    // ~7,000-line single function — the principal merge-conflict source for stdlib
    // PRs adding new `if calleeName == X { ... }` blocks). Each returns
    // `TypeID?`: a non-nil value means "handled, here is the inferred return
    // type"; a nil return means "didn't match, dispatcher should fall through".
    //
    // The semantics — including side-effecting calls to `driver.inferExpr` and
    // any `sema.bindings.bind*` mutations — are preserved bit-for-bit relative to
    // the original inline code. New stdlib APIs targeting the same domain (KClass
    // member access, lateinit `isInitialized`) should be added here rather than
    // in the dispatcher.
}
