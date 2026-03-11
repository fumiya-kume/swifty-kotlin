import Foundation

/// Synthetic stdlib stubs for buildList (STDLIB-070) and related builder DSL functions.
/// buildList<E>(builderAction: MutableList<E>.() -> Unit): List<E>
/// Lowering rewrites these to kk_build_* runtime calls.
extension DataFlowSemaPhase {
    func registerSyntheticBuilderDSLStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinCollectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        guard symbols.lookup(fqName: kotlinCollectionsPkg) != nil else {
            return
        }
        let listName = interner.intern("List")
        let mutableListName = interner.intern("MutableList")
        guard let listSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [listName]),
              let mutableListSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [mutableListName])
        else {
            return
        }

        registerSyntheticBuildListStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listSymbol: listSymbol,
            mutableListSymbol: mutableListSymbol
        )
    }

    private func registerSyntheticBuildListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listSymbol: SymbolID,
        mutableListSymbol: SymbolID
    ) {
        let buildListName = interner.intern("buildList")
        let buildListFQName = kotlinCollectionsPkg + [buildListName]
        if symbols.lookup(fqName: buildListFQName) != nil {
            return
        }

        let eName = interner.intern("E")
        let eFQName = buildListFQName + [eName]
        let eSymbol = symbols.define(
            kind: .typeParameter,
            name: eName,
            fqName: eFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let eType = types.make(.typeParam(TypeParamType(symbol: eSymbol, nullability: .nonNull)))

        let mutableListOfEType = types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(eType)],
            nullability: .nonNull
        )))
        let listOfEType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(eType)],
            nullability: .nonNull
        )))

        let builderActionType = types.make(.functionType(FunctionType(
            receiver: mutableListOfEType,
            params: [],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let builderActionName = interner.intern("builderAction")
        let builderActionSymbol = symbols.define(
            kind: .valueParameter,
            name: builderActionName,
            fqName: buildListFQName + [builderActionName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )

        let buildListSymbol = symbols.define(
            kind: .function,
            name: buildListName,
            fqName: buildListFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinCollectionsPkg) {
            symbols.setParentSymbol(packageSymbol, for: buildListSymbol)
        }
        symbols.setParentSymbol(buildListSymbol, for: eSymbol)
        symbols.setParentSymbol(buildListSymbol, for: builderActionSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [builderActionType],
                returnType: listOfEType,
                isSuspend: false,
                valueParameterSymbols: [builderActionSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [eSymbol],
                classTypeParameterCount: 0
            ),
            for: buildListSymbol
        )
    }
}
