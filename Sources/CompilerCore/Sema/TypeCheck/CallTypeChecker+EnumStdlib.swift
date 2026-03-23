import Foundation

enum EnumStdlibSpecialCallResult {
    case enumValues(enumType: TypeID, arrayType: TypeID, stubSymbol: SymbolID)
    case enumValueOf(enumType: TypeID, stubSymbol: SymbolID)
    case enumEntries(enumType: TypeID, entriesType: TypeID, stubSymbol: SymbolID)
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
        let enumEntriesName = interner.intern("enumEntries")
        guard calleeName == enumValuesName || calleeName == enumValueOfName || calleeName == enumEntriesName else {
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
            let arraySymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("Array"),
            ])
            guard let arraySymbol else {
                return nil
            }
            let arrayType = sema.types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
            let stubSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("enumValues"),
            ])
            guard let stubSymbol else {
                return nil
            }
            return .enumValues(enumType: enumType, arrayType: arrayType, stubSymbol: stubSymbol)
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

        if calleeName == enumEntriesName {
            guard args.isEmpty else {
                return nil
            }
            let enumEntriesInterfaceSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("EnumEntries"),
            ])
            guard let enumEntriesInterfaceSymbol else {
                return nil
            }
            let entriesType = sema.types.make(.classType(ClassType(
                classSymbol: enumEntriesInterfaceSymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
            let stubSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("enumEntries"),
            ])
            guard let stubSymbol else {
                return nil
            }
            return .enumEntries(enumType: enumType, entriesType: entriesType, stubSymbol: stubSymbol)
        }

        return nil
    }
}
