import Foundation

// SAM (Single Abstract Method) conversion helpers for functional interfaces.

extension TypeCheckHelpers {
    /// For a functional interface (SAM type), find the single abstract method and
    /// return its function signature.  Returns `nil` if the symbol is not a
    /// `funInterface` or has no abstract method with a signature.
    func samMethodSignature(
        for interfaceSymbol: SymbolID,
        sema: SemaModule
    ) -> FunctionSignature? {
        guard let sym = sema.symbols.symbol(interfaceSymbol),
              sym.kind == .interface,
              sym.flags.contains(.funInterface)
        else {
            return nil
        }
        // Walk child symbols and collect abstract function members.
        let children = sema.symbols.children(ofFQName: sym.fqName)
        var abstractSignatures: [FunctionSignature] = []
        for childID in children {
            guard let childSym = sema.symbols.symbol(childID),
                  childSym.kind == .function,
                  childSym.flags.contains(.abstractType),
                  let signature = sema.symbols.functionSignature(for: childID)
            else {
                continue
            }
            abstractSignatures.append(signature)
        }
        // A SAM type must have exactly one abstract method.
        guard abstractSignatures.count == 1 else {
            return nil
        }
        return abstractSignatures[0]
    }

    /// Extracts the SAM function type from a functional interface type.
    /// Given a `classType` whose symbol is a `funInterface`, returns the
    /// equivalent `FunctionType` derived from the SAM method's signature.
    func samFunctionType(
        for expectedType: TypeID,
        sema: SemaModule
    ) -> FunctionType? {
        guard case let .classType(classType) = sema.types.kind(of: expectedType) else {
            return nil
        }
        guard let signature = samMethodSignature(for: classType.classSymbol, sema: sema) else {
            return nil
        }
        let typeParamSymbols = sema.types.nominalTypeParameterSymbols(for: classType.classSymbol)
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        if typeParamSymbols.count == classType.args.count {
            for (index, arg) in classType.args.enumerated() {
                guard index < typeParamSymbols.count,
                      let typeVar = typeVarBySymbol[typeParamSymbols[index]]
                else {
                    continue
                }
                switch arg {
                case let .invariant(type), let .out(type), let .in(type):
                    substitution[typeVar] = type
                case .star:
                    substitution[typeVar] = sema.types.nullableAnyType
                }
            }
        }
        let substitute = { (type: TypeID) in
            sema.types.substituteTypeParameters(
                in: type,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
        }
        return FunctionType(
            params: signature.parameterTypes.map(substitute),
            returnType: substitute(signature.returnType),
            isSuspend: signature.isSuspend,
            nullability: .nonNull
        )
    }
}
