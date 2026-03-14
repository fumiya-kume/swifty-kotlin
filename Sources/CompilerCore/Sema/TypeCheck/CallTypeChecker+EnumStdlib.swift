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
        let enumValuesName = interner.intern("enumValues")
        let enumValueOfName = interner.intern("enumValueOf")
        guard calleeName == enumValuesName || calleeName == enumValueOfName else {
            return nil
        }
        let (visibleCandidates, _) = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName))
        let hasNonSyntheticUserCandidate = visibleCandidates.contains { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else {
                return false
            }
            return !symbol.flags.contains(.synthetic)
        }
        if locals[calleeName] != nil || hasNonSyntheticUserCandidate {
            return nil
        }
        guard explicitTypeArgs.count == 1 else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "Expected exactly one type argument for `\(interner.resolve(calleeName))`.",
                range: range
            )
            return nil
        }
        let typeArg = explicitTypeArgs[0]
        guard case let .classType(classType) = sema.types.kind(of: typeArg),
              classType.nullability == .nonNull,
              let nominalSymbol = sema.symbols.symbol(classType.classSymbol),
              nominalSymbol.kind == .enumClass
        else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "`\(interner.resolve(calleeName))` requires exactly one non-nullable enum type argument.",
                range: range
            )
            return nil
        }

        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: classType.classSymbol,
            args: [],
            nullability: .nonNull
        )))

        if calleeName == enumValuesName {
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

        if calleeName == enumValueOfName {
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
