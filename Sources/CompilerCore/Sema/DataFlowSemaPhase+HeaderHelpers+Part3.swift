import Foundation

// Collection type stubs (List<E>, MutableList<E>) for kotlin.collections.
// Split from DataFlowSemaPhase+HeaderHelpers.swift to stay within file-length limits.

extension DataFlowSemaPhase {
    func registerSyntheticCollectionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Ensure the "kotlin.collections" package exists.
        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        if symbols.lookup(fqName: kotlinCollectionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("collections"),
                fqName: kotlinCollectionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let listInterfaceSymbol = registerSyntheticListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )

        registerSyntheticMutableListStub(
            symbols: symbols, types: types, interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            listInterfaceSymbol: listInterfaceSymbol
        )
    }

    /// Register `kotlin.collections.List<E>` interface stub with `operator fun get(index: Int): E`.
    private func registerSyntheticListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let listName = interner.intern("List")
        let listFQName = kotlinCollectionsPkg + [listName]
        let listInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: listFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: listName,
                fqName: listFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Define type parameter E for List<E>
        let listTypeParamName = interner.intern("E")
        let listTypeParamFQName = listFQName + [listTypeParamName]
        let listTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: listTypeParamName,
            fqName: listTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let listTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: listTypeParamSymbol, nullability: .nonNull
        )))

        registerListGetOperator(
            symbols: symbols, types: types, interner: interner,
            listFQName: listFQName,
            listInterfaceSymbol: listInterfaceSymbol,
            listTypeParamSymbol: listTypeParamSymbol,
            listTypeParamType: listTypeParamType
        )
        return listInterfaceSymbol
    }

    /// Register `operator fun get(index: Int): E` on the List interface.
    // swiftlint:disable:next function_parameter_count
    private func registerListGetOperator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID
    ) {
        let listGetName = interner.intern("get")
        let listGetFQName = listFQName + [listGetName]
        guard symbols.lookup(fqName: listGetFQName) == nil else { return }
        let listReceiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))
        let listGetSymbol = symbols.define(
            kind: .function,
            name: listGetName,
            fqName: listGetFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(listInterfaceSymbol, for: listGetSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listReceiverType,
                parameterTypes: [types.intType],
                returnType: listTypeParamType,
                typeParameterSymbols: [listTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: listGetSymbol
        )
    }

    /// Register `kotlin.collections.MutableList<E>` interface stub with `operator fun set(index: Int, element: E): E`.
    private func registerSyntheticMutableListStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listInterfaceSymbol: SymbolID
    ) {
        let listTypeParamName = interner.intern("E")
        let mutableListName = interner.intern("MutableList")
        let mutableListFQName = kotlinCollectionsPkg + [mutableListName]
        let mutableListInterfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableListFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mutableListName,
                fqName: mutableListFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        // MutableList extends List
        symbols.setDirectSupertypes([listInterfaceSymbol], for: mutableListInterfaceSymbol)

        // Define type parameter E for MutableList<E>
        let mlTypeParamFQName = mutableListFQName + [listTypeParamName]
        let mlTypeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: listTypeParamName,
            fqName: mlTypeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mlTypeParamType = types.make(.typeParam(TypeParamType(
            symbol: mlTypeParamSymbol, nullability: .nonNull
        )))

        registerMutableListSetOperator(
            symbols: symbols, types: types, interner: interner,
            mutableListFQName: mutableListFQName,
            mutableListInterfaceSymbol: mutableListInterfaceSymbol,
            mlTypeParamSymbol: mlTypeParamSymbol,
            mlTypeParamType: mlTypeParamType
        )
    }

    /// Register `operator fun set(index: Int, element: E): E` on MutableList.
    // swiftlint:disable:next function_parameter_count
    private func registerMutableListSetOperator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        mutableListFQName: [InternedString],
        mutableListInterfaceSymbol: SymbolID,
        mlTypeParamSymbol: SymbolID,
        mlTypeParamType: TypeID
    ) {
        let mlSetName = interner.intern("set")
        let mlSetFQName = mutableListFQName + [mlSetName]
        guard symbols.lookup(fqName: mlSetFQName) == nil else { return }
        let mlReceiverType = types.make(.classType(ClassType(
            classSymbol: mutableListInterfaceSymbol,
            args: [.invariant(mlTypeParamType)],
            nullability: .nonNull
        )))
        let mlSetSymbol = symbols.define(
            kind: .function,
            name: mlSetName,
            fqName: mlSetFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(mutableListInterfaceSymbol, for: mlSetSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: mlReceiverType,
                parameterTypes: [types.intType, mlTypeParamType],
                returnType: mlTypeParamType,
                typeParameterSymbols: [mlTypeParamSymbol],
                classTypeParameterCount: 1
            ),
            for: mlSetSymbol
        )
    }
}
