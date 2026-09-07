@discardableResult
func emitNonThrowingCall(
    callee: InternedString,
    arg: KIRExprID,
    resultType: TypeID?,
    arena: KIRArena,
    into instructions: inout [KIRInstruction]
) -> KIRExprID {
    let result = arena.appendTemporary(type: resultType)
    emitNonThrowingCall(
        callee: callee,
        arg: arg,
        result: result,
        into: &instructions
    )
    return result
}

/// Boxes `value` (statically typed `sourceType`) for storage in an Any-erased
/// slot — vararg elements, array/collection elements, generateSequence seeds
/// and next-function results, and any other "primitive going into a
/// reference-typed slot" boundary. Resolves value classes/enums to their
/// underlying representation first (`resolveValueClassKind`) so a value class
/// or enum boxes via the correct callee instead of being silently skipped
/// (`.classType` never matches `BoxingCalleeTable`'s primitive-only lookup on
/// its own), then tags the box appropriately (`emitBoxCallWithValueClassTag`:
/// `kk_tag_value_class_box` for value classes, `kk_enum_box_ordinal` +
/// `$enumOrdinalToName$<encodedFqName>` for enums). Returns `value` unchanged when no
/// boxing is needed.
func boxValueForAnySlot(
    _ value: KIRExprID,
    sourceType: TypeID,
    types: TypeSystem,
    symbols: SymbolTable?,
    interner: StringInterner,
    arena: KIRArena,
    resultType: TypeID? = nil,
    requireNonNull: Bool = false,
    boxingCalleeTable: BoxingCalleeTable? = nil,
    into instructions: inout [KIRInstruction]
) -> KIRExprID {
    let rawKind = types.kind(of: sourceType)
    let resolvedKind = resolveValueClassKind(rawKind, types: types, symbols: symbols)
    let table = boxingCalleeTable ?? BoxingCalleeTable(interner: interner)
    guard let boxCallee = table.boxCallee(for: resolvedKind, requireNonNull: requireNonNull) else {
        return value
    }
    let effectiveResultType = resultType ?? types.anyType
    let boxedResult = arena.appendTemporary(type: effectiveResultType)
    emitBoxCallWithValueClassTag(
        boxCallee: boxCallee,
        value: value,
        rawSourceKind: rawKind,
        result: boxedResult,
        resultType: effectiveResultType,
        types: types,
        symbols: symbols,
        interner: interner,
        arena: arena,
        into: &instructions
    )
    return boxedResult
}

func emitNonThrowingCall(
    callee: InternedString,
    arg: KIRExprID,
    result: KIRExprID,
    symbol: SymbolID? = nil,
    into instructions: inout [KIRInstruction]
) {
    instructions.append(.call(
        symbol: symbol,
        callee: callee,
        arguments: [arg],
        result: result,
        canThrow: false,
        thrownResult: nil
    ))
}

/// Emits a runtime bridge call whose trailing `outThrown` channel must be
/// present even when the enclosing Kotlin function has no local catch block.
/// Try-lowering may route the call to its local exception slot later.
func emitThrowingCall(
    callee: InternedString,
    arg: KIRExprID,
    result: KIRExprID,
    into instructions: inout [KIRInstruction]
) {
    instructions.append(.call(
        symbol: nil,
        callee: callee,
        arguments: [arg],
        result: result,
        canThrow: true,
        thrownResult: nil
    ))
}

