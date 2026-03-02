import Foundation

// Type alias substitution helpers.
// Split from TypeCheckHelpers.swift to stay within file-length limits.

extension TypeCheckHelpers {
    /// Recursively apply type argument substitution to a type.
    func applyAliasSubstitution(
        _ typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        sema: SemaModule
    ) -> TypeID {
        let types = sema.types
        switch types.kind(of: typeID) {
        case let .typeParam(tp):
            if let replacement = argSubstitution[tp.symbol] {
                let replacementType: TypeID = switch replacement {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    inner
                case .star:
                    types.nullableAnyType
                }
                if tp.nullability == .nullable {
                    return applyNullabilityForTypeCheck(replacementType, types: types)
                }
                return replacementType
            }
            return typeID
        case let .classType(ct):
            let newArgs = ct.args.map { arg -> TypeArg in
                substituteAliasArg(arg, argSubstitution: argSubstitution, sema: sema)
            }
            if newArgs == ct.args { return typeID }
            return types.make(.classType(ClassType(
                classSymbol: ct.classSymbol, args: newArgs, nullability: ct.nullability
            )))
        case let .functionType(ft):
            let newReceiver = ft.receiver.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            let newParams = ft.params.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            let newReturn = applyAliasSubstitution(
                ft.returnType, argSubstitution: argSubstitution, sema: sema
            )
            if newReceiver == ft.receiver, newParams == ft.params, newReturn == ft.returnType {
                return typeID
            }
            return types.make(.functionType(FunctionType(
                receiver: newReceiver, params: newParams, returnType: newReturn,
                isSuspend: ft.isSuspend, nullability: ft.nullability
            )))
        case let .intersection(parts):
            let newParts = parts.map {
                applyAliasSubstitution($0, argSubstitution: argSubstitution, sema: sema)
            }
            if newParts == parts { return typeID }
            return types.make(.intersection(newParts))
        default:
            return typeID
        }
    }
}
