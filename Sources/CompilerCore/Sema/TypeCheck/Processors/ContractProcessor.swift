import Foundation

class ContractProcessor: CallTypeProcessorBase, CallTypeProcessor {
    
    func canHandle(
        calleeName: InternedString?,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let calleeName = calleeName else { return false }
        
        // contract { ... } のチェック
        return ctx.interner.resolve(calleeName) == "contract" && args.count == 1
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
        guard let calleeName = calleeName,
              ctx.interner.resolve(calleeName) == "contract",
              args.count == 1 else {
            return nil
        }
        
        let sema = ctx.sema
        let interner = ctx.interner
        
        let builderSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("contracts"),
            interner.intern("ContractBuilder"),
        ])
        
        let builderType = builderSymbol.map {
            sema.types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull)))
        } ?? sema.types.anyType
        
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            receiver: builderType,
            params: [],
            returnType: sema.types.unitType
        )))
        
        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx.with(implicitReceiverType: builderType),
            locals: &locals,
            expectedType: lambdaExpectedType
        )
        
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}