/// Resolve `componentN` for destructuring against `receiverType`.
///
/// External members lower to their runtime link name; the resolved symbol is
/// carried along so that source-defined members (e.g. bundled `kotlin.Pair`)
/// dispatch to the compiled function instead of a same-named runtime export,
/// and so that ABI lowering can unbox generic component results.
func resolveDestructuringComponentCallee(
    componentName: InternedString,
    receiverType: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> (symbol: SymbolID?, callee: InternedString) {
    let chosen = TypeCheckHelpers().collectMemberFunctionCandidates(
        named: componentName,
        receiverType: receiverType,
        sema: sema,
        interner: interner
    ).first
    guard let chosen else {
        return (nil, componentName)
    }
    let symbol = sema.symbols.isSourceBackedSymbol(chosen) ? chosen : nil
    if let linkName = sema.symbols.externalLinkName(for: chosen), !linkName.isEmpty {
        return (symbol, interner.intern(linkName))
    }
    return (symbol, componentName)
}

/// Unboxes `exprID` via `kk_unbox_int` when `staticType` is a concrete
/// (non-null) enum class, otherwise returns `exprID` unchanged.
///
/// Enum constants are raw ordinal Ints everywhere except when they round-trip
/// through an Any-erased slot (e.g. an element read out of
/// `values()`/`entries`, see `kk_enum_box_ordinal`), which leaves them as a
/// boxed handle. `kk_unbox_int` is a no-op pass-through on an
/// already-raw ordinal, so calling this on both operands of an enum
/// `==`/`when` comparison normalizes either representation to a raw ordinal
/// without needing to know which side (if either) is actually boxed.
///
/// Deliberately scoped to non-null enum types only: nullable enum
/// comparisons are unrelated to the values()/entries element bug this
/// exists for, and `kk_unbox_int` treats its null sentinel as ordinal 0,
/// which would misclassify a null as the first enum entry.
func unboxIfEnumTyped(
    _ exprID: KIRExprID,
    staticType: TypeID?,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    into instructions: inout [KIRInstruction]
) -> KIRExprID {
    guard let staticType,
          case let .classType(classType) = sema.types.kind(of: staticType),
          classType.nullability == .nonNull,
          let sym = sema.symbols.symbol(classType.classSymbol),
          sym.kind == .enumClass
    else {
        return exprID
    }
    let intType = sema.types.make(.primitive(.int, .nonNull))
    return emitNonThrowingCall(
        callee: ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner),
        arg: exprID,
        resultType: intType,
        arena: arena,
        into: &instructions
    )
}

/// Emits a primitive box call (`kk_box_int`/`kk_box_long`/...), and — when
/// `rawSourceKind` is a non-null value class — an additional
/// `kk_tag_value_class_box` call that tags the resulting box with the value
/// class's own stable nominal type ID.
///
/// Value classes are unboxed to their underlying primitive everywhere
/// (ValueClassUnboxingPass) except at reference-type boundaries, where every
/// boxing-callee lookup in ABILoweringPass and CollectionLiteralLoweringPass
/// resolves a value class to its underlying primitive kind first (so it can
/// reuse the ordinary `kk_box_*` callee). Without the extra tag, the
/// resulting box is indistinguishable from a plain boxed primitive, so
/// `is`/`as`/`KClass.isInstance` against the value class name would
/// incorrectly fail — and against the underlying primitive name would
/// incorrectly succeed. `rawSourceKind` must be the *unresolved* kind (i.e.
/// computed before resolving a value class to its underlying primitive) so
/// the value class identity is still visible.
func emitBoxCallWithValueClassTag(
    boxCallee: InternedString,
    value: KIRExprID,
    rawSourceKind: TypeKind,
    result: KIRExprID,
    resultType: TypeID?,
    types: TypeSystem,
    symbols: SymbolTable?,
    interner: StringInterner,
    arena: KIRArena,
    into instructions: inout [KIRInstruction]
) {
    func emitPlainBoxCall() {
        instructions.append(.call(
            symbol: nil, callee: boxCallee, arguments: [value],
            result: result, canThrow: false, thrownResult: nil
        ))
    }
    guard case let .classType(classType) = rawSourceKind,
          classType.nullability == .nonNull,
          let symbols,
          let sym = symbols.symbol(classType.classSymbol)
    else {
        emitPlainBoxCall()
        return
    }
    // `.synthetic` enum classes (e.g. Platform.OsFamily, RegexOption — see
    // ensureSyntheticPlatformEnumClass / rewriteSyntheticEnumEntryRefs) are
    // header-only symbols with no source declSite: they never get a
    // `.nominalType` KIR declaration, so DataEnumSealedSynthesisPass never
    // synthesizes their `$enumOrdinalToName$<encodedFqName>` helper. Fall back to a
    // plain (untagged) box for these — same as before this function grew
    // enum awareness — rather than emitting a call to a helper that will
    // never exist.
    if sym.kind == .enumClass, !sym.flags.contains(.synthetic) {
        emitEnumOrdinalBoxCall(
            ordinal: value,
            classSymbol: classType.classSymbol,
            result: result,
            resultType: resultType,
            types: types,
            symbols: symbols,
            interner: interner,
            arena: arena,
            into: &instructions
        )
        return
    }
    guard sym.flags.contains(.valueType) else {
        emitPlainBoxCall()
        return
    }
    let classID = RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: classType.classSymbol, symbols: symbols, interner: interner
    )
    guard classID != 0 else {
        emitPlainBoxCall()
        return
    }
    let boxedTemp = arena.appendTemporary(type: resultType)
    instructions.append(.call(
        symbol: nil, callee: boxCallee, arguments: [value],
        result: boxedTemp, canThrow: false, thrownResult: nil
    ))
    let intType = types.make(.primitive(.int, .nonNull))
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
    let tagCallee = interner.intern("kk_tag_value_class_box")
    instructions.append(.call(
        symbol: nil, callee: tagCallee, arguments: [boxedTemp, classIDExpr],
        result: result, canThrow: false, thrownResult: nil
    ))
}

