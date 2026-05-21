import Foundation

/// Synthetic Kotlin/JS `JsArray<T>.toList` conversion surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsArrayToListStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinCollectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )

        let jsArray = ensureJsArrayTypeForToList(
            kotlinJsPkg: kotlinJsPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        guard let listSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("List")]) else {
            return
        }

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: jsArray.typeParameterSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: jsArray.symbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))

        registerJsArrayToListMember(
            ownerSymbol: jsArray.symbol,
            ownerType: receiverType,
            returnType: returnType,
            typeParamSymbol: jsArray.typeParameterSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func ensureJsArrayTypeForToList(
        kotlinJsPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (symbol: SymbolID, typeParameterSymbol: SymbolID) {
        let className = interner.intern("JsArray")
        let classFQName = kotlinJsPkg + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName),
           symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .openType]
            )
        }
        if let packageSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
        symbols.insertFlags([.synthetic, .openType], for: classSymbol)
        appendJsArrayToListAnnotation(to: classSymbol, symbols: symbols)

        let typeParamName = interner.intern("T")
        let typeParamFQName = classFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(classSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.nullableAnyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)
        symbols.setPropertyType(classType, for: classSymbol)

        let jsAnySymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(packageSymbol, for: jsAnySymbol)
        }
        symbols.setDirectSupertypes([jsAnySymbol], for: classSymbol)
        types.setNominalDirectSupertypes([jsAnySymbol], for: classSymbol)

        return (classSymbol, typeParamSymbol)
    }

    private func registerJsArrayToListMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        returnType: TypeID,
        typeParamSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern("toList")
        let functionFQName = ownerInfo.fqName + [functionName]
        let externalLinkName = "kk_js_array_toList"

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
                && signature.typeParameterSymbols == [typeParamSymbol]
                && signature.classTypeParameterCount == 1
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            appendJsArrayToListAnnotation(to: existing, symbols: symbols)
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
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        appendJsArrayToListAnnotation(to: functionSymbol, symbols: symbols)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBoundsList: [[types.nullableAnyType]],
                classTypeParameterCount: 1
            ),
            for: functionSymbol
        )
    }

    private func appendJsArrayToListAnnotation(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let experimentalRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.js.ExperimentalWasmJsInterop"
        )
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(experimentalRecord) {
            annotations.append(experimentalRecord)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
