import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticStdlibLoopStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let repeatName = interner.intern("repeat")
        let repeatFQName = kotlinPkg + [repeatName]
        if symbols.lookupAll(fqName: repeatFQName).contains(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            guard signature.parameterTypes.count == 2,
                  case let .functionType(functionType) = types.kind(of: signature.parameterTypes[1])
            else {
                return false
            }
            return signature.parameterTypes[0] == types.intType
                && functionType.params == [types.intType]
                && functionType.returnType == types.unitType
        }) {
            return
        }

        let repeatSymbol = symbols.define(
            kind: .function,
            name: repeatName,
            fqName: repeatFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(packageSymbol, for: repeatSymbol)
        }

        let timesName = interner.intern("times")
        let actionName = interner.intern("action")
        let timesSymbol = symbols.define(
            kind: .valueParameter,
            name: timesName,
            fqName: repeatFQName + [timesName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let actionSymbol = symbols.define(
            kind: .valueParameter,
            name: actionName,
            fqName: repeatFQName + [actionName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(repeatSymbol, for: timesSymbol)
        symbols.setParentSymbol(repeatSymbol, for: actionSymbol)

        let actionType = types.make(.functionType(FunctionType(
            params: [types.intType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.intType, actionType],
                returnType: types.unitType,
                isSuspend: false,
                valueParameterSymbols: [timesSymbol, actionSymbol],
                valueParameterHasDefaultValues: [false, false],
                valueParameterIsVararg: [false, false]
            ),
            for: repeatSymbol
        )
    }
}