/// Boxes an enum ordinal via `kk_enum_box_ordinal(ordinal, name, classID)`
/// (BUG-177 / BUG-182), resolving `name` at runtime through the enum class's
/// `$enumOrdinalToName$<encodedFqName>` helper and tagging the box with the
/// enum class's stable nominal type ID so `is`/`as`/`as?`/`KClass.isInstance`
/// work after widening to `Any`.
///
/// The helper is called by `SymbolID` when available (e.g. for a precompiled
/// `.kklib` enum) and by bare name otherwise: boxing can be lowered *before*
/// DataEnumSealedSynthesisPass has run for source enums, so the Sema symbol
/// may not exist yet. Codegen resolves unnamed calls by scanning every KIR
/// function for one whose name and arity match (`resolveUnnamedInternalFunction`),
/// which by then includes the synthesized helper regardless of pass order.
func emitEnumOrdinalBoxCall(
    ordinal: KIRExprID,
    classSymbol: SymbolID,
    result: KIRExprID,
    resultType: TypeID?,
    types: TypeSystem,
    symbols: SymbolTable,
    interner: StringInterner,
    arena: KIRArena,
    into instructions: inout [KIRInstruction]
) {
    guard let classSym = symbols.symbol(classSymbol),
          classSym.kind == .enumClass,
          !classSym.flags.contains(.synthetic)
    else {
        preconditionFailure("emitEnumOrdinalBoxCall requires a non-synthetic, source-backed enum class symbol")
    }

    let nameHelperCallee = NameMangler.enumOrdinalToNameHelperName(for: classSym, interner: interner)
    let helperSymbol = symbols.lookupAll(fqName: classSym.fqName + [nameHelperCallee]).first { id in
        symbols.symbol(id).map { $0.kind == .function } ?? false
    }
    let nameResult = arena.appendTemporary(type: types.stringType)
    instructions.append(.call(
        symbol: helperSymbol, callee: nameHelperCallee, arguments: [ordinal],
        result: nameResult, canThrow: false, thrownResult: nil
    ))

    let classID = RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: classSymbol, symbols: symbols, interner: interner
    )
    let intType = types.make(.primitive(.int, .nonNull))
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))

    let boxCallee = interner.intern("kk_enum_box_ordinal")
    instructions.append(.call(
        symbol: nil, callee: boxCallee, arguments: [ordinal, nameResult, classIDExpr],
        result: result, canThrow: false, thrownResult: nil
    ))
}
