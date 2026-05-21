/// `List<E>.toList` / `toMutableList` / `toTypeArray` / `toIntArray` / `toDoubleArray` /
/// `toBooleanArray` / etc. conversion members extracted from
/// `HeaderHelpers+SyntheticListStubs.swift`.
extension DataFlowSemaPhase {
    func registerListConversionMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID,
        mapInterfaceSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID
    ) {
        guard let listTypeParamSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("List"), interner.intern("E")]
        ),
            let mutableListSymbol = symbols.lookup(
                fqName: kotlinCollectionsPkg + [interner.intern("MutableList")]
            ),
            let setInterfaceSymbol = symbols.lookup(
                fqName: kotlinCollectionsPkg + [interner.intern("Set")]
            ),
            let mutableSetInterfaceSymbol = symbols.lookup(
                fqName: kotlinCollectionsPkg + [interner.intern("MutableSet")]
            )
        else {
            return
        }
        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol, nullability: .nonNull
        )))
        registerListToMutableListMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            mutableListSymbol: mutableListSymbol
        )
        registerListToSetMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            setInterfaceSymbol: setInterfaceSymbol
        )
        registerListToMapMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            mapInterfaceSymbol: mapInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        let iterableSymbolForOps = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("Iterable")]
        ) ?? collectionInterfaceSymbol
        registerListSetOperationMembers(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            setInterfaceSymbol: setInterfaceSymbol,
            iterableInterfaceSymbol: iterableSymbolForOps
        )
        registerListToHashSetMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol
        )
        // STDLIB-651: List.toMutableSet() → kk_list_to_mutable_set
        registerListToMutableSetMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            mutableSetInterfaceSymbol: mutableSetInterfaceSymbol
        )
        registerListAsSequenceMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        registerListToGenericArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType,
            memberName: "toTypeArray",
            externalLinkName: "kk_list_toTypedArray"
        )
        let kotlinPkg = [interner.intern("kotlin")]
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toCharArray",
            arrayTypeName: "CharArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toCharArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toBooleanArray",
            arrayTypeName: "BooleanArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toBooleanArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toShortArray",
            arrayTypeName: "ShortArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toShortArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toDoubleArray",
            arrayTypeName: "DoubleArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toDoubleArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toFloatArray",
            arrayTypeName: "FloatArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toFloatArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toIntArray",
            arrayTypeName: "IntArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toIntArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toLongArray",
            arrayTypeName: "LongArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toLongArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toByteArray",
            arrayTypeName: "ByteArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toByteArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toUByteArray",
            arrayTypeName: "UByteArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toUByteArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toUShortArray",
            arrayTypeName: "UShortArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toUShortArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toUIntArray",
            arrayTypeName: "UIntArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toUIntArray"
        )
        registerListToPrimitiveArrayMember(
            symbols: symbols, types: types, interner: interner,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            memberName: "toULongArray",
            arrayTypeName: "ULongArray",
            arrayPackage: kotlinPkg,
            externalLinkName: "kk_list_toULongArray"
        )
    }

    /// Register a `List<E>.toTypeArray(): Array<E>` conversion member stub.
    private func registerListToGenericArrayMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        memberName: String,
        externalLinkName: String
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else {
            return
        }
        let arraySymbol = ensureClassSymbol(
            named: "Array",
            in: [interner.intern("kotlin")],
            symbols: symbols,
            interner: interner
        )

        let internedMemberName = interner.intern(memberName)
        let memberFQName = listFQName + [internedMemberName]
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(listTypeParamType)],
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: internedMemberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register a `List<E>.toXxxArray(): XxxArray` conversion member stub.
    ///
    /// Used for `toIntArray`, `toLongArray`, and `toByteArray` (STDLIB-LIST-PRIM-ARRAY).
    private func registerListToPrimitiveArrayMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        memberName: String,
        arrayTypeName: String,
        arrayPackage: [InternedString],
        externalLinkName: String
    ) {
        guard let listFQName = symbols.symbol(listInterfaceSymbol)?.fqName else { return }
        let internedMemberName = interner.intern(memberName)
        let memberFQName = listFQName + [internedMemberName]

        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol, nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))

        let arraySymbol = ensureClassSymbol(
            named: arrayTypeName,
            in: arrayPackage,
            symbols: symbols,
            interner: interner
        )
        
        // Ensure the primitive array has size property and toList() method
        let sizeName = interner.intern("size")
        let sizeFQName = arrayPackage + [interner.intern(arrayTypeName), sizeName]
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
            symbols.setPropertyType(types.intType, for: sizeSym)
            
            // Set external link name for size property
            let sizeLinkName: String = switch arrayTypeName {
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
            symbols.setExternalLinkName(sizeLinkName, for: sizeSym)
        }
        
        // Also register toList() method for this primitive array
        let toListName = interner.intern("toList")
        let toListFQName = arrayPackage + [interner.intern(arrayTypeName), toListName]
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
            
            let externalLinkName: String = switch arrayTypeName {
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
            
            // Get List interface for return type
            let listFQName = [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]
            if let listSymbol = symbols.lookup(fqName: listFQName) {
                let elementType: TypeID = switch arrayTypeName {
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
                    classSymbol: listSymbol,
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
        
        guard symbols.lookup(fqName: memberFQName) == nil else { return }

        let returnType = types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [],
            nullability: .nonNull
        )))

        let memberSymbol = symbols.define(
            kind: .function,
            name: internedMemberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    /// Register `kotlin.collections.MutableList<E>` interface stub with `operator fun set(index: Int, element: E): E`.
}
