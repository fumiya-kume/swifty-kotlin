import Foundation

class FlowBuilderProcessor: CallTypeProcessorBase, CallTypeProcessor {
    
    func canHandle(
        calleeName: InternedString?,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let calleeName = calleeName else { return false }
        
        let knownNames = KnownCompilerNames(interner: ctx.interner)
        
        // --- Flow builder function (CORO-003) ---
        if calleeName == knownNames.flow && args.count == 1 {
            return shouldUseBuiltinFlowFactorySpecialHandling(calleeName: calleeName, ctx: ctx)
        }
        
        // --- Flow builder lambda calls (CORO-003) ---
        if ctx.isFlowBuilderLambdaScope &&
           calleeName == knownNames.emit &&
           args.count == 1 &&
           ctx.cachedScopeLookup(calleeName).isEmpty {
            return true
        }
        
        return false
    }
    
    func processCall(
        _ id: ExprID,
        calleeName: InternedString?,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        guard let calleeName = calleeName else { return nil }
        
        let knownNames = KnownCompilerNames(interner: ctx.interner)
        let sema = ctx.sema
        
        // --- Flow builder function (CORO-003) ---
        if calleeName == knownNames.flow && args.count == 1 {
            return processFlowFunction(
                id: id,
                args: args,
                range: range,
                ctx: ctx,
                locals: &locals,
                explicitTypeArgs: explicitTypeArgs,
                sema: sema,
                knownNames: knownNames
            )
        }
        
        // --- Flow builder lambda calls (CORO-003) ---
        if ctx.isFlowBuilderLambdaScope &&
           calleeName == knownNames.emit &&
           args.count == 1 &&
           ctx.cachedScopeLookup(calleeName).isEmpty {
            return processEmitFunction(id: id, args: args, ctx: ctx, locals: &locals, sema: sema)
        }
        
        return nil
    }
    
    // MARK: - Private Helper Methods
    
    private func shouldUseBuiltinFlowFactorySpecialHandling(
        calleeName: InternedString,
        ctx: TypeInferenceContext
    ) -> Bool {
        // ユーザー定義（非合成）シンボルがない場合のみ特殊処理を使用
        return !ctx.cachedScopeLookup(calleeName).contains { candidate in
            guard let sym = ctx.cachedSymbol(candidate) else { return false }
            return !sym.flags.contains(.synthetic)
        }
    }
    
    private func processFlowFunction(
        id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        explicitTypeArgs: [TypeID],
        sema: SemaModule,
        knownNames: KnownCompilerNames
    ) -> TypeID {
        let flowLambdaExprID = args[0].expr
        let ast = ctx.ast
        
        guard isValidBuilderLambdaArgument(flowLambdaExprID, ast: ast) else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for call.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        
        var flowBuilderCtx = ctx.with(implicitReceiverType: sema.types.anyType)
        flowBuilderCtx.isFlowBuilderLambdaScope = true
        
        let flowLambdaExpectedType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: sema.types.unitType,
            isSuspend: true,
            nullability: .nonNull
        )))
        
        _ = driver.inferExpr(
            flowLambdaExprID,
            ctx: flowBuilderCtx,
            locals: &locals,
            expectedType: flowLambdaExpectedType
        )
        
        sema.bindings.markFlowExpr(id)
        
        if let explicitElementType = explicitTypeArgs.first {
            sema.bindings.bindFlowElementType(explicitElementType, forExpr: id)
        } else if let expectedType,
                  case let .classType(classType) = sema.types.kind(of: expectedType),
                  let firstArg = classType.args.first {
            switch firstArg {
            case let .invariant(type), let .in(type), let .out(type):
                sema.bindings.bindFlowElementType(type, forExpr: id)
            case .star:
                break
            }
        }
        
        let flowElementType = sema.bindings.flowElementType(forExpr: id) ?? sema.types.anyType
        let flowExprType = driver.helpers.makeFlowType(
            elementType: flowElementType, sema: sema, interner: ctx.interner
        ) ?? sema.types.anyType
        
        sema.bindings.bindExprType(id, type: flowExprType)
        return flowExprType
    }
    
    private func processEmitFunction(
        id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        sema: SemaModule
    ) -> TypeID {
        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}
