
/// Synthetic stdlib stubs split from the KSP-697 collection residual registry:
/// Array<T> and primitive array types (TYPE-103) plus the synthetic factory function helper.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    // MARK: - Array<T> and primitive arrays (TYPE-103)

    func registerSyntheticArrayStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        skipStats: SyntheticStubSkipStatsCollector? = nil
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
        // KSP-657: arrayOf / emptyArray / arrayOfNulls factories are now declared
        // as bundled Kotlin intrinsics in Stdlib/kotlin/ArrayIntrinsics.kt.

        // --- Array extension functions ---
        //
        // KSP-658: generic Array<T>.contentEquals / contentToString / copyOf /
        // copyOfRange are bundled Kotlin source
        // (Stdlib/kotlin/collections/ArrayContentAndCopy.kt); their synthetic
        // stubs were removed so source resolution takes precedence.

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
        // Keep primitive array class shells synthetic for the primitive type
        // system. Their `size` / conversion members are bundled Kotlin source.
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .class,
                    name: primName,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }

        // KSP-660: ByteArray/ShortArray/IntArray/LongArray -> unsigned array view
        // conversions (asUByteArray/asUShortArray/asUIntArray/asULongArray) are now
        // implemented in bundled Kotlin (Stdlib/kotlin/collections/UArrays.kt), which
        // delegates to the __kk_*_asU*Array runtime bridges.

        // KSP-660: UByteArray/UShortArray/UIntArray/ULongArray -> signed array view
        // conversions (asByteArray/asShortArray/asIntArray/asLongArray) are now
        // implemented in bundled Kotlin (Stdlib/kotlin/collections/UArrays.kt), which
        // delegates to the __kk_u*Array_as*Array runtime bridges.

        let primitiveArrayFactoryTypes: [(String, String, TypeID)] = [
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
