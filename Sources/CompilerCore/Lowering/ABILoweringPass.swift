
final class ABILoweringPass: LoweringPass, ParallelLoweringPass {
    static let name = "ABILowering"

    static func primitiveBoxingCallee(for primitive: PrimitiveType, interner: StringInterner) -> InternedString {
        guard let callee = BoxingCalleeTable(interner: interner).boxCallee(for: primitive) else {
            preconditionFailure("No boxing callee registered for \(primitive)")
        }
        return callee
    }

    static func primitiveUnboxingCallee(for primitive: PrimitiveType, interner: StringInterner) -> InternedString {
        guard let callee = BoxingCalleeTable(interner: interner).unboxCallee(for: primitive) else {
            preconditionFailure("No unboxing callee registered for \(primitive)")
        }
        return callee
    }

    static func primitiveUnboxingCallee(for kind: TypeKind, interner: StringInterner) -> InternedString? {
        BoxingCalleeTable(interner: interner).unboxCallee(for: kind, requireNonNull: false)
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        let nonThrowingCalleeSet = nonThrowingCallees(interner: ctx.interner)
        let boxingCalleeTable = BoxingCalleeTable(interner: ctx.interner)

        let types = ctx.sema?.types
        let symbols = ctx.sema?.symbols

        let inlineArithmeticCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_add"),
            ctx.interner.intern("kk_op_sub"),
            ctx.interner.intern("kk_op_mul"),
            ctx.interner.intern("kk_op_div"),
            ctx.interner.intern("kk_op_floor_div"),
            ctx.interner.intern("kk_op_lfloor_div"),
            ctx.interner.intern("kk_op_mod"),
            ctx.interner.intern("kk_op_floor_mod"),
            ctx.interner.intern("kk_op_lfloor_mod"),
            ctx.interner.intern("kk_op_ffloor_mod"),
            ctx.interner.intern("kk_op_dfloor_mod"),
            ctx.interner.intern("kk_op_udiv"),
            ctx.interner.intern("kk_op_urem"),
            ctx.interner.intern("kk_op_uadd"),
            ctx.interner.intern("kk_op_usub"),
            ctx.interner.intern("kk_op_umul"),
        ]
        // Comparison operators: result type is Boolean so we cannot use the
        // result to drive unboxing.  Instead unboxOperandToOwnType uses each
        // operand's own declared primitive type as the target, with a hint
        // from a sibling operand when one side has no direct type info.
        // Idempotent for already-unboxed values (kk_unbox_* passes raw
        // primitives through unchanged).
        let inlineComparisonCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_eq"),
            ctx.interner.intern("kk_op_ne"),
            ctx.interner.intern("kk_op_lt"),
            ctx.interner.intern("kk_op_le"),
            ctx.interner.intern("kk_op_gt"),
            ctx.interner.intern("kk_op_ge"),
            ctx.interner.intern("kk_op_ult"),
            ctx.interner.intern("kk_op_ule"),
            ctx.interner.intern("kk_op_ugt"),
            ctx.interner.intern("kk_op_uge"),
            ctx.interner.intern("kk_op_deq"),
            ctx.interner.intern("kk_op_dne"),
            ctx.interner.intern("kk_op_dlt"),
            ctx.interner.intern("kk_op_dle"),
            ctx.interner.intern("kk_op_dgt"),
            ctx.interner.intern("kk_op_dge"),
            ctx.interner.intern("kk_op_feq"),
            ctx.interner.intern("kk_op_fne"),
            ctx.interner.intern("kk_op_flt"),
            ctx.interner.intern("kk_op_fle"),
            ctx.interner.intern("kk_op_fgt"),
            ctx.interner.intern("kk_op_fge"),
        ]

        // Type-check intrinsics: `value` is a bare Int that the runtime can only
        // tell apart as Int/UInt/ULong/Long/Double/Float/Char by inspecting a
        // boxed pointer's Swift type — unlike Boolean/Unit, none of these share a
        // sound unboxed-value heuristic (they all reinterpret the same 64-bit
        // word). Box `value` whenever its intrinsic type is a concrete primitive,
        // even if the checked expression's own declared type is already a
        // concrete primitive (e.g. `x is Long` where `x: Int`): KIR local
        // declarations alias a variable directly to its initializer expression
        // (see ExprLowerer+ControlFlowAndBlocks.localDecl), so an unboxed literal
        // or primitive-typed value can flow into a type check unmodified.
        // These callees have no FunctionSignature, so the normal argument-boxing
        // path above leaves them untouched.
        let typeCheckValueCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_is"),
            ctx.interner.intern("kk_op_cast"),
            ctx.interner.intern("kk_op_safe_cast"),
        ]

        // Callees that retrieve an element from a generic collection. After
        // 75507ca0d, kk_mutable_list_add boxes primitives for type erasure, so
        // these accessors may return a boxed pointer even when the KIR result
        // type is a non-null primitive. Unbox at the retrieval site so that all
        // downstream uses of the element (arithmetic, comparisons, calls) see
        // the plain primitive value.
        let collectionElementAccessorCallees: Set<InternedString> = [
            ctx.interner.intern("kk_list_iterator_next"),
            ctx.interner.intern("kk_list_iterator_previous"),
        ]

        // `kk_array_get` reads an element out of both generic `Array<T>` (boxed
        // elements) and the primitive arrays (raw elements), so it needs the
        // same unboxing as the accessors above only for the generic receiver;
        // unboxing a raw `DoubleArray` element would corrupt values such as -0.0.
        let genericArrayGetCallee = ctx.interner.intern("kk_array_get")

        // `kk_array_is_empty` returns a boxed Boolean but is emitted for both
        // generic and primitive arrays without a Sema function signature. Keep
        // its result on the same ABI normalization path as other erased
        // collection results so conditions compare the unboxed Boolean.
        let boxedBooleanReturnCallees: Set<InternedString> = [
            ctx.interner.intern("kk_array_is_empty"),
        ]

        // __kk_op_rangeUntil backs the `until` infix function (registered in
        // HeaderHelpers+SyntheticRangeProgressionStubs.swift with a scalar
        // Int/Long return type, matching the isRangeExpr duck-typing convention
        // used for range operators) but always returns a boxed RuntimeRangeBox
        // reference at runtime (see __kk_op_rangeUntil in RuntimeRangeAndDispatch.swift).
        // Unlike `..`/`downTo`/`step`, calls to the named `until` function carry a
        // resolved Sema symbol, so resolveUnboxForCall would otherwise see a
        // Long/Int-typed return and insert an erroneous kk_unbox_long/kk_unbox_int
        // on the range object itself.
        let boxedReturnRangeCallees: Set<InternedString> = [
            ctx.interner.intern("__kk_op_rangeUntil"),
        ]

        var signatureByName: [InternedString: FunctionSignature] = [:]
        if let symbols {
            for decl in module.arena.declarations {
                guard case let .function(fn) = decl else { continue }
                if let sig = symbols.functionSignature(for: fn.symbol) {
                    signatureByName[fn.name] = sig
                }
            }
        }

        func transformFunction(_ function: KIRFunction) -> KIRFunction {
            var updated: KIRFunction = function
            var newBody: [KIRInstruction] = []
            newBody.reserveCapacity(function.body.count)

            let functionReturnKind: TypeKind? = types.map { $0.kind(of: function.returnType) }

            var idx = 0
            while idx < function.body.count {
                let instruction = function.body[idx]
                if case let .virtualCall(vcSymbol, vcCallee, vcReceiver, vcArguments, vcResult, _, vcThrownResult, vcDispatch) = instruction {
                    let vcIsClosureRelated = module.nonThrowingClosureCallees.contains(vcCallee)
                    let vcCanThrow = !vcIsClosureRelated
                        && !nonThrowingCalleeSet.contains(vcCallee)
                    var vcSignature: FunctionSignature?
                    if let symbols, let vcSymbol {
                        vcSignature = symbols.functionSignature(for: vcSymbol)
                    }
                    if vcSignature == nil {
                        vcSignature = signatureByName[vcCallee]
                    }
                    let vcBoxedArguments: [KIRExprID] = if let vcSignature, let types {
                        applyArgumentBoxing(
                            arguments: vcArguments,
                            signature: vcSignature,
                            receiverOffset: 0,
                            module: module,
                            types: types,
                            symbols: symbols,
                            boxingCalleeTable: boxingCalleeTable,
                            callee: vcCallee,
                            interner: ctx.interner,
                            newBody: &newBody
                        )
                    } else {
                        vcArguments
                    }
                    let vcUnbox = resolveUnboxForCall(
                        callSymbol: vcSymbol,
                        callee: vcCallee,
                        result: vcResult,
                        signatureByName: signatureByName,
                        module: module,
                        types: types,
                        symbols: symbols,
                        boxingCalleeTable: boxingCalleeTable,
                        boxedReturnCallees: boxedReturnRangeCallees
                    )
                    if let (vcUnboxCallee, vcReturnType) = vcUnbox, let vcResult {
                        let tempResult = module.arena.appendTemporary(type: vcReturnType
                        )
                        newBody.append(.virtualCall(
                            symbol: vcSymbol,
                            callee: vcCallee,
                            receiver: vcReceiver,
                            arguments: vcBoxedArguments,
                            result: tempResult,
                            canThrow: vcCanThrow,
                            thrownResult: vcThrownResult,
                            dispatch: vcDispatch
                        ))
                        if vcThrownResult != nil {
                            let nextIdx = idx + 1
                            if nextIdx < function.body.count,
                               case .jumpIfNotNull = function.body[nextIdx]
                            {
                                newBody.append(function.body[nextIdx])
                                idx += 1
                            }
                        }
                        emitNonThrowingCall(
                            callee: vcUnboxCallee,
                            arg: tempResult,
                            result: vcResult,
                            into: &newBody
                        )
                    } else {
                        newBody.append(.virtualCall(
                            symbol: vcSymbol,
                            callee: vcCallee,
                            receiver: vcReceiver,
                            arguments: vcBoxedArguments,
                            result: vcResult,
                            canThrow: vcCanThrow,
                            thrownResult: vcThrownResult,
                            dispatch: vcDispatch
                        ))
                    }
                    idx += 1
                    continue
                }

                // Handle returnValue: box primitive if function returns Any/Any?
                if case let .returnValue(value) = instruction, let types,
                   let rewritten = rewriteReturnValueBoxing(
                       value: value,
                       functionReturnKind: functionReturnKind,
                       returnType: function.returnType,
                       module: module, types: types, symbols: symbols,
                       interner: ctx.interner,
                       boxingCalleeTable: boxingCalleeTable
                   )
                {
                    newBody.append(contentsOf: rewritten)
                    idx += 1
                    continue
                }
                if case .returnValue = instruction {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                // Handle copy: insert boxing/unboxing at type boundaries
                if case let .copy(from, to) = instruction, let types,
                   let rewritten = rewriteCopyBoxingOrUnboxing(
                       from: from, to: to,
                       module: module, types: types, symbols: symbols,
                       interner: ctx.interner,
                       boxingCalleeTable: boxingCalleeTable
                   )
                {
                    newBody.append(contentsOf: rewritten)
                    idx += 1
                    continue
                }
                if case .copy = instruction {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                // Handle binary: unbox Any/reference-typed operands when the
                // result is a primitive (smart-cast after `is` check).
                if case let .binary(op, lhs, rhs, result) = instruction, let types {
                    let newLhs = unboxBinaryOperandIfNeeded(
                        operand: lhs, resultExpr: result,
                        module: module, types: types, symbols: symbols,
                        boxingCalleeTable: boxingCalleeTable, newBody: &newBody
                    )
                    let newRhs = unboxBinaryOperandIfNeeded(
                        operand: rhs, resultExpr: result,
                        module: module, types: types, symbols: symbols,
                        boxingCalleeTable: boxingCalleeTable, newBody: &newBody
                    )
                    newBody.append(.binary(op: op, lhs: newLhs, rhs: newRhs, result: result))
                    idx += 1
                    continue
                }

                guard case let .call(callSymbol, callee, arguments, result, _, thrownResult, isSuperCall, _) = instruction else {
                    newBody.append(instruction)
                    idx += 1
                    continue
                }

                // Most synthetic property accessors are field/property plumbing
                // and historically have no throwing ABI. Delegated properties
                // are different: their accessor invokes delegate getValue or
                // setValue, which can throw (e.g. Delegates.notNull()).
                let isSyntheticAccessor: Bool = {
                    guard let s = callSymbol else { return false }
                    return SyntheticSymbolScheme.isLikelySyntheticPropertyAccessor(s)
                }()
                let isDelegatedAccessor: Bool = {
                    guard isSyntheticAccessor,
                          let s = callSymbol,
                          let syms = symbols
                    else { return false }
                    let propertySymbol = SyntheticSymbolScheme.originalPropertySymbolFromAccessor(s)
                    return syms.delegateStorageSymbol(for: propertySymbol) != nil
                }()
                // ABI-001: For synthetic setter accessor calls whose callee is still
                // "set", derive the actual runtime store function name from the getter
                // link registered on the original property symbol (e.g.
                // __kk_atomic_bool_load → __kk_atomic_bool_store).
                let rewrittenCallee: InternedString? = {
                    guard isSyntheticAccessor,
                          let s = callSymbol,
                          SyntheticSymbolScheme.isLikelySyntheticSetterAccessor(s),
                          callee == ctx.interner.intern("set"),
                          let syms = symbols
                    else { return nil }
                    let propSym = SyntheticSymbolScheme.originalPropertySymbolFromSetterAccessor(s)
                    guard let getterLink = syms.externalLinkName(for: propSym),
                          getterLink.hasSuffix("_load")
                    else { return nil }
                    let storeLinkName = String(getterLink.dropLast("_load".count)) + "_store"
                    return ctx.interner.intern(storeLinkName)
                }()
                let effectiveCallee = rewrittenCallee ?? callee
                let effectiveCallSymbol: SymbolID? = rewrittenCallee != nil ? nil : callSymbol
                // Stubs explicitly marked .throwingFunction must always emit the
                // outThrown channel regardless of whether their callee name appears
                // in nonThrowingCallees.
                let isExplicitlyThrowing: Bool = {
                    guard let s = callSymbol, let sym = symbols?.symbol(s) else { return false }
                    return sym.flags.contains(.throwingFunction)
                }()
                // Closure-related callees (kk_closure_invoke_* wrappers and their
                // internal kk_lambda_* targets) are registered as non-throwing by
                // LambdaClosureConversionPass via module.nonThrowingClosureCallees.
                // This avoids brittle string-prefix coupling between passes.
                let isClosureRelatedCallee = module.nonThrowingClosureCallees.contains(effectiveCallee)
                let canThrow = isExplicitlyThrowing
                    || isDelegatedAccessor
                    || (!isSyntheticAccessor
                        && !isClosureRelatedCallee
                        && !nonThrowingCalleeSet.contains(effectiveCallee))

                var signature: FunctionSignature?
                if let symbols, let effectiveCallSymbol {
                    signature = symbols.functionSignature(for: effectiveCallSymbol)
                }
                if signature == nil {
                    signature = signatureByName[effectiveCallee]
                }
                var boxedArguments: [KIRExprID]
                if let signature, let types {
                    // A constructor bridged to an allocating runtime entry
                    // (`Pair`'s `__kk_pair_new`) is called without the allocated-object
                    // argument that an ordinary `<init>` receives, so its value
                    // arguments start at index 0. Using the signature's receiver
                    // unconditionally would shift every parameter by one and box each
                    // argument against its neighbour's declared type.
                    let receiverOffset: Int = {
                        guard signature.receiverType != nil else { return 0 }
                        if symbols?.symbol(effectiveCallSymbol ?? .invalid)?.kind == .constructor,
                           arguments.count == signature.parameterTypes.count
                        {
                            return 0
                        }
                        return 1
                    }()
                    boxedArguments = applyArgumentBoxing(
                        arguments: arguments,
                        signature: signature,
                        receiverOffset: receiverOffset,
                        module: module,
                        types: types,
                        symbols: symbols,
                        boxingCalleeTable: boxingCalleeTable,
                        callee: effectiveCallee,
                        interner: ctx.interner,
                        boxTypeParamArguments: isKotlinSourceCallee(effectiveCallSymbol, symbols: symbols),
                        newBody: &newBody
                    )
                } else {
                    boxedArguments = arguments
                }

                // `generateSequence` reaches this private runtime bridge after
                // its generic source wrapper is expanded. The bridge stores the
                // seed in an erased sequence element slot, so a raw primitive or
                // enum ordinal must be boxed here; otherwise enum ordinal zero
                // loses its entry name and prints as `0`.
                let generateSequenceBridgeLink = effectiveCallSymbol.flatMap { symbol in
                    symbols?.externalLinkName(for: symbol)
                }
                if (effectiveCallee == ctx.interner.intern("__kk_sequence_generate")
                    || generateSequenceBridgeLink == "__kk_sequence_generate"),
                   let types,
                   let seed = boxedArguments.first,
                   let seedType = intrinsicArgType(seed, arena: module.arena, types: types)
                {
                    boxedArguments[0] = boxValueForAnySlot(
                        seed,
                        sourceType: seedType,
                        types: types,
                        symbols: symbols,
                        interner: ctx.interner,
                        arena: module.arena,
                        into: &newBody
                    )
                }

                // Unbox Any/reference-typed arguments for inline arithmetic
                // calls (kk_op_add, etc.) when the result is a primitive.
                // These calls have no FunctionSignature so the normal
                // argument-boxing path above leaves them untouched.
                if signature == nil, let types, let result,
                   inlineArithmeticCallees.contains(effectiveCallee)
                {
                    for i in boxedArguments.indices {
                        boxedArguments[i] = unboxBinaryOperandIfNeeded(
                            operand: boxedArguments[i], resultExpr: result,
                            module: module, types: types, symbols: symbols,
                            boxingCalleeTable: boxingCalleeTable, newBody: &newBody
                        )
                    }
                }
                // Unbox operands for comparison operators (==, !=, <, etc.).
                // The result is Boolean so the arithmetic path above cannot
                // determine the operand's primitive type from the result; use
                // each operand's own declared type instead.
                // When one operand has no type info (e.g. the result of x+0 whose
                // Sema type was not recorded), collect a hint from a sibling operand
                // that does have type info and forward it so the unboxing can still
                // emit the correct kk_unbox_* call.
                if signature == nil, let types,
                   inlineComparisonCallees.contains(effectiveCallee)
                {
                    var primitiveHint: TypeKind?
                    for operand in boxedArguments {
                        if let opType = intrinsicArgType(operand, arena: module.arena, types: types) {
                            let opKind = resolveValueClassKind(types.kind(of: opType), types: types, symbols: symbols)
                            if case .primitive(_, .nonNull) = opKind {
                                primitiveHint = opKind
                                break
                            }
                        }
                    }
                    for i in boxedArguments.indices {
                        boxedArguments[i] = unboxOperandToOwnType(
                            boxedArguments[i],
                            hint: primitiveHint,
                            module: module, types: types, symbols: symbols,
                            boxingCalleeTable: boxingCalleeTable, newBody: &newBody
                        )
                    }
                }
                // Box the "value" operand of kk_op_is/kk_op_cast/kk_op_safe_cast
                // whenever it is a concrete primitive or a non-null enum. See
                // typeCheckValueCallees above. Enum values resolve to Int for their
                // unboxed representation, but must retain their nominal class ID when
                // boxed so nominal and interface checks can recognize them.
                if signature == nil, let types,
                   typeCheckValueCallees.contains(effectiveCallee),
                   let firstArg = boxedArguments.first
                {
                    let argType = intrinsicArgType(firstArg, arena: module.arena, types: types)
                    let rawArgKind = argType.map { types.kind(of: $0) }
                    let argKind = rawArgKind.map {
                        resolveValueClassKind($0, types: types, symbols: symbols)
                    }
                    if let argKind,
                       let boxCallee = boxCalleeForPrimitive(argKind, boxingCalleeTable: boxingCalleeTable)
                    {
                        let boxedResult = module.arena.appendTemporary(type: types.anyType)
                        emitBoxCallWithValueClassTag(
                            boxCallee: boxCallee,
                            value: firstArg,
                            rawSourceKind: rawArgKind ?? argKind,
                            result: boxedResult,
                            resultType: types.anyType,
                            types: types,
                            symbols: symbols,
                            interner: ctx.interner,
                            arena: module.arena,
                            into: &newBody
                        )
                        boxedArguments[0] = boxedResult
                    }
                }

                let resolvedUnbox = resolveUnboxForCall(
                    callSymbol: effectiveCallSymbol,
                    callee: effectiveCallee,
                    result: result,
                    signatureByName: signatureByName,
                    module: module,
                    types: types,
                    symbols: symbols,
                    boxingCalleeTable: boxingCalleeTable,
                    boxedReturnCallees: boxedReturnRangeCallees
                )

                // Fallback: collection element accessors may return a boxed primitive.
                // resolveUnboxForCall cannot handle these because they have no
                // FunctionSignature entry. Unbox using the KIR result type as the target.
                var effectiveUnbox: (InternedString, TypeID)? = resolvedUnbox
                let needsErasedResultUnbox =
                    collectionElementAccessorCallees.contains(effectiveCallee)
                    || (effectiveCallee == genericArrayGetCallee
                        && isGenericArrayReceiver(
                            boxedArguments.first,
                            module: module,
                            types: types,
                            symbols: symbols,
                            interner: ctx.interner
                        ))
                    || boxedBooleanReturnCallees.contains(effectiveCallee)
                if effectiveUnbox == nil,
                   needsErasedResultUnbox,
                   let result, let types,
                   let resultType = module.arena.exprType(result)
                {
                    let resultKind = resolveValueClassKind(
                        types.kind(of: resultType), types: types, symbols: symbols
                    )
                    // Strings stored in generic arrays/collections are represented as
                    // raw object handles at runtime; the backend already bridges that
                    // raw handle to a flat string aggregate when the result type is
                    // String. Inserting an explicit kk_string_to_flat here would
                    // unbox a flat aggregate as if it were a raw handle, causing a
                    // double conversion crash.
                    if case .stringStruct = resultKind {
                        // Leave string unboxing to the backend bridge.
                    } else if let unboxCallee = unboxingCallee(
                        sourceKind: TypeKind.any(.nullable), targetKind: resultKind,
                        boxingCalleeTable: boxingCalleeTable, types: types, symbols: symbols
                    ) {
                        effectiveUnbox = (unboxCallee, resultType)
                    }
                }

                if let (resolvedUnboxCallee, resolvedReturnType) = effectiveUnbox, let result {
                    let tempResult = module.arena.appendTemporary(type: resolvedReturnType
                    )
                    newBody.append(.call(
                        symbol: effectiveCallSymbol,
                        callee: effectiveCallee,
                        arguments: boxedArguments,
                        result: tempResult,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    ))
                    if thrownResult != nil {
                        let nextIdx = idx + 1
                        if nextIdx < function.body.count,
                           case .jumpIfNotNull = function.body[nextIdx]
                        {
                            newBody.append(function.body[nextIdx])
                            idx += 1
                        }
                    }
                    emitNonThrowingCall(
                        callee: resolvedUnboxCallee,
                        arg: tempResult,
                        result: result,
                        into: &newBody
                    )
                } else {
                    newBody.append(.call(
                        symbol: effectiveCallSymbol,
                        callee: effectiveCallee,
                        arguments: boxedArguments,
                        result: result,
                        canThrow: canThrow,
                        thrownResult: thrownResult,
                        isSuperCall: isSuperCall
                    ))
                }
                idx += 1
            }

            updated.replaceBody(newBody)
            return updated
        }
        module.arena.transformFunctions(transformFunction)
        module.recordLowering(Self.name)
    }

    private func rewriteReturnValueBoxing(
        value: KIRExprID,
        functionReturnKind: TypeKind?,
        returnType: TypeID,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        interner: StringInterner,
        boxingCalleeTable: BoxingCalleeTable
    ) -> [KIRInstruction]? {
        guard let functionReturnKind,
              isAnyOrNullableAny(functionReturnKind) || isNonValueClassReference(functionReturnKind, symbols: symbols),
              let valueType = intrinsicArgType(value, arena: module.arena, types: types)
        else {
            return nil
        }
        let rawValueKind = types.kind(of: valueType)
        let resolvedValueKind = resolveValueClassKind(rawValueKind, types: types, symbols: symbols)
        guard let boxCallee = boxCalleeForPrimitive(
            resolvedValueKind,
            boxingCalleeTable: boxingCalleeTable
        ) else {
            return nil
        }
        var instructions: [KIRInstruction] = []
        let boxedResult = module.arena.appendTemporary(type: returnType)
        emitBoxCallWithValueClassTag(
            boxCallee: boxCallee,
            value: value,
            rawSourceKind: rawValueKind,
            result: boxedResult,
            resultType: returnType,
            types: types,
            symbols: symbols,
            interner: interner,
            arena: module.arena,
            into: &instructions
        )
        instructions.append(.returnValue(boxedResult))
        return instructions
    }

    private func rewriteCopyBoxingOrUnboxing(
        from: KIRExprID, to: KIRExprID,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        interner: StringInterner,
        boxingCalleeTable: BoxingCalleeTable
    ) -> [KIRInstruction]? {
        guard let fromType = intrinsicArgType(from, arena: module.arena, types: types),
              let toType = module.arena.exprType(to)
        else {
            return nil
        }
        let rawFromKind = types.kind(of: fromType)
        let fromKind = resolveValueClassKind(rawFromKind, types: types, symbols: symbols)
        let rawToKind = types.kind(of: toType)
        let toKind = resolveValueClassKind(rawToKind, types: types, symbols: symbols)
        // A non-null enum local is stored as its raw ordinal. Keep copies between
        // values of the same enum class verbatim; otherwise resolving both sides
        // to Int below would add an unnecessary kk_unbox_int and corrupt the
        // ordinal before a later .name/.ordinal read.
        let isDirectNonNullEnumCopy: Bool = {
            guard case let .classType(sourceClass) = rawFromKind,
                  case let .classType(targetClass) = rawToKind,
                  sourceClass.nullability == .nonNull,
                  targetClass.nullability == .nonNull,
                  sourceClass.classSymbol == targetClass.classSymbol,
                  let symbols,
                  let sym = symbols.symbol(targetClass.classSymbol)
            else {
                return false
            }
            return sym.kind == .enumClass
        }()
        if !isDirectNonNullEnumCopy,
           isAnyOrNullableAny(toKind) || needsBoxingForCopy(sourceKind: fromKind, targetKind: toKind)
            || isNonValueClassReference(rawToKind, symbols: symbols),
            let boxCallee = boxCalleeForPrimitive(
                fromKind,
                boxingCalleeTable: boxingCalleeTable
            )
        {
            var instructions: [KIRInstruction] = []
            emitBoxCallWithValueClassTag(
                boxCallee: boxCallee,
                value: from,
                rawSourceKind: rawFromKind,
                result: to,
                resultType: toType,
                types: types,
                symbols: symbols,
                interner: interner,
                arena: module.arena,
                into: &instructions
            )
            return instructions
        }
        if !isDirectNonNullEnumCopy,
           needsUnboxing(sourceKind: fromKind, targetKind: toKind, symbols: symbols),
           let unboxCallee = unboxingCallee(
               sourceKind: fromKind, targetKind: toKind,
               boxingCalleeTable: boxingCalleeTable,
               types: types, symbols: symbols
           )
        {
            return [.call(symbol: nil, callee: unboxCallee, arguments: [from],
                         result: to, canThrow: false, thrownResult: nil)]
        }
        return nil
    }
}
