
/// Rewrites `kotlin.io.print`/`println` call sites so class, data-class and
/// enum values print via their `toString()` implementation instead of
/// `Any.toString()` falling back to the raw handle.
///
/// With `print`/`println` implemented in bundled Kotlin source, the `Any?`
/// receiver inside `Console.kt` loses the static class type, so the compiler
/// emits the generic `kk_any_to_string` path. This pass restores the previous
/// behavior by rewriting call sites at the KIR level, before `println` bodies
/// are inlined.
final class ConsolePrintLoweringPass: LoweringPass, ParallelLoweringPass {
    static let name = "ConsolePrintLowering"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        _ = module
        _ = ctx
        return true
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }
        let rawPrintCallee = ctx.interner.intern("__kk_print_raw")
        let intType = sema.types.intType
        let stringType = sema.types.stringType
        let kotlinName = ctx.interner.intern("kotlin")
        let ioName = ctx.interner.intern("io")
        let printlnName = ctx.interner.intern("println")
        let printName = ctx.interner.intern("print")

        module.arena.transformFunctions { function in
            var updated = function
            var newBody: [KIRInstruction] = []
            newBody.reserveCapacity(function.body.count)
            var nextLabel = Self.maxLabelNumber(in: function.body) + 1
            func allocateLabel() -> Int32 {
                defer { nextLabel += 1 }
                return nextLabel
            }

            for instruction in function.body {
                switch instruction {
                case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, _):
                    if let printKind = Self.consolePrintKind(
                        symbol: symbol,
                        callee: callee,
                        arguments: arguments,
                        sema: sema,
                        interner: ctx.interner,
                        kotlinName: kotlinName,
                        ioName: ioName,
                        printlnName: printlnName,
                        printName: printName
                    ),
                       self.rewritePrintCall(
                           isPrintln: printKind == .println,
                           symbol: symbol,
                           callee: callee,
                           arguments: arguments,
                           result: result,
                           canThrow: canThrow,
                           thrownResult: thrownResult,
                           isSuperCall: isSuperCall,
                           arena: module.arena,
                           sema: sema,
                           interner: ctx.interner,
                           rawPrintCallee: rawPrintCallee,
                           stringType: stringType,
                           intType: intType,
                           newBody: &newBody,
                           allocateLabel: allocateLabel
                       )
                    {
                        continue
                    }
                    newBody.append(instruction)
                default:
                    newBody.append(instruction)
                }
            }
            updated.replaceBody(newBody)
            return updated
        }
        module.recordLowering(Self.name)
    }

    private enum PrintKind {
        case print
        case println
    }

    /// Returns the console-print kind when the instruction is a call to
    /// `kotlin.io.print` or `kotlin.io.println`. Handles both source-backed
    /// calls (callee name is `print`/`println`) and library-imported calls
    /// (callee is `kk_fn_print...` but the symbol is the Kotlin function).
    private static func consolePrintKind(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        sema: SemaModule,
        interner: StringInterner,
        kotlinName: InternedString,
        ioName: InternedString,
        printlnName: InternedString,
        printName: InternedString
    ) -> PrintKind? {
        guard arguments.count <= 1 else { return nil }

        let calleeStr = interner.resolve(callee)
        if calleeStr == "println" {
            return .println
        }
        if calleeStr == "print" {
            return .print
        }

        guard let symbol,
              let sym = sema.symbols.symbol(symbol)
        else {
            return nil
        }

        let isConsoleName = sym.name == printlnName || sym.name == printName
        let isConsolePackage = sym.fqName.count == 3
            && sym.fqName[0] == kotlinName
            && sym.fqName[1] == ioName
        guard isConsoleName && isConsolePackage else {
            return nil
        }
        return sym.name == printlnName ? .println : .print
    }

    private func rewritePrintCall(
        isPrintln: Bool,
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        canThrow: Bool,
        thrownResult: KIRExprID?,
        isSuperCall: Bool,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        rawPrintCallee: InternedString,
        stringType: TypeID,
        intType: TypeID,
        newBody: inout [KIRInstruction],
        allocateLabel: () -> Int32
    ) -> Bool {
        if arguments.isEmpty {
            if isPrintln {
                let newline = appendStringLiteralConst("\n", arena: arena, interner: interner, stringType: stringType, to: &newBody)
                appendPrintRaw(newline, rawPrintCallee: rawPrintCallee, to: &newBody)
            }
            appendUnitResult(result, to: &newBody)
            return true
        }

        let argument = arguments[0]

        if let stringExpr = primitiveToStringExpression(
            argument: argument,
            arena: arena,
            sema: sema,
            interner: interner,
            stringType: stringType,
            intType: intType,
            newBody: &newBody
        ) {
            appendPrintRaw(stringExpr, rawPrintCallee: rawPrintCallee, to: &newBody)
            if isPrintln {
                let newline = appendStringLiteralConst("\n", arena: arena, interner: interner, stringType: stringType, to: &newBody)
                appendPrintRaw(newline, rawPrintCallee: rawPrintCallee, to: &newBody)
            }
            appendUnitResult(result, to: &newBody)
            return true
        }

        let argType = arena.exprType(argument) ?? sema.types.anyType
        let nonNullType = sema.types.makeNonNullable(argType)

        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let classSymbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }

        if sema.types.nullability(of: argType) != .nonNull {
            // Build the non-null rewrite first on a scratch body so we only
            // commit the branch when a class-specific toString is available.
            var nonNullBody: [KIRInstruction] = []
            guard let stringExpr = Self.classToStringExpression(
                argument: argument,
                classSymbol: classSymbol,
                receiverType: nonNullType,
                arena: arena,
                sema: sema,
                interner: interner,
                stringType: stringType
            ) else {
                return false
            }
            nonNullBody.append(contentsOf: stringExpr.instructions)
            appendPrintRaw(stringExpr.value, rawPrintCallee: rawPrintCallee, to: &nonNullBody)
            if isPrintln {
                let newline = appendStringLiteralConst("\n", arena: arena, interner: interner, stringType: stringType, to: &nonNullBody)
                appendPrintRaw(newline, rawPrintCallee: rawPrintCallee, to: &nonNullBody)
            }
            appendUnitResult(result, to: &nonNullBody)

            let nonNullLabel = allocateLabel()
            let endLabel = allocateLabel()

            // Null path: print "null" (and newline for println), then unit result.
            newBody.append(.jumpIfNotNull(value: argument, target: nonNullLabel))
            let nullString = appendStringLiteralConst("null", arena: arena, interner: interner, stringType: stringType, to: &newBody)
            appendPrintRaw(nullString, rawPrintCallee: rawPrintCallee, to: &newBody)
            if isPrintln {
                let newline = appendStringLiteralConst("\n", arena: arena, interner: interner, stringType: stringType, to: &newBody)
                appendPrintRaw(newline, rawPrintCallee: rawPrintCallee, to: &newBody)
            }
            appendUnitResult(result, to: &newBody)
            newBody.append(.jump(endLabel))

            // Non-null path.
            newBody.append(.label(nonNullLabel))
            newBody.append(contentsOf: nonNullBody)
            newBody.append(.label(endLabel))
            return true
        }

        guard let stringExpr = Self.classToStringExpression(
            argument: argument,
            classSymbol: classSymbol,
            receiverType: nonNullType,
            arena: arena,
            sema: sema,
            interner: interner,
            stringType: stringType
        ) else {
            return false
        }
        newBody.append(contentsOf: stringExpr.instructions)
        appendPrintRaw(stringExpr.value, rawPrintCallee: rawPrintCallee, to: &newBody)
        if isPrintln {
            let newline = appendStringLiteralConst("\n", arena: arena, interner: interner, stringType: stringType, to: &newBody)
            appendPrintRaw(newline, rawPrintCallee: rawPrintCallee, to: &newBody)
        }
        appendUnitResult(result, to: &newBody)
        return true
    }

    private func stringLiteral(
        _ value: String,
        arena: KIRArena,
        interner: StringInterner,
        stringType: TypeID
    ) -> KIRExprID {
        let interned = interner.intern(value)
        let expr = arena.appendExpr(.stringLiteral(interned), type: stringType)
        return expr
    }

    private func appendStringLiteralConst(
        _ value: String,
        arena: KIRArena,
        interner: StringInterner,
        stringType: TypeID,
        to body: inout [KIRInstruction]
    ) -> KIRExprID {
        let expr = stringLiteral(value, arena: arena, interner: interner, stringType: stringType)
        body.append(.constValue(result: expr, value: .stringLiteral(interner.intern(value))))
        return expr
    }

    private func appendPrintRaw(
        _ value: KIRExprID,
        rawPrintCallee: InternedString,
        to body: inout [KIRInstruction]
    ) {
        body.append(.call(
            symbol: nil,
            callee: rawPrintCallee,
            arguments: [value],
            result: nil,
            canThrow: false,
            thrownResult: nil,
            isSuperCall: false
        ))
    }

    private func appendUnitResult(_ result: KIRExprID?, to body: inout [KIRInstruction]) {
        if let result {
            body.append(.constValue(result: result, value: .unit))
        }
    }

    /// Returns a string expression for a primitive or string `println`/`print`
    /// argument, appending any needed instructions to `newBody`. Returns nil
    /// when the argument is not a primitive or string type (callers should fall
    /// through to class / `Any?` handling).
    private func primitiveToStringExpression(
        argument: KIRExprID,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        stringType: TypeID,
        intType: TypeID,
        newBody: inout [KIRInstruction]
    ) -> KIRExprID? {
        let argType = arena.exprType(argument) ?? inferPrimitiveType(
            argument: argument,
            sema: sema,
            interner: interner,
            newBody: newBody
        )
        let nonNullType = sema.types.makeNonNullable(argType)
        let kind = sema.types.kind(of: nonNullType)

        // String values should keep flowing through `kotlin.io.println` so the
        // existing String/Any boxing path (and the flat String ABI for virtual
        // dispatch) is preserved; only primitive scalars are rewritten here.
        switch kind {
        case .primitive:
            let requireNonNull = sema.types.nullability(of: argType) == .nonNull
            let boxingTable = BoxingCalleeTable(interner: interner)
            guard let boxCallee = boxingTable.boxCallee(
                for: argType,
                types: sema.types,
                requireNonNull: requireNonNull
            ) else {
                return nil
            }
            let boxed = arena.appendTemporary(type: intType)
            newBody.append(.call(
                symbol: nil,
                callee: boxCallee,
                arguments: [argument],
                result: boxed,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: false
            ))
            return appendAnyToString(
                argument: boxed,
                tag: 1,
                arena: arena,
                intType: intType,
                stringType: stringType,
                anyToStringCallee: interner.intern("kk_any_to_string"),
                newBody: &newBody
            )
        default:
            return nil
        }
    }

    /// Emits `kk_any_to_string(argument, tag)` and returns the string result.
    private func appendAnyToString(
        argument: KIRExprID,
        tag: Int64,
        arena: KIRArena,
        intType: TypeID,
        stringType: TypeID,
        anyToStringCallee: InternedString,
        newBody: inout [KIRInstruction]
    ) -> KIRExprID {
        let tagExpr = arena.appendExpr(.intLiteral(tag), type: intType)
        newBody.append(.constValue(result: tagExpr, value: .intLiteral(tag)))
        let result = arena.appendTemporary(type: stringType)
        newBody.append(.call(
            symbol: nil,
            callee: anyToStringCallee,
            arguments: [argument, tagExpr],
            result: result,
            canThrow: false,
            thrownResult: nil,
            isSuperCall: false
        ))
        return result
    }

    /// Infers a primitive (or string) type for `argument` from the instruction that
    /// produced it when `arena.exprType` is not available, e.g. for expressions
    /// restored from an imported library's inline KIR.
    private func inferPrimitiveType(
        argument: KIRExprID,
        sema: SemaModule,
        interner: StringInterner,
        newBody: [KIRInstruction]
    ) -> TypeID {
        for instruction in newBody.reversed() {
            switch instruction {
            case let .copy(from, to):
                if to == argument {
                    return inferPrimitiveType(
                        argument: from,
                        sema: sema,
                        interner: interner,
                        newBody: newBody
                    )
                }
            case let .call(_, callee, _, result, _, _, _, _):
                if result == argument {
                    let calleeName = interner.resolve(callee)
                    if let primitive = primitiveType(forRuntimeCallee: calleeName) {
                        return sema.types.make(.primitive(primitive, .nonNull))
                    }
                }
            default:
                break
            }
        }
        return sema.types.anyType
    }

    private func primitiveType(forRuntimeCallee calleeName: String) -> PrimitiveType? {
        let unboxMapping: [String: PrimitiveType] = [
            "kk_unbox_char": .char,
            "kk_char_sequence_get": .char,
            "kk_unbox_bool": .boolean,
            "kk_unbox_int": .int,
            "kk_unbox_long": .long,
            "kk_unbox_ulong": .ulong,
            "kk_unbox_float": .float,
            "kk_unbox_double": .double,
        ]
        if let primitive = unboxMapping[calleeName] {
            return primitive
        }
        let boxMapping: [String: PrimitiveType] = [
            "kk_box_char": .char,
            "kk_box_bool": .boolean,
            "kk_box_int": .int,
            "kk_box_long": .long,
            "kk_box_long_nonnull": .long,
            "kk_box_ulong": .ulong,
            "kk_box_ulong_nonnull": .ulong,
            "kk_box_float": .float,
            "kk_box_double": .double,
            "kk_box_double_nonnull": .double,
        ]
        return boxMapping[calleeName]
    }

    private struct KIRExprWithInstructions {
        let value: KIRExprID
        let instructions: [KIRInstruction]
    }

    /// Returns a string expression for the class-typed argument, appending any
    /// needed instructions to `body`. Returns nil when no class-specific
    /// toString behavior is available (callers should fall back to source `println`).
    private static func classToStringExpression(
        argument: KIRExprID,
        classSymbol: SemanticSymbol,
        receiverType: TypeID,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        stringType: TypeID
    ) -> KIRExprWithInstructions? {
        var instructions: [KIRInstruction] = []

        // Regular and data objects print their simple name.
        if classSymbol.kind == .object {
            let objectName = interner.resolve(classSymbol.name)
            let interned = interner.intern(objectName)
            let expr = arena.appendExpr(.stringLiteral(interned), type: stringType)
            instructions.append(.constValue(result: expr, value: .stringLiteral(interned)))
            return KIRExprWithInstructions(value: expr, instructions: instructions)
        }

        // Enum classes use the synthesized $enumOrdinalToName$ helper.
        if classSymbol.kind == .enumClass,
           let helperSymbol = enumNameHelperSymbol(for: classSymbol, sema: sema, interner: interner)
        {
            let helperName = NameMangler.enumOrdinalToNameHelperName(for: classSymbol, interner: interner)
            let result = arena.appendTemporary(type: stringType)
            instructions.append(.call(
                symbol: helperSymbol,
                callee: helperName,
                arguments: [argument],
                result: result,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: false
            ))
            return KIRExprWithInstructions(value: result, instructions: instructions)
        }

        // Data classes and classes with an overriding toString() have a symbol
        // in the class hierarchy; resolve it and emit a direct or virtual call.
        let toStringName = interner.intern("toString")
        guard let toStringSym = resolveClassToStringSymbol(
            for: classSymbol.id,
            sema: sema,
            interner: interner
        ) else {
            return nil
        }

        let externalLinkName = sema.symbols.externalLinkName(for: toStringSym)
        let toStringCallee: InternedString = if let externalLinkName, !externalLinkName.isEmpty {
            interner.intern(externalLinkName)
        } else {
            toStringName
        }
        let toStringResult = arena.appendTemporary(type: stringType)
        // A base-typed receiver holding a derived instance (e.g. `val a: Animal
        // = Dog()`) must call the *runtime* type's override, not classSymbol's
        // own -- resolveVirtualDispatchKind returns the vtable/itable slot for
        // that when toString is overridable; a direct .call is only correct
        // when the class is effectively final (no subtypes).
        if let dispatchKind = resolveVirtualDispatchKind(
            callee: toStringSym, receiverTypeID: receiverType, sema: sema, interner: interner
        ) {
            instructions.append(.virtualCall(
                symbol: toStringSym,
                callee: toStringCallee,
                receiver: argument,
                arguments: [],
                result: toStringResult,
                canThrow: false,
                thrownResult: nil,
                dispatch: dispatchKind
            ))
        } else {
            instructions.append(.call(
                symbol: toStringSym,
                callee: toStringCallee,
                arguments: [argument],
                result: toStringResult,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: false
            ))
        }
        return KIRExprWithInstructions(value: toStringResult, instructions: instructions)
    }

    private static func enumNameHelperSymbol(
        for classSymbol: SemanticSymbol,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let helperName = NameMangler.enumOrdinalToNameHelperName(for: classSymbol, interner: interner)
        let fqName = classSymbol.fqName + [helperName]
        return sema.symbols.lookupAll(fqName: fqName).first { id in
            sema.symbols.symbol(id).map { $0.kind == .function } ?? false
        }
    }

    private static func maxLabelNumber(in body: [KIRInstruction]) -> Int32 {
        var maxLabel: Int32 = -1
        for instruction in body {
            if case let .label(n) = instruction {
                maxLabel = max(maxLabel, n)
            }
        }
        return maxLabel
    }
}
