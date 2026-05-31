import Foundation

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// Comparable<in T> sub-helpers (compareTo operator, primitive compatibility, null-safe extensions).
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    /// Set up primitive types to implement Comparable<Self>
    func setupPrimitiveComparableImplementations(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparableSymbol: SymbolID
    ) {
        // Set up primitive types to implement Comparable<Self>
        let kotlinPkg = [interner.intern("kotlin")]
        
        let primitiveTypeNames = ["Int", "Long", "Double", "Float", "Char", "Boolean", "UInt", "ULong", "UByte", "UShort"]
        
        for typeName in primitiveTypeNames {
            let primitiveSymbol = ensureClassSymbol(named: typeName, in: kotlinPkg, symbols: symbols, interner: interner)
            
            // Set up Comparable<Self> as a supertype
            let primitiveType = types.make(.classType(ClassType(
                classSymbol: primitiveSymbol,
                args: [],
                nullability: .nonNull
            )))
            
            // Set direct supertypes for member resolution
            symbols.setDirectSupertypes([comparableSymbol], for: primitiveSymbol)
            types.setNominalDirectSupertypes([comparableSymbol], for: primitiveSymbol)
            symbols.setSupertypeTypeArgs([.in(primitiveType)], for: primitiveSymbol, supertype: comparableSymbol)
            types.setNominalSupertypeTypeArgs([.in(primitiveType)], for: primitiveSymbol, supertype: comparableSymbol)
        }
    }

    /// Register `operator fun compareTo(other: T): Int` on the Comparable interface with null-safe comparison support.
    func registerComparableCompareToOperator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparableFQName: [InternedString],
        comparableSymbol: SymbolID,
        tParamSymbol: SymbolID,
        tParamType: TypeID
    ) {
        let compareToName = interner.intern("compareTo")
        let compareToFQName = comparableFQName + [compareToName]
        guard symbols.lookup(fqName: compareToFQName) == nil else { return }
        let receiverType = tParamType
        let compareToSymbol = symbols.define(
            kind: .function,
            name: compareToName,
            fqName: compareToFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(comparableSymbol, for: compareToSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [tParamType],
                returnType: types.intType,
                typeParameterSymbols: [tParamSymbol],
                classTypeParameterCount: 1
            ),
            for: compareToSymbol
        )

        // Register null-safe comparison extensions
        registerNullSafeComparisonExtensions(
            symbols: symbols,
            types: types,
            interner: interner,
            comparableSymbol: comparableSymbol
        )
    }

    /// Register null-safe comparison extensions for Comparable types.
    private func registerNullSafeComparisonExtensions(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        comparableSymbol: SymbolID
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let extensionsPkg = kotlinPkg + [interner.intern("comparisons")]

        // Ensure comparisons package exists
        if symbols.lookup(fqName: extensionsPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("comparisons"),
                fqName: extensionsPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Register null-safe compareTo for nullable types
        registerNullSafeCompareTo(
            symbols: symbols,
            types: types,
            interner: interner,
            extensionsPkg: extensionsPkg,
            comparableSymbol: comparableSymbol
        )
    }

    /// Register null-safe compareTo extension for nullable Comparable types.
    private func registerNullSafeCompareTo(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        extensionsPkg: [InternedString],
        comparableSymbol: SymbolID
    ) {
        let functionName = interner.intern("compareToOrNull")
        let functionFQName = extensionsPkg + [functionName]

        guard symbols.lookup(fqName: functionFQName) == nil else { return }

        let nullableIntType = types.makeNullable(types.intType)

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // Define type parameter T for the extension function
        let tParamName = interner.intern("T")
        let tParamFQName = functionFQName + [tParamName]
        let tParamSymbol = symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: tParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let functionTParamType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))
        let nullableFunctionTParamType = types.makeNullable(functionTParamType)

        // Create upper bound: T : Comparable<T>
        let comparableUpperBounds: [TypeID] = [types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.in(functionTParamType)],
            nullability: .nonNull
        )))]

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [nullableFunctionTParamType, nullableFunctionTParamType],
                returnType: nullableIntType,
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [comparableUpperBounds],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}
