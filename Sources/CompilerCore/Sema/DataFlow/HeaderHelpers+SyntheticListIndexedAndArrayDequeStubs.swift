import Foundation

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// List indexed members, IndexedValue<T>, and ArrayDeque<T>.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    func registerListIndexedMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))

        // withIndex(): Iterable<IndexedValue<E>>
        let indexedValueSymbol = registerSyntheticIndexedValueStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        let indexedValueType = types.make(.classType(ClassType(
            classSymbol: indexedValueSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let iterableSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("Iterable")]) ?? listInterfaceSymbol
        let iterableIndexedValueType = types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(indexedValueType)],
            nullability: .nonNull
        )))
        let listSymbol = listInterfaceSymbol

        let withIndexName = interner.intern("withIndex")
        let withIndexFQName = listFQName + [withIndexName]
        if symbols.lookup(fqName: withIndexFQName) == nil {
            let memberSymbol = symbols.define(
                kind: .function,
                name: withIndexName,
                fqName: withIndexFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_withIndex", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: iterableIndexedValueType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // forEachIndexed(action: (Int, E) -> Unit)
        let forEachIndexedName = interner.intern("forEachIndexed")
        let forEachIndexedFQName = listFQName + [forEachIndexedName]
        if symbols.lookup(fqName: forEachIndexedFQName) == nil {
            let actionType = types.make(.functionType(FunctionType(
                params: [types.intType, listTypeParamType],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: forEachIndexedName,
                fqName: forEachIndexedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_forEachIndexed", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [actionType],
                    returnType: types.unitType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // mapIndexed(transform: (Int, E) -> R): List<R>
        let mapIndexedName = interner.intern("mapIndexed")
        let mapIndexedFQName = listFQName + [mapIndexedName]
        if symbols.lookup(fqName: mapIndexedFQName) == nil {
            // mapIndexed is tricky because of the generic R.
            // For synthetic stub, we might simplify to List<Any?> or just have it resolve via fallback if generic R is hard to define here.
            // But let's try to define a local type parameter R for the function.
            let rName = interner.intern("R")
            let rFQName = mapIndexedFQName + [rName]
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: rFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))

            let transformType = types.make(.functionType(FunctionType(
                params: [types.intType, listTypeParamType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let listRType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(rType)],
                nullability: .nonNull
            )))

            let memberSymbol = symbols.define(
                kind: .function,
                name: mapIndexedName,
                fqName: mapIndexedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_mapIndexed", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [transformType],
                    returnType: listRType,
                    typeParameterSymbols: [listTypeParamSymbol, rSymbol],
                    classTypeParameterCount: 1 // Only List's E is class-level
                ),
                for: memberSymbol
            )
        }

        // filterIndexed(predicate: (Int, T) -> Boolean): List<T>
        let filterIndexedName = interner.intern("filterIndexed")
        let filterIndexedFQName = listFQName + [filterIndexedName]
        if symbols.lookup(fqName: filterIndexedFQName) == nil {
            let predicateType = types.make(.functionType(FunctionType(
                params: [types.intType, listTypeParamType],
                returnType: types.booleanType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memberSymbol = symbols.define(
                kind: .function,
                name: filterIndexedName,
                fqName: filterIndexedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_filterIndexed", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [predicateType],
                    returnType: receiverType,
                    typeParameterSymbols: [listTypeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // foldIndexed(initial: R, operation: (Int, R, T) -> R): R
        let foldIndexedName = interner.intern("foldIndexed")
        let foldIndexedFQName = listFQName + [foldIndexedName]
        if symbols.lookup(fqName: foldIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = foldIndexedFQName + [rName]
            let rSymbol = symbols.define(kind: .typeParameter, name: rName, fqName: rFQName, declSite: nil, visibility: .private, flags: [])
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, rType, listTypeParamType], returnType: rType, isSuspend: false, nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: foldIndexedName, fqName: foldIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_foldIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [rType, operationType], returnType: rType, typeParameterSymbols: [listTypeParamSymbol, rSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // reduceIndexed(operation: (Int, S, T) -> S): S
        let reduceIndexedName = interner.intern("reduceIndexed")
        let reduceIndexedFQName = listFQName + [reduceIndexedName]
        if symbols.lookup(fqName: reduceIndexedFQName) == nil {
            let sName = interner.intern("S")
            let sFQName = reduceIndexedFQName + [sName]
            let sSymbol = symbols.define(kind: .typeParameter, name: sName, fqName: sFQName, declSite: nil, visibility: .private, flags: [])
            let sType = types.make(.typeParam(TypeParamType(symbol: sSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, sType, listTypeParamType], returnType: sType, isSuspend: false, nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: reduceIndexedName, fqName: reduceIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_reduceIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [operationType], returnType: sType, typeParameterSymbols: [listTypeParamSymbol, sSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // reduceIndexedOrNull(operation: (Int, S, T) -> S): S?
        let reduceIndexedOrNullName = interner.intern("reduceIndexedOrNull")
        let reduceIndexedOrNullFQName = listFQName + [reduceIndexedOrNullName]
        if symbols.lookup(fqName: reduceIndexedOrNullFQName) == nil {
            let sName = interner.intern("S")
            let sFQName = reduceIndexedOrNullFQName + [sName]
            let sSymbol = symbols.define(kind: .typeParameter, name: sName, fqName: sFQName, declSite: nil, visibility: .private, flags: [])
            let sType = types.make(.typeParam(TypeParamType(symbol: sSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, sType, listTypeParamType], returnType: sType, isSuspend: false, nullability: .nonNull)))
            let nullableAccumulatorType = types.makeNullable(sType)
            let memberSymbol = symbols.define(kind: .function, name: reduceIndexedOrNullName, fqName: reduceIndexedOrNullFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_reduceIndexedOrNull", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [operationType], returnType: nullableAccumulatorType, typeParameterSymbols: [listTypeParamSymbol, sSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // runningFoldIndexed(initial: R, operation: (Int, R, T) -> R): List<R>
        let runningFoldIndexedName = interner.intern("runningFoldIndexed")
        let runningFoldIndexedFQName = listFQName + [runningFoldIndexedName]
        if symbols.lookup(fqName: runningFoldIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = runningFoldIndexedFQName + [rName]
            let rSymbol = symbols.define(kind: .typeParameter, name: rName, fqName: rFQName, declSite: nil, visibility: .private, flags: [])
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, rType, listTypeParamType], returnType: rType, isSuspend: false, nullability: .nonNull)))
            let listRType = types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(rType)], nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: runningFoldIndexedName, fqName: runningFoldIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_runningFoldIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [rType, operationType], returnType: listRType, typeParameterSymbols: [listTypeParamSymbol, rSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // runningReduceIndexed(operation: (Int, S, T) -> S): List<S>
        let runningReduceIndexedName = interner.intern("runningReduceIndexed")
        let runningReduceIndexedFQName = listFQName + [runningReduceIndexedName]
        if symbols.lookup(fqName: runningReduceIndexedFQName) == nil {
            let sName = interner.intern("S")
            let sFQName = runningReduceIndexedFQName + [sName]
            let sSymbol = symbols.define(kind: .typeParameter, name: sName, fqName: sFQName, declSite: nil, visibility: .private, flags: [])
            let sType = types.make(.typeParam(TypeParamType(symbol: sSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, sType, listTypeParamType], returnType: sType, isSuspend: false, nullability: .nonNull)))
            let listSType = types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(sType)], nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: runningReduceIndexedName, fqName: runningReduceIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_runningReduceIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [operationType], returnType: listSType, typeParameterSymbols: [listTypeParamSymbol, sSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // scanIndexed(initial: R, operation: (Int, R, T) -> R): List<R>
        let scanIndexedName = interner.intern("scanIndexed")
        let scanIndexedFQName = listFQName + [scanIndexedName]
        if symbols.lookup(fqName: scanIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = scanIndexedFQName + [rName]
            let rSymbol = symbols.define(kind: .typeParameter, name: rName, fqName: rFQName, declSite: nil, visibility: .private, flags: [])
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, rType, listTypeParamType], returnType: rType, isSuspend: false, nullability: .nonNull)))
            let listRType = types.make(.classType(ClassType(classSymbol: listSymbol, args: [.out(rType)], nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: scanIndexedName, fqName: scanIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_scanIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [rType, operationType], returnType: listRType, typeParameterSymbols: [listTypeParamSymbol, rSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // foldRight(initial: R, operation: (T, acc: R) -> R): R
        let foldRightName = interner.intern("foldRight")
        let foldRightFQName = listFQName + [foldRightName]
        if symbols.lookup(fqName: foldRightFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = foldRightFQName + [rName]
            let rSymbol = symbols.define(kind: .typeParameter, name: rName, fqName: rFQName, declSite: nil, visibility: .private, flags: [])
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [listTypeParamType, rType], returnType: rType, isSuspend: false, nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: foldRightName, fqName: foldRightFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_foldRight", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [rType, operationType], returnType: rType, typeParameterSymbols: [listTypeParamSymbol, rSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // foldRightIndexed(initial: R, operation: (index: Int, T, acc: R) -> R): R
        let foldRightIndexedName = interner.intern("foldRightIndexed")
        let foldRightIndexedFQName = listFQName + [foldRightIndexedName]
        if symbols.lookup(fqName: foldRightIndexedFQName) == nil {
            let rName = interner.intern("R")
            let rFQName = foldRightIndexedFQName + [rName]
            let rSymbol = symbols.define(kind: .typeParameter, name: rName, fqName: rFQName, declSite: nil, visibility: .private, flags: [])
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [types.intType, listTypeParamType, rType], returnType: rType, isSuspend: false, nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: foldRightIndexedName, fqName: foldRightIndexedFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_foldRightIndexed", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [rType, operationType], returnType: rType, typeParameterSymbols: [listTypeParamSymbol, rSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }

        // reduceRight(operation: (T, acc: S) -> S): S
        let reduceRightName = interner.intern("reduceRight")
        let reduceRightFQName = listFQName + [reduceRightName]
        if symbols.lookup(fqName: reduceRightFQName) == nil {
            let sName = interner.intern("S")
            let sFQName = reduceRightFQName + [sName]
            let sSymbol = symbols.define(kind: .typeParameter, name: sName, fqName: sFQName, declSite: nil, visibility: .private, flags: [])
            let sType = types.make(.typeParam(TypeParamType(symbol: sSymbol, nullability: .nonNull)))
            let operationType = types.make(.functionType(FunctionType(params: [listTypeParamType, sType], returnType: sType, isSuspend: false, nullability: .nonNull)))
            let memberSymbol = symbols.define(kind: .function, name: reduceRightName, fqName: reduceRightFQName, declSite: nil, visibility: .public, flags: [.synthetic, .inlineFunction])
            symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_list_reduceRight", for: memberSymbol)
            symbols.setFunctionSignature(FunctionSignature(receiverType: receiverType, parameterTypes: [operationType], returnType: sType, typeParameterSymbols: [listTypeParamSymbol, sSymbol], classTypeParameterCount: 1), for: memberSymbol)
        }
    }

    private func registerSyntheticIndexedValueStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let name = interner.intern("IndexedValue")
        let fqName = kotlinCollectionsPkg + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        let symbol = symbols.define(
            kind: .class,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .dataType]
        )
        let tName = interner.intern("T")
        let tFQName = fqName + [tName]
        let tSymbol = symbols.define(
            kind: .typeParameter,
            name: tName,
            fqName: tFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let tType = types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([tSymbol], for: symbol)
        types.setNominalTypeParameterVariances([.out], for: symbol)

        // Add index: Int and value: T properties (component1, component2 for destructuring)
        let receiverType = types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [.out(tType)],
            nullability: .nonNull
        )))

        func registerComponent(name: String, ret: TypeID, externalLinkName: String) {
            let mName = interner.intern(name)
            let mFQName = fqName + [mName]
            let mSymbol = symbols.define(
                kind: .function,
                name: mName,
                fqName: mFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .operatorFunction]
            )
            symbols.setParentSymbol(symbol, for: mSymbol)
            symbols.setExternalLinkName(externalLinkName, for: mSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: ret,
                    typeParameterSymbols: [tSymbol],
                    classTypeParameterCount: 1
                ),
                for: mSymbol
            )
        }

        func registerPropertyGetter(name: String, ret: TypeID, externalLinkName: String) {
            let mName = interner.intern(name)
            let mFQName = fqName + [mName]
            let mSymbol = symbols.define(
                kind: .property,
                name: mName,
                fqName: mFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(symbol, for: mSymbol)
            symbols.setExternalLinkName(externalLinkName, for: mSymbol)
            symbols.setPropertyType(ret, for: mSymbol)
        }

        registerComponent(name: "component1", ret: types.intType, externalLinkName: "kk_pair_first")
        registerComponent(name: "component2", ret: tType, externalLinkName: "kk_pair_second")
        registerPropertyGetter(name: "index", ret: types.intType, externalLinkName: "kk_pair_first")
        registerPropertyGetter(name: "value", ret: tType, externalLinkName: "kk_pair_second")

        return symbol
    }

    // MARK: - ArrayDeque (STDLIB-240)

    func registerSyntheticArrayDequeStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let arrayDequeName = interner.intern("ArrayDeque")
        let arrayDequeFQName = kotlinCollectionsPkg + [arrayDequeName]
        let arrayDequeSymbol: SymbolID = if let existing = symbols.lookup(fqName: arrayDequeFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: arrayDequeName,
                fqName: arrayDequeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Define type parameter E for ArrayDeque<E>
        let typeParamName = interner.intern("E")
        let typeParamFQName = arrayDequeFQName + [typeParamName]
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol, nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: arrayDequeSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: arrayDequeSymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: arrayDequeSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        // Constructor: ArrayDeque() → kk_arraydeque_new
        let initName = interner.intern("<init>")
        let initFQName = arrayDequeFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arrayDequeSymbol, for: initSymbol)
            symbols.setExternalLinkName("kk_arraydeque_new", for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: receiverType,
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        // addFirst(element: E): Unit
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "addFirst", externalName: "kk_arraydeque_addFirst",
            parameterTypes: [typeParamType], returnType: types.unitType
        )

        // addLast(element: E): Unit
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "addLast", externalName: "kk_arraydeque_addLast",
            parameterTypes: [typeParamType], returnType: types.unitType
        )

        // removeFirst(): E (can throw)
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "removeFirst", externalName: "kk_arraydeque_removeFirst",
            parameterTypes: [], returnType: typeParamType
        )

        // removeLast(): E (can throw)
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "removeLast", externalName: "kk_arraydeque_removeLast",
            parameterTypes: [], returnType: typeParamType
        )

        // first(): E (can throw)
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "first", externalName: "kk_arraydeque_first",
            parameterTypes: [], returnType: typeParamType
        )

        // last(): E (can throw)
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "last", externalName: "kk_arraydeque_last",
            parameterTypes: [], returnType: typeParamType
        )

        // size: Int (property-like)
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "size", externalName: "kk_arraydeque_size",
            parameterTypes: [], returnType: types.intType
        )

        // isEmpty(): Boolean
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "isEmpty", externalName: "kk_arraydeque_isEmpty",
            parameterTypes: [], returnType: types.booleanType
        )

        // toString(): String
        registerArrayDequeMember(
            symbols: symbols, types: types, interner: interner,
            fqName: arrayDequeFQName, parentSymbol: arrayDequeSymbol,
            receiverType: receiverType, typeParamSymbol: typeParamSymbol,
            memberName: "toString", externalName: "kk_arraydeque_toString",
            parameterTypes: [], returnType: types.stringType
        )
    }

    private func registerArrayDequeMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        fqName: [InternedString],
        parentSymbol: SymbolID,
        receiverType: TypeID,
        typeParamSymbol: SymbolID,
        memberName: String,
        externalName: String,
        parameterTypes: [TypeID],
        returnType: TypeID
    ) {
        let internedName = interner.intern(memberName)
        let memberFQName = fqName + [internedName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }
        let memberSymbol = symbols.define(
            kind: .function,
            name: internedName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(parentSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalName, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Create a type parameter `R` with upper bound `Comparable<R>` for use in
    /// selector-based HOF stubs (sortedBy, sortedByDescending, maxByOrNull, etc.).
    ///
    /// When `Comparable` is not yet registered, the `R` parameter is omitted and
    /// `selectorReturnType` falls back to `Any`, avoiding an unconstrained generic.
    ///
    /// - Returns: A tuple of `(rSymbol, rType, comparableRBounds)` when the
    ///   Comparable interface is available, or `nil` when it is not.
}
