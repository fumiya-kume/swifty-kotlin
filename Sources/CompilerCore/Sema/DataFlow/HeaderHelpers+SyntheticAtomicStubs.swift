import Foundation

/// Synthetic stdlib stubs for kotlin.concurrent.AtomicInt, AtomicLong, AtomicReference,
/// and kotlin.concurrent.atomics.AtomicReference.
/// Registers constructors, load/store/exchange/compareAndSet/compareAndExchange methods,
/// arithmetic methods (AtomicInt/AtomicLong), and the `value` property.
extension DataFlowSemaPhase {
    func registerSyntheticAtomicStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let concurrentPkg = ensureAtomicPackage(
            path: ["kotlin", "concurrent"],
            symbols: symbols,
            interner: interner
        )

        let intType = types.intType
        let longType = types.longType
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let unitType = types.unitType

        // -- AtomicInt --
        let atomicIntSymbol = ensureClassSymbol(
            named: "AtomicInt",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicIntType = types.make(.classType(ClassType(
            classSymbol: atomicIntSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicIntType, for: atomicIntSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            externalLinkName: "kk_atomic_int_create",
            paramType: intType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            getterLinkName: "kk_atomic_int_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int",
            symbols: symbols,
            interner: interner
        )

        registerAtomicArithmeticMethods(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            prefix: "kk_atomic_int",
            symbols: symbols,
            interner: interner
        )
        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            prefix: "kk_atomic_int",
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicIntSymbol,
            ownerType: atomicIntType,
            valueType: intType,
            prefix: "kk_atomic_int",
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- AtomicLong --
        let atomicLongSymbol = ensureClassSymbol(
            named: "AtomicLong",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicLongType = types.make(.classType(ClassType(
            classSymbol: atomicLongSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicLongType, for: atomicLongSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            externalLinkName: "kk_atomic_long_create",
            paramType: longType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            getterLinkName: "kk_atomic_long_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_long",
            symbols: symbols,
            interner: interner
        )

        registerAtomicArithmeticMethods(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            prefix: "kk_atomic_long",
            symbols: symbols,
            interner: interner
        )
        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            prefix: "kk_atomic_long",
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicLongSymbol,
            ownerType: atomicLongType,
            valueType: longType,
            prefix: "kk_atomic_long",
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- AtomicReference<T> --
        registerAtomicReferenceStubs(
            packagePath: ["kotlin", "concurrent"],
            symbols: symbols,
            types: types,
            interner: interner,
            boolType: boolType,
            unitType: unitType
        )

        // -- AtomicBoolean --
        let atomicBoolSymbol = ensureClassSymbol(
            named: "AtomicBoolean",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicBoolType = types.make(.classType(ClassType(
            classSymbol: atomicBoolSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicBoolType, for: atomicBoolSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            externalLinkName: "kk_atomic_bool_create",
            paramType: boolType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            valueType: boolType,
            getterLinkName: "kk_atomic_bool_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            valueType: boolType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_bool",
            symbols: symbols,
            interner: interner
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicBoolSymbol,
            ownerType: atomicBoolType,
            valueType: boolType,
            prefix: "kk_atomic_bool",
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- AtomicReference<T> (kotlin.concurrent.atomics) --
        registerAtomicReferenceStubs(
            packagePath: ["kotlin", "concurrent", "atomics"],
            symbols: symbols,
            types: types,
            interner: interner,
            boolType: boolType,
            unitType: unitType
        )
    }

    // MARK: - Helpers

    private func registerAtomicReferenceStubs(
        packagePath: [String],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        boolType: TypeID,
        unitType: TypeID
    ) {
        let atomicPkg = ensureAtomicPackage(
            path: packagePath,
            symbols: symbols,
            interner: interner
        )
        let atomicRefSymbol = ensureClassSymbol(
            named: "AtomicReference",
            in: atomicPkg,
            symbols: symbols,
            interner: interner
        )
        guard let atomicRefInfo = symbols.symbol(atomicRefSymbol) else { return }

        let tName = interner.intern("T")
        let tFQName = atomicRefInfo.fqName + [tName]
        let tSymbol: SymbolID
        if let existing = symbols.lookup(fqName: tFQName) {
            tSymbol = existing
        } else {
            tSymbol = symbols.define(
                kind: .typeParameter,
                name: tName,
                fqName: tFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setParentSymbol(atomicRefSymbol, for: tSymbol)

        let tType = types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([tSymbol], for: atomicRefSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: atomicRefSymbol)

        let atomicRefType = types.make(.classType(ClassType(
            classSymbol: atomicRefSymbol,
            args: [.invariant(tType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicRefType, for: atomicRefSymbol)

        // AtomicReference is source-level generic over T, but the ABI stores
        // values as Any? so the runtime can erase the element type.
        registerAtomicConstructor(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            externalLinkName: "kk_atomic_ref_create",
            paramType: tType,
            typeParameterSymbols: [tSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: tType,
            getterLinkName: "kk_atomic_ref_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: tType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_ref",
            typeParameterSymbols: [tSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: tType,
            prefix: "kk_atomic_ref",
            typeParameterSymbols: [tSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner,
            types: types
        )
    }

    private func registerAtomicConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        paramType: TypeID,
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatch = symbols.lookupAll(fqName: ctorFQName).contains { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .constructor,
                  let sig = symbols.functionSignature(for: id)
            else { return false }
            return sig.parameterTypes == [paramType]
        }
        guard !hasMatch else { return }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        let paramName = interner.intern("initial")
        let paramSymbol = symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: ctorFQName + [paramName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ctorSymbol, for: paramSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [paramType],
                returnType: ownerType,
                valueParameterSymbols: [paramSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: ctorSymbol
        )
    }

    private func registerAtomicValueProperty(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        getterLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern("value")
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { id in
            symbols.symbol(id)?.kind == .property
        }) {
            symbols.setExternalLinkName(getterLinkName, for: existing)
            symbols.setPropertyType(valueType, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(getterLinkName, for: propertySymbol)
        symbols.setPropertyType(valueType, for: propertySymbol)
    }

    private func registerAtomicCoreMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        boolType: TypeID,
        unitType: TypeID,
        prefix: String,
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        // load() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "load", externalLinkName: "\(prefix)_load",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // store(value: T) -> Unit (returns via side effect)
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "store", externalLinkName: "\(prefix)_store",
            returnType: unitType, parameters: [(name: "value", type: valueType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // exchange(new: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "exchange", externalLinkName: "\(prefix)_exchange",
            returnType: valueType, parameters: [(name: "new", type: valueType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // compareAndSet(expect: T, update: T) -> Boolean
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "compareAndSet", externalLinkName: "\(prefix)_compareAndSet",
            returnType: boolType,
            parameters: [
                (name: "expect", type: valueType),
                (name: "update", type: valueType),
            ],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // compareAndExchange(expect: T, update: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "compareAndExchange", externalLinkName: "\(prefix)_compareAndExchange",
            returnType: valueType,
            parameters: [
                (name: "expect", type: valueType),
                (name: "update", type: valueType),
            ],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicArithmeticMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        prefix: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        // fetchAndAdd(delta: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndAdd", externalLinkName: "\(prefix)_fetchAndAdd",
            returnType: valueType, parameters: [(name: "delta", type: valueType)],
            symbols: symbols, interner: interner
        )
        // addAndFetch(delta: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "addAndFetch", externalLinkName: "\(prefix)_addAndFetch",
            returnType: valueType, parameters: [(name: "delta", type: valueType)],
            symbols: symbols, interner: interner
        )
        // fetchAndIncrement() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndIncrement", externalLinkName: "\(prefix)_fetchAndIncrement",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
        // incrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "incrementAndFetch", externalLinkName: "\(prefix)_incrementAndFetch",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
        // decrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "decrementAndFetch", externalLinkName: "\(prefix)_decrementAndFetch",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicGetAndUpdateMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        prefix: String,
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let transformType = types.make(.functionType(FunctionType(
            params: [valueType],
            returnType: valueType,
            isSuspend: false,
            nullability: .nonNull
        )))
        // getAndUpdate(transform: (T) -> T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "getAndUpdate", externalLinkName: "\(prefix)_getAndUpdate",
            returnType: valueType, parameters: [(name: "transform", type: transformType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // updateAndGet(transform: (T) -> T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "updateAndGet", externalLinkName: "\(prefix)_updateAndGet",
            returnType: valueType, parameters: [(name: "transform", type: transformType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
    }

    private func registerAtomicMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { id in
            guard let sig = symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == parameters.map(\.type) &&
                sig.returnType == returnType
        }) == nil else { return }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: memberSymbol
        )
    }

    private func ensureAtomicPackage(
        path: [String],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        var fqName: [InternedString] = []
        for component in path {
            let interned = interner.intern(component)
            fqName.append(interned)
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: interned,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
        return fqName
    }
}
