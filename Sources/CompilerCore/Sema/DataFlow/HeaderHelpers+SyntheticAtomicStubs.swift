import Foundation

/// Synthetic stdlib stubs for kotlin.concurrent atomic and lock types.
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
        let atomicsPkg = ensureAtomicPackage(
            path: ["kotlin", "concurrent", "atomics"],
            symbols: symbols,
            interner: interner
        )

        let intType = types.intType
        let longType = types.longType
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let unitType = types.unitType

        registerAtomicScalarFamily(
            packageFQName: concurrentPkg,
            className: "AtomicInt",
            constructorLinkName: "kk_atomic_int_create",
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int",
            includeArithmetic: true,
            includeGetAndUpdate: true,
            includeFetchAndUpdateAlias: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicScalarFamily(
            packageFQName: concurrentPkg,
            className: "AtomicLong",
            constructorLinkName: "kk_atomic_long_create",
            valueType: longType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_long",
            includeArithmetic: true,
            includeGetAndUpdate: true,
            includeFetchAndUpdateAlias: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicScalarFamily(
            packageFQName: concurrentPkg,
            className: "AtomicBoolean",
            constructorLinkName: "kk_atomic_bool_create",
            valueType: boolType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_bool",
            includeArithmetic: false,
            includeGetAndUpdate: true,
            includeFetchAndUpdateAlias: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerAtomicReferenceStubs(
            ownerPackage: concurrentPkg,
            ownerPackageSymbol: symbols.lookup(fqName: concurrentPkg) ?? .invalid,
            symbols: symbols,
            types: types,
            interner: interner,
            externalLinkPrefix: "kk_atomic_ref"
        )
        registerAtomicArrayFamily(
            packageFQName: concurrentPkg,
            className: "AtomicIntArray",
            constructorLinkName: "kk_atomic_int_array_create",
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int_array",
            includeArithmetic: true,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicArrayFamily(
            packageFQName: concurrentPkg,
            className: "AtomicLongArray",
            constructorLinkName: "kk_atomic_long_array_create",
            valueType: longType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_long_array",
            includeArithmetic: true,
            symbols: symbols,
            interner: interner,
            types: types
        )

        registerSyntheticAtomicAnnotation(
            named: "ExperimentalAtomicApi",
            in: atomicsPkg,
            symbols: symbols,
            interner: interner
        )
        let memoryOrderSymbol = ensureAtomicMemoryOrderEnum(
            in: atomicsPkg,
            symbols: symbols,
            interner: interner
        )
        let memoryOrderType = types.make(.classType(ClassType(
            classSymbol: memoryOrderSymbol,
            args: [],
            nullability: .nonNull
        )))
        setAtomicEnumEntryTypes(
            enumSymbol: memoryOrderSymbol,
            enumType: memoryOrderType,
            symbols: symbols
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicInt",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicInt",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicLong",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicLong",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicBoolean",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicBoolean",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicTypeAlias(
            aliasName: "AtomicReference",
            aliasPackageFQName: atomicsPkg,
            targetName: "AtomicReference",
            targetPackageFQName: concurrentPkg,
            symbols: symbols,
            interner: interner,
            types: types,
            typeParameterNames: ["T"]
        )
        registerAtomicNativePtrSurface(
            packageFQName: atomicsPkg,
            packageSymbol: symbols.lookup(fqName: atomicsPkg),
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicAsJavaAtomicFunction(
            packageFQName: atomicsPkg,
            receiverPackageFQName: concurrentPkg,
            receiverName: "AtomicInt",
            javaAtomicName: "AtomicInteger",
            externalLinkName: "kk_atomic_int_asJavaAtomic",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicAsJavaAtomicFunction(
            packageFQName: atomicsPkg,
            receiverPackageFQName: concurrentPkg,
            receiverName: "AtomicLong",
            javaAtomicName: "AtomicLong",
            externalLinkName: "kk_atomic_long_asJavaAtomic",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicAsJavaAtomicFunction(
            packageFQName: atomicsPkg,
            receiverPackageFQName: concurrentPkg,
            receiverName: "AtomicBoolean",
            javaAtomicName: "AtomicBoolean",
            externalLinkName: "kk_atomic_bool_asJavaAtomic",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicReferenceAsJavaAtomicFunction(
            packageFQName: atomicsPkg,
            receiverPackageFQName: concurrentPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicAsKotlinAtomicFunctions(
            packageFQName: atomicsPkg,
            receiverPackageFQName: concurrentPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerAtomicArrayFamily(
            packageFQName: atomicsPkg,
            className: "AtomicIntArray",
            constructorLinkName: "kk_atomic_int_array_create",
            valueType: intType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_int_array",
            includeArithmetic: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            includeFetchAndUpdate: true,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicArrayAsJavaAtomicArrayFunction(
            packageFQName: atomicsPkg,
            receiverName: "AtomicIntArray",
            javaAtomicName: "AtomicIntegerArray",
            externalLinkName: "kk_atomic_int_array_asJavaAtomicArray",
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerAtomicArrayFamily(
            packageFQName: atomicsPkg,
            className: "AtomicLongArray",
            constructorLinkName: "kk_atomic_long_array_create",
            valueType: longType,
            boolType: boolType,
            unitType: unitType,
            prefix: "kk_atomic_long_array",
            includeArithmetic: true,
            includeIncrementAndGetAlias: true,
            includeGetAndIncrementAlias: true,
            includeGetAndDecrementAlias: true,
            includeGetAndSetAlias: true,
            includeGetAndAddAlias: true,
            includeDecrementAndGetAlias: true,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicLongArrayAsJavaAtomicArrayFunction(
            packageFQName: atomicsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerAtomicRefArrayStub(
            packageFQName: atomicsPkg,
            boolType: boolType,
            unitType: unitType,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicRefArrayAsJavaAtomicArrayFunction(
            packageFQName: atomicsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicAsKotlinAtomicArrayFunctions(
            packageFQName: atomicsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicArrayOfNullsFactory(
            packageFQName: atomicsPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )
        registerAtomicArrayOfFactory(
            packageFQName: atomicsPkg,
            symbols: symbols,
            interner: interner,
            types: types
        )

        // -- Lock --
        let lockSymbol = ensureClassSymbol(
            named: "Lock",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let lockType = types.make(.classType(ClassType(
            classSymbol: lockSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(lockType, for: lockSymbol)
        registerAtomicMember(
            ownerSymbol: lockSymbol,
            ownerType: lockType,
            name: "withLock",
            externalLinkName: "kk_lock_withLock",
            returnType: types.anyType,
            parameters: [(
                name: "action",
                type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            )],
            symbols: symbols,
            interner: interner
        )

        // -- ReentrantReadWriteLock --
        let rwLockSymbol = ensureClassSymbol(
            named: "ReentrantReadWriteLock",
            in: concurrentPkg,
            symbols: symbols,
            interner: interner
        )
        let rwLockType = types.make(.classType(ClassType(
            classSymbol: rwLockSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(rwLockType, for: rwLockSymbol)

        registerReadWriteLockConstructor(
            ownerSymbol: rwLockSymbol,
            ownerType: rwLockType,
            externalLinkName: "kk_read_write_lock_create",
            symbols: symbols,
            interner: interner
        )

        let readWriteActionType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerAtomicMember(
            ownerSymbol: rwLockSymbol,
            ownerType: rwLockType,
            name: "read",
            externalLinkName: "kk_read_write_lock_read",
            returnType: types.anyType,
            parameters: [(
                name: "action",
                type: readWriteActionType
            )],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: rwLockSymbol,
            ownerType: rwLockType,
            name: "write",
            externalLinkName: "kk_read_write_lock_write",
            returnType: types.anyType,
            parameters: [(
                name: "action",
                type: readWriteActionType
            )],
            symbols: symbols,
            interner: interner
        )

        registerReadWriteLockFactory(
            packageFQName: concurrentPkg,
            returnType: rwLockType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Helpers

    private func ensureAtomicMemoryOrderEnum(
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("MemoryOrder")
        let fqName = pkg + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        let symbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
            symbols.setParentSymbol(pkgSymbol, for: symbol)
        }

        let entries = [
            "RELAXED",
            "ACQUIRE",
            "RELEASE",
            "ACQUIRE_RELEASE",
            "SEQUENTIALLY_CONSISTENT",
        ]
        for entry in entries {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(symbol, for: entrySymbol)
        }
        return symbol
    }

    private func setAtomicEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        let children = symbols.children(ofFQName: enumInfo.fqName)
        for child in children {
            guard let childSym = symbols.symbol(child),
                  childSym.kind == .field
            else {
                continue
            }
            if symbols.propertyType(for: child) == nil {
                symbols.setPropertyType(enumType, for: child)
            }
        }
    }

    private func registerAtomicScalarFamily(
        packageFQName: [InternedString],
        className: String,
        constructorLinkName: String,
        valueType: TypeID,
        boolType: TypeID,
        unitType: TypeID,
        prefix: String,
        includeArithmetic: Bool,
        includeGetAndUpdate: Bool,
        includeFetchAndUpdateAlias: Bool = false,
        includeUpdateAndFetchAlias: Bool = false,
        includeIncrementAndGetAlias: Bool = false,
        includeGetAndIncrementAlias: Bool = false,
        includeGetAndDecrementAlias: Bool = false,
        includeGetAndSetAlias: Bool = false,
        includeGetAndAddAlias: Bool = false,
        includeDecrementAndGetAlias: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let symbol = ensureClassSymbol(
            named: className,
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        let ownerType = types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: symbol)

        registerAtomicConstructor(
            ownerSymbol: symbol,
            ownerType: ownerType,
            externalLinkName: constructorLinkName,
            paramType: valueType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: symbol,
            ownerType: ownerType,
            valueType: valueType,
            getterLinkName: "\(prefix)_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: symbol,
            ownerType: ownerType,
            valueType: valueType,
            boolType: boolType,
            unitType: unitType,
            prefix: prefix,
            includeGetAndSetAlias: includeGetAndSetAlias,
            symbols: symbols,
            interner: interner
        )

        if includeArithmetic {
            registerAtomicArithmeticMethods(
                ownerSymbol: symbol,
                ownerType: ownerType,
                valueType: valueType,
                prefix: prefix,
                includeIncrementAndGetAlias: includeIncrementAndGetAlias,
                includeGetAndIncrementAlias: includeGetAndIncrementAlias,
                includeGetAndDecrementAlias: includeGetAndDecrementAlias,
                includeGetAndAddAlias: includeGetAndAddAlias,
                includeDecrementAndGetAlias: includeDecrementAndGetAlias,
                symbols: symbols,
                interner: interner
            )
        }

        if includeGetAndUpdate {
            registerAtomicGetAndUpdateMethods(
                ownerSymbol: symbol,
                ownerType: ownerType,
                valueType: valueType,
                prefix: prefix,
                includeFetchAndUpdateAlias: includeFetchAndUpdateAlias,
                includeUpdateAndFetchAlias: includeUpdateAndFetchAlias,
                symbols: symbols,
                interner: interner,
                types: types
            )
        }
    }

    /// Registers `kotlin.concurrent.atomics.AtomicArray<T>` backed by
    /// `kk_atomic_ref_array_*` ABI functions.  CAS uses identity semantics.
    private func registerAtomicRefArrayStub(
        packageFQName: [InternedString],
        boolType: TypeID,
        unitType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let className = interner.intern("AtomicArray")
        let symbol = ensureClassSymbol(
            named: "AtomicArray",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )

        // Register the T type parameter
        let typeParamName = interner.intern("T")
        let typeParamFQName = packageFQName + [className, typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nullable)))
        let ownerType = types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: symbol)
        types.setNominalTypeParameterVariances([.invariant], for: symbol)
        symbols.setPropertyType(ownerType, for: symbol)

        // constructor(size: Int)
        registerAtomicConstructor(
            ownerSymbol: symbol,
            ownerType: ownerType,
            externalLinkName: "kk_atomic_ref_array_new",
            paramType: types.intType,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // size: Int
        registerAtomicReadOnlyProperty(
            ownerSymbol: symbol,
            ownerType: ownerType,
            propertyName: "size",
            valueType: types.intType,
            getterLinkName: "kk_atomic_ref_array_size",
            symbols: symbols,
            interner: interner
        )

        // loadAt(index: Int): T
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "loadAt",
            externalLinkName: "kk_atomic_ref_array_loadAt",
            returnType: typeParamType,
            parameters: [(name: "index", type: types.intType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // storeAt(index: Int, value: T): Unit
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "storeAt",
            externalLinkName: "kk_atomic_ref_array_storeAt",
            returnType: unitType,
            parameters: [(name: "index", type: types.intType), (name: "value", type: typeParamType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // exchangeAt(index: Int, newValue: T): T
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "exchangeAt",
            externalLinkName: "kk_atomic_ref_array_exchangeAt",
            returnType: typeParamType,
            parameters: [(name: "index", type: types.intType), (name: "newValue", type: typeParamType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "getAndSet",
            externalLinkName: "kk_atomic_ref_array_exchangeAt",
            returnType: typeParamType,
            parameters: [(name: "index", type: types.intType), (name: "newValue", type: typeParamType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // compareAndSetAt(index: Int, expect: T, update: T): Boolean
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "compareAndSetAt",
            externalLinkName: "kk_atomic_ref_array_compareAndSetAt",
            returnType: boolType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "expect", type: typeParamType),
                (name: "update", type: typeParamType),
            ],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // compareAndExchangeAt(index: Int, expect: T, update: T): T
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "compareAndExchangeAt",
            externalLinkName: "kk_atomic_ref_array_compareAndExchangeAt",
            returnType: typeParamType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "expect", type: typeParamType),
                (name: "update", type: typeParamType),
            ],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        let transformType = types.make(.functionType(FunctionType(
            params: [typeParamType],
            returnType: typeParamType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "fetchAndUpdateAt",
            externalLinkName: "kk_atomic_ref_array_fetchAndUpdateAt",
            returnType: typeParamType,
            parameters: [(name: "index", type: types.intType), (name: "transform", type: transformType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "updateAt",
            externalLinkName: "kk_atomic_ref_array_updateAt",
            returnType: unitType,
            parameters: [(name: "index", type: types.intType), (name: "transform", type: transformType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "updateAndFetchAt",
            externalLinkName: "kk_atomic_ref_array_updateAndFetchAt",
            returnType: typeParamType,
            parameters: [(name: "index", type: types.intType), (name: "transform", type: transformType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        // get operator alias (index: Int): T
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "get",
            externalLinkName: "kk_atomic_ref_array_loadAt",
            returnType: typeParamType,
            parameters: [(name: "index", type: types.intType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )

        // set operator alias (index: Int, value: T): Unit
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "set",
            externalLinkName: "kk_atomic_ref_array_storeAt",
            returnType: unitType,
            parameters: [(name: "index", type: types.intType), (name: "value", type: typeParamType)],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicArrayAsJavaAtomicArrayFunction(
        packageFQName: [InternedString],
        receiverName: String,
        javaAtomicName: String,
        externalLinkName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let receiverSymbol = symbols.lookup(fqName: packageFQName + [interner.intern(receiverName)]) else {
            return
        }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: receiverSymbol,
            args: [],
            nullability: .nonNull
        )))
        let javaAtomicPackage = ensurePackage(
            path: ["java", "util", "concurrent", "atomic"],
            symbols: symbols,
            interner: interner
        )
        let javaAtomicSymbol = ensureClassSymbol(
            named: javaAtomicName,
            in: javaAtomicPackage,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: javaAtomicPackage) {
            symbols.setParentSymbol(packageSymbol, for: javaAtomicSymbol)
        }
        let javaAtomicType = types.make(.classType(ClassType(
            classSymbol: javaAtomicSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(javaAtomicType, for: javaAtomicSymbol)

        registerAtomicExtensionFunction(
            packageFQName: packageFQName,
            name: "asJavaAtomicArray",
            externalLinkName: externalLinkName,
            receiverType: receiverType,
            returnType: javaAtomicType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicRefArrayAsJavaAtomicArrayFunction(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let receiverSymbol = symbols.lookup(fqName: packageFQName + [interner.intern("AtomicArray")]) else {
            return
        }

        let functionName = interner.intern("asJavaAtomicArray")
        let functionFQName = packageFQName + [functionName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nullable
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: receiverSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        let javaAtomicPackage = ensurePackage(
            path: ["java", "util", "concurrent", "atomic"],
            symbols: symbols,
            interner: interner
        )
        let javaAtomicReferenceArraySymbol = ensureClassSymbol(
            named: "AtomicReferenceArray",
            in: javaAtomicPackage,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: javaAtomicPackage) {
            symbols.setParentSymbol(packageSymbol, for: javaAtomicReferenceArraySymbol)
        }
        let javaTypeParamFQName = javaAtomicPackage + [interner.intern("AtomicReferenceArray"), typeParamName]
        let javaTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: javaTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: javaTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let javaTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: javaTypeParamSymbol,
            nullability: .nullable
        )))
        let javaAtomicReferenceArrayType = types.make(.classType(ClassType(
            classSymbol: javaAtomicReferenceArraySymbol,
            args: [.invariant(javaTypeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([javaTypeParamSymbol], for: javaAtomicReferenceArraySymbol)
        types.setNominalTypeParameterVariances([.invariant], for: javaAtomicReferenceArraySymbol)
        symbols.setPropertyType(javaAtomicReferenceArrayType, for: javaAtomicReferenceArraySymbol)

        let returnType = types.make(.classType(ClassType(
            classSymbol: javaAtomicReferenceArraySymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        registerAtomicExtensionFunction(
            packageFQName: packageFQName,
            name: "asJavaAtomicArray",
            externalLinkName: "kk_atomic_ref_array_asJavaAtomicArray",
            receiverType: receiverType,
            returnType: returnType,
            typeParameterSymbols: [typeParamSymbol],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicAsKotlinAtomicArrayFunctions(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaAtomicPackage = ensurePackage(
            path: ["java", "util", "concurrent", "atomic"],
            symbols: symbols,
            interner: interner
        )
        registerAtomicArrayAsKotlinAtomicArrayFunction(
            packageFQName: packageFQName,
            javaPackageFQName: javaAtomicPackage,
            javaAtomicName: "AtomicIntegerArray",
            kotlinAtomicName: "AtomicIntArray",
            constructorLinkName: "kk_atomic_int_array_create",
            externalLinkName: "kk_java_atomic_int_array_asKotlinAtomicArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicArrayAsKotlinAtomicArrayFunction(
            packageFQName: packageFQName,
            javaPackageFQName: javaAtomicPackage,
            javaAtomicName: "AtomicLongArray",
            kotlinAtomicName: "AtomicLongArray",
            constructorLinkName: "kk_atomic_long_array_create",
            externalLinkName: "kk_java_atomic_long_array_asKotlinAtomicArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicRefArrayAsKotlinAtomicArrayFunction(
            packageFQName: packageFQName,
            javaPackageFQName: javaAtomicPackage,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerAtomicArrayAsKotlinAtomicArrayFunction(
        packageFQName: [InternedString],
        javaPackageFQName: [InternedString],
        javaAtomicName: String,
        kotlinAtomicName: String,
        constructorLinkName: String,
        externalLinkName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let kotlinAtomicSymbol = symbols.lookup(fqName: packageFQName + [interner.intern(kotlinAtomicName)]) else {
            return
        }
        let kotlinAtomicType = types.make(.classType(ClassType(
            classSymbol: kotlinAtomicSymbol,
            args: [],
            nullability: .nonNull
        )))
        let javaAtomicSymbol = ensureClassSymbol(
            named: javaAtomicName,
            in: javaPackageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: javaPackageFQName) {
            symbols.setParentSymbol(packageSymbol, for: javaAtomicSymbol)
        }
        let javaAtomicType = types.make(.classType(ClassType(
            classSymbol: javaAtomicSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(javaAtomicType, for: javaAtomicSymbol)
        registerAtomicConstructor(
            ownerSymbol: javaAtomicSymbol,
            ownerType: javaAtomicType,
            externalLinkName: constructorLinkName,
            paramType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerAtomicExtensionFunction(
            packageFQName: packageFQName,
            name: "asKotlinAtomicArray",
            externalLinkName: externalLinkName,
            receiverType: javaAtomicType,
            returnType: kotlinAtomicType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicRefArrayAsKotlinAtomicArrayFunction(
        packageFQName: [InternedString],
        javaPackageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let atomicArraySymbol = symbols.lookup(fqName: packageFQName + [interner.intern("AtomicArray")]) else {
            return
        }

        let javaAtomicReferenceArrayName = interner.intern("AtomicReferenceArray")
        let javaAtomicReferenceArraySymbol = ensureClassSymbol(
            named: "AtomicReferenceArray",
            in: javaPackageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: javaPackageFQName) {
            symbols.setParentSymbol(packageSymbol, for: javaAtomicReferenceArraySymbol)
        }

        let classTypeParamName = interner.intern("T")
        let classTypeParamFQName = javaPackageFQName + [javaAtomicReferenceArrayName, classTypeParamName]
        let classTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: classTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: classTypeParamName,
                fqName: classTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let classTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: classTypeParamSymbol,
            nullability: .nullable
        )))
        let javaAtomicReferenceArrayType = types.make(.classType(ClassType(
            classSymbol: javaAtomicReferenceArraySymbol,
            args: [.invariant(classTypeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([classTypeParamSymbol], for: javaAtomicReferenceArraySymbol)
        types.setNominalTypeParameterVariances([.invariant], for: javaAtomicReferenceArraySymbol)
        symbols.setPropertyType(javaAtomicReferenceArrayType, for: javaAtomicReferenceArraySymbol)
        registerAtomicConstructor(
            ownerSymbol: javaAtomicReferenceArraySymbol,
            ownerType: javaAtomicReferenceArrayType,
            externalLinkName: "kk_atomic_ref_array_new",
            paramType: types.intType,
            typeParameterSymbols: [classTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        let functionName = interner.intern("asKotlinAtomicArray")
        let functionFQName = packageFQName + [functionName]
        let functionTypeParamName = interner.intern("T")
        let functionTypeParamFQName = functionFQName + [functionTypeParamName]
        let functionTypeParamSymbol = symbols.lookup(fqName: functionTypeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: functionTypeParamName,
            fqName: functionTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let functionTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: functionTypeParamSymbol,
            nullability: .nullable
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: javaAtomicReferenceArraySymbol,
            args: [.invariant(functionTypeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: atomicArraySymbol,
            args: [.invariant(functionTypeParamType)],
            nullability: .nonNull
        )))
        registerAtomicExtensionFunction(
            packageFQName: packageFQName,
            name: "asKotlinAtomicArray",
            externalLinkName: "kk_java_atomic_ref_array_asKotlinAtomicArray",
            receiverType: receiverType,
            returnType: returnType,
            typeParameterSymbols: [functionTypeParamSymbol],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicArrayFamily(
        packageFQName: [InternedString],
        className: String,
        constructorLinkName: String,
        valueType: TypeID,
        boolType: TypeID,
        unitType: TypeID,
        prefix: String,
        includeArithmetic: Bool,
        includeIncrementAndGetAlias: Bool = false,
        includeGetAndIncrementAlias: Bool = false,
        includeGetAndDecrementAlias: Bool = false,
        includeGetAndSetAlias: Bool = false,
        includeGetAndAddAlias: Bool = false,
        includeDecrementAndGetAlias: Bool = false,
        includeFetchAndUpdate: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let symbol = ensureClassSymbol(
            named: className,
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        let ownerType = types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: symbol)

        registerAtomicConstructor(
            ownerSymbol: symbol,
            ownerType: ownerType,
            externalLinkName: constructorLinkName,
            paramType: types.intType,
            symbols: symbols,
            interner: interner
        )

        registerAtomicReadOnlyProperty(
            ownerSymbol: symbol,
            ownerType: ownerType,
            propertyName: "size",
            valueType: types.intType,
            getterLinkName: "\(prefix)_size",
            symbols: symbols,
            interner: interner
        )

        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "loadAt",
            externalLinkName: "\(prefix)_loadAt",
            returnType: valueType,
            parameters: [(name: "index", type: types.intType)],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "storeAt",
            externalLinkName: "\(prefix)_storeAt",
            returnType: unitType,
            parameters: [(name: "index", type: types.intType), (name: "value", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "get",
            externalLinkName: "\(prefix)_loadAt",
            returnType: valueType,
            parameters: [(name: "index", type: types.intType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "set",
            externalLinkName: "\(prefix)_storeAt",
            returnType: unitType,
            parameters: [(name: "index", type: types.intType), (name: "value", type: valueType)],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
            ownerSymbol: symbol,
            ownerType: ownerType,
            name: "exchangeAt",
            externalLinkName: "\(prefix)_exchangeAt",
            returnType: valueType,
            parameters: [(name: "index", type: types.intType), (name: "newValue", type: valueType)],
            symbols: symbols,
            interner: interner
        )
        if includeGetAndSetAlias {
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "getAndSet",
                externalLinkName: "\(prefix)_exchangeAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType), (name: "newValue", type: valueType)],
                symbols: symbols,
                interner: interner
            )
        }
        registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "compareAndSetAt",
                externalLinkName: "\(prefix)_compareAndSetAt",
                returnType: boolType,
                parameters: [
                (name: "index", type: types.intType),
                (name: "expect", type: valueType),
                (name: "update", type: valueType),
            ],
            symbols: symbols,
            interner: interner
        )
        registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "compareAndExchangeAt",
                externalLinkName: "\(prefix)_compareAndExchangeAt",
                returnType: valueType,
                parameters: [
                (name: "index", type: types.intType),
                (name: "expect", type: valueType),
                (name: "update", type: valueType),
            ],
            symbols: symbols,
            interner: interner
        )

        if includeFetchAndUpdate {
            let transformType = types.make(.functionType(FunctionType(
                params: [valueType],
                returnType: valueType,
                isSuspend: false,
                nullability: .nonNull
            )))
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "fetchAndUpdateAt",
                externalLinkName: "\(prefix)_fetchAndUpdateAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType), (name: "transform", type: transformType)],
                symbols: symbols,
                interner: interner
            )
        }

        if includeArithmetic {
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "fetchAndAddAt",
                externalLinkName: "\(prefix)_fetchAndAddAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType), (name: "delta", type: valueType)],
                symbols: symbols,
                interner: interner
            )
            if includeGetAndAddAlias {
                registerAtomicMember(
                    ownerSymbol: symbol,
                    ownerType: ownerType,
                    name: "getAndAdd",
                    externalLinkName: "\(prefix)_fetchAndAddAt",
                    returnType: valueType,
                    parameters: [(name: "index", type: types.intType), (name: "delta", type: valueType)],
                    symbols: symbols,
                    interner: interner
                )
            }
            if includeIncrementAndGetAlias {
                registerAtomicMember(
                    ownerSymbol: symbol,
                    ownerType: ownerType,
                    name: "incrementAndGet",
                    externalLinkName: "\(prefix)_incrementAndFetchAt",
                    returnType: valueType,
                    parameters: [(name: "index", type: types.intType)],
                    symbols: symbols,
                    interner: interner
                )
            }
            if includeGetAndIncrementAlias {
                registerAtomicMember(
                    ownerSymbol: symbol,
                    ownerType: ownerType,
                    name: "getAndIncrement",
                    externalLinkName: "\(prefix)_fetchAndIncrementAt",
                    returnType: valueType,
                    parameters: [(name: "index", type: types.intType)],
                    symbols: symbols,
                    interner: interner
                )
            }
            if includeGetAndDecrementAlias {
                registerAtomicMember(
                    ownerSymbol: symbol,
                    ownerType: ownerType,
                    name: "getAndDecrement",
                    externalLinkName: "\(prefix)_fetchAndDecrementAt",
                    returnType: valueType,
                    parameters: [(name: "index", type: types.intType)],
                    symbols: symbols,
                    interner: interner
                )
            }
            if includeDecrementAndGetAlias {
                registerAtomicMember(
                    ownerSymbol: symbol,
                    ownerType: ownerType,
                    name: "decrementAndGet",
                    externalLinkName: "\(prefix)_decrementAndFetchAt",
                    returnType: valueType,
                    parameters: [(name: "index", type: types.intType)],
                    symbols: symbols,
                    interner: interner
                )
            }
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "addAndFetchAt",
                externalLinkName: "\(prefix)_addAndFetchAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType), (name: "delta", type: valueType)],
                symbols: symbols,
                interner: interner
            )
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "fetchAndIncrementAt",
                externalLinkName: "\(prefix)_fetchAndIncrementAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType)],
                symbols: symbols,
                interner: interner
            )
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "fetchAndDecrementAt",
                externalLinkName: "\(prefix)_fetchAndDecrementAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType)],
                symbols: symbols,
                interner: interner
            )
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "incrementAndFetchAt",
                externalLinkName: "\(prefix)_incrementAndFetchAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType)],
                symbols: symbols,
                interner: interner
            )
            registerAtomicMember(
                ownerSymbol: symbol,
                ownerType: ownerType,
                name: "decrementAndFetchAt",
                externalLinkName: "\(prefix)_decrementAndFetchAt",
                returnType: valueType,
                parameters: [(name: "index", type: types.intType)],
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticAtomicAnnotation(
        named name: String,
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let annotationName = interner.intern(name)
        let fqName = packageFQName + [annotationName]
        guard symbols.lookup(fqName: fqName) == nil else { return }

        _ = symbols.define(
            kind: .annotationClass,
            name: annotationName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    private func registerAtomicTypeAlias(
        aliasName: String,
        aliasPackageFQName: [InternedString],
        targetName: String,
        targetPackageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem,
        typeParameterNames: [String] = []
    ) {
        let aliasInterned = interner.intern(aliasName)
        let aliasFQName = aliasPackageFQName + [aliasInterned]
        guard symbols.lookup(fqName: aliasFQName) == nil else { return }

        let targetInterned = interner.intern(targetName)
        let targetFQName = targetPackageFQName + [targetInterned]
        guard let targetSymbol = symbols.lookup(fqName: targetFQName) else { return }

        let aliasSymbol = symbols.define(
            kind: .typeAlias,
            name: aliasInterned,
            fqName: aliasFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let underlyingArgs: [TypeArg]
        if typeParameterNames.isEmpty {
            underlyingArgs = []
        } else {
            let typeParamSymbols = typeParameterNames.map { paramName in
                let internedParam = interner.intern(paramName)
                let typeParamFQName = aliasFQName + [internedParam]
                return symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
                    kind: .typeParameter,
                    name: internedParam,
                    fqName: typeParamFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
            }
            symbols.setTypeAliasTypeParameters(typeParamSymbols, for: aliasSymbol)
            underlyingArgs = typeParamSymbols.map { typeParamSymbol in
                .invariant(types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nullable))))
            }
        }
        let underlyingType = types.make(.classType(ClassType(
            classSymbol: targetSymbol,
            args: underlyingArgs,
            nullability: .nonNull
        )))
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
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

        let paramName = interner.intern("size")
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

    private func registerAtomicArrayOfNullsFactory(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let functionName = interner.intern("atomicArrayOfNulls")
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes == [types.intType]
                && signature.typeParameterSymbols.count == 1
        }) {
            symbols.setExternalLinkName("kk_atomic_ref_array_new", for: existing)
            return
        }

        guard let atomicArraySymbol = symbols.lookup(fqName: packageFQName + [interner.intern("AtomicArray")]) else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_atomic_ref_array_new", for: functionSymbol)

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nullable)))
        let returnType = types.make(.classType(ClassType(
            classSymbol: atomicArraySymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        let sizeName = interner.intern("size")
        let sizeSymbol = symbols.define(
            kind: .valueParameter,
            name: sizeName,
            fqName: functionFQName + [sizeName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: sizeSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [types.intType],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [sizeSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    private func registerAtomicArrayOfFactory(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        let functionName = interner.intern("atomicArrayOf")
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.count == 1
                && signature.valueParameterIsVararg.first == true
        }) {
            symbols.setExternalLinkName("kk_atomic_ref_array_of", for: existing)
            return
        }

        guard let atomicArraySymbol = symbols.lookup(fqName: packageFQName + [interner.intern("AtomicArray")]) else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_atomic_ref_array_of", for: functionSymbol)

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nonNull)))
        let returnType = types.make(.classType(ClassType(
            classSymbol: atomicArraySymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [typeParamType],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    private func registerAtomicAsJavaAtomicFunction(
        packageFQName: [InternedString],
        receiverPackageFQName: [InternedString],
        receiverName: String,
        javaAtomicName: String,
        externalLinkName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let receiverSymbol = symbols.lookup(
            fqName: receiverPackageFQName + [interner.intern(receiverName)]
        ) else {
            return
        }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: receiverSymbol,
            args: [],
            nullability: .nonNull
        )))
        let javaAtomicPackage = ensurePackage(
            path: ["java", "util", "concurrent", "atomic"],
            symbols: symbols,
            interner: interner
        )
        let javaAtomicSymbol = ensureClassSymbol(
            named: javaAtomicName,
            in: javaAtomicPackage,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: javaAtomicPackage) {
            symbols.setParentSymbol(packageSymbol, for: javaAtomicSymbol)
        }
        let javaAtomicType = types.make(.classType(ClassType(
            classSymbol: javaAtomicSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(javaAtomicType, for: javaAtomicSymbol)

        registerAtomicExtensionFunction(
            packageFQName: packageFQName,
            name: "asJavaAtomic",
            externalLinkName: externalLinkName,
            receiverType: receiverType,
            returnType: javaAtomicType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicReferenceAsJavaAtomicFunction(
        packageFQName: [InternedString],
        receiverPackageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let receiverSymbol = symbols.lookup(
            fqName: receiverPackageFQName + [interner.intern("AtomicReference")]
        ) else {
            return
        }

        let functionName = interner.intern("asJavaAtomic")
        let functionFQName = packageFQName + [functionName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: receiverSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        let javaAtomicPackage = ensurePackage(
            path: ["java", "util", "concurrent", "atomic"],
            symbols: symbols,
            interner: interner
        )
        let javaAtomicReferenceSymbol = ensureClassSymbol(
            named: "AtomicReference",
            in: javaAtomicPackage,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: javaAtomicPackage) {
            symbols.setParentSymbol(packageSymbol, for: javaAtomicReferenceSymbol)
        }
        let javaTypeParamFQName = javaAtomicPackage + [interner.intern("AtomicReference"), typeParamName]
        let javaTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: javaTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: javaTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let javaTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: javaTypeParamSymbol,
            nullability: .nonNull
        )))
        let javaAtomicReferenceType = types.make(.classType(ClassType(
            classSymbol: javaAtomicReferenceSymbol,
            args: [.invariant(javaTypeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([javaTypeParamSymbol], for: javaAtomicReferenceSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: javaAtomicReferenceSymbol)
        symbols.setPropertyType(javaAtomicReferenceType, for: javaAtomicReferenceSymbol)

        let returnType = types.make(.classType(ClassType(
            classSymbol: javaAtomicReferenceSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        registerAtomicExtensionFunction(
            packageFQName: packageFQName,
            name: "asJavaAtomic",
            externalLinkName: "kk_atomic_ref_asJavaAtomic",
            receiverType: receiverType,
            returnType: returnType,
            typeParameterSymbols: [typeParamSymbol],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicLongArrayAsJavaAtomicArrayFunction(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let receiverSymbol = symbols.lookup(
            fqName: packageFQName + [interner.intern("AtomicLongArray")]
        ) else {
            return
        }
        let receiverType = types.make(.classType(ClassType(
            classSymbol: receiverSymbol,
            args: [],
            nullability: .nonNull
        )))
        let javaAtomicPackage = ensurePackage(
            path: ["java", "util", "concurrent", "atomic"],
            symbols: symbols,
            interner: interner
        )
        let javaAtomicLongArraySymbol = ensureClassSymbol(
            named: "AtomicLongArray",
            in: javaAtomicPackage,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: javaAtomicPackage) {
            symbols.setParentSymbol(packageSymbol, for: javaAtomicLongArraySymbol)
        }
        let javaAtomicLongArrayType = types.make(.classType(ClassType(
            classSymbol: javaAtomicLongArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(javaAtomicLongArrayType, for: javaAtomicLongArraySymbol)

        registerAtomicExtensionFunction(
            packageFQName: packageFQName,
            name: "asJavaAtomicArray",
            externalLinkName: "kk_atomic_long_array_asJavaAtomicArray",
            receiverType: receiverType,
            returnType: javaAtomicLongArrayType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicAsKotlinAtomicFunctions(
        packageFQName: [InternedString],
        receiverPackageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaAtomicPackage = ensurePackage(
            path: ["java", "util", "concurrent", "atomic"],
            symbols: symbols,
            interner: interner
        )

        registerAtomicAsKotlinAtomicFunction(
            packageFQName: packageFQName,
            receiverPackageFQName: receiverPackageFQName,
            javaPackageFQName: javaAtomicPackage,
            javaClassName: "AtomicInteger",
            kotlinClassName: "AtomicInt",
            constructorLinkName: "kk_atomic_int_create",
            valueType: types.intType,
            externalLinkName: "kk_java_atomic_int_asKotlinAtomic",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicAsKotlinAtomicFunction(
            packageFQName: packageFQName,
            receiverPackageFQName: receiverPackageFQName,
            javaPackageFQName: javaAtomicPackage,
            javaClassName: "AtomicLong",
            kotlinClassName: "AtomicLong",
            constructorLinkName: "kk_atomic_long_create",
            valueType: types.longType,
            externalLinkName: "kk_java_atomic_long_asKotlinAtomic",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicAsKotlinAtomicFunction(
            packageFQName: packageFQName,
            receiverPackageFQName: receiverPackageFQName,
            javaPackageFQName: javaAtomicPackage,
            javaClassName: "AtomicBoolean",
            kotlinClassName: "AtomicBoolean",
            constructorLinkName: "kk_atomic_bool_create",
            valueType: types.make(.primitive(.boolean, .nonNull)),
            externalLinkName: "kk_java_atomic_bool_asKotlinAtomic",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerAtomicReferenceAsKotlinAtomicFunction(
            packageFQName: packageFQName,
            receiverPackageFQName: receiverPackageFQName,
            javaPackageFQName: javaAtomicPackage,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerAtomicAsKotlinAtomicFunction(
        packageFQName: [InternedString],
        receiverPackageFQName: [InternedString],
        javaPackageFQName: [InternedString],
        javaClassName: String,
        kotlinClassName: String,
        constructorLinkName: String,
        valueType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let kotlinAtomicSymbol = symbols.lookup(
            fqName: receiverPackageFQName + [interner.intern(kotlinClassName)]
        ) else {
            return
        }
        let kotlinAtomicType = types.make(.classType(ClassType(
            classSymbol: kotlinAtomicSymbol,
            args: [],
            nullability: .nonNull
        )))
        let javaAtomicSymbol = ensureClassSymbol(
            named: javaClassName,
            in: javaPackageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: javaPackageFQName) {
            symbols.setParentSymbol(packageSymbol, for: javaAtomicSymbol)
        }
        let javaAtomicType = types.make(.classType(ClassType(
            classSymbol: javaAtomicSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(javaAtomicType, for: javaAtomicSymbol)
        registerAtomicConstructor(
            ownerSymbol: javaAtomicSymbol,
            ownerType: javaAtomicType,
            externalLinkName: constructorLinkName,
            paramType: valueType,
            symbols: symbols,
            interner: interner
        )
        registerAtomicExtensionFunction(
            packageFQName: packageFQName,
            name: "asKotlinAtomic",
            externalLinkName: externalLinkName,
            receiverType: javaAtomicType,
            returnType: kotlinAtomicType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerAtomicReferenceAsKotlinAtomicFunction(
        packageFQName: [InternedString],
        receiverPackageFQName: [InternedString],
        javaPackageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let kotlinAtomicReferenceSymbol = symbols.lookup(
            fqName: receiverPackageFQName + [interner.intern("AtomicReference")]
        ) else {
            return
        }

        let javaAtomicReferenceName = interner.intern("AtomicReference")
        let javaAtomicReferenceSymbol = ensureClassSymbol(
            named: "AtomicReference",
            in: javaPackageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: javaPackageFQName) {
            symbols.setParentSymbol(packageSymbol, for: javaAtomicReferenceSymbol)
        }
        let classTypeParamName = interner.intern("T")
        let classTypeParamFQName = javaPackageFQName + [javaAtomicReferenceName, classTypeParamName]
        let classTypeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: classTypeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: classTypeParamName,
                fqName: classTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let classTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: classTypeParamSymbol,
            nullability: .nonNull
        )))
        let javaAtomicReferenceClassType = types.make(.classType(ClassType(
            classSymbol: javaAtomicReferenceSymbol,
            args: [.invariant(classTypeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([classTypeParamSymbol], for: javaAtomicReferenceSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: javaAtomicReferenceSymbol)
        symbols.setPropertyType(javaAtomicReferenceClassType, for: javaAtomicReferenceSymbol)
        registerAtomicConstructor(
            ownerSymbol: javaAtomicReferenceSymbol,
            ownerType: javaAtomicReferenceClassType,
            externalLinkName: "kk_atomic_ref_create",
            paramType: classTypeParamType,
            typeParameterSymbols: [classTypeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        let functionName = interner.intern("asKotlinAtomic")
        let functionFQName = packageFQName + [functionName]
        let functionTypeParamName = interner.intern("T")
        let functionTypeParamFQName = functionFQName + [functionTypeParamName]
        let functionTypeParamSymbol = symbols.lookup(fqName: functionTypeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: functionTypeParamName,
            fqName: functionTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let functionTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: functionTypeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: javaAtomicReferenceSymbol,
            args: [.invariant(functionTypeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: kotlinAtomicReferenceSymbol,
            args: [.invariant(functionTypeParamType)],
            nullability: .nonNull
        )))
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == [functionTypeParamSymbol]
        }) {
            symbols.setExternalLinkName("kk_java_atomic_ref_asKotlinAtomic", for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setParentSymbol(functionSymbol, for: functionTypeParamSymbol)
        symbols.setExternalLinkName("kk_java_atomic_ref_asKotlinAtomic", for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [functionTypeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    private func registerAtomicExtensionFunction(
        packageFQName: [InternedString],
        name: String,
        externalLinkName: String,
        receiverType: TypeID,
        returnType: TypeID,
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == typeParameterSymbols
                && signature.classTypeParameterCount == classTypeParameterCount
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: functionSymbol
        )
    }

    private func registerAtomicNativePtrSurface(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePtrType = nativeConcurrentClassType(
            packagePath: ["kotlinx", "cinterop"],
            name: "NativePtr",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let classSymbol = ensureClassSymbol(
            named: "AtomicNativePtr",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
        let ownerType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: classSymbol)

        registerNativeConcurrentConstructor(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            parameters: [(name: "value", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMutableProperty(
            ownerSymbol: classSymbol,
            name: "value",
            propertyType: nativePtrType,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "load",
            returnType: nativePtrType,
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "store",
            returnType: types.unitType,
            parameters: [(name: "value", type: nativePtrType)],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "exchange",
            returnType: nativePtrType,
            parameters: [(name: "new", type: nativePtrType)],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "getAndSet",
            returnType: nativePtrType,
            parameters: [(name: "newValue", type: nativePtrType)],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "compareAndSet",
            returnType: types.booleanType,
            parameters: [
                (name: "expect", type: nativePtrType),
                (name: "update", type: nativePtrType),
            ],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "compareAndExchange",
            returnType: nativePtrType,
            parameters: [
                (name: "expect", type: nativePtrType),
                (name: "update", type: nativePtrType),
            ],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        let transformType = types.make(.functionType(FunctionType(
            params: [nativePtrType],
            returnType: nativePtrType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: ownerType,
            name: "fetchAndUpdate",
            returnType: nativePtrType,
            parameters: [(name: "transform", type: transformType)],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerReadWriteLockConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        if let existing = symbols.lookupAll(fqName: ctorFQName).first(where: { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .constructor,
                  let sig = symbols.functionSignature(for: id)
            else { return false }
            return sig.parameterTypes.isEmpty
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

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
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: ownerType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
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
            flags: [.synthetic, .mutable]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(getterLinkName, for: propertySymbol)
        symbols.setPropertyType(valueType, for: propertySymbol)
    }

    private func registerAtomicReadOnlyProperty(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        propertyName: String,
        valueType: TypeID,
        getterLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propertyName = interner.intern(propertyName)
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
        includeGetAndSetAlias: Bool = false,
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
        if includeGetAndSetAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "getAndSet", externalLinkName: "\(prefix)_exchange",
                returnType: valueType, parameters: [(name: "newValue", type: valueType)],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
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
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        includeIncrementAndGetAlias: Bool = false,
        includeGetAndIncrementAlias: Bool = false,
        includeGetAndDecrementAlias: Bool = false,
        includeGetAndAddAlias: Bool = false,
        includeDecrementAndGetAlias: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        // fetchAndAdd(delta: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndAdd", externalLinkName: "\(prefix)_fetchAndAdd",
            returnType: valueType, parameters: [(name: "delta", type: valueType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeGetAndAddAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "getAndAdd", externalLinkName: "\(prefix)_fetchAndAdd",
                returnType: valueType, parameters: [(name: "delta", type: valueType)],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
        // addAndFetch(delta: T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "addAndFetch", externalLinkName: "\(prefix)_addAndFetch",
            returnType: valueType, parameters: [(name: "delta", type: valueType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        // fetchAndIncrement() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndIncrement", externalLinkName: "\(prefix)_fetchAndIncrement",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeGetAndIncrementAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "getAndIncrement", externalLinkName: "\(prefix)_fetchAndIncrement",
                returnType: valueType, parameters: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
        // fetchAndDecrement() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "fetchAndDecrement", externalLinkName: "\(prefix)_fetchAndDecrement",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeGetAndDecrementAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "getAndDecrement", externalLinkName: "\(prefix)_fetchAndDecrement",
                returnType: valueType, parameters: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
        // incrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "incrementAndFetch", externalLinkName: "\(prefix)_incrementAndFetch",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeIncrementAndGetAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "incrementAndGet", externalLinkName: "\(prefix)_incrementAndFetch",
                returnType: valueType, parameters: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
        // decrementAndFetch() -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "decrementAndFetch", externalLinkName: "\(prefix)_decrementAndFetch",
            returnType: valueType, parameters: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeDecrementAndGetAlias {
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "decrementAndGet", externalLinkName: "\(prefix)_decrementAndFetch",
                returnType: valueType, parameters: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
    }

    private func registerAtomicGetAndUpdateMethods(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        valueType: TypeID,
        prefix: String,
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        includeFetchAndUpdateAlias: Bool = false,
        includeUpdateAndFetchAlias: Bool = false,
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
        if includeFetchAndUpdateAlias {
            // fetchAndUpdate has the same old-value return contract as getAndUpdate.
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "fetchAndUpdate", externalLinkName: "\(prefix)_getAndUpdate",
                returnType: valueType, parameters: [(name: "transform", type: transformType)],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
        // updateAndGet(transform: (T) -> T) -> T
        registerAtomicMember(
            ownerSymbol: ownerSymbol, ownerType: ownerType,
            name: "updateAndGet", externalLinkName: "\(prefix)_updateAndGet",
            returnType: valueType, parameters: [(name: "transform", type: transformType)],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: classTypeParameterCount,
            symbols: symbols, interner: interner
        )
        if includeUpdateAndFetchAlias {
            // updateAndFetch has the same new-value return contract as updateAndGet.
            registerAtomicMember(
                ownerSymbol: ownerSymbol, ownerType: ownerType,
                name: "updateAndFetch", externalLinkName: "\(prefix)_updateAndGet",
                returnType: valueType, parameters: [(name: "transform", type: transformType)],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount,
                symbols: symbols, interner: interner
            )
        }
    }

    private func registerAtomicReferenceStubs(
        ownerPackage: [InternedString],
        ownerPackageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        externalLinkPrefix: String
    ) {
        let atomicRefSymbol = ensureClassSymbol(
            named: "AtomicReference",
            in: ownerPackage,
            symbols: symbols,
            interner: interner
        )
        if ownerPackageSymbol != .invalid {
            symbols.setParentSymbol(ownerPackageSymbol, for: atomicRefSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = ownerPackage + [interner.intern("AtomicReference"), typeParamName]
        let typeParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let atomicRefType = types.make(.classType(ClassType(
            classSymbol: atomicRefSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: atomicRefSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: atomicRefSymbol)
        symbols.setPropertyType(atomicRefType, for: atomicRefSymbol)

        registerAtomicConstructor(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            externalLinkName: "\(externalLinkPrefix)_create",
            paramType: typeParamType,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )

        registerAtomicValueProperty(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: typeParamType,
            getterLinkName: "\(externalLinkPrefix)_load",
            symbols: symbols,
            interner: interner
        )

        registerAtomicCoreMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: typeParamType,
            boolType: types.make(.primitive(.boolean, .nonNull)),
            unitType: types.unitType,
            prefix: externalLinkPrefix,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            includeGetAndSetAlias: true,
            symbols: symbols,
            interner: interner
        )

        registerAtomicGetAndUpdateMethods(
            ownerSymbol: atomicRefSymbol,
            ownerType: atomicRefType,
            valueType: typeParamType,
            prefix: externalLinkPrefix,
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            includeFetchAndUpdateAlias: true,
            includeUpdateAndFetchAlias: true,
            symbols: symbols,
            interner: interner,
            types: types
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
        flags: SymbolFlags = [.synthetic],
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
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: memberSymbol
        )
    }

    private func registerReadWriteLockFactory(
        packageFQName: [InternedString],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern("readWriteLock")
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes.isEmpty
                && existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName("kk_read_write_lock_create", for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_read_write_lock_create", for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
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
