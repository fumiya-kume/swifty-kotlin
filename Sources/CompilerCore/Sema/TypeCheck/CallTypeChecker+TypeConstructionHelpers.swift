/// Synthetic type-construction helpers used by `inferCallExpr` /
/// `inferMemberCallExpr` to materialize `List`, `Iterable`, `Sequence`,
/// `Set`, `MutableSet`, `LinkedHashSet`, `Map`, `MutableMap`, `Array`,
/// and primitive-array types when the call site needs them.
///
/// Also includes the contract-effect propagation helper used after
/// callable resolution.
///
/// Split out from `CallTypeChecker.swift`.
extension CallTypeChecker {
    /// Promoted from `private` to module-`internal` so the
    /// `+MemberCallInference*` extension files can share the single definition
    /// instead of duplicating it.
    func makeSyntheticListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    /// Shared helper for synthesizing `Iterable<T>` types.
    /// Falls back to `Any` if `kotlin.collections.Iterable` is not registered.
    func makeSyntheticIterableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard let iterableSymbol = symbols.lookup(fqName: iterableFQName) else {
            // Fall back to Any rather than List<Char> to avoid granting
            // list-only members (e.g. get()) to the iterable result type.
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    /// Build `Array<elementType>` -- generic array with preserved element type.
    func makeSyntheticArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let arrayFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Array"),
        ]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    /// Build a primitive array type (`IntArray`, `LongArray`, etc.) by name.
    func makeSyntheticPrimitiveArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        arrayName: String
    ) -> TypeID {
        let arrayFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern(arrayName),
        ]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    /// Build a nominal class type from a fully-qualified name (no type arguments).
    /// Falls back to `Any` when the symbol is not registered.
    /// Promoted from `private` to module-`internal` so the
    /// `+MemberCallInference*` extension files can share the single definition
    /// instead of duplicating it.
    func makeSyntheticNominalType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner _: StringInterner,
        fqName: [InternedString]
    ) -> TypeID {
        guard let symbol = symbols.lookup(fqName: fqName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func makeSyntheticSequenceType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let sequenceFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("Sequence"),
        ]
        guard let sequenceSymbol = symbols.lookup(fqName: sequenceFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func inferSyntheticMapKeyValueTypes(
        from argTypes: [TypeID],
        ctx: TypeInferenceContext
    ) -> (keyType: TypeID, valueType: TypeID)? {
        let sema = ctx.sema
        let interner = ctx.interner
        let pairFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Pair"),
        ]
        guard let pairSymbol = sema.symbols.lookup(fqName: pairFQName) else {
            return nil
        }

        var keyTypes: [TypeID] = []
        var valueTypes: [TypeID] = []
        for type in argTypes {
            guard case let .classType(classType) = sema.types.kind(of: type),
                  classType.classSymbol == pairSymbol,
                  classType.args.count == 2
            else {
                return nil
            }
            func projected(_ arg: TypeArg) -> TypeID {
                switch arg {
                case let .invariant(t), let .out(t), let .in(t):
                    return t
                case .star:
                    return sema.types.anyType
                }
            }
            keyTypes.append(projected(classType.args[0]))
            valueTypes.append(projected(classType.args[1]))
        }

        guard !keyTypes.isEmpty, !valueTypes.isEmpty else {
            return nil
        }
        return (sema.types.lub(keyTypes), sema.types.lub(valueTypes))
    }

    func inferMapTypeArgumentsFromConstructorArgument(
        from argTypes: [TypeID],
        ctx: TypeInferenceContext
    ) -> (keyType: TypeID, valueType: TypeID)? {
        guard argTypes.count == 1,
              case let .classType(argumentClass) = ctx.sema.types.kind(of: argTypes[0])
        else {
            return nil
        }
        let interner = ctx.interner
        let mapSymbol = ctx.sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ])
        guard let mapSymbol,
              let mapArgs = ctx.sema.types.liftedNominalSupertypeArgs(
                  from: argumentClass.classSymbol,
                  childArgs: argumentClass.args,
                  to: mapSymbol
              ),
              mapArgs.count == 2
        else {
            return nil
        }

        func projected(_ arg: TypeArg) -> TypeID {
            switch arg {
            case let .invariant(type), let .in(type), let .out(type):
                return type
            case .star:
                return ctx.sema.types.anyType
            }
        }
        return (projected(mapArgs[0]), projected(mapArgs[1]))
    }

    func makeSyntheticMutableListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let mutableListFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableList"),
        ]
        guard let mutableListSymbol = symbols.lookup(fqName: mutableListFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticListConstructorType(
        name: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let fqName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern(name),
        ]
        guard let classSymbol = symbols.lookup(fqName: fqName),
              symbols.symbol(classSymbol)?.kind == .class
        else {
            return makeSyntheticMutableListType(
                symbols: symbols,
                types: types,
                interner: interner,
                elementType: elementType
            )
        }
        return types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let setFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Set"),
        ]
        guard let setSymbol = symbols.lookup(fqName: setFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: setSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticMutableSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let mutableSetFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableSet"),
        ]
        guard let mutableSetSymbol = symbols.lookup(fqName: mutableSetFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mutableSetSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticHashSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let hashSetFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("HashSet"),
        ]
        guard let hashSetSymbol = symbols.lookup(fqName: hashSetFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: hashSetSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticLinkedHashSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let linkedHashSetFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("LinkedHashSet"),
        ]
        guard let linkedHashSetSymbol = symbols.lookup(fqName: linkedHashSetFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: linkedHashSetSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticMapType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        keyType: TypeID,
        valueType: TypeID
    ) -> TypeID {
        let mapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ]
        guard let mapSymbol = symbols.lookup(fqName: mapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticMutableMapType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        keyType: TypeID,
        valueType: TypeID
    ) -> TypeID {
        let mapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableMap"),
        ]
        guard let mapSymbol = symbols.lookup(fqName: mapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
    }

    func makeSourceBackedHashMapType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        keyType: TypeID,
        valueType: TypeID
    ) -> TypeID {
        let hashMapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("HashMap"),
        ]
        guard let hashMapSymbol = symbols.lookup(fqName: hashMapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: hashMapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
    }

    func applyContractEffects(
        chosen: SymbolID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
        guard let signature = sema.symbols.functionSignature(for: chosen) else {
            return
        }
        let parameterIndex: Int
        if let effect = sema.symbols.contractNonNullEffect(for: chosen),
           effect.appliesOnAnyReturn,
           let index = signature.valueParameterSymbols.firstIndex(of: effect.parameterSymbol),
           index < args.count,
           index < signature.parameterTypes.count
        {
            parameterIndex = index
        } else if let effect = sema.symbols.contractConditionEffect(for: chosen),
                  // STDLIB-591: only `returns() implies (condition)` (any normal
                  // return) is handled here; `returns(true/false) implies (...)`
                  // would need to correlate with how the call's own result is
                  // branched on at the use site, which this post-call helper
                  // doesn't have visibility into.
                  effect.returnsValue == nil,
                  effect.conditionParameterIndex < args.count,
                  effect.conditionParameterIndex < signature.parameterTypes.count
        {
            parameterIndex = effect.conditionParameterIndex
        } else {
            return
        }
        let conditionExpr = args[parameterIndex].expr
        // Synthetic precondition effects describe a Boolean condition, while
        // source-backed contract effects point directly at the nullable
        // argument from a returns() implies clause.
        let narrowedState: DataFlowState
        if signature.parameterTypes[parameterIndex] == sema.types.booleanType {
            let branch = ctx.dataFlow.branchOnCondition(
                conditionExpr,
                base: ctx.flowState,
                locals: locals,
                ast: ctx.ast,
                sema: sema,
                interner: ctx.interner,
                scope: ctx.scope
            )
            narrowedState = branch.trueState
        } else {
            narrowedState = ctx.dataFlow.narrowNonNull(
                conditionExpr,
                base: ctx.flowState,
                locals: locals,
                ast: ctx.ast,
                sema: sema,
                interner: ctx.interner
            )
        }
        driver.exprChecker.applyFlowStateToLocals(
            narrowedState,
            locals: &locals,
            sema: sema
        )
    }
}
