import Foundation

// swiftlint:disable:next type_body_length
final class DataEnumSealedSynthesisPass: LoweringPass {
    static let name = "DataEnumSealedSynthesis"

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            if updated.body.isEmpty {
                updated.body = [.nop, .returnUnit]
            }
            return updated
        }

        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let existingFunctionSymbols = Set(module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .function(function) = decl else {
                return nil
            }
            return function.symbol
        })
        let nominalSymbols = module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .nominalType(nominal) = decl else {
                return nil
            }
            return nominal.symbol
        }

        for nominalSymbolID in nominalSymbols {
            guard let nominalSymbol = sema.symbols.symbol(nominalSymbolID) else {
                continue
            }

            if nominalSymbol.kind == .enumClass {
                let entries = enumEntrySymbols(owner: nominalSymbol, symbols: sema.symbols)
                let valuesCount = Int64(entries.count)
                let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$enumValuesCount")
                appendSyntheticCountFunctionIfNeeded(
                    name: helperName,
                    owner: nominalSymbol,
                    value: valuesCount,
                    returnType: intType,
                    module: module,
                    sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols
                )

                let stringType = sema.types.make(.primitive(.string, .nonNull))

                // Synthesize ordinal and name helpers per entry
                for (ordinal, entry) in entries.enumerated() {
                    let entryName = ctx.interner.resolve(entry.name)

                    let ordinalHelperName = ctx.interner.intern("\(entryName)$enumOrdinal")
                    appendSyntheticCountFunctionIfNeeded(
                        name: ordinalHelperName,
                        owner: nominalSymbol,
                        value: Int64(ordinal),
                        returnType: intType,
                        module: module,
                        sema: sema,
                        existingFunctionSymbols: existingFunctionSymbols
                    )

                    let nameHelperName = ctx.interner.intern("\(entryName)$enumName")
                    appendSyntheticStringFunctionIfNeeded(
                        name: nameHelperName,
                        owner: nominalSymbol,
                        value: ctx.interner.intern(entryName),
                        returnType: stringType,
                        module: module,
                        sema: sema,
                        existingFunctionSymbols: existingFunctionSymbols
                    )
                }

                // Synthesize values() – returns count followed by entry ordinals
                let valuesName = ctx.interner.intern("values")
                appendSyntheticEnumValuesIfNeeded(
                    name: valuesName,
                    owner: nominalSymbol,
                    entries: entries,
                    module: module,
                    sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols
                )

                // Synthesize valueOf(String)
                let valueOfName = ctx.interner.intern("valueOf")
                appendSyntheticEnumValueOfIfNeeded(
                    name: valueOfName,
                    owner: nominalSymbol,
                    entries: entries,
                    module: module,
                    sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols,
                    interner: ctx.interner
                )
            }

            if nominalSymbol.flags.contains(.sealedType) {
                let subtypeCount = Int64(sema.symbols.directSubtypes(of: nominalSymbol.id).count)
                let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$sealedSubtypeCount")
                appendSyntheticCountFunctionIfNeeded(
                    name: helperName,
                    owner: nominalSymbol,
                    value: subtypeCount,
                    returnType: intType,
                    module: module,
                    sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols
                )
            }

            if nominalSymbol.flags.contains(.dataType) {
                let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$copy")
                appendSyntheticDataCopyIfNeeded(
                    name: helperName,
                    owner: nominalSymbol,
                    module: module,
                    sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols,
                    interner: ctx.interner
                )
                if nominalSymbol.kind == .object {
                    let toStringName = ctx.interner.intern("toString")
                    let objectNameStr = nominalSymbol.name
                    let toStringFQName = nominalSymbol.fqName + [toStringName]
                    let existingToStringSymbol = sema.symbols.lookupAll(fqName: toStringFQName).first { id in
                        sema.symbols.symbol(id).map { $0.flags.contains(.synthetic) } ?? false
                    }
                    appendSyntheticDataObjectToStringIfNeeded(
                        name: toStringName,
                        owner: nominalSymbol,
                        objectName: objectNameStr,
                        existingSymbol: existingToStringSymbol,
                        module: module,
                        sema: sema,
                        existingFunctionSymbols: existingFunctionSymbols,
                        interner: ctx.interner
                    )
                    let equalsName = ctx.interner.intern("equals")
                    let equalsFQName = nominalSymbol.fqName + [equalsName]
                    let existingEqualsSymbol = sema.symbols.lookupAll(fqName: equalsFQName).first { id in
                        sema.symbols.symbol(id).map { $0.flags.contains(.synthetic) } ?? false
                    }
                    appendSyntheticDataObjectEqualsIfNeeded(
                        owner: nominalSymbol,
                        existingSymbol: existingEqualsSymbol,
                        module: module,
                        sema: sema,
                        existingFunctionSymbols: existingFunctionSymbols,
                        interner: ctx.interner
                    )
                }
            }
        }

        module.recordLowering(Self.name)
    }

    private func enumEntrySymbols(owner: SemanticSymbol, symbols: SymbolTable) -> [SemanticSymbol] {
        symbols.children(ofFQName: owner.fqName)
            .compactMap { symbols.symbol($0) }
            .filter { $0.kind == .field }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })
    }

    private func appendSyntheticCountFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        value: Int64,
        returnType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: returnType
        )
        // swiftlint:disable trailing_comma
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .intLiteral(value)),
            .returnValue(resultExpr),
        ]
        // swiftlint:enable trailing_comma
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

    private func appendSyntheticDataCopyIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class || owner.kind == .enumClass || owner.kind == .object else {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let parameterName = interner.intern("$self")
        let fqName = owner.fqName + [name]
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: receiverType)
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: receiverType
        )
        // swiftlint:disable trailing_comma
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .symbolRef(parameterSymbol)),
            .returnValue(resultExpr),
        ]
        // swiftlint:enable trailing_comma
        let signature = FunctionSignature(
            parameterTypes: [receiverType],
            returnType: receiverType,
            isSuspend: false,
            valueParameterSymbols: [parameterSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    // swiftlint:disable function_parameter_count
    /// Synthesizes `toString(): String` for data object, returning the object name.
    /// Uses existingSymbol when provided (from Sema) so call resolution matches the KIR function.
    private func appendSyntheticDataObjectToStringIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        objectName: InternedString,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .object, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let parameterName = interner.intern("$self")
        let fqName = owner.fqName + [name]
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: receiverType)
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: stringType
        )
        // swiftlint:disable trailing_comma
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .stringLiteral(objectName)),
            .returnValue(resultExpr),
        ]
        // swiftlint:enable trailing_comma
        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: stringType,
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: [],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: name,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body
        )
    }

    // swiftlint:enable function_parameter_count

    // swiftlint:disable function_parameter_count function_body_length
    /// Synthesizes `equals(other: Any?): Boolean` for data object (identity comparison via kk_op_eq).
    private func appendSyntheticDataObjectEqualsIfNeeded(
        owner: SemanticSymbol,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .object, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = sema.types.nullableAnyType
        let equalsName = interner.intern("equals")
        let paramName = interner.intern("other")
        let fqName = owner.fqName + [equalsName]
        let paramSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: fqName + [paramName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverParam = KIRParameter(
            symbol: sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("$self"),
                fqName: fqName + [interner.intern("$self")],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            ),
            type: receiverType
        )
        let otherParam = KIRParameter(symbol: paramSymbol, type: nullableAnyType)
        let receiverRef = module.arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
        let otherRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: nullableAnyType)
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: boolType
        )
        // swiftlint:disable trailing_comma
        let body: [KIRInstruction] = [
            .constValue(result: receiverRef, value: .symbolRef(receiverParam.symbol)),
            .constValue(result: otherRef, value: .symbolRef(paramSymbol)),
            .call(
                symbol: nil,
                callee: interner.intern("kk_op_eq"),
                arguments: [receiverRef, otherRef],
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ),
            .returnValue(resultExpr),
        ]
        // swiftlint:enable trailing_comma
        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [nullableAnyType],
            returnType: boolType,
            isSuspend: false,
            valueParameterSymbols: [paramSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: equalsName,
            module: module,
            sema: sema,
            signature: signature,
            params: [receiverParam, otherParam],
            body: body
        )
    }

    // swiftlint:enable function_parameter_count function_body_length

    private func appendSyntheticStringFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        value: InternedString,
        returnType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)
        let resultExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: returnType
        )
        // swiftlint:disable trailing_comma
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .stringLiteral(value)),
            .returnValue(resultExpr),
        ]
        // swiftlint:enable trailing_comma
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

    /// Synthesizes `values()` which calls `kk_enum_values_<ClassName>` with
    /// the count of entries. The runtime or codegen is expected to return an
    /// array-like representation. The body emits a call to a well-known
    /// helper `kk_enum_values` passing the count as argument.
    private func appendSyntheticEnumValuesIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))

        // values() returns an Int (count) which codegen interprets as the
        // number of entries in the enum. Each entry's ordinal/name can be
        // retrieved through the per-entry helpers.
        let signature = FunctionSignature(parameterTypes: [], returnType: intType, isSuspend: false)

        var body: [KIRInstruction] = []

        // Emit count constant
        let countExpr = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: intType
        )
        body.append(.constValue(result: countExpr, value: .intLiteral(Int64(entries.count))))

        // Directly return the count; the runtime helper for building an
        // Array<T> will be introduced when the full array return type is wired.
        body.append(.returnValue(countExpr))

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

    /// Synthesizes `valueOf(String)` which does a linear comparison of the
    /// argument against each entry name and returns the matching ordinal.
    /// If no match is found, it calls `kk_enum_valueOf_throw` to signal an
    /// IllegalArgumentException.
    private func appendSyntheticEnumValueOfIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))

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

            // Match found – return ordinal
            let ordinalExpr = module.arena.appendExpr(
                .intLiteral(Int64(ordinal)),
                type: intType
            )
            body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))
            body.append(.returnValue(ordinalExpr))

            body.append(.label(nextLabel))
        }

        // No match – call throw helper
        let throwCallee = interner.intern("kk_enum_valueOf_throw")
        let throwResult = module.arena.appendExpr(
            .temporary(Int32(module.arena.expressions.count)),
            type: sema.types.nothingType
        )
        body.append(.call(
            symbol: nil,
            callee: throwCallee,
            arguments: [paramRef],
            result: throwResult,
            canThrow: true,
            thrownResult: nil
        ))
        body.append(.returnValue(throwResult))

        let signature = FunctionSignature(
            parameterTypes: [stringType],
            returnType: intType,
            isSuspend: false,
            valueParameterSymbols: [parameterSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    // swiftlint:disable function_parameter_count
    /// Appends a KIR function using an existing symbol (e.g. from Sema). Used when the symbol
    /// was already registered for resolution so call sites bind to the same symbol.
    private func appendSyntheticFunctionWithSymbol(
        functionSymbol: SymbolID,
        name: InternedString,
        module: KIRModule,
        sema: SemaModule,
        signature: FunctionSignature,
        params: [KIRParameter],
        body: [KIRInstruction]
    ) {
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: signature.receiverType,
                parameterTypes: signature.parameterTypes,
                returnType: signature.returnType,
                isSuspend: signature.isSuspend,
                valueParameterSymbols: params.map(\.symbol),
                valueParameterHasDefaultValues: params.map { _ in false },
                valueParameterIsVararg: params.map { _ in false },
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
        _ = module.arena.appendDecl(.function(
            KIRFunction(
                symbol: functionSymbol,
                name: name,
                params: params,
                returnType: signature.returnType,
                body: body,
                isSuspend: false,
                isInline: false
            )
        ))
    }

    // swiftlint:enable function_parameter_count

    private func appendSyntheticFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        signature: FunctionSignature,
        params: [KIRParameter],
        body: [KIRInstruction],
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let fqName = owner.fqName + [name]
        let nonSyntheticConflict = sema.symbols.lookupAll(fqName: fqName).contains { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID) else {
                return false
            }
            return symbol.kind == .function && !symbol.flags.contains(.synthetic)
        }
        if nonSyntheticConflict {
            return
        }

        let functionSymbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: fqName,
            declSite: owner.declSite,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: signature.receiverType,
                parameterTypes: signature.parameterTypes,
                returnType: signature.returnType,
                isSuspend: signature.isSuspend,
                valueParameterSymbols: params.map(\.symbol),
                valueParameterHasDefaultValues: params.map { _ in false },
                valueParameterIsVararg: params.map { _ in false },
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
        _ = module.arena.appendDecl(.function(
            KIRFunction(
                symbol: functionSymbol,
                name: name,
                params: params,
                returnType: signature.returnType,
                body: body,
                isSuspend: false,
                isInline: false
            )
        ))
    }
    // swiftlint:disable:next file_length
}
