/// Synthetic `AbstractIterator` and primitive iterator stubs
/// (STDLIB-COL-TYPE-002).
///
/// Split out from `HeaderHelpers+SyntheticIterableStubs.swift`.
extension DataFlowSemaPhase {
    /// Register `kotlin.collections.AbstractIterator<T>` surface (STDLIB-COL-TYPE-002).
    func registerSyntheticAbstractIteratorStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iteratorSymbol: SymbolID
    ) {
        let abstractIteratorName = interner.intern("AbstractIterator")
        let abstractIteratorFQName = kotlinCollectionsPkg + [abstractIteratorName]
        let abstractIteratorSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractIteratorFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractIteratorName,
                fqName: abstractIteratorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = abstractIteratorFQName + [typeParamName]
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
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: abstractIteratorSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: abstractIteratorSymbol)

        let abstractIteratorType = types.make(.classType(ClassType(
            classSymbol: abstractIteratorSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractIteratorType, for: abstractIteratorSymbol)
        symbols.setDirectSupertypes([iteratorSymbol], for: abstractIteratorSymbol)
        types.setNominalDirectSupertypes([iteratorSymbol], for: abstractIteratorSymbol)
        symbols.setSupertypeTypeArgs([.out(typeParamType)], for: abstractIteratorSymbol, supertype: iteratorSymbol)
        types.setNominalSupertypeTypeArgs([.out(typeParamType)], for: abstractIteratorSymbol, supertype: iteratorSymbol)

        let initName = interner.intern("<init>")
        let initFQName = abstractIteratorFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractIteratorSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractIteratorType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: initSymbol
            )
        }

        func registerAbstractIteratorFunction(
            name: String,
            visibility: Visibility,
            flags: SymbolFlags,
            parameterTypes: [TypeID],
            returnType: TypeID,
            valueParameterNames: [String] = []
        ) {
            let memberName = interner.intern(name)
            let memberFQName = abstractIteratorFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: visibility,
                flags: flags
            )
            symbols.setParentSymbol(abstractIteratorSymbol, for: memberSymbol)

            var valueParameterSymbols: [SymbolID] = []
            for parameterName in valueParameterNames {
                let interned = interner.intern(parameterName)
                let parameterSymbol = symbols.define(
                    kind: .valueParameter,
                    name: interned,
                    fqName: memberFQName + [interned],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
                valueParameterSymbols.append(parameterSymbol)
            }

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: abstractIteratorType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    valueParameterSymbols: valueParameterSymbols,
                    valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                    valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                    typeParameterSymbols: [typeParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: memberSymbol
            )
        }

        registerAbstractIteratorFunction(
            name: "computeNext",
            visibility: .protected,
            flags: [.synthetic, .abstractType],
            parameterTypes: [],
            returnType: types.unitType
        )
        registerAbstractIteratorFunction(
            name: "done",
            visibility: .protected,
            flags: [.synthetic],
            parameterTypes: [],
            returnType: types.unitType
        )
        registerAbstractIteratorFunction(
            name: "setNext",
            visibility: .protected,
            flags: [.synthetic],
            parameterTypes: [typeParamType],
            returnType: types.unitType,
            valueParameterNames: ["value"]
        )
        registerAbstractIteratorFunction(
            name: "hasNext",
            visibility: .public,
            flags: [.synthetic, .openType, .overrideMember, .operatorFunction],
            parameterTypes: [],
            returnType: types.booleanType
        )
        registerAbstractIteratorFunction(
            name: "next",
            visibility: .public,
            flags: [.synthetic, .openType, .overrideMember, .operatorFunction],
            parameterTypes: [],
            returnType: typeParamType
        )
    }

    /// Register primitive iterator class surfaces (STDLIB-COL-TYPE-004).
    func registerSyntheticPrimitiveIteratorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iteratorSymbol: SymbolID
    ) {
        let specs: [(className: String, nextName: String, elementType: TypeID)] = [
            ("BooleanIterator", "nextBoolean", types.booleanType),
            ("ByteIterator", "nextByte", types.intType),
            ("ShortIterator", "nextShort", types.intType),
            ("IntIterator", "nextInt", types.intType),
            ("LongIterator", "nextLong", types.longType),
            ("FloatIterator", "nextFloat", types.floatType),
            ("DoubleIterator", "nextDouble", types.doubleType),
            ("CharIterator", "nextChar", types.charType),
        ]

        for spec in specs {
            registerSyntheticPrimitiveIteratorStub(
                named: spec.className,
                nextMemberName: spec.nextName,
                elementType: spec.elementType,
                symbols: symbols,
                types: types,
                interner: interner,
                kotlinCollectionsPkg: kotlinCollectionsPkg,
                iteratorSymbol: iteratorSymbol
            )
        }
    }

    func registerSyntheticPrimitiveIteratorStub(
        named className: String,
        nextMemberName: String,
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        iteratorSymbol: SymbolID
    ) {
        let classInternedName = interner.intern(className)
        let classFQName = kotlinCollectionsPkg + [classInternedName]
        let classSymbol: SymbolID = if let existing = symbols.lookup(fqName: classFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: classInternedName,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(classType, for: classSymbol)
        symbols.setDirectSupertypes([iteratorSymbol], for: classSymbol)
        types.setNominalDirectSupertypes([iteratorSymbol], for: classSymbol)
        symbols.setSupertypeTypeArgs([.out(elementType)], for: classSymbol, supertype: iteratorSymbol)
        types.setNominalSupertypeTypeArgs([.out(elementType)], for: classSymbol, supertype: iteratorSymbol)

        let initName = interner.intern("<init>")
        let initFQName = classFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: classType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [],
                    classTypeParameterCount: 0
                ),
                for: initSymbol
            )
        }

        func registerFunction(name: String, flags: SymbolFlags, returnType: TypeID) {
            let memberName = interner.intern(name)
            let memberFQName = classFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(classSymbol, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: classType,
                    parameterTypes: [],
                    returnType: returnType,
                    typeParameterSymbols: [],
                    classTypeParameterCount: 0
                ),
                for: memberSymbol
            )
        }

        registerFunction(
            name: nextMemberName,
            flags: [.synthetic, .abstractType],
            returnType: elementType
        )
        registerFunction(
            name: "next",
            flags: [.synthetic, .openType, .overrideMember, .operatorFunction],
            returnType: elementType
        )
    }

}
