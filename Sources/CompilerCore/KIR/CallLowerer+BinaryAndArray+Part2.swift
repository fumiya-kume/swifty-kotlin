import Foundation


extension CallLowerer {
    func lowerIndexedAccessExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let propertyConstantInitializers = shared.propertyConstantInitializers
        let boundType = sema.bindings.exprTypes[exprID]
        let receiverID = driver.lowerExpr(
            receiverExpr,
            shared: shared,
            emit: &instructions
        )
        // Built-in array get only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed access")
        let indexID = driver.lowerExpr(
            indices[0],
            shared: shared,
            emit: &instructions
        )
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    func lowerIndexedAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let propertyConstantInitializers = shared.propertyConstantInitializers
        let receiverID = driver.lowerExpr(
            receiverExpr,
            shared: shared,
            emit: &instructions
        )
        // Built-in array set only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed assign")
        let indexID = driver.lowerExpr(
            indices[0],
            shared: shared,
            emit: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            shared: shared,
            emit: &instructions
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, valueID],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerIndexedCompoundAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let propertyConstantInitializers = shared.propertyConstantInitializers
        // Conceptual desugaring: a[i] += v
        //   1) t = kk_array_get(a, i)
        //   2) t' = kk_op_*(t, v)      // appropriate kk_op_* for the compound operator
        //   3) kk_array_set(a, i, t')
        let receiverID = driver.lowerExpr(
            receiverExpr,
            shared: shared,
            emit: &instructions
        )
        // Built-in array compound assign only supports a single Int index
        assert(!indices.isEmpty, "indices must not be empty for indexed compound assign")
        let indexID = driver.lowerExpr(
            indices[0],
            shared: shared,
            emit: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            shared: shared,
            emit: &instructions
        )
        // Step 1: get current value
        let getResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get"),
            arguments: [receiverID, indexID],
            result: getResult,
            canThrow: false,
            thrownResult: nil
        ))
        // Step 2: apply binary op
        let opResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
        guard let expr = ast.arena.expr(exprID),
              case .indexedCompoundAssign(let op, _, _, _, _) = expr else {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // Determine the runtime op stub.
        // Use kk_string_concat for String += String (matching lowerBinaryExpr pattern),
        // otherwise use the appropriate numeric op stub.
        // Note: exprID's bound type is always unitType for compound assign, so we
        // derive the element type from the receiver's array type instead.
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        // Derive element type from the receiver's array type.
        // Mirrors TypeCheckHelpers.arrayElementType logic but also checks
        // the value expression type as a heuristic for non-IntArray receivers.
        let receiverBoundType = sema.bindings.exprTypes[receiverExpr]
        let isStringElement: Bool = {
            guard let recvType = receiverBoundType,
                  case .classType(let classType) = sema.types.kind(of: recvType) else {
                return false
            }
            // Prefer the explicit element type from type arguments, if present.
            if let firstArg = classType.args.first {
                let elementType: TypeID?
                switch firstArg {
                case .invariant(let t), .out(let t), .in(let t): elementType = t
                case .star: elementType = nil
                }
                if let elementType {
                    return elementType == stringType
                }
            }
            // Fallback: support legacy non-generic StringArray by name only.
            if let symbol = sema.symbols.symbol(classType.classSymbol) {
                let name = interner.resolve(symbol.name)
                return name == "StringArray"
            }
            return false
        }()
        let opName: String
        if op == .plusAssign, isStringElement {
            opName = "kk_string_concat"
        } else {
            switch op {
            case .plusAssign: opName = "kk_op_add"
            case .minusAssign: opName = "kk_op_sub"
            case .timesAssign: opName = "kk_op_mul"
            case .divAssign: opName = "kk_op_div"
            case .modAssign: opName = "kk_op_mod"
            }
        }
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(opName),
            arguments: [getResult, valueID],
            result: opResult,
            canThrow: false,
            thrownResult: nil
        ))
        // Step 3: set new value
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [receiverID, indexID, opResult],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }
}
