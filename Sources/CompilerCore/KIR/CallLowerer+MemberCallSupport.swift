
struct MemberCallReceiver {
    let expr: ExprID
    let loweredID: KIRExprID
}

/// Tag scheme shared by every `kk_any_to_string`/`kk_any_hashCode`/`kk_any_equals`
/// call site (Any-fallback member calls, string concatenation/interpolation,
/// data class `toString()` synthesis, `println(dataClass)` rewriting, ...):
/// 1=default (Int/erased Any), 2=Boolean, 3=String, 4=Char, 5=Float,
/// 6=Double, 7=ULong, 8=Long. ULong spans the full 64 bits, so kk_any_to_string
/// must reinterpret it as unsigned (tag 1 would print the signed
/// reinterpretation, or even "null" for values whose bit pattern equals
/// Int.min). UInt/UByte/UShort stay on the default tag: they are always
/// zero-extended into this container, so tag 1's signed decimal rendering
/// already matches their unsigned value. Long gets its own tag (distinct from
/// the default) solely so `kk_any_hashCode` can apply the `(this xor (this
/// ushr 32)).toInt()` formula to unboxed Long receivers; `kk_any_to_string`
/// and `kk_any_equals` treat tag 8 exactly like tag 1 (Long's raw 64-bit slot
/// value already prints/compares correctly without reinterpretation), so this
/// addition changes no other call site's behavior. This is a free function
/// (not a `CallLowerer` method) so every lowering pass that stringifies an
/// arbitrary Any-typed value can share the exact same tag computation instead
/// of drifting out of sync.
func computeAnyFallbackTag(for type: TypeID, sema: SemaModule) -> Int64 {
    switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
    case .primitive(.boolean, _):
        2
    case .stringStruct:
        3
    case .primitive(.char, _):
        4
    case .primitive(.float, _):
        5
    case .primitive(.double, _):
        6
    case .primitive(.ulong, _):
        7
    case .primitive(.long, _):
        8
    default:
        1
    }
}

