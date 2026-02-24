import Foundation

public enum MangledDeclKind {
    case automatic
    case getter
    case setter
}

public final class NameMangler {
    public init() {}

    public func mangle(
        moduleName: String,
        symbol: SemanticSymbol,
        signature: String,
        declKind: MangledDeclKind = .automatic,
        nameResolver: ((InternedString) -> String)? = nil
    ) -> String {
        let fqPart = encodeFQName(symbol.fqName, nameResolver: nameResolver)
        let kind = kindCode(symbol.kind, declKind: declKind)
        let base = "_KK_\(moduleName)__\(fqPart)__\(kind)__\(signature)"
        let hash = fnv1a32Hex(base)
        return "\(base)__\(hash)"
    }

    public func mangle(
        moduleName: String,
        symbol: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem,
        declKind: MangledDeclKind = .automatic,
        nameResolver: ((InternedString) -> String)? = nil
    ) -> String {
        let signature = mangledSignature(
            for: symbol,
            symbols: symbols,
            types: types,
            nameResolver: nameResolver
        )
        return mangle(
            moduleName: moduleName,
            symbol: symbol,
            signature: signature,
            declKind: declKind,
            nameResolver: nameResolver
        )
    }

    func mangledSignature(
        for symbol: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem,
        nameResolver: ((InternedString) -> String)? = nil
    ) -> String {
        switch symbol.kind {
        case .function, .constructor:
            guard let signature = symbols.functionSignature(for: symbol.id) else {
                return "_"
            }
            let erasedFunctionType = types.make(
                .functionType(
                    FunctionType(
                        receiver: signature.receiverType,
                        params: signature.parameterTypes,
                        returnType: signature.returnType,
                        isSuspend: signature.isSuspend,
                        nullability: .nonNull
                    )
                )
            )
            return encodeType(erasedFunctionType, symbols: symbols, types: types, nameResolver: nameResolver)

        case .property, .field, .backingField:
            guard let propertyType = symbols.propertyType(for: symbol.id) else {
                return "_"
            }
            return encodeType(propertyType, symbols: symbols, types: types, nameResolver: nameResolver)

        case .typeAlias:
            guard let underlyingType = symbols.typeAliasUnderlyingType(for: symbol.id) else {
                return "_"
            }
            return encodeType(underlyingType, symbols: symbols, types: types, nameResolver: nameResolver)

        default:
            return "_"
        }
    }

    private func encodeFQName(_ components: [InternedString], nameResolver: ((InternedString) -> String)?) -> String {
        components
            .map { encode(component: render(name: $0, nameResolver: nameResolver)) }
            .joined(separator: "_")
    }

    private func encode(component: String) -> String {
        "\(component.count)\(component)"
    }

    private func render(name: InternedString, nameResolver: ((InternedString) -> String)?) -> String {
        if let nameResolver {
            return nameResolver(name)
        }
        return String(name.rawValue)
    }

    private func kindCode(_ kind: SymbolKind, declKind: MangledDeclKind) -> String {
        switch declKind {
        case .getter:
            return "G"
        case .setter:
            return "S"
        case .automatic:
            break
        }

        switch kind {
        case .function:
            return "F"
        case .class:
            return "C"
        case .property:
            return "P"
        case .constructor:
            return "K"
        case .object:
            return "O"
        case .typeAlias:
            return "T"
        case .interface:
            return "I"
        case .enumClass:
            return "E"
        case .annotationClass:
            return "A"
        case .package:
            return "N"
        case .field:
            return "D"
        case .backingField:
            return "BF"
        case .typeParameter:
            return "Y"
        case .valueParameter:
            return "V"
        case .local:
            return "L"
        case .label:
            return "B"
        }
    }

    func encodeType(
        _ type: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        nameResolver: ((InternedString) -> String)?
    ) -> String {
        switch types.kind(of: type) {
        case .error:
            return "E"

        case .unit:
            return "U"

        case .nothing(let nullability):
            return applyNullability("N", nullability: nullability)

        case .any(let nullability):
            return applyNullability("A", nullability: nullability)

        case .primitive(let primitive, let nullability):
            let encoded: String
            switch primitive {
            case .boolean:
                encoded = "Z"
            case .char:
                encoded = "C"
            case .int:
                encoded = "I"
            case .long:
                encoded = "J"
            case .float:
                encoded = "F"
            case .double:
                encoded = "D"
            case .string:
                encoded = "Lkotlin_String;"
            }
            return applyNullability(encoded, nullability: nullability)

        case .classType(let classType):
            let className: String
            if let classSymbol = symbols.symbol(classType.classSymbol) {
                className = classSymbol.fqName
                    .map { render(name: $0, nameResolver: nameResolver) }
                    .joined(separator: ".")
            } else {
                className = "sym\(classType.classSymbol.rawValue)"
            }
            var encoded = "L\(className)"
            if !classType.args.isEmpty {
                let args = classType.args.map {
                    encodeTypeArg($0, symbols: symbols, types: types, nameResolver: nameResolver)
                }.joined(separator: ",")
                encoded += "<\(args)>"
            }
            encoded += ";"
            return applyNullability(encoded, nullability: classType.nullability)

        case .typeParam(let typeParam):
            let encoded = "T\(typeParam.symbol.rawValue)"
            return applyNullability(encoded, nullability: typeParam.nullability)

        case .functionType(let functionType):
            var components: [String] = []
            if let receiver = functionType.receiver {
                components.append("R\(encodeType(receiver, symbols: symbols, types: types, nameResolver: nameResolver))")
            }
            components.append(contentsOf: functionType.params.map {
                encodeType($0, symbols: symbols, types: types, nameResolver: nameResolver)
            })
            components.append(encodeType(functionType.returnType, symbols: symbols, types: types, nameResolver: nameResolver))
            let prefix = functionType.isSuspend ? "SF" : "F"
            let encoded = "\(prefix)\(functionType.params.count)<\(components.joined(separator: ","))>"
            return applyNullability(encoded, nullability: functionType.nullability)

        case .intersection(let parts):
            let encodedParts = parts.map {
                encodeType($0, symbols: symbols, types: types, nameResolver: nameResolver)
            }.joined(separator: "&")
            return "X<\(encodedParts)>"
        }
    }

    private func encodeTypeArg(
        _ arg: TypeArg,
        symbols: SymbolTable,
        types: TypeSystem,
        nameResolver: ((InternedString) -> String)?
    ) -> String {
        switch arg {
        case .invariant(let type):
            return encodeType(type, symbols: symbols, types: types, nameResolver: nameResolver)
        case .out(let type):
            return "O<\(encodeType(type, symbols: symbols, types: types, nameResolver: nameResolver))>"
        case .in(let type):
            return "N<\(encodeType(type, symbols: symbols, types: types, nameResolver: nameResolver))>"
        case .star:
            return "*"
        }
    }

    private func applyNullability(_ encoded: String, nullability: Nullability) -> String {
        if nullability == .nullable {
            return "Q<\(encoded)>"
        }
        return encoded
    }

    private func fnv1a32Hex(_ value: String) -> String {
        let prime: UInt32 = 16777619
        var hash: UInt32 = 2166136261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash &*= prime
        }
        return String(format: "%08x", hash)
    }
}
