/// Enum synthesis methods: `values()`, `entries`, ordinal-to-name,
/// `valueOf(...)`, and the static-init function that materializes
/// enum entry singletons.
///
/// Split out from `DataEnumSealedSynthesisPass.swift`.
extension DataEnumSealedSynthesisPass {
    /// enum entry singletons.
    /// The body is: kk_array_new(count) -> kk_array_set for each entry -> kk_enum_make_values_array.
    func appendSyntheticEnumValuesIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))

        // Compute the enum entry type from the owner symbol
        let entryType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        // values() returns Array<T>, represented as anyType at the erased level
        let returnType = sema.types.anyType

        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)

        var body: [KIRInstruction] = []

        // count constant
        let countExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: intType
        )
        body.append(.constValue(result: countExpr, value: .intLiteral(Int64(entries.count))))

        // kk_array_new(count) -- intermediate array uses anyType
        let arrayExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: sema.types.anyType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_new"),
            arguments: [countExpr],
            result: arrayExpr,
            canThrow: false,
            thrownResult: nil
        ))

        // Enum values are represented by their ordinal payloads at runtime, so
        // populate the array directly with ordinal literals rather than reading
        // enum globals that may not have been static-initialized yet.
        for (ordinal, _) in entries.enumerated() {
            let indexExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: intType
            )
            body.append(.constValue(result: indexExpr, value: .intLiteral(Int64(ordinal))))

            let entryRef = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: entryType
            )
            body.append(.constValue(result: entryRef, value: .intLiteral(Int64(ordinal))))

            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [arrayExpr, indexExpr, entryRef],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        // kk_enum_make_values_array(array, count) -- result uses the enum type
        let listExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: returnType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_enum_make_values_array"),
            arguments: [arrayExpr, countExpr],
            result: listExpr,
            canThrow: false,
            thrownResult: nil
        ))

        body.append(.returnValue(listExpr))

        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Synthesizes the `entries` getter on the companion object.
    /// `Color.entries` returns an EnumEntries (List) containing all enum entry singletons.
    /// The body is: kk_array_new(count) → kk_array_set for each entry → kk_enum_make_entries_list.
    func appendSyntheticEnumEntriesGetterIfNeeded(
        owner: SemanticSymbol,
        enumSymbol: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let getterName = interner.intern("entries$get")

        // Compute correct types from enumSymbol, matching CallLowerer+EnumStdlib pattern
        let entryType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol.id,
            args: [],
            nullability: .nonNull
        )))
        // entries getter returns EnumEntries<T> (List), represented as anyType at the erased level
        let returnType = sema.types.anyType

        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)

        var body: [KIRInstruction] = []

        // count constant
        let countExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: intType
        )
        body.append(.constValue(result: countExpr, value: .intLiteral(Int64(entries.count))))

        // kk_array_new(count) -- intermediate array uses anyType
        let arrayExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: sema.types.anyType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_new"),
            arguments: [countExpr],
            result: arrayExpr,
            canThrow: false,
            thrownResult: nil
        ))

        // Enum values are represented by their ordinal payloads at runtime, so
        // populate the array directly with ordinal literals rather than reading
        // enum globals that may not have been static-initialized yet.
        for (ordinal, _) in entries.enumerated() {
            let indexExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: intType
            )
            body.append(.constValue(result: indexExpr, value: .intLiteral(Int64(ordinal))))

            let entryRef = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)), type: entryType
            )
            body.append(.constValue(result: entryRef, value: .intLiteral(Int64(ordinal))))

            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [arrayExpr, indexExpr, entryRef],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        // kk_enum_make_entries_list(array, count) -- returns List for EnumEntries
        let listExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)), type: returnType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_enum_make_entries_list"),
            arguments: [arrayExpr, countExpr],
            result: listExpr,
            canThrow: false,
            thrownResult: nil
        ))

        body.append(.returnValue(listExpr))

        appendSyntheticFunctionIfNeeded(
            name: getterName,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Synthesizes `$enumOrdinalToName(ordinal: Int): String` for (valueOf result).name.
    /// Switches on ordinal and returns the entry name via the per-entry $enumName helpers.
    func appendSyntheticEnumOrdinalToNameIfNeeded(
        owner: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let name = interner.intern("$enumOrdinalToName")
        let fqName = owner.fqName + [name]
        let paramName = interner.intern("$ordinal")
        let paramSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: fqName + [paramName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let param = KIRParameter(symbol: paramSymbol, type: intType)
        let paramRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: intType)
        let unboxedOrdinalRef = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: intType
        )

        var body: [KIRInstruction] = []
        body.append(.constValue(result: paramRef, value: .symbolRef(paramSymbol)))
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_unbox_int"),
            arguments: [paramRef],
            result: unboxedOrdinalRef,
            canThrow: false,
            thrownResult: nil
        ))
        var labelCounter: Int32 = 6000

        for (ordinal, entry) in entries.enumerated() {
            let entryName = interner.resolve(entry.name)
            let helperName = interner.intern("\(entryName)$enumName")
            let resultExpr = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: stringType
            )
            let ordinalExpr = module.arena.appendExpr(
                .intLiteral(Int64(ordinal)),
                type: intType
            )
            body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))
            let nextLabel = labelCounter
            labelCounter += 1
            let matchLabel = labelCounter
            labelCounter += 1
            body.append(.jumpIfEqual(lhs: unboxedOrdinalRef, rhs: ordinalExpr, target: matchLabel))
            body.append(.jump(nextLabel))
            body.append(.label(matchLabel))
            body.append(.call(
                symbol: nil,
                callee: helperName,
                arguments: [],
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ))
            body.append(.returnValue(resultExpr))
            body.append(.label(nextLabel))
        }
        let emptyExpr = module.arena.appendExpr(
            .stringLiteral(interner.intern("")),
            type: stringType
        )
        body.append(.constValue(result: emptyExpr, value: .stringLiteral(interner.intern(""))))
        body.append(.returnValue(emptyExpr))

        let signature = FunctionSignature(
            parameterTypes: [intType],
            returnType: stringType,
            isSuspend: false,
            valueParameterSymbols: [paramSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [param],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Synthesizes `valueOf(String)` which does a linear comparison of the
    /// argument against each entry name and returns the matching ordinal.
    /// If no match is found, it calls `kk_enum_valueOf_throw` to signal an
    /// IllegalArgumentException. When owner is the companion, uses the stub's
    /// symbol so Color.valueOf resolves to the same KIR function.
    func appendSyntheticEnumValueOfIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        enumName: InternedString,
        enumType: TypeID,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let stringType = sema.types.make(.primitive(.string, .nonNull))

        let fqName = owner.fqName + [name]
        let parameterName = interner.intern("$name")
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: stringType)
        let paramRef = module.arena.appendExpr(
            .symbolRef(parameterSymbol),
            type: stringType
        )

        var body: [KIRInstruction] = []
        body.append(.constValue(result: paramRef, value: .symbolRef(parameterSymbol)))

        var labelCounter: Int32 = 5000

        // For each entry, compare name and return ordinal if matched
        for (ordinal, entry) in entries.enumerated() {
            let entryNameStr = interner.intern(interner.resolve(entry.name))
            let entryNameExpr = module.arena.appendExpr(
                .stringLiteral(entryNameStr),
                type: stringType
            )
            body.append(.constValue(result: entryNameExpr, value: .stringLiteral(entryNameStr)))

            let cmpResult = module.arena.appendExpr(
                .temporary(Int32(module.arena.expressions.count)),
                type: sema.types.make(.primitive(.boolean, .nonNull))
            )
            let cmpCallee = interner.intern("kk_string_equals")
            body.append(.call(
                symbol: nil,
                callee: cmpCallee,
                arguments: [paramRef, entryNameExpr],
                result: cmpResult,
                canThrow: false,
                thrownResult: nil
            ))

            let falseExpr = module.arena.appendExpr(
                .boolLiteral(false),
                type: sema.types.make(.primitive(.boolean, .nonNull))
            )
            body.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

            let nextLabel = labelCounter
            labelCounter += 1

            body.append(.jumpIfEqual(lhs: cmpResult, rhs: falseExpr, target: nextLabel))

            // Match found – return ordinal (enum values are represented as ordinals)
            let ordinalExpr = module.arena.appendExpr(
                .intLiteral(Int64(ordinal)),
                type: enumType
            )
            body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))
            body.append(.returnValue(ordinalExpr))

            body.append(.label(nextLabel))
        }

        // No match – build "ClassName." + name and call throw helper.
        // Kotlin throws: IllegalArgumentException: No enum constant ClassName.value
        let classNameStr = interner.resolve(enumName)
        let prefixInterned = interner.intern("\(classNameStr).")
        let prefixExpr = module.arena.appendExpr(
            .stringLiteral(prefixInterned),
            type: stringType
        )
        body.append(.constValue(result: prefixExpr, value: .stringLiteral(prefixInterned)))

        let qualifiedNameExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: stringType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_string_concat"),
            arguments: [prefixExpr, paramRef],
            result: qualifiedNameExpr,
            canThrow: false,
            thrownResult: nil
        ))

        let throwCallee = interner.intern("kk_enum_valueOf_throw")
        let throwResult = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: sema.types.nothingType
        )
        body.append(.call(
            symbol: nil,
            callee: throwCallee,
            arguments: [qualifiedNameExpr],
            result: throwResult,
            canThrow: true,
            thrownResult: nil
        ))
        body.append(.returnValue(throwResult))

        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let signature = FunctionSignature(
            receiverType: companionType,
            parameterTypes: [stringType],
            returnType: enumType,
            isSuspend: false,
            valueParameterSymbols: [parameterSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )

        // Use existing stub symbol when companion has valueOf from Sema
        let existingValueOf = sema.symbols.lookupAll(fqName: fqName).first { candidate in
            guard let sym = sema.symbols.symbol(candidate),
                  sym.kind == .function,
                  sym.flags.contains(.synthetic),
                  sema.symbols.parentSymbol(for: candidate) == owner.id
            else { return false }
            return true
        }
        if let existingSymbol = existingValueOf, !existingFunctionSymbols.contains(existingSymbol) {
            let receiverParam = KIRParameter(
                symbol: sema.symbols.define(
                    kind: .valueParameter,
                    name: interner.intern("$self"),
                    fqName: fqName + [interner.intern("$self")],
                    declSite: owner.declSite,
                    visibility: .private,
                    flags: [.synthetic]
                ),
                type: companionType
            )
            appendSyntheticFunctionWithSymbol(
                functionSymbol: existingSymbol,
                name: name,
                module: module,
                sema: sema,
                signature: signature,
                params: [receiverParam, parameter],
                body: body
            )
        } else {
            let receiverParam = KIRParameter(
                symbol: sema.symbols.define(
                    kind: .valueParameter,
                    name: interner.intern("$self"),
                    fqName: fqName + [interner.intern("$self")],
                    declSite: owner.declSite,
                    visibility: .private,
                    flags: [.synthetic]
                ),
                type: companionType
            )
            appendSyntheticFunctionIfNeeded(
                name: name,
                owner: owner,
                module: module,
                sema: sema,
                signature: signature,
                params: [receiverParam, parameter],
                body: body,
                existingFunctionSymbols: existingFunctionSymbols
            )
        }
    }

    /// Synthesizes `__enum_static_init_<ClassName>()` which initialises the
    /// global slots for each enum entry with their ordinal values, and ensures
    /// KIRGlobal declarations exist so that codegen allocates LLVM global
    /// variables for the entries. These globals model ordinal storage, so the
    /// slot declarations and writes must stay typed as `Int`.
    func appendSyntheticEnumStaticInitIfNeeded(
        owner: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard !entries.isEmpty else { return }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        // Collect existing global symbols so we don't create duplicates.
        var existingGlobalSymbols = Set(module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .global(global) = decl else {
                return nil
            }
            return global.symbol
        })

        // Ensure a KIRGlobal exists for every entry field. BuildKIR emits these
        // for `enumEntryDecl` nodes, but when the enum class comes from a
        // nominalType-only module (e.g. library metadata) the globals may be
        // absent. Adding them here is idempotent thanks to the guard.
        for entry in entries {
            if !existingGlobalSymbols.contains(entry.id) {
                _ = module.arena.appendDecl(.global(KIRGlobal(symbol: entry.id, type: intType)))
                existingGlobalSymbols.insert(entry.id)
            }
        }

        // Build the static initialiser body.
        let ownerName = interner.resolve(owner.name)
        let initName = interner.intern("__enum_static_init_\(ownerName)")

        var body: [KIRInstruction] = []

        for (ordinal, entry) in entries.enumerated() {
            // Produce the ordinal value.
            let ordinalExpr = module.arena.appendExpr(
                .intLiteral(Int64(ordinal)),
                type: intType
            )
            body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))

            // Reference the entry's global slot.
            let entryRef = module.arena.appendExpr(
                .symbolRef(entry.id),
                type: intType
            )
            body.append(.constValue(result: entryRef, value: .symbolRef(entry.id)))

            // Store ordinal into the global slot.
            body.append(.copy(from: ordinalExpr, to: entryRef))
        }

        body.append(.returnUnit)

        let unitType = sema.types.unitType
        let signature = FunctionSignature(parameterTypes: [], returnType: unitType, isSuspend: false)

        appendSyntheticFunctionIfNeeded(
            name: initName,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Appends a KIR function using an existing symbol (e.g. from Sema). Used when the symbol
    /// was already registered for resolution so call sites bind to the same symbol.
}
