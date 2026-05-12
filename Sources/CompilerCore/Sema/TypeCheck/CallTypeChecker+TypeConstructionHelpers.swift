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
        from args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> (keyType: TypeID, valueType: TypeID)? {
        let sema = ctx.sema
        let interner = ctx.interner
        let ast = ctx.ast
        var keyTypes: [TypeID] = []
        var valueTypes: [TypeID] = []

        for argument in args {
            guard let expr = ast.arena.expr(argument.expr) else { return nil }
            switch expr {
            case let .memberCall(receiver, callee, _, pairArgs, _)
                where callee == KnownCompilerNames(interner: interner).to && pairArgs.count == 1:
                let keyType = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
                let valueType = driver.inferExpr(pairArgs[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                keyTypes.append(keyType)
                valueTypes.append(valueType)
            case let .call(calleeExpr, _, pairArgs, _):
                guard pairArgs.count == 2,
                      let callee = ast.arena.expr(calleeExpr),
                      case let .nameRef(name, _) = callee,
                      name == KnownCompilerNames(interner: interner).to
                else {
                    return nil
                }
                let keyType = driver.inferExpr(pairArgs[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                let valueType = driver.inferExpr(pairArgs[1].expr, ctx: ctx, locals: &locals, expectedType: nil)
                keyTypes.append(keyType)
                valueTypes.append(valueType)
            default:
                return nil
            }
        }

        guard !keyTypes.isEmpty, !valueTypes.isEmpty else {
            return nil
        }
        return (sema.types.lub(keyTypes), sema.types.lub(valueTypes))
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

    func applyContractEffects(
        chosen: SymbolID,
        args: [CallArgument],
        argTypes: [TypeID],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
        guard let effect = sema.symbols.contractNonNullEffect(for: chosen),
              effect.appliesOnAnyReturn,
              let parameterIndex = sema.symbols.functionSignature(for: chosen)?
              .valueParameterSymbols.firstIndex(of: effect.parameterSymbol),
              parameterIndex < args.count,
              parameterIndex < argTypes.count
        else {
            return
        }
        let conditionExpr = args[parameterIndex].expr
        let branch = ctx.dataFlow.branchOnCondition(
            conditionExpr,
            base: ctx.flowState,
            locals: locals,
            ast: ctx.ast,
            sema: sema,
            interner: ctx.interner,
            scope: ctx.scope
        )
        driver.exprChecker.applyFlowStateToLocals(
            branch.trueState,
            locals: &locals,
            sema: sema
        )
    }
}
