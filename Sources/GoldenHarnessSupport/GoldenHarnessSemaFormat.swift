@testable import CompilerCore
import Foundation

enum GoldenHarnessSemaFormat {
    static func renderDecl(_ decl: Decl, interner: StringInterner) -> String {
        switch decl {
        case let .classDecl(classDecl):
            "class \(interner.resolve(classDecl.name))"
        case let .interfaceDecl(interfaceDecl):
            "interface \(interner.resolve(interfaceDecl.name))"
        case let .funDecl(funDecl):
            "fun \(interner.resolve(funDecl.name)) suspend=\(funDecl.isSuspend ? 1 : 0) inline=\(funDecl.isInline ? 1 : 0)"
        case let .propertyDecl(propertyDecl):
            "property \(interner.resolve(propertyDecl.name)) var=\(propertyDecl.isVar ? 1 : 0)"
        case let .typeAliasDecl(typeAliasDecl):
            "typealias \(interner.resolve(typeAliasDecl.name))"
        case let .objectDecl(objectDecl):
            "object \(interner.resolve(objectDecl.name))"
        case let .enumEntryDecl(enumEntryDecl):
            "enumEntry \(interner.resolve(enumEntryDecl.name))"
        }
    }

    static func renderDeclSymbol(_ declID: DeclID, sema: SemaModule) -> String {
        if let symbol = sema.bindings.declSymbols[declID] {
            return "s\(symbol.rawValue)"
        }
        return "_"
    }

    static func renderAnnotationArgument(_ argument: String) -> String {
        guard argument.count >= 2,
              argument.first == "\"",
              argument.last == "\""
        else {
            return argument
        }
        let innerStart = argument.index(after: argument.startIndex)
        let innerEnd = argument.index(before: argument.endIndex)
        let inner = String(argument[innerStart ..< innerEnd])
        if inner.first == "\"", inner.last == "\"" {
            return inner
        }
        return argument
    }

    static func renderFunctionSignature(
        _ signature: FunctionSignature,
        types: TypeSystem
    ) -> String {
        let receiver = signature.receiverType.map { types.renderType($0) } ?? "_"
        let parameters = signature.parameterTypes.map { types.renderType($0) }.joined(separator: ",")
        let returnType = types.renderType(signature.returnType)
        let defaults = signature.valueParameterHasDefaultValues.map { $0 ? "1" : "0" }.joined(separator: ",")
        let vararg = signature.valueParameterIsVararg.map { $0 ? "1" : "0" }.joined(separator: ",")
        var result = "recv=\(receiver) params=[\(parameters)] ret=\(returnType)"
        result += " suspend=\(signature.isSuspend ? 1 : 0) defaults=[\(defaults)] vararg=[\(vararg)]"
        let hasBounds = !signature.typeParameterUpperBoundsList.isEmpty
            && signature.typeParameterUpperBoundsList.contains(where: { !$0.isEmpty })
        if hasBounds {
            let bounds = signature.typeParameterUpperBoundsList.map { upperBounds in
                if upperBounds.isEmpty {
                    return "_"
                }
                return upperBounds.map { types.renderType($0) }.joined(separator: "&")
            }.joined(separator: ",")
            result += " bounds=[\(bounds)]"
        }
        return result
    }

    static func renderSymbolFlags(_ flags: SymbolFlags) -> String {
        if flags.isEmpty {
            return "_"
        }
        var names: [String] = []
        if flags.contains(.suspendFunction) { names.append("suspendFunction") }
        if flags.contains(.inlineFunction) { names.append("inlineFunction") }
        if flags.contains(.mutable) { names.append("mutable") }
        if flags.contains(.synthetic) { names.append("synthetic") }
        if flags.contains(.static) { names.append("static") }
        if flags.contains(.sealedType) { names.append("sealedType") }
        if flags.contains(.dataType) { names.append("dataType") }
        if flags.contains(.reifiedTypeParameter) { names.append("reifiedTypeParameter") }
        if flags.contains(.innerClass) { names.append("innerClass") }
        if flags.contains(.valueType) { names.append("valueType") }
        if flags.contains(.operatorFunction) { names.append("operatorFunction") }
        if flags.contains(.constValue) { names.append("constValue") }
        if flags.contains(.abstractType) { names.append("abstractType") }
        if flags.contains(.openType) { names.append("openType") }
        if flags.contains(.overrideMember) { names.append("overrideMember") }
        if flags.contains(.finalMember) { names.append("finalMember") }
        if flags.contains(.funInterface) { names.append("funInterface") }
        if flags.contains(.expectDeclaration) { names.append("expectDeclaration") }
        if flags.contains(.actualDeclaration) { names.append("actualDeclaration") }
        if flags.contains(.readOnlyProperty) { names.append("readOnlyProperty") }
        return names.joined(separator: "|")
    }

    static func renderFQName(
        _ fqName: [InternedString],
        interner: StringInterner
    ) -> String {
        if fqName.isEmpty {
            return "_"
        }
        return fqName.map { interner.resolve($0) }.joined(separator: ".")
    }
}