/// The `$enumOrdinalToName$<encodedFqName>(ordinal): String` helper for `type`,
/// when `type` is a non-null enum class that has one.
///
/// `.synthetic` enum classes (Platform.OsFamily, RegexOption, …) are
/// header-only symbols with no source declSite, so
/// DataEnumSealedSynthesisPass never synthesizes their helper — see
/// `emitBoxCallWithValueClassTag`, which skips them for the same reason.
/// A nullable enum is excluded too: its null sentinel would be fed to the
/// helper as an ordinal.
///
/// A free function (not a `CallLowerer` method) so `DataEnumSealedSynthesisPass`
/// can share it too: its data-class `toString()` synthesis stringifies each
/// property with this same enum/class resolution, but it runs as a standalone
/// KIR rewrite with no `KIRLoweringDriver` to construct a `CallLowerer`.
func resolveEnumOrdinalToNameCallee(
    for type: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> (callee: InternedString, symbol: SymbolID?)? {
    guard case let .classType(classType) = sema.types.kind(of: type),
          classType.nullability == .nonNull,
          let symbol = sema.symbols.symbol(classType.classSymbol),
          symbol.kind == .enumClass,
          !symbol.flags.contains(.synthetic)
    else {
        return nil
    }
    let helperName = NameMangler.enumOrdinalToNameHelperName(for: symbol, interner: interner)
    let helperSymbol = sema.symbols.lookupAll(fqName: symbol.fqName + [helperName]).first { id in
        sema.symbols.symbol(id).map { $0.kind == .function } ?? false
    }
    return (helperName, helperSymbol)
}

/// Resolves the nearest class-declared `toString()` symbol — user-defined, or
/// synthesized by `DataEnumSealedSynthesisPass` for a data class — while
/// walking the class inheritance chain. The synthetic `kotlin.Any.toString()`
/// placeholder every class inherits by default is excluded.
func resolveClassToStringSymbol(
    for classSymbolID: SymbolID,
    sema: SemaModule,
    interner: StringInterner
) -> SymbolID? {
    let toStringName = interner.intern("toString")
    var currentSymbolID = classSymbolID
    var visited: Set<SymbolID> = []

    while visited.insert(currentSymbolID).inserted {
        guard let classSymbol = sema.symbols.symbol(currentSymbolID) else {
            break
        }
        let candidate = sema.symbols.lookupAll(
            fqName: classSymbol.fqName + [toStringName]
        ).first { id in
            guard let symbol = sema.symbols.symbol(id), symbol.kind == .function else {
                return false
            }
            return sema.symbols.functionSignature(for: id)?.parameterTypes.isEmpty ?? true
        }
        if let candidate,
           let symbol = sema.symbols.symbol(candidate),
           !isSyntheticAnyToStringSymbol(symbol, interner: interner)
        {
            return candidate
        }

        guard let superclass = sema.symbols.directSupertypes(for: currentSymbolID).first(where: { id in
            sema.symbols.symbol(id)?.kind == .class
        }) else {
            break
        }
        currentSymbolID = superclass
    }
    return nil
}

/// Resolves `type`'s class-declared `toString()` symbol — user-defined, or
/// synthesized by `DataEnumSealedSynthesisPass` for a data class — when one
/// exists and is not the `kotlin.Any.toString()` placeholder every class
/// inherits by default. The class hierarchy is searched from the static class
/// type toward its direct superclass.
/// `type` may be nullable: the class symbol is resolved from its non-null
/// form, but callers passing a nullable `type` are responsible for
/// null-guarding the receiver before invoking the returned callee (calling a
/// member function on a null receiver crashes) — see the null-guard scaffold
/// in `CallLowerer.emitAnyToStringWithNullGuard` for the pattern.
///
/// Shared by every pass that must call a class-typed value's own toString()
/// directly instead of falling back to the generic `kk_any_to_string`
/// Any-fallback tag path, which cannot distinguish a class's own fields from
/// an ordinary heap pointer, or — for a value class — from its raw unboxed
/// primitive representation: `CallLowerer.emitAnyToStringWithNullGuard`
/// (string template interpolation, `+`/`+=` string concatenation) and
/// `DataEnumSealedSynthesisPass`'s per-property data class `toString()`
/// synthesis. Mirrors (but does not replace) the equivalent resolution in
/// `ConsolePrintLoweringPass.classToStringExpression`, which additionally
/// special-cases object/enum receivers for `println`/`print`.
func resolveClassOwnToStringCallee(
    for type: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> (callee: InternedString, symbol: SymbolID)? {
    let toStringName = interner.intern("toString")
    let toStringSymbolID: SymbolID?
    if case .unit = sema.types.kind(of: sema.types.makeNonNullable(type)) {
        // Unit has the builtin value representation, so it has no classType
        // symbol to resolve. Its source-backed object member is still the
        // authoritative implementation for direct and statically-known calls.
        guard let unitClassSymbol = sema.types.unitClassSymbol,
              let unitSymbol = sema.symbols.symbol(unitClassSymbol)
        else {
            return nil
        }
        let toStringFQName = unitSymbol.fqName + [toStringName]
        toStringSymbolID = sema.symbols.lookupAll(fqName: toStringFQName).first { id in
            guard let symbol = sema.symbols.symbol(id), symbol.kind == .function else {
                return false
            }
            return sema.symbols.functionSignature(for: id)?.parameterTypes.isEmpty ?? true
        }
    } else {
        guard let (_, classSymbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return nil
        }
        toStringSymbolID = resolveClassToStringSymbol(
            for: classSymbol.id,
            sema: sema,
            interner: interner
        )
    }
    guard let toStringSymbolID,
          let toStringSymbol = sema.symbols.symbol(toStringSymbolID),
          !isSyntheticAnyToStringSymbol(toStringSymbol, interner: interner)
    else {
        return nil
    }
    let externalLinkName = sema.symbols.externalLinkName(for: toStringSymbolID)
    let callee: InternedString = if let externalLinkName, !externalLinkName.isEmpty {
        interner.intern(externalLinkName)
    } else {
        toStringName
    }
    return (callee, toStringSymbolID)
}

private func isSyntheticAnyToStringSymbol(_ sym: SemanticSymbol, interner: StringInterner) -> Bool {
    guard sym.flags.contains(.synthetic) else { return false }
    let anyToStringFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Any"), interner.intern("toString")]
    return sym.fqName == anyToStringFQName
}

extension CallLowerer {
    static let unresolvedCoroutineHandleMemberNames: Set<String> = [
        "await", "join", "awaitCompletion",
        "cancel", "complete", "completeExceptionally",
        "isActive", "isCompleted", "isCancelled"
    ]
    // KSP-678: close / isClosedForReceive / isClosedForSend migrated to bundled
    // Kotlin source; only the suspension core send / receive remain here.
    static let unresolvedChannelMemberNames: Set<String> = ["send", "receive"]
    // Flow operators beyond map/filter/take/collect (already covered by
    // unresolvedCollectionMemberNames because those names also exist on
    // collections). These names are Flow-specific, so a Flow receiver with an
    // unresolved chosenCallee still needs its receiver argument inserted here.
    static let unresolvedFlowMemberNames: Set<String> = [
        "buffer", "conflate", "collectLatest", "debounce", "sample", "delayEach", "flowOn",
        "transform", "dropWhile", "flatMapConcat", "flatMapMerge", "flatMapLatest",
        "catch", "retry", "retryWhen", "onErrorReturn", "onErrorResume", "single",
    ]

    enum PrimitiveCompareABIKind: Int32 {
        case int = 0
        case long = 1
        case uint = 2
        case ulong = 3
        case boolean = 4
        case char = 5
        case float = 6
        case double = 7
    }

    func primitiveCompareABIKind(for type: TypeID, sema: SemaModule) -> PrimitiveCompareABIKind? {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.int, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return .int
        case .primitive(.long, _):
            return .long
        case .primitive(.uint, _):
            return .uint
        case .primitive(.ulong, _):
            return .ulong
        case .primitive(.boolean, _):
            return .boolean
        case .primitive(.char, _):
            return .char
        case .primitive(.float, _):
            return .float
        case .primitive(.double, _):
            return .double
        default:
            return nil
        }
    }

    func anyFallbackTag(for type: TypeID, sema: SemaModule) -> Int64 {
        computeAnyFallbackTag(for: type, sema: sema)
    }

    /// Target kind for `kk_number_to_primitive` (KSP-1540). Mirrors the
    /// Runtime-side `RuntimeNumberConversionTargetKind` by raw value — the two
    /// enums live in separate modules linked only through the C ABI, so they
    /// must be kept in sync manually.
    enum NumberConversionTargetKind: Int32 {
        case double = 0
        case float = 1
        case long = 2
        case int = 3
        case short = 4
        case byte = 5
    }

    func numberConversionTargetKind(for calleeName: InternedString, interner: StringInterner) -> NumberConversionTargetKind? {
        switch interner.resolve(calleeName) {
        case "toDouble": return .double
        case "toFloat": return .float
        case "toLong": return .long
        case "toInt": return .int
        case "toShort": return .short
        case "toByte": return .byte
        default: return nil
        }
    }

    func enumOrdinalToNameCallee(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> (callee: InternedString, symbol: SymbolID?)? {
        resolveEnumOrdinalToNameCallee(for: type, sema: sema, interner: interner)
    }

    /// Converts `valueID` (of static type `valueType`) to a `String` via
    /// `kk_any_to_string`, using `anyFallbackTag`'s tag for `valueType` and
    /// guarding against the null-sentinel collision for nullable
    /// Float?/Double?/ULong? (tags 5/6/7): their null-sentinel bit pattern
    /// (Int.min) coincides with a legitimate in-range value (-0.0, or a
    /// ULong of exactly 2^63), and kk_any_to_string decodes those tags
    /// *before* checking for the sentinel, so an actually-null value must be
    /// intercepted here first or it renders as that in-range value instead of
    /// "null". Every call site that stringifies an arbitrary Any-typed value
    /// for concatenation/interpolation should route through this helper
    /// rather than calling kk_any_to_string directly, so a future tag needing
    /// the same guard only has to be added in one place.
    func emitAnyToStringWithNullGuard(
        valueID: KIRExprID,
        valueType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.stringType
        let isNullable = sema.types.makeNonNullable(valueType) != valueType
        let isUnit: Bool = if case .unit = sema.types.kind(of: sema.types.makeNonNullable(valueType)) {
            true
        } else {
            false
        }
        // Unit has no nullable TypeKind variant, but a safe call returning Unit
        // still carries the null sentinel at runtime. Keep the null guard for
        // Unit values so string interpolation does not invoke Unit.toString()
        // on that sentinel.
        let needsNullGuard = isNullable || isUnit
        // A statically enum-typed value is represented as its bare ordinal, so
        // `kk_any_to_string` would render the number. The enum class's
        // `$enumOrdinalToName$<encodedFqName>` helper maps it back to the entry name —
        // the same helper `emitBoxCallWithValueClassTag` uses when an enum crosses
        // an Any-erased boundary.
        if let nameHelper = enumOrdinalToNameCallee(for: valueType, sema: sema, interner: interner) {
            let name = arena.appendTemporary(type: stringType)
            instructions.append(.call(
                symbol: nameHelper.symbol,
                callee: nameHelper.callee,
                arguments: [valueID],
                result: name,
                canThrow: false,
                thrownResult: nil
            ))
            return name
        }
        // A statically class-typed value (data class, ordinary class, or value
        // class) is represented at runtime as a heap pointer or — for a
        // non-nullable value class — its raw unboxed underlying primitive.
        // Neither representation carries enough information for the generic
        // kk_any_to_string tag path below to recover the class's own
        // toString(). Use the shared resolver so data-class synthesis and this
        // string-conversion funnel agree on the selected symbol. When the
        // receiver is open/interface-typed, preserve virtual dispatch so a
        // derived override is selected at runtime.
        if let classToString = resolveClassOwnToStringCallee(for: valueType, sema: sema, interner: interner) {
            let converted = arena.appendTemporary(type: stringType)
            func emitToStringCall(into result: KIRExprID) -> KIRInstruction {
                tryEmitVirtualDispatch(
                    chosenCallee: classToString.symbol,
                    calleeName: classToString.callee,
                    receiverExpr: nil,
                    loweredReceiverID: valueID,
                    isSuperCall: false,
                    finalArguments: [],
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner
                ) ?? .call(
                    symbol: classToString.symbol,
                    callee: classToString.callee,
                    arguments: [valueID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            }
            guard needsNullGuard else {
                instructions.append(emitToStringCall(into: converted))
                return converted
            }
            let nonNullLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            let nullStr = interner.intern("null")
            let nullStrID = arena.appendExpr(.stringLiteral(nullStr), type: stringType)
            instructions.append(.constValue(result: nullStrID, value: .stringLiteral(nullStr)))
            instructions.append(.jumpIfNotNull(value: valueID, target: nonNullLabel))
            instructions.append(.copy(from: nullStrID, to: converted))
            instructions.append(.jump(endLabel))
            instructions.append(.label(nonNullLabel))
            let innerConverted = arena.appendTemporary(type: stringType)
            instructions.append(emitToStringCall(into: innerConverted))
            instructions.append(.copy(from: innerConverted, to: converted))
            instructions.append(.label(endLabel))
            return converted
        }
        let tag = anyFallbackTag(for: valueType, sema: sema)
        let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
        instructions.append(.constValue(result: tagID, value: .intLiteral(tag)))
        let converted = arena.appendTemporary(type: stringType)
        guard isNullable, tag == 5 || tag == 6 || tag == 7 else {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_to_string"),
                arguments: [valueID, tagID],
                result: converted,
                canThrow: false,
                thrownResult: nil
            ))
            return converted
        }
        let nonNullLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        let nullStr = interner.intern("null")
        let nullStrID = arena.appendExpr(.stringLiteral(nullStr), type: stringType)
        instructions.append(.constValue(result: nullStrID, value: .stringLiteral(nullStr)))
        instructions.append(.jumpIfNotNull(value: valueID, target: nonNullLabel))
        instructions.append(.copy(from: nullStrID, to: converted))
        instructions.append(.jump(endLabel))
        instructions.append(.label(nonNullLabel))
        let innerConverted = arena.appendTemporary(type: stringType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_to_string"),
            arguments: [valueID, tagID],
            result: innerConverted,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.copy(from: innerConverted, to: converted))
        instructions.append(.label(endLabel))
        return converted
    }

    func isCoroutineHandleReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        return knownNames.isCoroutineHandleSymbol(symbol)
    }

    func isChannelReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        return knownNames.isChannelSymbol(symbol)
    }

    func isFlowReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (classType, _) = resolveClassTypeSymbol(receiverType, sema: sema),
              let flowSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("kotlinx"), interner.intern("coroutines"),
                  interner.intern("flow"), interner.intern("Flow"),
              ])
        else {
            return false
        }
        return classType.classSymbol == flowSymbol
    }

    func isCoroutineContextReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        guard interner.resolve(symbol.name) == "CoroutineContext" else {
            return false
        }
        let kotlinxCoroutinesPkg: [InternedString] = [
            interner.intern("kotlinx"),
            interner.intern("coroutines"),
        ]
        let kotlinCoroutinesPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
        ]
        return symbol.fqName.starts(with: kotlinxCoroutinesPkg)
            || symbol.fqName.starts(with: kotlinCoroutinesPkg)
    }
    static let unresolvedCollectionMemberNames: Set<String> = [
        "size", "get", "contains", "containsAll", "containsKey", "containsValue",
        "isEmpty", "first", "last", "indexOf", "lastIndexOf", "indexOfFirst", "indexOfLast",
        "count", "iterator",
        "map", "filter", "filterNot", "mapNotNull", "mapIndexedNotNullTo", "flatMapIndexedTo", "flatMapIndexed", "firstNotNullOf", "firstNotNullOfOrNull", "filterNotNull", "requireNoNulls", "forEach", "flatMap",
        "map", "filter", "filterNot", "mapNotNull", "mapIndexedNotNullTo", "flatMapTo", "firstNotNullOf", "firstNotNullOfOrNull", "filterNotNull", "requireNoNulls", "forEach", "flatMap",
        "any", "none", "all",
        "fold", "foldIndexed", "foldRight", "foldRightIndexed",
        "reduce", "reduceRight", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "reduceIndexed", "reduceIndexedOrNull",
        "scan", "scanIndexed", "scanReduce", "runningFold", "runningFoldIndexed",
        "runningReduce", "runningReduceIndexed",
        "groupBy", "groupByTo", "groupingBy", "sortedBy", "find", "findLast", "associateBy", "associateByTo", "associateWith", "associateWithTo", "associate", "associateTo", "zip", "zipWithNext", "unzip",
        "eachCount", "eachCountTo", "aggregate", "aggregateTo",
        "withIndex", "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo", "filterKeys", "filterValues",
        "getValue", "getOrDefault", "getOrElse", "getOrPut", "getOrNull", "elementAtOrNull", "elementAt", "elementAtOrElse",
        "putAll", "addAll",
        "maxBy", "minBy", "max", "min", "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull", "maxOrNull", "minOrNull",
        "plus", "plusElement", "minus", "minusElement",
        "asSequence", "asIterable", "toList", "toSet", "toMap", "toCollection", "toMutableList", "toMutableSet", "toSortedSet", "toTypedArray",
        // Kept for non-List receivers (Set / Iterable): List receivers are
        // source-backed since KSP-628 and no longer reach this path.
        "toBooleanArray", "toCharArray", "toShortArray", "toDoubleArray", "toFloatArray", "toIntArray", "toLongArray", "toByteArray", "toUByteArray", "toUShortArray", "toUIntArray", "toULongArray",
        "take", "takeWhile", "takeLast", "drop", "reversed", "asReversed", "sorted", "distinct", "flatten", "chunked", "windowed", "collect", "subList",
        "sortedDescending", "sortedByDescending", "sortedWith", "partition",
        "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
        "maxOf", "minOf",
        "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
        "sort", "sortWith", "sortBy", "sortByDescending",
        "onEach", "onEachIndexed",
        "fill",
        "firstOrNull", "lastOrNull", "singleOrNull",
        "addAll", "removeAll", "retainAll",
        "intersect", "union", "subtract",
        "toHashSet",
        "containsAll", "binarySearch", "average",
        "addFirst", "addLast",
        "sum", "sumOf", "sumBy", "sumByDouble",
    ]

}
