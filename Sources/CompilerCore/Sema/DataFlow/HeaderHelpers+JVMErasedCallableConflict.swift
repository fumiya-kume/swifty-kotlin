import Foundation

extension DataFlowSemaPhase {
    func checkAndReportJVMErasedCallableConflict(
        for symbol: SymbolID,
        fqName: [InternedString],
        range: SourceRange?,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine
    ) {
        guard let newSymbol = symbols.symbol(symbol),
              newSymbol.kind == .function,
              let newSignature = symbols.functionSignature(for: symbol)
        else {
            return
        }

        let hasConflict = symbols.lookupAll(fqName: fqName).contains { existingID in
            guard existingID != symbol,
                  let existingSymbol = symbols.symbol(existingID),
                  existingSymbol.kind == newSymbol.kind,
                  !canCoexistAsExpectActualPair(newSymbol, existingSymbol),
                  let existingSignature = symbols.functionSignature(for: existingID)
            else {
                return false
            }
            return hasSameJVMErasedCallableSignature(
                newSignature,
                existingSignature,
                types: types
            )
        }

        if hasConflict {
            diagnostics.error(
                "KSWIFTK-SEMA-0001",
                "Duplicate JVM-erased callable declaration in the same package scope.",
                range: range
            )
        }
    }

    func hasSameJVMErasedCallableSignature(
        _ lhs: FunctionSignature,
        _ rhs: FunctionSignature,
        types: TypeSystem
    ) -> Bool {
        let lhsReceiver = lhs.receiverType.map { jvmErasedCallableType($0, types: types) }
        let rhsReceiver = rhs.receiverType.map { jvmErasedCallableType($0, types: types) }
        guard lhsReceiver == rhsReceiver,
              lhs.parameterTypes.count == rhs.parameterTypes.count
        else {
            return false
        }

        let lhsParameters = lhs.parameterTypes.map { jvmErasedCallableType($0, types: types) }
        let rhsParameters = rhs.parameterTypes.map { jvmErasedCallableType($0, types: types) }
        return zip(lhsParameters, rhsParameters).allSatisfy(==)
    }

    func jvmErasedCallableType(_ type: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: type) {
        case let .primitive(primitive, _):
            if primitive == .string {
                return types.makeNonNullable(type)
            }
            return type
        default:
            return types.makeNonNullable(type)
        }
    }

    func canCoexistAsExpectActualPair(_ lhs: SemanticSymbol, _ rhs: SemanticSymbol) -> Bool {
        guard lhs.kind == rhs.kind else {
            return false
        }

        let lhsIsExpect = lhs.flags.contains(.expectDeclaration)
        let lhsIsActual = lhs.flags.contains(.actualDeclaration)
        let rhsIsExpect = rhs.flags.contains(.expectDeclaration)
        let rhsIsActual = rhs.flags.contains(.actualDeclaration)

        guard lhsIsExpect != lhsIsActual,
              rhsIsExpect != rhsIsActual
        else {
            return false
        }

        return (lhsIsExpect && rhsIsActual) || (lhsIsActual && rhsIsExpect)
    }
}
