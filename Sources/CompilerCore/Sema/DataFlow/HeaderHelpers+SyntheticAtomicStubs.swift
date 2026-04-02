import Foundation

/// Synthetic stdlib stubs for kotlin.concurrent.AtomicInt, AtomicLong, AtomicLongArray, AtomicReference.
/// Registers constructors, load/store/exchange/compareAndSet/compareAndExchange methods,
/// arithmetic methods (AtomicInt/AtomicLong), AtomicLongArray access/update methods,
/// and the `value` property.
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
        let anyNullableType = types.make(.any(.nullable))
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

        // -- kotlin.concurrent.atomics.AtomicLongArray --
        let atomicLongArrayCommonPkg = ensureAtomicPackage(
            path: ["kotlin", "concurrent", "atomics"],
            symbols: symbols,
            interner: interner
        )
        let atomicLongArrayCommonSymbol = ensureClassSymbol(
            named: "AtomicLongArray",
            in: atomicLongArrayCommonPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicLongArrayCommonType = types.make(.classType(ClassType(
            classSymbol: atomicLongArrayCommonSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicLongArrayCommonType, for: atomicLongArrayCommonSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicLongArrayCommonSymbol,
            ownerType: atomicLongArrayCommonType,
            externalLinkName: "kk_atomic_long_array_create",
            paramType: intType,
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerAtomicProperty(
            ownerSymbol: atomicLongArrayCommonSymbol,
            ownerType: atomicLongArrayCommonType,
            propertyName: "size",
            propertyType: intType,
            getterLinkName: "kk_atomic_long_array_length",
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicLongArrayCommonSymbol,
            ownerType: atomicLongArrayCommonType,
            name: "loadAt",
            externalLinkName: "kk_atomic_long_array_get",
            returnType: longType,
            parameters: [(name: "index", type: intType)],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicLongArrayCommonSymbol,
            ownerType: atomicLongArrayCommonType,
            name: "storeAt",
            externalLinkName: "kk_atomic_long_array_set",
            returnType: unitType,
            parameters: [
                (name: "index", type: intType),
                (name: "value", type: longType),
            ],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicLongArrayCommonSymbol,
            ownerType: atomicLongArrayCommonType,
            name: "exchangeAt",
            externalLinkName: "kk_atomic_long_array_getAndSet",
            returnType: longType,
            parameters: [
                (name: "index", type: intType),
                (name: "newValue", type: longType),
            ],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicLongArrayCommonSymbol,
            ownerType: atomicLongArrayCommonType,
            name: "compareAndSetAt",
            externalLinkName: "kk_atomic_long_array_compareAndSet",
            returnType: boolType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: longType),
                (name: "newValue", type: longType),
            ],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicLongArrayCommonSymbol,
            ownerType: atomicLongArrayCommonType,
            name: "compareAndExchangeAt",
            externalLinkName: "kk_atomic_long_array_compareAndExchange",
            returnType: longType,
            parameters: [
                (name: "index", type: intType),
                (name: "expectedValue", type: longType),
                (name: "newValue", type: longType),
            ],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicLongArrayCommonSymbol,
            ownerType: atomicLongArrayCommonType,
            name: "fetchAndAddAt",
            externalLinkName: "kk_atomic_long_array_getAndAdd",
            returnType: longType,
            parameters: [
                (name: "index", type: intType),
                (name: "delta", type: longType),
            ],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicLongArrayCommonSymbol,
            ownerType: atomicLongArrayCommonType,
            name: "addAndFetchAt",
            externalLinkName: "kk_atomic_long_array_addAndGet",
            returnType: longType,
            parameters: [
                (name: "index", type: intType),
                (name: "delta", type: longType),
            ],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: atomicLongArrayCommonSymbol,
            ownerType: atomicLongArrayCommonType,
            name: "toString",
            externalLinkName: "kk_atomic_long_array_toString",
            returnType: types.stringType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        // -- AtomicReference<T> --
        let atomicRefSymbol = ensureClassSymbol(
            named: "AtomicReference",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let atomicRefType = types.make(.classType(ClassType(
            classSymbol: atomicRefSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(atomicRefType, for: atomicRefSymbol)

        // AtomicReference stores values as Any? at the ABI level.
        registerAtomicConstructor(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            externalLinkName: "kk_atomic_ref_create",
            paramType: anyNullableType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: anyNullableType,
            getterLinkName: "kk_atomic_ref_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: anyNullableType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_ref",
            symbols: symbols,
            interner: interner
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: anyNullableType,
            prefix: "kk_atomic_ref",
            symbols: symbols,
            interner: interner,
            types: types
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
    }

    // MARK: - Helpers

    private func registerAtomicConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        paramType: TypeID,
        canThrow: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let existingMatches = symbols.lookupAll(fqName: ctorFQName)
        if let existing = existingMatches.first(where: { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .constructor,
                  let sig = symbols.functionSignature(for: id)
            else { return false }
            return sig.parameterTypes == [paramType]
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if canThrow {
                symbols.insertFlags([.throwingFunction], for: existing)
            }
            return
        }

        var flags: SymbolFlags = [.synthetic]
        if canThrow { flags.formUnion([.throwingFunction]) }
        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
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
                valueParameterIsVararg: [false]
            ),
            for: ctorSymbol
        )
    }

    private func registerAtomicTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        canThrow: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == nil &&
                existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if canThrow {
                symbols.insertFlags([.throwingFunction], for: existing)
            }
            return
        }

        var flags: SymbolFlags = [.synthetic]
        if canThrow { flags.formUnion([.throwingFunction]) }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerAtomicProperty(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        propertyName: String,
        propertyType: TypeID,
        getterLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyNameID = interner.intern(propertyName)
        let propertyFQName = ownerInfo.fqName + [propertyNameID]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { id in
            symbols.symbol(id)?.kind == .property
        }) {
            symbols.setExternalLinkName(getterLinkName, for: existing)
            symbols.setPropertyType(propertyType, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyNameID,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(getterLinkName, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
    }

    private func registerAtomicValueProperty(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        getterLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerAtomicProperty(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            propertyName: "value",
            propertyType: valueType,
            getterLinkName: getterLinkName,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicCoreMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        boolType: TypeID,
        unitType: TypeID,
        prefix: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        // load() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "load", externalLinkName: "\(prefix)_load",
            returnType: valueType, parameters: [],
            symbols: symbols, interner: interner
        )
        // store(value: T) -> Unit (returns via side effect)
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "store", externalLinkName: "\(prefix)_store",
            returnType: unitType, parameters: [(name: "value", type: valueType)],
            symbols: symbols, interner: interner
        )
        // exchange(new: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "exchange", externalLinkName: "\(prefix)_exchange",
            returnType: valueType, parameters: [(name: "new", type: valueType)],
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
            symbols: symbols, interner: interner
        )
        // updateAndGet(transform: (T) -> T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "updateAndGet", externalLinkName: "\(prefix)_updateAndGet",
            returnType: valueType, parameters: [(name: "transform", type: transformType)],
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
        canThrow: Bool = false,
        isOperator: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { id in
            guard let sig = symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == parameters.map(\.type) &&
                sig.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            var extraFlags = SymbolFlags()
            if canThrow { extraFlags.formUnion([.throwingFunction]) }
            if isOperator { extraFlags.formUnion([.operatorFunction]) }
            if !extraFlags.isEmpty {
                symbols.insertFlags(extraFlags, for: existing)
            }
            return
        }

        var flags: SymbolFlags = [.synthetic]
        if canThrow { flags.formUnion([.throwingFunction]) }
        if isOperator { flags.formUnion([.operatorFunction]) }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
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
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
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
