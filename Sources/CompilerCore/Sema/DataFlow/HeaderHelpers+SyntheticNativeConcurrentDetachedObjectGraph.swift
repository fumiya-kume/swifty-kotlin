import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: DetachedObjectGraph<T> class and attach extension function.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - DetachedObjectGraph<T>

    func registerNativeConcurrentDetachedObjectGraph(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        transferModeType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let graphName = interner.intern("DetachedObjectGraph")
        let graphFQName = packageFQName + [graphName]

        let graphSymbol: SymbolID
        if let existing = symbols.lookup(fqName: graphFQName), symbols.symbol(existing)?.kind == .class {
            graphSymbol = existing
        } else {
            graphSymbol = symbols.define(
                kind: .class,
                name: graphName,
                fqName: graphFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: graphSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = graphFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
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
        let graphType = types.make(.classType(ClassType(
            classSymbol: graphSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: graphSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: graphSymbol)
        symbols.setPropertyType(graphType, for: graphSymbol)

        let cOpaquePointerType = nativeConcurrentClassType(
            packagePath: ["kotlinx", "cinterop"],
            name: "COpaquePointer",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let nullableCOpaquePointerType = types.makeNullable(cOpaquePointerType)
        let producerType = types.make(.functionType(FunctionType(
            params: [],
            returnType: typeParamType
        )))

        registerNativeConcurrentConstructor(
            ownerSymbol: graphSymbol,
            ownerType: graphType,
            parameters: [
                (name: "mode", type: transferModeType),
                (name: "producer", type: producerType),
            ],
            defaultValues: [true, false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentConstructor(
            ownerSymbol: graphSymbol,
            ownerType: graphType,
            parameters: [(name: "pointer", type: nullableCOpaquePointerType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: graphSymbol,
            ownerType: graphType,
            name: "asCPointer",
            returnType: nullableCOpaquePointerType,
            parameters: [],
            defaultValues: [],
            typeParameterSymbols: [typeParamSymbol],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentAttachExtension(
            packageFQName: packageFQName,
            graphSymbol: graphSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentAttachExtension(
        packageFQName: [InternedString],
        graphSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("attach")
        let functionFQName = packageFQName + [functionName]
        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
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
            classSymbol: graphSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == typeParamType
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
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: typeParamType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}
