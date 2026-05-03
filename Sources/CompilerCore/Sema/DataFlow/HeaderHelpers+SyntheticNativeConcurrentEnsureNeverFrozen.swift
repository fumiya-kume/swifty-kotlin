import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Any.ensureNeverFrozen() extension.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - ensureNeverFrozen

    func registerNativeConcurrentEnsureNeverFrozen(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("ensureNeverFrozen")
        let functionFQName = packageFQName + [functionName]
        let receiverType = types.anyType

        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == types.unitType
        }) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .throwingFunction]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType,
                isSuspend: false,
                canThrow: true,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }
}
