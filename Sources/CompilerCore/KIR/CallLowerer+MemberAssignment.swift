
/// Lowering for member assignment expressions.
extension CallLowerer {
    // MARK: - Member Assignment

    func lowerMemberAssignExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        // Synthetic properties whose getter external link ends in `_load`
        // (e.g. AtomicBoolean.value → __kk_atomic_bool_load) must route their
        // setter to the matching `_store` runtime function rather than a
        // direct field-offset write, which would corrupt the underlying
        // runtime-managed box.
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           let info = sema.symbols.symbol(propertySymbol),
           info.flags.contains(.synthetic),
           let getterLink = sema.symbols.externalLinkName(for: propertySymbol),
           getterLink.hasSuffix("_load")
        {
            let storeLinkName = String(getterLink.dropLast("_load".count)) + "_store"
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(storeLinkName),
                arguments: [receiverID, valueID],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // Custom setters and delegated properties must run before direct
        // storage paths so their bodies (or the delegate's `setValue`) observe
        // explicit-receiver assignments as Kotlin does.
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .class || ownerInfo.kind == .interface
           || ownerInfo.kind == .object,
           memberPropertyUsesSetterAccessor(propertySymbol, ast: ast, sema: sema)
        {
            // BUG-227: an open/abstract/override property with a custom
            // setter whose owner has known subtypes must dispatch through the
            // setter's vtable slot, exactly like the getter side — a direct
            // call always runs *this* declaration's own setter body,
            // regardless of the receiver's actual runtime type.
            if let (accessorSymbol, dispatch) = tryResolvePropertyAccessorVirtualDispatch(
                propertySymbol: propertySymbol,
                receiverExpr: receiverExpr,
                accessorKind: .setter,
                ast: ast,
                sema: sema
            ) {
                let result = arena.appendTemporary(type: sema.types.unitType)
                instructions.append(.virtualCall(
                    symbol: accessorSymbol,
                    callee: interner.intern("set"),
                    receiver: receiverID,
                    arguments: [valueID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: dispatch
                ))
                let unit = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
            let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
            let result = arena.appendTemporary(type: sema.types.unitType)
            instructions.append(.call(
                symbol: setterSymbol,
                callee: interner.intern("set"),
                arguments: [receiverID, valueID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        // `object` member properties are stored as flat global slots keyed by
        // the property's own symbol — the same storage `tryLowerObjectMemberPropertyRead`
        // reads via `loadGlobal` and bare-name assignment inside the object body
        // writes via `copy`-to-`symbolRef`. The heap object some objects allocate
        // via `kk_object_new` (for interface/vtable dispatch) never holds the
        // object's own stored properties, so it must not be treated as
        // field-offset storage here.
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .object
        {
            let propType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
            let globalRef = arena.appendExpr(.symbolRef(propertySymbol), type: propType)
            instructions.append(.constValue(result: globalRef, value: .symbolRef(propertySymbol)))
            instructions.append(.copy(from: valueID, to: globalRef))
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit
        }
        if let propertySymbol = sema.bindings.identifierSymbol(for: exprID),
           let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .class || ownerInfo.kind == .interface
        {
            // BUG-227: a stored open/abstract/override property whose owner
            // has known subtypes must dispatch through its setter's vtable
            // slot — the field offset below is only this declaration's own
            // storage, which is correct only when no runtime-type override
            // can be in play.
            if let (accessorSymbol, dispatch) = tryResolvePropertyAccessorVirtualDispatch(
                propertySymbol: propertySymbol,
                receiverExpr: receiverExpr,
                accessorKind: .setter,
                ast: ast,
                sema: sema
            ) {
                let result = arena.appendTemporary(type: sema.types.unitType)
                instructions.append(.virtualCall(
                    symbol: accessorSymbol,
                    callee: interner.intern("set"),
                    receiver: receiverID,
                    arguments: [valueID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: dispatch
                ))
                let unit = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
            if let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            ] {
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [receiverID, offsetExpr, valueID],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
                let unit = arena.appendExpr(.unit, type: sema.types.unitType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
        }
        // Use the call binding from sema if available (property setter).
        let callBinding = sema.bindings.callBindings[exprID]
        let chosenCallee = callBinding?.chosenCallee
        let setterName = loweredMemberCalleeName(
            chosenCallee: chosenCallee,
            fallback: calleeName,
            receiverExpr: receiverExpr,
            argumentCount: 2, // receiver + value
            sema: sema,
            interner: interner
        )
        let result = arena.appendTemporary(type: sema.types.unitType)
        instructions.append(.call(
            symbol: chosenCallee,
            callee: setterName,
            arguments: [receiverID, valueID],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    // MARK: - Member Compound Assignment

    /// Lowers `receiver.field op= value` (and the desugared form of
    /// `receiver.field++` / `receiver.field--`) as load -> compute -> store,
    /// evaluating `receiver` exactly once. The load and store sides mirror
    /// `lowerMemberAssignExpr`'s safe, well-defined storage strategies —
    /// a synthetic runtime accessor (`_load`/`_store` link-name pair), an
    /// `object` member's global slot, or a direct field offset on a
    /// class/interface instance — falling back to a best-effort setter/getter
    /// name for anything else, the same fallback (and the same pre-existing
    /// limitations for custom accessors reached through an explicit
    /// receiver) that plain member assignment already relies on.
    func lowerMemberCompoundAssignExpr(
        _ exprID: ExprID,
        op: CompoundAssignOp,
        receiverExpr: ExprID,
        calleeName: InternedString,
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let receiverID = driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let valueID = driver.lowerExpr(
            valueExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let propertySymbol = sema.bindings.identifierSymbol(for: exprID)
        let propType = propertySymbol.flatMap { sema.symbols.propertyType(for: $0) }
            ?? sema.bindings.exprTypes[exprID]
            ?? sema.types.anyType

        // Synthetic runtime accessor (e.g. AtomicBoolean.value -> __kk_atomic_bool_load/_store).
        let syntheticLinks: (load: String, store: String)? = {
            guard let propertySymbol,
                  let info = sema.symbols.symbol(propertySymbol),
                  info.flags.contains(.synthetic),
                  let getterLink = sema.symbols.externalLinkName(for: propertySymbol),
                  getterLink.hasSuffix("_load")
            else {
                return nil
            }
            return (getterLink, String(getterLink.dropLast("_load".count)) + "_store")
        }()

        // `object` member properties are stored as flat global slots keyed by
        // the property's own symbol (see `lowerMemberAssignExpr` for the full
        // rationale), not as per-instance field-offset storage.
        let isObjectOwned: Bool = {
            guard syntheticLinks == nil,
                  let propertySymbol,
                  let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
                  let ownerInfo = sema.symbols.symbol(ownerSymbol)
            else {
                return false
            }
            return ownerInfo.kind == .object
        }()

        // Properties whose reads and writes go through accessors (custom
        // get/set bodies, delegated properties) have no usable backing storage
        // for a load/compute/store round trip.
        let usesAccessors: Bool = {
            guard let propertySymbol else { return false }
            return memberPropertyUsesAccessor(propertySymbol, ast: ast, sema: sema)
                || memberPropertyUsesSetterAccessor(propertySymbol, ast: ast, sema: sema)
        }()

        // Direct field-offset storage for ordinary stored properties on
        // class/interface instances.
        let fieldOffset: Int? = {
            guard syntheticLinks == nil,
                  !isObjectOwned,
                  !usesAccessors,
                  let propertySymbol,
                  let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol),
                  let ownerInfo = sema.symbols.symbol(ownerSymbol),
                  ownerInfo.kind == .class || ownerInfo.kind == .interface
            else {
                return nil
            }
            return sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[
                sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
            ]
        }()

        // BUG-227: an open/abstract/override property whose owner has known
        // subtypes must dispatch both the read and the write half of this
        // compound assignment through the getter/setter's vtable slot —
        // mirroring `lowerMemberAssignExpr`'s identical treatment of a plain
        // (`=`) assignment. Resolved once up front since both the load and
        // store sections below need it.
        let virtualGetterDispatch = propertySymbol.flatMap { propertySymbol in
            tryResolvePropertyAccessorVirtualDispatch(
                propertySymbol: propertySymbol,
                receiverExpr: receiverExpr,
                accessorKind: .getter,
                ast: ast,
                sema: sema
            )
        }
        let virtualSetterDispatch = propertySymbol.flatMap { propertySymbol in
            tryResolvePropertyAccessorVirtualDispatch(
                propertySymbol: propertySymbol,
                receiverExpr: receiverExpr,
                accessorKind: .setter,
                ast: ast,
                sema: sema
            )
        }

        // ── Load ─────────────────────────────────────────────────────────
        let currentValue: KIRExprID
        if let syntheticLinks {
            let result = arena.appendTemporary(type: propType)
            emitNonThrowingCall(
                callee: interner.intern(syntheticLinks.load),
                arg: receiverID,
                result: result,
                into: &instructions
            )
            currentValue = result
        } else if isObjectOwned, let propertySymbol {
            let result = arena.appendExpr(.symbolRef(propertySymbol), type: propType)
            instructions.append(.loadGlobal(result: result, symbol: propertySymbol))
            currentValue = wrapLateinitReadIfNeeded(
                result, symbol: propertySymbol, sema: sema, arena: arena, interner: interner,
                instructions: &instructions
            )
        } else if let virtualGetterDispatch {
            let result = arena.appendTemporary(type: propType)
            instructions.append(.virtualCall(
                symbol: virtualGetterDispatch.accessorSymbol,
                callee: interner.intern("get"),
                receiver: receiverID,
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil,
                dispatch: virtualGetterDispatch.dispatch
            ))
            currentValue = result
        } else if usesAccessors, let propertySymbol {
            let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
            let result = arena.appendTemporary(type: propType)
            instructions.append(.call(
                symbol: getterSymbol,
                callee: interner.intern("get"),
                arguments: [receiverID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            currentValue = result
        } else if let fieldOffset {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let result = arena.appendTemporary(type: propType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverID, offsetExpr],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            currentValue = propertySymbol.map {
                wrapLateinitReadIfNeeded(
                    result, symbol: $0, sema: sema, arena: arena, interner: interner,
                    instructions: &instructions
                )
            } ?? result
        } else {
            let getterName = loweredMemberCalleeName(
                chosenCallee: nil,
                fallback: calleeName,
                receiverExpr: receiverExpr,
                argumentCount: 1,
                sema: sema,
                interner: interner
            )
            let result = arena.appendTemporary(type: propType)
            emitNonThrowingCall(
                callee: getterName,
                arg: receiverID,
                result: result,
                into: &instructions
            )
            currentValue = result
        }

        // ── Compute ──────────────────────────────────────────────────────
        // `newValue == nil` means a Unit-returning `plusAssign`-style operator
        // already mutated the loaded value in place, so no store is needed —
        // mirrors bare-name compound assign's handling in ExprLowerer.
        let newValue: KIRExprID? = {
            if let callBinding = sema.bindings.callBindings[exprID],
               let signature = sema.symbols.functionSignature(for: callBinding.chosenCallee),
               signature.receiverType != nil
            {
                let normalized = driver.callSupportLowerer.normalizedCallArguments(
                    providedArguments: [valueID],
                    callBinding: callBinding,
                    chosenCallee: callBinding.chosenCallee,
                    spreadFlags: [false],
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                var finalArguments = normalized.arguments
                finalArguments.insert(currentValue, at: 0)
                let returnType = signature.returnType
                let callResult = arena.appendTemporary(type: returnType)
                let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: callBinding.chosenCallee),
                                                            !externalLinkName.isEmpty
                {
                    interner.intern(externalLinkName)
                } else {
                    sema.symbols.symbol(callBinding.chosenCallee)?.name ?? interner.intern(op.kotlinFunctionName)
                }
                instructions.append(.call(
                    symbol: callBinding.chosenCallee,
                    callee: loweredCalleeName,
                    arguments: finalArguments,
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                return returnType == sema.types.unitType ? nil : callResult
            }

            // Builtin path: Int/Long/Double/... arithmetic or String
            // concatenation, matching bare-name compound assign's fallback.
            let kirOp: KIRBinaryOp = switch op {
            case .plusAssign: .add
            case .minusAssign: .subtract
            case .timesAssign: .multiply
            case .divAssign: .divide
            case .modAssign: .modulo
            }
            let stringType = sema.types.stringType
            let nullableStringType = sema.types.makeNullable(stringType)
            let valueType = arena.exprType(valueID)
            let isStringCompound = op == .plusAssign
                && (propType == stringType || propType == nullableStringType
                    || valueType == stringType || valueType == nullableStringType)
            if !isStringCompound {
                let result = arena.appendTemporary(type: propType)
                instructions.append(.binary(op: kirOp, lhs: currentValue, rhs: valueID, result: result))
                return result
            }
            // Kotlin's `String += Any?` calls toString() on a non-String operand
            // (Kotlin's String.plus(other: Any?)); a non-String currentValue/valueID
            // must be converted the same way `+`/string-template concatenation does
            // (CallLowerer.emitAnyToStringWithNullGuard) before reaching
            // kk_string_concat_flat, which assumes both arguments are already
            // flat String aggregates -- feeding it a raw boxed value (e.g. a class
            // instance, or an unboxed Int/Boolean) reads it as one, silently
            // dropping/mis-rendering the value or crashing.
            let effectiveCurrent: KIRExprID = if propType == stringType || propType == nullableStringType {
                currentValue
            } else {
                emitAnyToStringWithNullGuard(
                    valueID: currentValue,
                    valueType: propType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            let effectiveValue: KIRExprID = if valueType == stringType || valueType == nullableStringType {
                valueID
            } else {
                emitAnyToStringWithNullGuard(
                    valueID: valueID,
                    valueType: valueType ?? sema.types.anyType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            let result = arena.appendTemporary(type: stringType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_string_concat_flat"),
                arguments: [effectiveCurrent, effectiveValue],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }()

        // ── Store ────────────────────────────────────────────────────────
        if let newValue {
            if let syntheticLinks {
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern(syntheticLinks.store),
                    arguments: [receiverID, newValue],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if isObjectOwned, let propertySymbol {
                let globalRef = arena.appendExpr(.symbolRef(propertySymbol), type: propType)
                instructions.append(.constValue(result: globalRef, value: .symbolRef(propertySymbol)))
                instructions.append(.copy(from: newValue, to: globalRef))
            } else if let virtualSetterDispatch {
                let setterResult = arena.appendTemporary(type: sema.types.unitType)
                instructions.append(.virtualCall(
                    symbol: virtualSetterDispatch.accessorSymbol,
                    callee: interner.intern("set"),
                    receiver: receiverID,
                    arguments: [newValue],
                    result: setterResult,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: virtualSetterDispatch.dispatch
                ))
            } else if usesAccessors, let propertySymbol {
                let setterSymbol = sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                    ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
                let setterResult = arena.appendTemporary(type: sema.types.unitType)
                instructions.append(.call(
                    symbol: setterSymbol,
                    callee: interner.intern("set"),
                    arguments: [receiverID, newValue],
                    result: setterResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if let fieldOffset {
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
                instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [receiverID, offsetExpr, newValue],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                let setterName = loweredMemberCalleeName(
                    chosenCallee: nil,
                    fallback: calleeName,
                    receiverExpr: receiverExpr,
                    argumentCount: 2,
                    sema: sema,
                    interner: interner
                )
                let setterResult = arena.appendTemporary(type: sema.types.unitType)
                instructions.append(.call(
                    symbol: nil,
                    callee: setterName,
                    arguments: [receiverID, newValue],
                    result: setterResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
        }

        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    /// Mirrors `memberPropertyUsesAccessor` (the read-side/getter check in
    /// `CallLowerer+MemberPropertyReads.swift`) but for the setter half: true
    /// when the property has a real, user-written `set(...) { ... }` body, in
    /// which case assignment must dispatch to the setter accessor instead of
    /// writing storage directly.
    func memberPropertyUsesSetterAccessor(
        _ propertySymbol: SymbolID,
        ast: ASTModule,
        sema: SemaModule
    ) -> Bool {
        for rawDecl in ast.arena.decls.indices {
            let declID = DeclID(rawValue: Int32(rawDecl))
            guard sema.bindings.declSymbols[declID] == propertySymbol,
                  let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl
            else {
                continue
            }
            if let setter = propertyDecl.setter {
                return setter.body != .unit
            }
            return propertyDecl.delegateExpression != nil
        }
        return false
    }
}
