import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Continuation0/1/2 classes and callContinuation0/1/2 extension functions.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - Continuation0 / Continuation1 / Continuation2

    func registerNativeConcurrentContinuationTypes(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nullableCOpaquePointerType = types.makeNullable(nativeConcurrentCOpaquePointerType(
            symbols: symbols,
            types: types,
            interner: interner
        ))
        let invokerCallbackType = types.make(.functionType(FunctionType(
            params: [nullableCOpaquePointerType],
            returnType: types.unitType
        )))
        let cFunctionType = nativeConcurrentCFunctionType(
            functionType: invokerCallbackType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let invokerType = nativeConcurrentCPointerType(
            pointeeType: cFunctionType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerNativeConcurrentContinuationType(
            name: "Continuation0",
            typeParameterNames: [],
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            invokerType: invokerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentContinuationType(
            name: "Continuation1",
            typeParameterNames: ["T1"],
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            invokerType: invokerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentContinuationType(
            name: "Continuation2",
            typeParameterNames: ["T1", "T2"],
            packageFQName: packageFQName,
            pkgSymbol: pkgSymbol,
            invokerType: invokerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentContinuationType(
        name: String,
        typeParameterNames: [String],
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        invokerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let continuationName = interner.intern(name)
        let continuationFQName = packageFQName + [continuationName]
        let continuationSymbol: SymbolID
        if let existing = symbols.lookup(fqName: continuationFQName), symbols.symbol(existing)?.kind == .class {
            continuationSymbol = existing
        } else {
            continuationSymbol = symbols.define(
                kind: .class,
                name: continuationName,
                fqName: continuationFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: continuationSymbol)
        }

        let typeParameterSymbols = typeParameterNames.map { typeParameterName in
            let internedName = interner.intern(typeParameterName)
            let fqName = continuationFQName + [internedName]
            if let existing = symbols.lookup(fqName: fqName) {
                return existing
            }
            let symbol = symbols.define(
                kind: .typeParameter,
                name: internedName,
                fqName: fqName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(continuationSymbol, for: symbol)
            return symbol
        }
        let typeParameterTypes = typeParameterSymbols.map { symbol in
            types.make(.typeParam(TypeParamType(symbol: symbol, nullability: .nonNull)))
        }
        let continuationType = types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: typeParameterTypes.map { .invariant($0) },
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols(typeParameterSymbols, for: continuationSymbol)
        types.setNominalTypeParameterVariances(
            Array(repeating: .invariant, count: typeParameterSymbols.count),
            for: continuationSymbol
        )
        symbols.setPropertyType(continuationType, for: continuationSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["message = \"This API is deprecated without replacement\""]
                ),
            ],
            to: continuationSymbol,
            symbols: symbols
        )

        let blockType = types.make(.functionType(FunctionType(
            params: typeParameterTypes,
            returnType: types.unitType
        )))
        registerNativeConcurrentContinuationFunctionSupertype(
            ownerSymbol: continuationSymbol,
            functionArity: typeParameterTypes.count,
            functionArgumentTypes: typeParameterTypes,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentConstructor(
            ownerSymbol: continuationSymbol,
            ownerType: continuationType,
            parameters: [
                (name: "block", type: blockType),
                (name: "invoker", type: invokerType),
                (name: "singleShot", type: types.booleanType),
            ],
            defaultValues: [false, false, true],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: typeParameterSymbols.count,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: continuationSymbol,
            ownerType: continuationType,
            name: "dispose",
            returnType: types.unitType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: typeParameterSymbols.count,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: continuationSymbol,
            ownerType: continuationType,
            name: "invoke",
            returnType: types.unitType,
            parameters: typeParameterTypes.enumerated().map { index, type in
                (name: "p\(index + 1)", type: type)
            },
            defaultValues: [],
            typeParameterSymbols: typeParameterSymbols,
            classTypeParameterCount: typeParameterSymbols.count,
            flags: [.synthetic, .operatorFunction, .overrideMember, .openType],
            symbols: symbols,
            interner: interner
        )
    }

    func registerNativeConcurrentCallContinuationFunctions(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let receiverType = nativeConcurrentCOpaquePointerType(
            symbols: symbols,
            types: types,
            interner: interner
        )

        for arity in 0...2 {
            registerNativeConcurrentCallContinuationFunction(
                arity: arity,
                packageFQName: packageFQName,
                receiverType: receiverType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    private func registerNativeConcurrentCallContinuationFunction(
        arity: Int,
        packageFQName: [InternedString],
        receiverType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("callContinuation\(arity)")
        let functionFQName = packageFQName + [functionName]
        let typeParameterSymbols: [SymbolID] = arity == 0 ? [] : (1...arity).map { index in
            let typeParameterName = interner.intern("T\(index)")
            let typeParameterFQName = functionFQName + [typeParameterName]
            if let existing = symbols.lookup(fqName: typeParameterFQName) {
                return existing
            }
            let symbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            return symbol
        }

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == types.unitType
                && signature.typeParameterSymbols == typeParameterSymbols
        }) == nil else {
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
        for typeParameterSymbol in typeParameterSymbols {
            symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
        }
        appendNativeConcurrentMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["message = \"This API is deprecated without replacement\""]
                ),
            ],
            to: functionSymbol,
            symbols: symbols
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}
