import Foundation

// Property delegate interface stubs (Lazy<T>, ReadWriteProperty, lazy(), Delegates, etc.).
// Split from DataFlowSemaPhase+HeaderHelpers.swift to stay within file-length limits.

extension DataFlowSemaPhase {
    // swiftlint:disable:next function_body_length
    func registerSyntheticPropertyInterfaceStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString],
        kotlinPropertiesPkg: [InternedString]
    ) {
        let anyType = types.anyType

        // Register kotlin.properties.Lazy<T> interface stub.
        let lazyInterfaceSymbol = ensureInterfaceSymbol(
            named: "Lazy", in: kotlinPropertiesPkg, symbols: symbols, interner: interner
        )
        let lazyInterfaceType = types.make(.classType(ClassType(
            classSymbol: lazyInterfaceSymbol, args: [], nullability: .nonNull
        )))

        // Register kotlin.properties.ReadWriteProperty<T, V> interface stub.
        let rwPropertySymbol = ensureInterfaceSymbol(
            named: "ReadWriteProperty", in: kotlinPropertiesPkg, symbols: symbols, interner: interner
        )
        let rwPropertyType = types.make(.classType(ClassType(
            classSymbol: rwPropertySymbol, args: [], nullability: .nonNull
        )))

        // Register kotlin.properties.ReadOnlyProperty<in T, out V> interface stub.
        _ = ensureInterfaceSymbol(
            named: "ReadOnlyProperty", in: kotlinPropertiesPkg, symbols: symbols, interner: interner
        )

        // Register `lazy` as a top-level function in the kotlin package.
        // Kotlin signature: fun <T> lazy(initializer: () -> T): Lazy<T>
        let lazyName = interner.intern("lazy")
        let lazyFQName = kotlinPkg + [lazyName]
        if symbols.lookup(fqName: lazyFQName) == nil {
            let lazySymbol = symbols.define(
                kind: .function, name: lazyName, fqName: lazyFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            let initializerType = types.make(.functionType(FunctionType(
                params: [], returnType: anyType, isSuspend: false, nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(parameterTypes: [initializerType], returnType: lazyInterfaceType),
                for: lazySymbol
            )
        }

        // Also register `lazy` with explicit thread-safety mode overload.
        // Kotlin signature: fun <T> lazy(mode: LazyThreadSafetyMode, initializer: () -> T): Lazy<T>
        let lazyModeFQName = kotlinPkg + [lazyName, interner.intern("mode")]
        if symbols.lookup(fqName: lazyModeFQName) == nil {
            let lazyModeSymbol = symbols.define(
                kind: .function, name: lazyName, fqName: lazyModeFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            let initializerType = types.make(.functionType(FunctionType(
                params: [], returnType: anyType, isSuspend: false, nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(parameterTypes: [anyType, initializerType], returnType: lazyInterfaceType),
                for: lazyModeSymbol
            )
        }

        // Register `Delegates` as an object in kotlin.properties.
        let delegatesName = interner.intern("Delegates")
        let delegatesFQName = kotlinPropertiesPkg + [delegatesName]
        let delegatesSymbol: SymbolID = if let existing = symbols.lookup(fqName: delegatesFQName) {
            existing
        } else {
            symbols.define(
                kind: .object, name: delegatesName, fqName: delegatesFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let delegatesType = types.make(.classType(ClassType(
            classSymbol: delegatesSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(delegatesType, for: delegatesSymbol)

        registerDelegatesMemberFunction(
            named: "observable", on: delegatesSymbol, delegatesType: delegatesType,
            returnType: rwPropertyType, anyType: anyType,
            symbols: symbols, interner: interner
        )
        registerDelegatesMemberFunction(
            named: "vetoable", on: delegatesSymbol, delegatesType: delegatesType,
            returnType: rwPropertyType, anyType: anyType,
            symbols: symbols, interner: interner
        )
    }

    /// Register a single member function on the Delegates object.
    private func registerDelegatesMemberFunction(
        named name: String,
        on delegatesSymbol: SymbolID,
        delegatesType: TypeID,
        returnType: TypeID,
        anyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let internedName = interner.intern(name)
        guard let ownerSym = symbols.symbol(delegatesSymbol) else { return }
        let fqName = ownerSym.fqName + [internedName]
        guard symbols.lookup(fqName: fqName) == nil else { return }
        let funcSymbol = symbols.define(
            kind: .function, name: internedName, fqName: fqName,
            declSite: nil, visibility: .public, flags: [.synthetic]
        )
        symbols.setParentSymbol(delegatesSymbol, for: funcSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: delegatesType, parameterTypes: [anyType], returnType: returnType
            ),
            for: funcSymbol
        )
    }
}
