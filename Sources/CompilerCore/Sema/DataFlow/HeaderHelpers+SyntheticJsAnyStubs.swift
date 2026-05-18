import Foundation

/// Synthetic Kotlin/JS `JsAny` external interface surface.
extension DataFlowSemaPhase {
    func registerSyntheticJsAnyStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let jsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let jsPkgSymbol = symbols.lookup(fqName: jsPkg)

        let interfaceSymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: jsPkg,
            symbols: symbols,
            interner: interner
        )
        if let jsPkgSymbol {
            symbols.setParentSymbol(jsPkgSymbol, for: interfaceSymbol)
        }

        appendJsAnyAnnotationMetadata(to: interfaceSymbol, symbols: symbols)
        let jsAnyType = types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(jsAnyType, for: interfaceSymbol)

        let throwableType = ensureJsAnyThrowableType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerJsAnyToThrowableOrNull(
            ownerSymbol: interfaceSymbol,
            ownerType: jsAnyType,
            returnType: types.makeNullable(throwableType),
            symbols: symbols,
            interner: interner
        )
    }

    private func appendJsAnyAnnotationMetadata(
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

    private func ensureJsAnyThrowableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let throwableSymbol = ensureClassSymbol(
            named: "Throwable",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: throwableSymbol)
        }
        let throwableType = types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(throwableType, for: throwableSymbol)
        return throwableType
    }

    private func registerJsAnyToThrowableOrNull(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern("toThrowableOrNull")
        let functionFQName = ownerInfo.fqName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbol in
            guard let signature = symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
        }) {
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: ownerType,
                    parameterTypes: [],
                    returnType: returnType
                ),
                for: existing
            )
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
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: functionSymbol
        )
    }
}
