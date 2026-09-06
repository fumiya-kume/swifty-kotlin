extension CallLowerer {
    func tryLowerCollectionFactoryCall(
        sourceCalleeName: InternedString,
        args: [CallArgument],
        loweredArgIDs: [KIRExprID],
        chosenCallee: SymbolID?,
        boundType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let name = interner.resolve(sourceCalleeName)
        guard isStdlibCollectionFactoryTarget(
            name: name,
            chosenCallee: chosenCallee,
            sema: sema,
            interner: interner
        ) else {
            return nil
        }

        let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
        switch name {
        case "emptyList", "listOf":
            if loweredArgIDs.isEmpty {
                emitNoArgCall("__kk_emptyList", result: result, interner: interner, instructions: &instructions)
                return result
            }
            let packed = emitPackedCollectionFactoryArguments(
                args: args,
                loweredArgIDs: loweredArgIDs,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            emitRuntimeCollectionFactory(
                "__kk_list_of",
                array: packed.array,
                count: packed.count,
                result: result,
                interner: interner,
                instructions: &instructions
            )
            return result

        case "mutableListOf", "arrayListOf":
            if loweredArgIDs.isEmpty {
                emitNullArrayCountCall(
                    "__kk_list_of",
                    arity: 1,
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                return result
            }
            let packed = emitPackedCollectionFactoryArguments(
                args: args,
                loweredArgIDs: loweredArgIDs,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            emitRuntimeCollectionFactory(
                "__kk_list_of",
                array: packed.array,
                count: packed.count,
                result: result,
                interner: interner,
                instructions: &instructions
            )
            return result

        case "emptySet", "setOf", "setOfNotNull":
            if loweredArgIDs.isEmpty {
                emitNoArgCall("__kk_emptySet", result: result, interner: interner, instructions: &instructions)
                return result
            }
            let packed = emitPackedCollectionFactoryArguments(
                args: args,
                loweredArgIDs: loweredArgIDs,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            emitRuntimeCollectionFactory(
                name == "setOfNotNull" ? "__kk_set_of_not_null" : "__kk_set_of",
                array: packed.array,
                count: packed.count,
                result: result,
                interner: interner,
                instructions: &instructions
            )
            return result

        case "mutableSetOf", "hashSetOf", "linkedSetOf":
            let runtimeCallee = name == "hashSetOf" ? "__kk_hash_set_of" : "__kk_set_of"
            if loweredArgIDs.isEmpty {
                emitNullArrayCountCall(
                    runtimeCallee,
                    arity: 1,
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                return result
            }
            let packed = emitPackedCollectionFactoryArguments(
                args: args,
                loweredArgIDs: loweredArgIDs,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            emitRuntimeCollectionFactory(
                runtimeCallee,
                array: packed.array,
                count: packed.count,
                result: result,
                interner: interner,
                instructions: &instructions
            )
            return result

        case "emptyMap", "mapOf":
            if loweredArgIDs.isEmpty {
                emitNoArgCall("__kk_emptyMap", result: result, interner: interner, instructions: &instructions)
                return result
            }
            return emitMapFactoryCall(
                loweredArgIDs: loweredArgIDs,
                args: args,
                spreadFlags: args.map(\.isSpread),
                result: result,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )

        case "mutableMapOf", "hashMapOf", "linkedMapOf":
            if loweredArgIDs.isEmpty {
                emitNullArrayCountCall(
                    "__kk_map_of",
                    arity: 2,
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                return result
            }
            return emitMapFactoryCall(
                loweredArgIDs: loweredArgIDs,
                args: args,
                spreadFlags: args.map(\.isSpread),
                result: result,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )

        default:
            return nil
        }
    }

    private func isStdlibCollectionFactoryTarget(
        name: String,
        chosenCallee: SymbolID?,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard [
            "emptyList", "listOf", "mutableListOf", "arrayListOf",
            "emptySet", "setOf", "setOfNotNull", "mutableSetOf", "hashSetOf", "linkedSetOf",
            "emptyMap", "mapOf", "mutableMapOf", "hashMapOf", "linkedMapOf",
        ].contains(name),
            let chosenCallee,
            let symbol = sema.symbols.symbol(chosenCallee),
            symbol.kind == .function,
            symbol.name == interner.intern(name),
            symbol.fqName.count >= 3
        else {
            return false
        }
        return interner.resolve(symbol.fqName[0]) == "kotlin"
            && interner.resolve(symbol.fqName[1]) == "collections"
    }

    private func emitPackedCollectionFactoryArguments(
        args: [CallArgument],
        loweredArgIDs: [KIRExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> (array: KIRExprID, count: KIRExprID) {
        let intType = sema.types.intType
        let boxedArgs = loweredArgIDs.enumerated().map { index, argID in
            if index < args.count, args[index].isSpread {
                return argID
            }
            return boxCollectionFactoryElementIfNeeded(
                argID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        let argIndices = Array(boxedArgs.indices)
        let array = driver.callSupportLowerer.packVarargArguments(
            argIndices: argIndices,
            providedArguments: boxedArgs,
            spreadFlags: args.map(\.isSpread),
            listifyResult: false,
            arena: arena,
            interner: interner,
            intType: intType,
            anyType: sema.types.anyType,
            types: sema.types,
            symbols: sema.symbols,
            instructions: &instructions
        )

        if args.contains(where: \.isSpread) {
            let count = arena.appendTemporary(type: intType)
            emitNonThrowingCall(
                callee: interner.intern("__kk_array_size"),
                arg: array,
                result: count,
                into: &instructions
            )
            return (array, count)
        }

        let count = arena.appendExpr(.intLiteral(Int64(loweredArgIDs.count)), type: intType)
        instructions.append(.constValue(result: count, value: .intLiteral(Int64(loweredArgIDs.count))))
        return (array, count)
    }

    /// Boxes a lowered argument into `Any?` when it is an unboxed primitive, so it can be
    /// stored as an element of an `Any?`-typed array/list. Reused by other vararg-into-`Any?`
    /// lowering paths (e.g. `StringBuilder.append(vararg value: Any?)`).
    ///
    /// A value class with no interface is unboxed to its underlying primitive
    /// elsewhere (ValueClassUnboxingPass), so its *declared* type here is still
    /// `.classType` — resolve it to that underlying primitive kind first, or
    /// `BoxingCalleeTable` sees a non-primitive kind and skips boxing entirely,
    /// storing the raw unboxed value directly in the Any-typed backing array.
    /// Mirrors `ABILoweringPass.resolveValueClassKind` / the equivalent fix in
    /// `CollectionLiteralLoweringPass+FactoryPredicates.primitiveBoxCalleeName`.
    func boxCollectionFactoryElementIfNeeded(
        _ argID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let argType = arena.exprType(argID) else {
            return argID
        }
        let rawSourceKind = sema.types.kind(of: argType)
        let boxKind = resolveValueClassKind(
            rawSourceKind,
            types: sema.types,
            symbols: sema.symbols
        )
        guard let boxCallee = BoxingCalleeTable(interner: interner).boxCallee(
            for: boxKind,
            requireNonNull: false
        )
        else {
            return argID
        }
        let boxedResult = arena.appendTemporary(type: sema.types.anyType)
        emitBoxCallWithValueClassTag(
            boxCallee: boxCallee,
            value: argID,
            rawSourceKind: rawSourceKind,
            result: boxedResult,
            resultType: sema.types.anyType,
            types: sema.types,
            symbols: sema.symbols,
            interner: interner,
            arena: arena,
            into: &instructions
        )
        return boxedResult
    }

    private func emitMapFactoryCall(
        loweredArgIDs: [KIRExprID],
        args: [CallArgument],
        spreadFlags: [Bool],
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        if spreadFlags.contains(true) {
            let packed = emitPackedCollectionFactoryArguments(
                args: args,
                loweredArgIDs: loweredArgIDs,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            emitRuntimeCollectionFactory(
                "__kk_map_of_pairs",
                array: packed.array,
                count: packed.count,
                result: result,
                interner: interner,
                instructions: &instructions
            )
            return result
        }

        let intType = sema.types.intType
        let count = arena.appendExpr(.intLiteral(Int64(loweredArgIDs.count)), type: intType)
        instructions.append(.constValue(result: count, value: .intLiteral(Int64(loweredArgIDs.count))))
        let keysArray = driver.callSupportLowerer.emitArrayNew(
            count: loweredArgIDs.count,
            arena: arena,
            interner: interner,
            intType: intType,
            anyType: sema.types.anyType,
            instructions: &instructions
        )
        let valuesArray = driver.callSupportLowerer.emitArrayNew(
            count: loweredArgIDs.count,
            arena: arena,
            interner: interner,
            intType: intType,
            anyType: sema.types.anyType,
            instructions: &instructions
        )

        for (index, pair) in loweredArgIDs.enumerated() {
            let indexExpr = arena.appendExpr(.intLiteral(Int64(index)), type: intType)
            instructions.append(.constValue(result: indexExpr, value: .intLiteral(Int64(index))))

            let key = arena.appendTemporary(type: sema.types.anyType)
            emitNonThrowingCall(
                callee: interner.intern("__kk_pair_first"),
                arg: pair,
                result: key,
                into: &instructions
            )
            let value = arena.appendTemporary(type: sema.types.anyType)
            emitNonThrowingCall(
                callee: interner.intern("__kk_pair_second"),
                arg: pair,
                result: value,
                into: &instructions
            )

            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [keysArray, indexExpr, key],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [valuesArray, indexExpr, value],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_map_of"),
            arguments: [keysArray, valuesArray, count],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    private func emitNoArgCall(
        _ callee: String,
        result: KIRExprID,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(callee),
            arguments: [],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
    }

    private func emitNullArrayCountCall(
        _ callee: String,
        arity: Int,
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let zero = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: zero, value: .intLiteral(0)))
        var arguments: [KIRExprID] = []
        for _ in 0 ..< arity {
            let nullArray = arena.appendExpr(.intLiteral(0), type: sema.types.anyType)
            instructions.append(.constValue(result: nullArray, value: .intLiteral(0)))
            arguments.append(nullArray)
        }
        arguments.append(zero)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(callee),
            arguments: arguments,
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
    }

    private func emitRuntimeCollectionFactory(
        _ callee: String,
        array: KIRExprID,
        count: KIRExprID,
        result: KIRExprID,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(callee),
            arguments: [array, count],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
    }
}
