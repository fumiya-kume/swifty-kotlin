import Foundation

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// Array<T> and primitive array types (TYPE-103) plus the synthetic factory function helper.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    // MARK: - Array<T> and primitive arrays (TYPE-103)

    func registerSyntheticArrayStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]

        // --- kotlin.Array<T> ---
        let arrayFQName = kotlinPkg + [interner.intern("Array")]
        let arraySymbol: SymbolID = if let existing = symbols.lookup(fqName: arrayFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: interner.intern("Array"),
                fqName: arrayFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let tParamName = interner.intern("T")
        let tParamSymbol = symbols.lookup(fqName: arrayFQName + [tParamName]) ?? symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: arrayFQName + [tParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([tParamSymbol], for: arraySymbol)
        types.setNominalTypeParameterVariances([.invariant], for: arraySymbol)
        let arrayTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))

        // Register size property for Array<T>
        let sizeReturnType = types.intType
        let sizeName = interner.intern("size")
        let sizeFQName = arrayFQName + [sizeName]
        if symbols.lookup(fqName: sizeFQName) == nil {
            let sizeSym = symbols.define(
                kind: .property,
                name: sizeName,
                fqName: sizeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: sizeSym)
            symbols.setPropertyType(sizeReturnType, for: sizeSym)
            symbols.setExternalLinkName("kk_array_size", for: sizeSym)
        }

        // Register toList() method for Array<T>
        let toListName = interner.intern("toList")
        let toListFQName = arrayFQName + [toListName]
        if symbols.lookup(fqName: toListFQName) == nil {
            let toListSym = symbols.define(
                kind: .function,
                name: toListName,
                fqName: toListFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: toListSym)
            symbols.setExternalLinkName("kk_array_toList", for: toListSym)
            
            // Get List<T> type for return type
            let listFQName = [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]
            if let listSymbol = symbols.lookup(fqName: listFQName) {
                let listElementType = types.make(.typeParam(TypeParamType(
                    symbol: tParamSymbol,
                    nullability: .nonNull
                )))
                let listReturnType = types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(listElementType)],
                    nullability: .nonNull
                )))
                
                let arrayReceiverType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [.invariant(listElementType)],
                    nullability: .nonNull
                )))
                
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: [],
                        returnType: listReturnType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: [tParamSymbol]
                    ),
                    for: toListSym
                )
            }
        }

        // --- STDLIB-410: arrayOf / emptyArray<T>() ---
        let emptyArrayName = interner.intern("emptyArray")
        let emptyArrayFQName = kotlinPkg + [emptyArrayName]
        if symbols.lookup(fqName: emptyArrayFQName) == nil {
            let emptyArraySymbol = symbols.define(
                kind: .function,
                name: emptyArrayName,
                fqName: emptyArrayFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(packageSymbol, for: emptyArraySymbol)
            }
            symbols.setExternalLinkName("kk_empty_array", for: emptyArraySymbol)
            let fnTypeParamName = interner.intern("T")
            let fnTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: fnTypeParamName,
                fqName: emptyArrayFQName + [fnTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(emptyArraySymbol, for: fnTypeParamSymbol)
            let elementType = types.make(.typeParam(TypeParamType(
                symbol: fnTypeParamSymbol,
                nullability: .nonNull
            )))
            let returnType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(elementType)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: returnType,
                    isSuspend: false,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [fnTypeParamSymbol]
                ),
                for: emptyArraySymbol
            )
        }

        let arrayOfNullsName = interner.intern("arrayOfNulls")
        let arrayOfNullsFQName = kotlinPkg + [arrayOfNullsName]
        if symbols.lookup(fqName: arrayOfNullsFQName) == nil {
            let arrayOfNullsSymbol = symbols.define(
                kind: .function,
                name: arrayOfNullsName,
                fqName: arrayOfNullsFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(packageSymbol, for: arrayOfNullsSymbol)
            }
            symbols.setExternalLinkName("kk_array_of_nulls", for: arrayOfNullsSymbol)

            let fnTypeParamName = interner.intern("T")
            let fnTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: fnTypeParamName,
                fqName: arrayOfNullsFQName + [fnTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arrayOfNullsSymbol, for: fnTypeParamSymbol)

            let sizeParamName = interner.intern("size")
            let sizeParamSymbol = symbols.define(
                kind: .valueParameter,
                name: sizeParamName,
                fqName: arrayOfNullsFQName + [sizeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arrayOfNullsSymbol, for: sizeParamSymbol)

            let elementType = types.make(.typeParam(TypeParamType(
                symbol: fnTypeParamSymbol,
                nullability: .nonNull
            )))
            let nullableElementType = types.makeNullable(elementType)
            let returnType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(nullableElementType)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [types.intType],
                    returnType: returnType,
                    isSuspend: false,
                    valueParameterSymbols: [sizeParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [fnTypeParamSymbol]
                ),
                for: arrayOfNullsSymbol
            )
        }

        let arrayOfName = interner.intern("arrayOf")
        let arrayOfFQName = kotlinPkg + [arrayOfName]
        if symbols.lookup(fqName: arrayOfFQName) == nil {
            let arrayOfSymbol = symbols.define(
                kind: .function,
                name: arrayOfName,
                fqName: arrayOfFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(packageSymbol, for: arrayOfSymbol)
            }
            symbols.setExternalLinkName("kk_array_of", for: arrayOfSymbol)
            let fnTypeParamName = interner.intern("T")
            let fnTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: fnTypeParamName,
                fqName: arrayOfFQName + [fnTypeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arrayOfSymbol, for: fnTypeParamSymbol)
            let elementType = types.make(.typeParam(TypeParamType(
                symbol: fnTypeParamSymbol,
                nullability: .nonNull
            )))
            let returnType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(elementType)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [elementType],
                    returnType: returnType,
                    isSuspend: false,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [true],
                    typeParameterSymbols: [fnTypeParamSymbol]
                ),
                for: arrayOfSymbol
            )
        }

        // --- Array extension functions: contentEquals, contentDeepEquals, contentDeepToString, contentDeepHashCode, contentHashCode, copyInto, reversedArray ---

        // contentEquals(other: Array<T>): Boolean
        let contentEqualsName = interner.intern("contentEquals")
        let contentEqualsFQName = arrayFQName + [contentEqualsName]
        if symbols.lookup(fqName: contentEqualsFQName) == nil {
            let contentEqualsSymbol = symbols.define(
                kind: .function,
                name: contentEqualsName,
                fqName: contentEqualsFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: contentEqualsSymbol)
            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let receiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            let otherArrayType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [otherArrayType],
                    returnType: types.booleanType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: contentEqualsSymbol
            )
            symbols.setExternalLinkName("kk_array_contentEquals", for: contentEqualsSymbol)
        }

        // contentToString(): String
        let contentToStringName = interner.intern("contentToString")
        let contentToStringFQName = arrayFQName + [contentToStringName]
        if symbols.lookup(fqName: contentToStringFQName) == nil {
            let contentToStringSymbol = symbols.define(
                kind: .function,
                name: contentToStringName,
                fqName: contentToStringFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: contentToStringSymbol)
            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let receiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: types.stringType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: contentToStringSymbol
            )
            symbols.setExternalLinkName("kk_array_contentToString", for: contentToStringSymbol)
        }

        // contentDeepEquals(other: Array<T>): Boolean
        let contentDeepEqualsName = interner.intern("contentDeepEquals")
        let contentDeepEqualsFQName = arrayFQName + [contentDeepEqualsName]
        if symbols.lookup(fqName: contentDeepEqualsFQName) == nil {
            let contentDeepEqualsSymbol = symbols.define(
                kind: .function,
                name: contentDeepEqualsName,
                fqName: contentDeepEqualsFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: contentDeepEqualsSymbol)
            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let receiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            let otherArrayType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [otherArrayType],
                    returnType: types.booleanType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: contentDeepEqualsSymbol
            )
            symbols.setExternalLinkName("kk_array_contentDeepEquals", for: contentDeepEqualsSymbol)
        }

        // contentHashCode(): Int
        let contentHashCodeName = interner.intern("contentHashCode")
        let contentHashCodeFQName = arrayFQName + [contentHashCodeName]
        if symbols.lookup(fqName: contentHashCodeFQName) == nil {
            let contentHashCodeSymbol = symbols.define(
                kind: .function,
                name: contentHashCodeName,
                fqName: contentHashCodeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: contentHashCodeSymbol)
            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let receiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: types.intType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: contentHashCodeSymbol
            )
            symbols.setExternalLinkName("kk_array_contentHashCode", for: contentHashCodeSymbol)
        }

        // contentDeepToString(): String
        let contentDeepToStringName = interner.intern("contentDeepToString")
        let contentDeepToStringFQName = arrayFQName + [contentDeepToStringName]
        if symbols.lookup(fqName: contentDeepToStringFQName) == nil {
            let contentDeepToStringSymbol = symbols.define(
                kind: .function,
                name: contentDeepToStringName,
                fqName: contentDeepToStringFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: contentDeepToStringSymbol)
            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let receiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: types.stringType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: contentDeepToStringSymbol
            )
            symbols.setExternalLinkName("kk_array_contentDeepToString", for: contentDeepToStringSymbol)
        }

        // contentDeepHashCode(): Int
        let contentDeepHashCodeName = interner.intern("contentDeepHashCode")
        let contentDeepHashCodeFQName = arrayFQName + [contentDeepHashCodeName]
        if symbols.lookup(fqName: contentDeepHashCodeFQName) == nil {
            let contentDeepHashCodeSymbol = symbols.define(
                kind: .function,
                name: contentDeepHashCodeName,
                fqName: contentDeepHashCodeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: contentDeepHashCodeSymbol)
            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let receiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: types.intType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: contentDeepHashCodeSymbol
            )
            symbols.setExternalLinkName("kk_array_contentDeepHashCode", for: contentDeepHashCodeSymbol)
        }

        // reversedArray(): Array<T>
        let reversedArrayName = interner.intern("reversedArray")
        let reversedArrayFQName = arrayFQName + [reversedArrayName]
        if symbols.lookup(fqName: reversedArrayFQName) == nil {
            let reversedArraySymbol = symbols.define(
                kind: .function,
                name: reversedArrayName,
                fqName: reversedArrayFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: reversedArraySymbol)
            symbols.setExternalLinkName("kk_array_reversedArray", for: reversedArraySymbol)

            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let arrayType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: arrayType,
                    parameterTypes: [],
                    returnType: arrayType,
                    isSuspend: false,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: reversedArraySymbol
            )
        }

        // copyInto(destination, destinationOffset, startIndex, endIndex): Array<T>
        let copyIntoName = interner.intern("copyInto")
        let copyIntoFQName = arrayFQName + [copyIntoName]
        if symbols.lookup(fqName: copyIntoFQName) == nil {
            let copyIntoSymbol = symbols.define(
                kind: .function,
                name: copyIntoName,
                fqName: copyIntoFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: copyIntoSymbol)
            symbols.setExternalLinkName("kk_array_copyInto", for: copyIntoSymbol)

            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let arrayType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            let parameterSymbols = ["destination", "destinationOffset", "startIndex", "endIndex"].map { parameterName in
                let internedParameterName = interner.intern(parameterName)
                let parameterSymbol = symbols.define(
                    kind: .valueParameter,
                    name: internedParameterName,
                    fqName: copyIntoFQName + [internedParameterName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(copyIntoSymbol, for: parameterSymbol)
                return parameterSymbol
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: arrayType,
                    parameterTypes: [arrayType, types.intType, types.intType, types.intType],
                    returnType: arrayType,
                    isSuspend: false,
                    valueParameterSymbols: parameterSymbols,
                    valueParameterHasDefaultValues: [false, true, true, true],
                    valueParameterIsVararg: [false, false, false, false],
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: copyIntoSymbol
            )
        }

        // Array.binarySearch(element, comparator, fromIndex, toIndex)
        // The comparator overload is patched to kotlin.Comparator<T> after the
        // Comparator synthetic stubs are registered.
        let binarySearchName = interner.intern("binarySearch")
        let binarySearchFQName = arrayFQName + [interner.intern(binarySearchCompareFQSuffix)]
        if symbols.lookup(fqName: binarySearchFQName) == nil {
            let arrayElementType = types.make(.typeParam(TypeParamType(
                symbol: tParamSymbol,
                nullability: .nonNull
            )))
            let arrayReceiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayElementType)],
                nullability: .nonNull
            )))
            let comparatorType = if let comparatorSymbol = symbols.lookupByShortName(interner.intern("Comparator")).first {
                types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(arrayElementType)],
                    nullability: .nonNull
                )))
            } else {
                types.make(.functionType(FunctionType(
                    params: [arrayElementType, arrayElementType],
                    returnType: types.intType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            }
            let memberSymbol = symbols.define(
                kind: .function,
                name: binarySearchName,
                fqName: binarySearchFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(arraySymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_array_binarySearch_compare", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: arrayReceiverType,
                    parameterTypes: [arrayElementType, comparatorType, types.intType, types.intType],
                    returnType: types.intType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [false, false, true, true],
                    valueParameterIsVararg: [false, false, false, false],
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        // Array.sortedArrayWith(comparator)
        // The comparator overload is patched to kotlin.Comparator<T> after the
        // Comparator synthetic stubs are registered.
        let sortedArrayWithName = interner.intern("sortedArrayWith")
        let sortedArrayWithFQName = arrayFQName + [sortedArrayWithName]
        if symbols.lookup(fqName: sortedArrayWithFQName) == nil {
            let arrayElementType = types.make(.typeParam(TypeParamType(
                symbol: tParamSymbol,
                nullability: .nonNull
            )))
            let arrayReceiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.out(arrayElementType)],
                nullability: .nonNull
            )))
            let comparatorType = if let comparatorSymbol = symbols.lookupByShortName(interner.intern("Comparator")).first {
                types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(arrayElementType)],
                    nullability: .nonNull
                )))
            } else {
                types.make(.functionType(FunctionType(
                    params: [arrayElementType, arrayElementType],
                    returnType: types.intType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            }
            let memberSymbol = symbols.define(
                kind: .function,
                name: sortedArrayWithName,
                fqName: sortedArrayWithFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            symbols.setParentSymbol(arraySymbol, for: memberSymbol)
            symbols.setExternalLinkName("kk_array_sortedArrayWith", for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: arrayReceiverType,
                    parameterTypes: [comparatorType],
                    returnType: arrayReceiverType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        if types.comparableInterfaceSymbol == nil {
            registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
        }
        let comparableElementBounds: [TypeID] = if let comparableSymbol = types.comparableInterfaceSymbol {
            [types.make(.classType(ClassType(
                classSymbol: comparableSymbol,
                args: [.in(arrayTypeParamType)],
                nullability: .nonNull
            )))]
        } else {
            []
        }

        // sortedArray(): Array<T>
        let sortedArrayName = interner.intern("sortedArray")
        let sortedArrayFQName = arrayFQName + [sortedArrayName]
        if symbols.lookup(fqName: sortedArrayFQName) == nil {
            let sortedArraySymbol = symbols.define(
                kind: .function,
                name: sortedArrayName,
                fqName: sortedArrayFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: sortedArraySymbol)
            symbols.setExternalLinkName("kk_array_sortedArray", for: sortedArraySymbol)
            let sortedArrayReceiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.out(arrayTypeParamType)],
                nullability: .nonNull
            )))
            let sortedArrayReturnType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParamType)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: sortedArrayReceiverType,
                    parameterTypes: [],
                    returnType: sortedArrayReturnType,
                    isSuspend: false,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [tParamSymbol],
                    typeParameterUpperBoundsList: [comparableElementBounds],
                    classTypeParameterCount: 1
                ),
                for: sortedArraySymbol
            )
        }

        // sortedArrayDescending(): Array<T>
        let sortedArrayDescendingName = interner.intern("sortedArrayDescending")
        let sortedArrayDescendingFQName = arrayFQName + [sortedArrayDescendingName]
        if symbols.lookup(fqName: sortedArrayDescendingFQName) == nil {
            let sortedArrayDescendingSymbol = symbols.define(
                kind: .function,
                name: sortedArrayDescendingName,
                fqName: sortedArrayDescendingFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: sortedArrayDescendingSymbol)
            symbols.setExternalLinkName("kk_array_sortedArrayDescending", for: sortedArrayDescendingSymbol)
            let sortedArrayReceiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.out(arrayTypeParamType)],
                nullability: .nonNull
            )))
            let sortedArrayReturnType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParamType)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: sortedArrayReceiverType,
                    parameterTypes: [],
                    returnType: sortedArrayReturnType,
                    isSuspend: false,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [tParamSymbol],
                    typeParameterUpperBoundsList: [comparableElementBounds],
                    classTypeParameterCount: 1
                ),
                for: sortedArrayDescendingSymbol
            )
        }

        // binarySearch(element, fromIndex, toIndex)
        let elementBinarySearchName = interner.intern("binarySearch")
        let elementBinarySearchFQName = arrayFQName + [elementBinarySearchName]
        if symbols.lookup(fqName: elementBinarySearchFQName) == nil {
            let binarySearchSymbol = symbols.define(
                kind: .function,
                name: elementBinarySearchName,
                fqName: elementBinarySearchFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: binarySearchSymbol)
            symbols.setExternalLinkName("kk_array_binarySearch", for: binarySearchSymbol)
            let binarySearchReceiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.out(arrayTypeParamType)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: binarySearchReceiverType,
                    parameterTypes: [arrayTypeParamType, types.intType, types.intType],
                    returnType: types.intType,
                    typeParameterSymbols: [tParamSymbol],
                    typeParameterUpperBoundsList: [comparableElementBounds],
                    classTypeParameterCount: 1
                ),
                for: binarySearchSymbol
            )
        }

        // --- Primitive array types: IntArray, LongArray, etc. ---
        let primitiveArrayNames = [
            "IntArray",
            "LongArray",
            "UIntArray",
            "ULongArray",
            "DoubleArray",
            "FloatArray",
            "BooleanArray",
            "CharArray",
            "ByteArray",
            "ShortArray",
            "UByteArray",
            "UShortArray",
        ]
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            // Ensure the class symbol exists, whether previously defined or not.
            let sym: SymbolID = if let existing = symbols.lookup(fqName: fqName) {
                existing
            } else {
                symbols.define(
                    kind: .class,
                    name: primName,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            // Register size property independently of class existence,
            // so that even if the class was defined elsewhere without size,
            // we still add the property.
            let primSizeFQName = fqName + [sizeName]
            if symbols.lookup(fqName: primSizeFQName) == nil {
                let primSizeSym = symbols.define(
                    kind: .property,
                    name: sizeName,
                    fqName: primSizeFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(sym, for: primSizeSym)
                symbols.setPropertyType(sizeReturnType, for: primSizeSym)
                
                // Set external link name for size property
                let sizeLinkName: String = switch name {
                case "IntArray": "kk_intArray_size"
                case "LongArray": "kk_longArray_size"
                case "ByteArray": "kk_byteArray_size"
                case "ShortArray": "kk_shortArray_size"
                case "UIntArray": "kk_uIntArray_size"
                case "ULongArray": "kk_uLongArray_size"
                case "DoubleArray": "kk_doubleArray_size"
                case "FloatArray": "kk_floatArray_size"
                case "BooleanArray": "kk_booleanArray_size"
                case "CharArray": "kk_charArray_size"
                case "UByteArray": "kk_uByteArray_size"
                case "UShortArray": "kk_uShortArray_size"
                default: "kk_array_size"
                }
                symbols.setExternalLinkName(sizeLinkName, for: primSizeSym)
            }
        }

        // Register toList() methods for primitive arrays
        let listFQName = [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]
        let listInterfaceSym = symbols.lookup(fqName: listFQName)
        
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }
            
            let toListName = interner.intern("toList")
            let toListFQName = fqName + [toListName]
            if symbols.lookup(fqName: toListFQName) == nil, let listInterfaceSym = listInterfaceSym {
                let toListSym = symbols.define(
                    kind: .function,
                    name: toListName,
                    fqName: toListFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: toListSym)
                
                let externalLinkName: String = switch name {
                case "IntArray": "kk_intArray_toList"
                case "LongArray": "kk_longArray_toList"
                case "ByteArray": "kk_byteArray_toList"
                case "ShortArray": "kk_shortArray_toList"
                case "UIntArray": "kk_uIntArray_toList"
                case "ULongArray": "kk_uLongArray_toList"
                case "DoubleArray": "kk_doubleArray_toList"
                case "FloatArray": "kk_floatArray_toList"
                case "BooleanArray": "kk_booleanArray_toList"
                case "CharArray": "kk_charArray_toList"
                case "UByteArray": "kk_uByteArray_toList"
                case "UShortArray": "kk_uShortArray_toList"
                default: "kk_array_toList"
                }
                symbols.setExternalLinkName(externalLinkName, for: toListSym)
                
                let elementType: TypeID = switch name {
                case "IntArray": types.intType
                case "LongArray": types.longType
                case "ByteArray": types.intType
                case "ShortArray": types.intType
                case "UIntArray": types.uintType
                case "ULongArray": types.ulongType
                case "DoubleArray": types.doubleType
                case "FloatArray": types.floatType
                case "BooleanArray": types.booleanType
                case "CharArray": types.charType
                case "UByteArray": types.ubyteType
                case "UShortArray": types.ushortType
                default: types.intType
                }
                
                let listReturnType = types.make(.classType(ClassType(
                    classSymbol: listInterfaceSym,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
                
                let arrayReceiverType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))
                
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: [],
                        returnType: listReturnType,
                        isSuspend: false
                    ),
                    for: toListSym
                )
            }
        }

        // Register asList() view methods for unsigned primitive arrays
        let unsignedPrimitiveArrayNames = [
            "UByteArray",
            "UShortArray",
            "UIntArray",
            "ULongArray",
        ]
        for name in unsignedPrimitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName), let listInterfaceSym = listInterfaceSym else {
                continue
            }

            let asListName = interner.intern("asList")
            let asListFQName = fqName + [asListName]
            if symbols.lookup(fqName: asListFQName) == nil {
                let asListSym = symbols.define(
                    kind: .function,
                    name: asListName,
                    fqName: asListFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: asListSym)

                let externalLinkName: String = switch name {
                case "UByteArray": "kk_uByteArray_asList"
                case "UShortArray": "kk_uShortArray_asList"
                case "UIntArray": "kk_uIntArray_asList"
                case "ULongArray": "kk_uLongArray_asList"
                default: "kk_array_toList"
                }
                symbols.setExternalLinkName(externalLinkName, for: asListSym)

                let elementType: TypeID = switch name {
                case "UByteArray": types.ubyteType
                case "UShortArray": types.ushortType
                case "UIntArray": types.uintType
                case "ULongArray": types.ulongType
                default: types.intType
                }

                let listReturnType = types.make(.classType(ClassType(
                    classSymbol: listInterfaceSym,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))

                let arrayReceiverType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: [],
                        returnType: listReturnType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: asListSym
                )
            }
        }

        // Register signed primitive array to unsigned primitive array view conversions.
        let unsignedViewConversions: [(source: String, target: String, member: String, external: String)] = [
            ("ByteArray", "UByteArray", "asUByteArray", "kk_byteArray_asUByteArray"),
            ("ShortArray", "UShortArray", "asUShortArray", "kk_shortArray_asUShortArray"),
            ("IntArray", "UIntArray", "asUIntArray", "kk_intArray_asUIntArray"),
            ("LongArray", "ULongArray", "asULongArray", "kk_longArray_asULongArray"),
        ]
        for conversion in unsignedViewConversions {
            let sourceFQName = kotlinPkg + [interner.intern(conversion.source)]
            let targetFQName = kotlinPkg + [interner.intern(conversion.target)]
            guard let sourceSymbol = symbols.lookup(fqName: sourceFQName),
                  let targetSymbol = symbols.lookup(fqName: targetFQName)
            else {
                continue
            }

            let memberName = interner.intern(conversion.member)
            let memberFQName = sourceFQName + [memberName]
            if symbols.lookup(fqName: memberFQName) == nil {
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: memberName,
                    fqName: memberFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(sourceSymbol, for: memberSymbol)
                symbols.setExternalLinkName(conversion.external, for: memberSymbol)

                let receiverType = types.make(.classType(ClassType(
                    classSymbol: sourceSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let returnType = types.make(.classType(ClassType(
                    classSymbol: targetSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: returnType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: memberSymbol
                )
            }
        }

        // Register toTypedArray() for unsigned primitive arrays.
        if let genericArraySymbol = symbols.lookup(fqName: arrayFQName) {
            for name in unsignedPrimitiveArrayNames {
                let primName = interner.intern(name)
                let fqName = kotlinPkg + [primName]
                guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                    continue
                }

                let toTypedArrayName = interner.intern("toTypedArray")
                let toTypedArrayFQName = fqName + [toTypedArrayName]
                if symbols.lookup(fqName: toTypedArrayFQName) == nil {
                    let toTypedArraySym = symbols.define(
                        kind: .function,
                        name: toTypedArrayName,
                        fqName: toTypedArrayFQName,
                        declSite: nil,
                        visibility: .public,
                        flags: [.synthetic]
                    )
                    symbols.setParentSymbol(arraySymbol, for: toTypedArraySym)
                    symbols.setExternalLinkName("kk_array_copyOf", for: toTypedArraySym)

                    let elementType: TypeID = switch name {
                    case "UByteArray": types.ubyteType
                    case "UShortArray": types.ushortType
                    case "UIntArray": types.uintType
                    case "ULongArray": types.ulongType
                    default: types.intType
                    }
                    let receiverType = types.make(.classType(ClassType(
                        classSymbol: arraySymbol,
                        args: [],
                        nullability: .nonNull
                    )))
                    let returnType = types.make(.classType(ClassType(
                        classSymbol: genericArraySymbol,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))

                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: receiverType,
                            parameterTypes: [],
                            returnType: returnType,
                            isSuspend: false,
                            valueParameterSymbols: [],
                            valueParameterHasDefaultValues: [],
                            valueParameterIsVararg: [],
                            typeParameterSymbols: []
                        ),
                        for: toTypedArraySym
                    )
                }
            }
        }

        // Register unsigned primitive array to signed primitive array view conversions.
        let signedViewConversions: [(source: String, target: String, member: String, external: String)] = [
            ("UByteArray", "ByteArray", "asByteArray", "kk_uByteArray_asByteArray"),
            ("UShortArray", "ShortArray", "asShortArray", "kk_uShortArray_asShortArray"),
            ("UIntArray", "IntArray", "asIntArray", "kk_uIntArray_asIntArray"),
            ("ULongArray", "LongArray", "asLongArray", "kk_uLongArray_asLongArray"),
        ]
        for conversion in signedViewConversions {
            let sourceFQName = kotlinPkg + [interner.intern(conversion.source)]
            let targetFQName = kotlinPkg + [interner.intern(conversion.target)]
            guard let sourceSymbol = symbols.lookup(fqName: sourceFQName),
                  let targetSymbol = symbols.lookup(fqName: targetFQName)
            else {
                continue
            }

            let memberName = interner.intern(conversion.member)
            let memberFQName = sourceFQName + [memberName]
            if symbols.lookup(fqName: memberFQName) == nil {
                let memberSymbol = symbols.define(
                    kind: .function,
                    name: memberName,
                    fqName: memberFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(sourceSymbol, for: memberSymbol)
                symbols.setExternalLinkName(conversion.external, for: memberSymbol)

                let receiverType = types.make(.classType(ClassType(
                    classSymbol: sourceSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let returnType = types.make(.classType(ClassType(
                    classSymbol: targetSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: returnType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: memberSymbol
                )
            }
        }

        // Register copyOf(newSize) and copyOf(newSize, init) for unsigned primitive arrays.
        for name in unsignedPrimitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let elementType: TypeID = switch name {
            case "UByteArray": types.ubyteType
            case "UShortArray": types.ushortType
            case "UIntArray": types.uintType
            case "ULongArray": types.ulongType
            default: types.intType
            }
            let arrayReceiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [],
                nullability: .nonNull
            )))
            let initFunctionType = types.make(.functionType(FunctionType(
                params: [types.intType],
                returnType: elementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let copyOfName = interner.intern("copyOf")
            let copyOfFQName = fqName + [copyOfName]

            func registerCopyOfOverload(
                parameterTypes: [TypeID],
                parameterNames: [String],
                parameterFQNameSuffix: String,
                externalLinkName: String,
                flags: SymbolFlags = [.synthetic]
            ) {
                let alreadyRegistered = symbols.lookupAll(fqName: copyOfFQName).contains { symbolID in
                    guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == arrayReceiverType
                        && sig.parameterTypes == parameterTypes
                        && sig.returnType == arrayReceiverType
                }
                guard !alreadyRegistered else { return }
                let copyOfSym = symbols.define(
                    kind: .function,
                    name: copyOfName,
                    fqName: copyOfFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: flags
                )
                symbols.setParentSymbol(arraySymbol, for: copyOfSym)
                symbols.setExternalLinkName(externalLinkName, for: copyOfSym)
                let parameterSymbols = parameterNames.map { parameterName -> SymbolID in
                    let internedParameterName = interner.intern(parameterName)
                    let parameterSymbol = symbols.define(
                        kind: .valueParameter,
                        name: internedParameterName,
                        fqName: copyOfFQName + [interner.intern("\(parameterName)$\(parameterFQNameSuffix)")],
                        declSite: nil,
                        visibility: .private,
                        flags: [.synthetic]
                    )
                    symbols.setParentSymbol(copyOfSym, for: parameterSymbol)
                    return parameterSymbol
                }
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: parameterTypes,
                        returnType: arrayReceiverType,
                        isSuspend: false,
                        valueParameterSymbols: parameterSymbols,
                        valueParameterHasDefaultValues: Array(repeating: false, count: parameterTypes.count),
                        valueParameterIsVararg: Array(repeating: false, count: parameterTypes.count),
                        typeParameterSymbols: []
                    ),
                    for: copyOfSym
                )
            }

            registerCopyOfOverload(
                parameterTypes: [types.intType],
                parameterNames: ["newSize"],
                parameterFQNameSuffix: "newSize",
                externalLinkName: "kk_array_copyOf_newSize"
            )
            registerCopyOfOverload(
                parameterTypes: [types.intType, initFunctionType],
                parameterNames: ["newSize", "init"],
                parameterFQNameSuffix: "newSizeInit",
                externalLinkName: "kk_array_copyOf_newSize_init",
                flags: [.synthetic, .inlineFunction, .throwingFunction]
            )
        }

        // Register copyOfRange(fromIndex, toIndex) for unsigned primitive arrays.
        for name in unsignedPrimitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let copyOfRangeName = interner.intern("copyOfRange")
            let copyOfRangeFQName = fqName + [copyOfRangeName]
            if symbols.lookup(fqName: copyOfRangeFQName) == nil {
                let copyOfRangeSym = symbols.define(
                    kind: .function,
                    name: copyOfRangeName,
                    fqName: copyOfRangeFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: copyOfRangeSym)
                symbols.setExternalLinkName("kk_array_copyOfRange", for: copyOfRangeSym)

                let arrayType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayType,
                        parameterTypes: [types.intType, types.intType],
                        returnType: arrayType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: copyOfRangeSym
                )
            }
        }

        // Register contentToString() methods for primitive arrays.
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let contentToStringName = interner.intern("contentToString")
            let contentToStringFQName = fqName + [contentToStringName]
            if symbols.lookup(fqName: contentToStringFQName) == nil {
                let contentToStringSym = symbols.define(
                    kind: .function,
                    name: contentToStringName,
                    fqName: contentToStringFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: contentToStringSym)

                let externalLinkName: String = switch name {
                case "IntArray": "kk_intArray_contentToString"
                case "LongArray": "kk_longArray_contentToString"
                case "ByteArray": "kk_byteArray_contentToString"
                case "ShortArray": "kk_shortArray_contentToString"
                case "UIntArray": "kk_uIntArray_contentToString"
                case "ULongArray": "kk_uLongArray_contentToString"
                case "DoubleArray": "kk_doubleArray_contentToString"
                case "FloatArray": "kk_floatArray_contentToString"
                case "BooleanArray": "kk_booleanArray_contentToString"
                case "CharArray": "kk_charArray_contentToString"
                case "UByteArray": "kk_uByteArray_contentToString"
                case "UShortArray": "kk_uShortArray_contentToString"
                default: "kk_array_contentToString"
                }
                symbols.setExternalLinkName(externalLinkName, for: contentToStringSym)

                let arrayReceiverType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: [],
                        returnType: types.stringType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: contentToStringSym
                )
            }
        }

        // Register reversedArray() and copyInto(destination, destinationOffset, startIndex, endIndex) for primitive arrays.
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let reversedArrayName = interner.intern("reversedArray")
            let reversedArrayFQName = fqName + [reversedArrayName]
            if symbols.lookup(fqName: reversedArrayFQName) == nil {
                let reversedArraySym = symbols.define(
                    kind: .function,
                    name: reversedArrayName,
                    fqName: reversedArrayFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: reversedArraySym)
                symbols.setExternalLinkName("kk_array_reversedArray", for: reversedArraySym)

                let arrayType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayType,
                        parameterTypes: [],
                        returnType: arrayType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: reversedArraySym
                )
            }

            let copyIntoName = interner.intern("copyInto")
            let copyIntoFQName = fqName + [copyIntoName]
            if symbols.lookup(fqName: copyIntoFQName) == nil {
                let copyIntoSym = symbols.define(
                    kind: .function,
                    name: copyIntoName,
                    fqName: copyIntoFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: copyIntoSym)
                symbols.setExternalLinkName("kk_array_copyInto", for: copyIntoSym)

                let arrayType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let parameterSymbols = ["destination", "destinationOffset", "startIndex", "endIndex"].map { parameterName in
                    let internedParameterName = interner.intern(parameterName)
                    let parameterSymbol = symbols.define(
                        kind: .valueParameter,
                        name: internedParameterName,
                        fqName: copyIntoFQName + [internedParameterName],
                        declSite: nil,
                        visibility: .private,
                        flags: [.synthetic]
                    )
                    symbols.setParentSymbol(copyIntoSym, for: parameterSymbol)
                    return parameterSymbol
                }

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayType,
                        parameterTypes: [arrayType, types.intType, types.intType, types.intType],
                        returnType: arrayType,
                        isSuspend: false,
                        valueParameterSymbols: parameterSymbols,
                        valueParameterHasDefaultValues: [false, true, true, true],
                        valueParameterIsVararg: [false, false, false, false],
                        typeParameterSymbols: []
                    ),
                    for: copyIntoSym
                )
            }
        }

        // Register sortedArray() for primitive arrays.
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let sortedArrayName = interner.intern("sortedArray")
            let sortedArrayFQName = fqName + [sortedArrayName]
            if symbols.lookup(fqName: sortedArrayFQName) == nil {
                let sortedArraySym = symbols.define(
                    kind: .function,
                    name: sortedArrayName,
                    fqName: sortedArrayFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: sortedArraySym)
                symbols.setExternalLinkName("kk_array_sortedArray", for: sortedArraySym)

                let arrayType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayType,
                        parameterTypes: [],
                        returnType: arrayType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: sortedArraySym
                )
            }
        }

        // Register sortedArrayDescending() for primitive arrays.
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let sortedArrayDescendingName = interner.intern("sortedArrayDescending")
            let sortedArrayDescendingFQName = fqName + [sortedArrayDescendingName]
            if symbols.lookup(fqName: sortedArrayDescendingFQName) == nil {
                let sortedArrayDescendingSym = symbols.define(
                    kind: .function,
                    name: sortedArrayDescendingName,
                    fqName: sortedArrayDescendingFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: sortedArrayDescendingSym)
                symbols.setExternalLinkName("kk_array_sortedArrayDescending", for: sortedArrayDescendingSym)

                let arrayType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayType,
                        parameterTypes: [],
                        returnType: arrayType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: sortedArrayDescendingSym
                )
            }
        }

        // Register binarySearch(element, fromIndex, toIndex) for primitive arrays.
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let binarySearchName = interner.intern("binarySearch")
            let binarySearchFQName = fqName + [binarySearchName]
            if symbols.lookup(fqName: binarySearchFQName) == nil {
                let binarySearchSym = symbols.define(
                    kind: .function,
                    name: binarySearchName,
                    fqName: binarySearchFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: binarySearchSym)

                let externalLinkName: String = switch name {
                case "IntArray": "kk_intArray_binarySearch"
                case "LongArray": "kk_longArray_binarySearch"
                case "ByteArray": "kk_byteArray_binarySearch"
                case "ShortArray": "kk_shortArray_binarySearch"
                case "UIntArray": "kk_uIntArray_binarySearch"
                case "ULongArray": "kk_uLongArray_binarySearch"
                case "DoubleArray": "kk_doubleArray_binarySearch"
                case "FloatArray": "kk_floatArray_binarySearch"
                case "BooleanArray": "kk_booleanArray_binarySearch"
                case "CharArray": "kk_charArray_binarySearch"
                case "UByteArray": "kk_uByteArray_binarySearch"
                case "UShortArray": "kk_uShortArray_binarySearch"
                default: "kk_array_binarySearch"
                }
                symbols.setExternalLinkName(externalLinkName, for: binarySearchSym)

                let elementType: TypeID = switch name {
                case "IntArray": types.intType
                case "LongArray": types.longType
                case "ByteArray": types.intType
                case "ShortArray": types.intType
                case "UIntArray": types.uintType
                case "ULongArray": types.ulongType
                case "DoubleArray": types.doubleType
                case "FloatArray": types.floatType
                case "BooleanArray": types.booleanType
                case "CharArray": types.charType
                case "UByteArray": types.ubyteType
                case "UShortArray": types.ushortType
                default: types.intType
                }

                let arrayReceiverType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: [elementType, types.intType, types.intType],
                        returnType: types.intType,
                        isSuspend: false
                    ),
                    for: binarySearchSym
                )
            }
        }

        let primitiveArrayFactoryTypes: [(String, String, TypeID)] = [
            ("intArrayOf", "IntArray", types.intType),
            ("longArrayOf", "LongArray", types.longType),
            ("doubleArrayOf", "DoubleArray", types.doubleType),
            ("floatArrayOf", "FloatArray", types.floatType),
            ("booleanArrayOf", "BooleanArray", types.booleanType),
            ("charArrayOf", "CharArray", types.charType),
            ("byteArrayOf", "ByteArray", types.intType),
            ("shortArrayOf", "ShortArray", types.intType),
            ("ubyteArrayOf", "UByteArray", types.ubyteType),
            ("ushortArrayOf", "UShortArray", types.ushortType),
            ("uintArrayOf", "UIntArray", types.uintType),
            ("ulongArrayOf", "ULongArray", types.ulongType),
        ]
        for (factoryName, arrayName, elementType) in primitiveArrayFactoryTypes {
            guard let primitiveArraySymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern(arrayName)]) else {
                continue
            }
            let returnType = types.make(.classType(ClassType(
                classSymbol: primitiveArraySymbol,
                args: [],
                nullability: .nonNull
            )))
            registerSyntheticArrayFactoryFunction(
                named: factoryName,
                packageFQName: kotlinPkg,
                returnType: returnType,
                valueParameterTypes: [elementType],
                valueParameterIsVararg: [true],
                typeParamNames: [],
                externalLinkName: "kk_array_of",
                symbols: symbols,
                interner: interner
            )
        }

    }

    private func registerSyntheticArrayFactoryFunction(
        named name: String,
        packageFQName: [InternedString],
        returnType: TypeID,
        valueParameterTypes: [TypeID],
        valueParameterIsVararg: [Bool],
        typeParamNames: [String],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else { return }

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

        var typeParameterSymbols: [SymbolID] = []
        for paramName in typeParamNames {
            let typeParamName = interner.intern(paramName)
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: functionFQName + [typeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
            typeParameterSymbols.append(typeParamSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: valueParameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterTypes.count),
                valueParameterIsVararg: valueParameterIsVararg,
                typeParameterSymbols: typeParameterSymbols
            ),
            for: functionSymbol
        )
    }
}
