/// Binding for `String.windowed` / `windowedSequence`(size, step = 1, partialWindows = false, transform)
/// overloads: the `List<R>` / `Sequence<R>` counterparts. Sequence overloads
/// that already match by arity are resolved from the bundled declarations in
/// `StringWindowChunkTransform.kt`; skipped-default trailing-lambda forms
/// (`windowed(2) { }` / `windowedSequence(2) { }`) go through this binder so
/// `it` is typed as `CharSequence` before overload resolution.
///
/// The windowed list transform overload still uses a uniquely named bundled
/// function because the KIR lowering layer has legacy by-name dispatch for
/// `windowed`. The public `chunked` overload has a normal bundled declaration
/// and is resolved by the ordinary source-backed call path.
///
/// Split out from `CallTypeChecker+MemberCallInference.swift`.
extension CallTypeChecker {
    func tryBindStringWindowedTransform(
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
        let callee = interner.resolve(calleeName)
        // kotlinc: windowed/windowedSequence(size, step = 1, partialWindows = false, transform).
        // A trailing lambda binds to `transform` while skipped defaults are
        // filled from the source signature — same shape as List/Sequence
        // `canMatchViaTrailingLambda`. Requiring args.count == 4 made
        // `windowed(2) { ... }` / `windowedSequence(2) { ... }` miss this
        // overload entirely (`it` never bound).
        guard (2...4).contains(args.count),
              callee == "windowed" || callee == "windowedSequence",
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
        guard (1...3).contains(scalarArgIndices.count) else {
            return nil
        }
        func labeledScalar(_ name: String) -> Int? {
            scalarArgIndices.first { index in
                guard let label = args[index].label else { return false }
                return interner.resolve(label) == name
            }
        }
        var sizeArgIndex = labeledScalar("size")
        var stepArgIndex = labeledScalar("step")
        var partialArgIndex = labeledScalar("partialWindows")
        var assigned = Set<Int>()
        if let sizeArgIndex { assigned.insert(sizeArgIndex) }
        if let stepArgIndex { assigned.insert(stepArgIndex) }
        if let partialArgIndex { assigned.insert(partialArgIndex) }
        var unlabeled = scalarArgIndices.filter { !assigned.contains($0) }
        func takeUnlabeled() -> Int? {
            guard !unlabeled.isEmpty else { return nil }
            return unlabeled.removeFirst()
        }
        if sizeArgIndex == nil {
            sizeArgIndex = takeUnlabeled()
        }
        if stepArgIndex == nil {
            stepArgIndex = takeUnlabeled()
        }
        if partialArgIndex == nil {
            partialArgIndex = takeUnlabeled()
        }
        guard let sizeArgIndex, unlabeled.isEmpty else {
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
        if let stepArgIndex {
            _ = driver.inferExpr(args[stepArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
        }
        if let partialArgIndex {
            _ = driver.inferExpr(args[partialArgIndex].expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
        }
        sema.bindings.markCollectionHOFLambdaExpr(args[lambdaArgIndex].expr)
        _ = driver.inferExpr(args[lambdaArgIndex].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
        let bodyType = explicitTypeArgs.first
            ?? inferredLambdaReturnType(argExpr: args[lambdaArgIndex].expr, ast: ast, sema: sema)
        guard let chosen = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern(callee == "windowed" ? "kswiftkWindowedTransform" : "windowedSequence"),
        ]).first(where: { candidate in
            isSourceBackedStringWindowChunkTransformCandidate(
                candidate,
                parameterCount: 4,
                sema: sema
            )
        }) else {
            return nil
        }
        var parameterMapping: [Int: Int] = [
            sizeArgIndex: 0,
            lambdaArgIndex: 3,
        ]
        if let stepArgIndex {
            parameterMapping[stepArgIndex] = 1
        }
        if let partialArgIndex {
            parameterMapping[partialArgIndex] = 2
        }
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [bodyType],
                parameterMapping: parameterMapping
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        let resultType = callee == "windowed"
            ? makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: bodyType
            )
            : makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: bodyType
            )
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isSourceBackedStringWindowChunkTransformCandidate(
        _ candidate: SymbolID,
        parameterCount: Int,
        sema: SemaModule
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(candidate),
              symbol.kind == .function,
              sema.symbols.isSourceBackedSymbol(candidate),
              let signature = sema.symbols.functionSignature(for: candidate)
        else {
            return false
        }
        return signature.parameterTypes.count == parameterCount
    }
}
