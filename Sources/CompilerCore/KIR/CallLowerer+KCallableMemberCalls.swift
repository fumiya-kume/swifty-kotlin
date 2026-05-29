import Foundation

/// KProperty / KFunction reflection-aware member-call lowerings.
///
/// Split out from `CallLowerer+MemberCalls.swift`.
extension CallLowerer {
    // MARK: - KProperty member access lowering (PROP-007)

    /// Checks if the receiver type is a `kotlin.reflect.KProperty` (or related reflect interface)
    /// and the callee is a known property like `name`, and if so emits the runtime call.
    private func isKPropertyReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let resolvedName = interner.resolve(symbol.name)
        return resolvedName == "KProperty" || resolvedName == "KProperty0"
            || resolvedName == "KProperty1" || resolvedName == "KCallable"
            || resolvedName == "KMutableProperty" || resolvedName == "KMutableProperty0"
            || resolvedName == "KMutableProperty1"
    }

    func tryLowerKPropertyMemberAccess(
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
        guard calleeStr == "name" else { return nil }
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard isKPropertyReceiverType(receiverType, sema: sema, interner: interner) else { return nil }

        // Lower the receiver expression.
        let receiverID = driver.exprLowerer.lowerExpr(
            receiverExpr, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let resultType = sema.bindings.exprTypes[exprID]
            ?? sema.types.make(.primitive(.string, .nonNull))
        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: resultType
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_kproperty_stub_name"),
            arguments: [receiverID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    // MARK: - KFunction member access lowering (STDLIB-REFLECT-063)

    /// Checks if the receiver type is a `kotlin.reflect.KFunction` (or related reflect interface)
    /// so that member accesses like `.name`, `.returnType`, `.parameters`, `.isSuspend` can be lowered.
    private func isKFunctionReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        // Check for KFunction class types.
        if case let .classType(classType) = sema.types.kind(of: nonNullType),
           let symbol = sema.symbols.symbol(classType.classSymbol)
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
        "name": "kk_kfunction_get_name",
        "returnType": "kk_kfunction_get_return_type",
        "parameters": "kk_kfunction_get_parameters",
        "valueParameters": "kk_kfunction_get_value_parameters",
        "isSuspend": "kk_kfunction_is_suspend",
        "type": "kk_kfunction_get_type",
        "visibility": "kk_kfunction_get_visibility",
        "annotations": "kk_kfunction_get_annotations",
    ]

    func tryLowerKFunctionMemberAccess(
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
        let result = arena.appendExpr(
            .temporary(Int32(arena.expressions.count)),
            type: resultType
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(runtimeFunc),
            arguments: [receiverID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
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
        case 0: callCallee = "kk_kfunction_call_0"
        case 1: callCallee = "kk_kfunction_call_1"
        case 2: callCallee = "kk_kfunction_call_2"
        case 3: callCallee = "kk_kfunction_call_3"
        default: callCallee = "kk_kfunction_call_vararg"
        }

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType

        if argExprs.count <= 3 {
            // Direct arity-specific call: kk_kfunction_call_N(handle, arg1, ..., outThrown)
            let thrownResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.nullableAnyType
            )
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: resultType
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
            // Vararg path: pack args into a list, call kk_kfunction_call_vararg.
            // First, create a runtime list with the args.
            let listExpr = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_list_of"),
                arguments: argExprs,
                result: listExpr,
                canThrow: false,
                thrownResult: nil
            ))
            let thrownResult = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: sema.types.nullableAnyType
            )
            let result = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: resultType
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
