import Foundation

enum EnumStdlibSpecialCallResult {
    case enumValues(enumType: TypeID, listType: TypeID, stubSymbol: SymbolID)
    case enumValueOf(enumType: TypeID, stubSymbol: SymbolID)
}

extension CallTypeChecker {
    func enumStdlibSpecialCallKind(
        calleeName: InternedString,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        interner: StringInterner,
        sema: SemaModule,
        range: SourceRange
    ) -> EnumStdlibSpecialCallResult? {
        let name = interner.resolve(calleeName)
        guard name == "enumValues" || name == "enumValueOf" else {
            return nil
        }
        if locals[calleeName] != nil {
            return nil
        }
        guard explicitTypeArgs.count == 1 else {
            return nil
        }
        let typeArg = explicitTypeArgs[0]
        guard case let .classType(classType) = sema.types.kind(of: typeArg),
              let nominalSymbol = sema.symbols.symbol(classType.classSymbol),
              nominalSymbol.kind == .enumClass
        else {
            return nil
        }

        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: classType.classSymbol,
            args: [],
            nullability: .nonNull
        )))

        if name == "enumValues" {
            guard args.isEmpty else {
                return nil
            }
            let listSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("List"),
            ])
            guard let listSymbol else {
                return nil
            }
            let listType = sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(enumType)],
                nullability: .nonNull
            )))
            let stubSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("enumValues"),
            ])
            guard let stubSymbol else {
                return nil
            }
            return .enumValues(enumType: enumType, listType: listType, stubSymbol: stubSymbol)
        }

        if name == "enumValueOf" {
            guard args.count == 1 else {
                return nil
            }
            let stubSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("enumValueOf"),
            ])
            guard let stubSymbol else {
                return nil
            }
            return .enumValueOf(enumType: enumType, stubSymbol: stubSymbol)
        }

        return nil
    }
}
