/// Binding for `String.chunkedSequence(transform:)` and
/// `String.windowedSequence(transform:)` overloads (STDLIB-CHUNKED / WINDOWED).
///
/// Split out from `CallTypeChecker+MemberCallInference.swift`.
extension CallTypeChecker {
    func tryBindStringChunkedSequenceTransform(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard args.count == 2,
              interner.resolve(calleeName) == "chunkedSequence",
              isSyntheticStringLikeType(receiverType, sema: sema)
        else {
            return nil
        }
        guard let lambdaArgIndex = args.indices.first(where: { index in
            ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
        }) else {
            return nil
        }
        guard let sizeArgIndex = args.indices.first(where: { index in
            index != lambdaArgIndex
        }) else {
            return nil
        }
        guard explicitTypeArgs.count <= 1 else {
            sema.bindings.bindExprType(id, type: sema.types.anyType)
            return sema.types.anyType
        }
        let charSequenceType = syntheticCharSequenceType(sema: sema) ?? sema.types.stringType
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            params: [charSequenceType],
            returnType: explicitTypeArgs.first ?? sema.types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        _ = driver.inferExpr(args[sizeArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        sema.bindings.markCollectionHOFLambdaExpr(args[lambdaArgIndex].expr)
        _ = driver.inferExpr(args[lambdaArgIndex].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
        let bodyType = explicitTypeArgs.first
            ?? inferredLambdaReturnType(argExpr: args[lambdaArgIndex].expr, ast: ast, sema: sema)
        guard let chosen = sema.symbols.lookupAll(fqName: [
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
                && sema.symbols.externalLinkName(for: candidate) == "kk_string_chunked_sequence_transform"
        }) else {
            return nil
        }
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [bodyType],
                parameterMapping: [sizeArgIndex: 0, lambdaArgIndex: 1]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
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

    func tryBindStringWindowedSequenceTransform(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard args.count == 4,
              interner.resolve(calleeName) == "windowedSequence",
              isSyntheticStringLikeType(receiverType, sema: sema)
        else {
            return nil
        }
        guard let lambdaArgIndex = args.indices.first(where: { index in
            ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
        }) else {
            return nil
        }
        let scalarArgIndices = args.indices.filter { $0 != lambdaArgIndex }
        guard scalarArgIndices.count == 3 else {
            return nil
        }
        func scalarArgIndex(named name: String, fallbackPosition: Int) -> Int? {
            if let labeled = scalarArgIndices.first(where: { index in
                guard let label = args[index].label else { return false }
                return interner.resolve(label) == name
            }) {
                return labeled
            }
            guard fallbackPosition < scalarArgIndices.count else {
                return nil
            }
            return scalarArgIndices[fallbackPosition]
        }
        guard let sizeArgIndex = scalarArgIndex(named: "size", fallbackPosition: 0),
              let stepArgIndex = scalarArgIndex(named: "step", fallbackPosition: 1),
              let partialArgIndex = scalarArgIndex(named: "partialWindows", fallbackPosition: 2)
        else {
            return nil
        }
        guard explicitTypeArgs.count <= 1 else {
            sema.bindings.bindExprType(id, type: sema.types.anyType)
            return sema.types.anyType
        }
        let charSequenceType = syntheticCharSequenceType(sema: sema) ?? sema.types.stringType
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            params: [charSequenceType],
            returnType: explicitTypeArgs.first ?? sema.types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        _ = driver.inferExpr(args[sizeArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        _ = driver.inferExpr(args[stepArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        _ = driver.inferExpr(args[partialArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
        sema.bindings.markCollectionHOFLambdaExpr(args[lambdaArgIndex].expr)
        _ = driver.inferExpr(args[lambdaArgIndex].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
        let bodyType = explicitTypeArgs.first
            ?? inferredLambdaReturnType(argExpr: args[lambdaArgIndex].expr, ast: ast, sema: sema)
        guard let chosen = sema.symbols.lookupAll(fqName: [
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
                && sema.symbols.externalLinkName(for: candidate) == "kk_string_windowedSequence_transform"
        }) else {
            return nil
        }
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [bodyType],
                parameterMapping: [
                    sizeArgIndex: 0,
                    stepArgIndex: 1,
                    partialArgIndex: 2,
                    lambdaArgIndex: 3,
                ]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
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
}
