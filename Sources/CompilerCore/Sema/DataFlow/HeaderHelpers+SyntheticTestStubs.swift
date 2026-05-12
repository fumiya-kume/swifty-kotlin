import Foundation

/// Synthetic `kotlin.test` stubs for basic assertion helpers and lifecycle annotations.
/// The annotations are compile-time only; runtime behavior lives in `RuntimeTest.swift`.
extension DataFlowSemaPhase {
    func registerSyntheticTestFrameworkStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) {
        let testPkg = ensureSyntheticPackageHierarchy(
            fqName: kotlinPkg + [interner.intern("test")],
            symbols: symbols
        )
        let packageSymbol = symbols.lookup(fqName: testPkg) ?? .invalid

        registerSyntheticAnnotationClass(
            named: "Test",
            packageFQName: testPkg,
            packageSymbol: packageSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "Before",
            packageFQName: testPkg,
            packageSymbol: packageSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "After",
            packageFQName: testPkg,
            packageSymbol: packageSymbol,
            symbols: symbols,
            interner: interner
        )

        let anyNullable = types.makeNullable(types.anyType)

        registerSyntheticTopLevelFunction(
            named: "assertEquals",
            packageFQName: testPkg,
            parameters: [
                (name: "expected", type: anyNullable),
                (name: "actual", type: anyNullable),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_test_assertEquals",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "assertEquals",
            packageFQName: testPkg,
            parameters: [
                (name: "expected", type: anyNullable),
                (name: "actual", type: anyNullable),
                (name: "message", type: anyNullable),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_test_assertEquals_message",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "assertTrue",
            packageFQName: testPkg,
            parameters: [
                (name: "actual", type: types.booleanType),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_test_assertTrue",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "assertTrue",
            packageFQName: testPkg,
            parameters: [
                (name: "actual", type: types.booleanType),
                (name: "message", type: anyNullable),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_test_assertTrue_message",
            symbols: symbols,
            interner: interner
        )

        registerSyntheticTopLevelFunction(
            named: "assertNull",
            packageFQName: testPkg,
            parameters: [
                (name: "actual", type: anyNullable),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_test_assertNull",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticTopLevelFunction(
            named: "assertNull",
            packageFQName: testPkg,
            parameters: [
                (name: "actual", type: anyNullable),
                (name: "message", type: anyNullable),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_test_assertNull_message",
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureSyntheticPackageHierarchy(
        fqName path: [InternedString],
        symbols: SymbolTable
    ) -> [InternedString] {
        guard !path.isEmpty else { return path }
        var current: [InternedString] = []
        for part in path {
            current.append(part)
            if symbols.lookup(fqName: current) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: part,
                    fqName: current,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
        return current
    }

    private func registerSyntheticTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }
}
