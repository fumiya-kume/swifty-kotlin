
/// KProperty / KFunction reflection-aware member-call lowerings.
///
/// Split out from `CallLowerer+MemberCalls.swift`.
extension CallLowerer {
    // MARK: - KProperty member access lowering (PROP-007)

    private func isKCallableReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return false
        }
        let resolvedName = interner.resolve(symbol.name)
        return resolvedName == "KCallable"
            || resolvedName == "KFunction"
            || resolvedName == "KFunction0"
            || resolvedName == "KFunction1"
            || resolvedName == "KFunction2"
            || resolvedName == "KFunction3"
            || resolvedName == "KProperty"
            || resolvedName == "KProperty0"
            || resolvedName == "KProperty1"
            || resolvedName == "KProperty2"
            || resolvedName == "KMutableProperty"
            || resolvedName == "KMutableProperty0"
            || resolvedName == "KMutableProperty1"
            || resolvedName == "KMutableProperty2"
    }

    private func isKPropertyReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return false
        }
        let resolvedName = interner.resolve(symbol.name)
        return resolvedName == "KProperty" || resolvedName == "KProperty0"
            || resolvedName == "KProperty1" || resolvedName == "KProperty2"
            || resolvedName == "KCallable"
            || resolvedName == "KMutableProperty" || resolvedName == "KMutableProperty0"
            || resolvedName == "KMutableProperty1" || resolvedName == "KMutableProperty2"
    }

    func tryLowerKPropertyMemberAccess(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeStr = interner.resolve(calleeName)
        guard calleeStr == "name" || calleeStr == "returnType" else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard isKCallableReceiverType(receiverType, sema: sema, interner: interner) else { return nil }

        // Lower the receiver expression.
        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let resultType = sema.bindings.exprTypes[exprID]
            ?? (calleeStr == "name" ? sema.types.stringType : sema.types.anyType)
        let result = arena.appendTemporary(type: resultType)
        emitNonThrowingCall(
            callee: interner.intern(
                calleeStr == "name" ? "__kk_kcallable_get_name" : "__kk_kcallable_get_return_type"
            ),
            arg: receiverID,
            result: result,
            into: &instructions
        )
        return result
    }

    /// Emits a KCallable metadata property after the safe-call null check has
    /// already passed.
    func tryLowerKCallableNameAccess(
        receiverType: TypeID,
        receiverID: KIRExprID,
        result: KIRExprID,
        calleeName: InternedString,
        sema: SemaModule,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> Bool {
        let memberName = interner.resolve(calleeName)
        guard (memberName == "name" || memberName == "returnType"),
              isKCallableReceiverType(receiverType, sema: sema, interner: interner)
        else {
            return false
        }
        emitNonThrowingCall(
            callee: interner.intern(
                memberName == "name" ? "__kk_kcallable_get_name" : "__kk_kcallable_get_return_type"
            ),
            arg: receiverID,
            result: result,
            into: &instructions
        )
        return true
    }

    // MARK: - KFunction member access lowering (STDLIB-REFLECT-063)

    private func isKFunctionReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        // Check for KFunction class types.
        if let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema)
        {
            let resolvedName = interner.resolve(symbol.name)
            return resolvedName == "KFunction" || resolvedName == "KFunction0"
                || resolvedName == "KFunction1" || resolvedName == "KFunction2"
                || resolvedName == "KFunction3" || resolvedName == "KCallable"
        }
        // Also check function types — callable references (`::foo`) have function types
        // but are tagged as KFunction at runtime.
        if case .functionType = sema.types.kind(of: nonNullType) {
            return false // Plain function types are not KFunction; only tagged callable refs are.
        }
        return false
    }

    /// Known KFunction member names and their corresponding runtime function.
    private static let kFunctionMemberMap: [String: String] = [
        "name": "__kk_kcallable_get_name",
        "returnType": "__kk_kcallable_get_return_type",
        "parameters": "__kk_kfunction_get_parameters",
        "valueParameters": "__kk_kfunction_get_value_parameters",
        "isSuspend": "__kk_kfunction_is_suspend",
        "type": "__kk_kfunction_get_type",
    ]

    func tryLowerKFunctionMemberAccess(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeStr = interner.resolve(calleeName)
        guard let runtimeFunc = Self.kFunctionMemberMap[calleeStr] else { return nil }

        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard isKFunctionReceiverType(receiverType, sema: sema, interner: interner) else { return nil }

        // Lower the receiver expression.
        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let result = arena.appendTemporary(type: resultType
        )
        emitNonThrowingCall(
            callee: interner.intern(runtimeFunc),
            arg: receiverID,
            result: result,
            into: &instructions
        )
        return result
    }

    // MARK: - KParameter member access lowering (STDLIB-REFLECT-TYPE-013)

    private func isKParameterReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return false
        }
        return interner.resolve(symbol.name) == "KParameter"
    }

    /// Known KParameter member names and their corresponding runtime function.
    private static let kParameterMemberMap: [String: String] = [
        "index": "__kk_kparameter_get_index",
        "name": "__kk_kparameter_get_name",
        "type": "__kk_kparameter_get_type",
        "isOptional": "__kk_kparameter_is_optional",
        "kind": "__kk_kparameter_get_kind",
    ]

    func tryLowerKParameterMemberAccess(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeStr = interner.resolve(calleeName)
        guard let runtimeFunc = Self.kParameterMemberMap[calleeStr] else { return nil }

        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard isKParameterReceiverType(receiverType, sema: sema, interner: interner) else { return nil }

        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let result = arena.appendTemporary(type: resultType
        )
        emitNonThrowingCall(
            callee: interner.intern(runtimeFunc),
            arg: receiverID,
            result: result,
            into: &instructions
        )
        return result
    }

    /// Lowers KFunction.call() with arguments to the appropriate arity-specific runtime call.
    func tryLowerKFunctionCallInvocation(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let calleeStr = interner.resolve(calleeName)
        guard calleeStr == "call" else { return nil }

        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard isKFunctionReceiverType(receiverType, sema: sema, interner: interner) else { return nil }

        // Lower the receiver expression (the KFunction handle).
        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        // Lower all arguments.
        var argExprs: [KIRExprID] = []
        for arg in args {
            let argExpr = driver.exprLowerer.lowerExpr(
                arg.expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            argExprs.append(argExpr)
        }

        // Choose the appropriate arity-specific call.
        let callCallee: String
        switch argExprs.count {
        case 0: callCallee = "__kk_kfunction_call_0"
        case 1: callCallee = "__kk_kfunction_call_1"
        case 2: callCallee = "__kk_kfunction_call_2"
        case 3: callCallee = "__kk_kfunction_call_3"
        default: callCallee = "__kk_kfunction_call_vararg"
        }

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType

        if argExprs.count <= 3 {
            // Direct arity-specific call: kk_kfunction_call_N(handle, arg1, ..., outThrown)
            let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType
            )
            let result = arena.appendTemporary(type: resultType
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(callCallee),
                arguments: [receiverID] + argExprs,
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            return result
        } else {
            // Vararg path: pack args into a list, call __kk_kfunction_call_vararg.
            // First, create a runtime list with the args.
            let listExpr = arena.appendTemporary(type: sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("__kk_list_of"),
                arguments: argExprs,
                result: listExpr,
                canThrow: false,
                thrownResult: nil
            ))
            let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType
            )
            let result = arena.appendTemporary(type: resultType
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(callCallee),
                arguments: [receiverID, listExpr],
                result: result,
                canThrow: true,
                thrownResult: thrownResult
            ))
            return result
        }
    }
}
