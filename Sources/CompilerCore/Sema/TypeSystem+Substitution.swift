extension TypeSystem {
    func renderType(_ type: TypeID) -> String {
        switch kind(of: type) {
        case .error:
            return "<error>"
        case .unit:
            return "Unit"
        case .nothing:
            return "Nothing"
        case .any(let nullability):
            return nullability == .nullable ? "Any?" : "Any"
        case .primitive(let primitive, let nullability):
            let base: String
            switch primitive {
            case .boolean:
                base = "Boolean"
            case .char:
                base = "Char"
            case .int:
                base = "Int"
            case .long:
                base = "Long"
            case .float:
                base = "Float"
            case .double:
                base = "Double"
            case .string:
                base = "String"
            }
            return nullability == .nullable ? "\(base)?" : base
        case .classType(let classType):
            let args: String
            if classType.args.isEmpty {
                args = ""
            } else {
                args = "<" + classType.args.map(renderTypeArg).joined(separator: ", ") + ">"
            }
            let nullSuffix = classType.nullability == .nullable ? "?" : ""
            return "Class#\(classType.classSymbol.rawValue)\(args)\(nullSuffix)"
        case .typeParam(let typeParam):
            let nullSuffix = typeParam.nullability == .nullable ? "?" : ""
            return "T#\(typeParam.symbol.rawValue)\(nullSuffix)"
        case .functionType(let functionType):
            let receiverPrefix: String
            if let receiver = functionType.receiver {
                receiverPrefix = "\(renderType(receiver))."
            } else {
                receiverPrefix = ""
            }
            let suspendPrefix = functionType.isSuspend ? "suspend " : ""
            let params = functionType.params.map(renderType).joined(separator: ", ")
            let nullSuffix = functionType.nullability == .nullable ? "?" : ""
            return "\(suspendPrefix)\(receiverPrefix)(\(params)) -> \(renderType(functionType.returnType))\(nullSuffix)"
        case .intersection(let parts):
            return parts.map(renderType).joined(separator: " & ")
        }
    }

    private func renderTypeArg(_ arg: TypeArg) -> String {
        switch arg {
        case .invariant(let type):
            return renderType(type)
        case .out(let type):
            return "out \(renderType(type))"
        case .in(let type):
            return "in \(renderType(type))"
        case .star:
            return "*"
        }
    }

    public func makeTypeVarBySymbol(_ symbols: [SymbolID]) -> [SymbolID: TypeVarID] {
        var mapping: [SymbolID: TypeVarID] = [:]
        for (index, symbol) in symbols.enumerated() {
            mapping[symbol] = TypeVarID(rawValue: Int32(index))
        }
        return mapping
    }

    public func substituteTypeParameters(
        in type: TypeID,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID]
    ) -> TypeID {
        let kind = kind(of: type)
        switch kind {
        case .typeParam(let typeParam):
            if let variable = typeVarBySymbol[typeParam.symbol],
               let concrete = substitution[variable] {
                return concrete
            }
            return type

        case .classType(let classType):
            let newArgs: [TypeArg] = classType.args.map { arg in
                switch arg {
                case .invariant(let inner):
                    return .invariant(substituteTypeParameters(
                        in: inner,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    ))
                case .out(let inner):
                    return .out(substituteTypeParameters(
                        in: inner,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    ))
                case .in(let inner):
                    return .in(substituteTypeParameters(
                        in: inner,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    ))
                case .star:
                    return .star
                }
            }
            if newArgs == classType.args {
                return type
            }
            return make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: newArgs,
                nullability: classType.nullability
            )))

        case .functionType(let functionType):
            let newReceiver = functionType.receiver.map { receiver in
                substituteTypeParameters(
                    in: receiver,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
            let newParams = functionType.params.map { param in
                substituteTypeParameters(
                    in: param,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
            let newReturn = substituteTypeParameters(
                in: functionType.returnType,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            if newReceiver == functionType.receiver &&
                newParams == functionType.params &&
                newReturn == functionType.returnType {
                return type
            }
            return make(.functionType(FunctionType(
                receiver: newReceiver,
                params: newParams,
                returnType: newReturn,
                isSuspend: functionType.isSuspend,
                nullability: functionType.nullability
            )))

        case .intersection(let parts):
            let newParts = parts.map { part in
                substituteTypeParameters(
                    in: part,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
            if newParts == parts {
                return type
            }
            return make(.intersection(newParts))

        default:
            return type
        }
    }
}
