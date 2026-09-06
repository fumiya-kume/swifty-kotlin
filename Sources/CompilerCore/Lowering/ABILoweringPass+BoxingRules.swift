/// Resolves a value class's `TypeKind` to the `TypeKind` of its underlying
/// primitive, so the caller's boxing-callee lookup treats a value class like
/// its underlying representation (value classes are unboxed everywhere
/// except at reference-type boundaries — ValueClassUnboxingPass — and except
/// when the value class implements an interface, in which case it stays
/// boxed for polymorphic dispatch; see `effectiveValueClassUnderlyingType`).
/// Non-null enum classes resolve the same way, to `Int`: enum constants are
/// raw ordinal Ints everywhere outside Any-erased slots (see
/// `emitBoxCallWithValueClassTag`, which boxes them via
/// `kk_enum_box_ordinal` instead of the plain `kk_box_int` this resolution
/// would otherwise imply). Non-value-class/non-enum kinds, and nullable
/// value classes/enums, pass through unchanged.
///
/// Shared as a free function (rather than an `ABILoweringPass` method) so
/// `CollectionLiteralLoweringPass`'s `listOf`/`setOf`/array-literal boxing —
/// which must stay in sync with ABILoweringPass's typeParam boxing boundary,
/// per `typeParamBoxingBoundaryCallees` below — can resolve value classes the
/// same way.
func resolveValueClassKind(
    _ kind: TypeKind,
    types: TypeSystem,
    symbols: SymbolTable?
) -> TypeKind {
    guard let symbols else { return kind }
    guard case let .classType(classType) = kind,
          classType.nullability == .nonNull
    else {
        return kind
    }
    guard let sym = symbols.symbol(classType.classSymbol) else {
        return kind
    }
    if sym.kind == .enumClass {
        return .primitive(.int, .nonNull)
    }
    guard sym.flags.contains(.valueType),
          let underlyingType = symbols.effectiveValueClassUnderlyingType(for: classType.classSymbol)
    else {
        return kind
    }
    return types.kind(of: underlyingType)
}

extension ABILoweringPass {
    /// Callees whose `typeParam`-typed parameter stores the argument verbatim into a
    /// generic container. Because type parameters are erased to Any at runtime, a
    /// primitive argument to one of these must be boxed so it carries its concrete
    /// type (notably `Char`, which would otherwise be stored as a bare code point and
    /// render as a number). This mirrors the collection-literal lowering path, so an
    /// element inserted via `add`/`set` is boxed identically to one created by
    /// `listOf(...)` / `setOf(...)` / `toMutableList()`.
    static let typeParamBoxingBoundaryCallees: Set<String> = [
        "__kk_pair_new",
        "__kk_triple_new",
        "__kk_mutable_collection_add",
        "__kk_mutable_list_add",
        "__kk_mutable_list_add_at",
        "__kk_mutable_list_set",
        "__kk_mutable_set_add",
        "__kk_mutable_map_put",
        "__kk_mutable_map_putAll",
        "__kk_mutable_map_plusAssign_pair",
        "__kk_sequence_builder_yield",
        "__kk_iterator_builder_yield",
    ]

    /// True when the call target is a declaration compiled from Kotlin source —
    /// bundled stdlib source in this compilation (no external link name) or the
    /// same declaration imported from a library artifact (`kk_fn_*`). Such a
    /// callee follows the compiler's own generic ABI, where type-parameter
    /// slots carry boxed values; every other `kk_*` symbol is a hand-written
    /// runtime bridge whose raw parameter convention must be left alone.
    func isKotlinSourceCallee(_ callSymbol: SymbolID?, symbols: SymbolTable?) -> Bool {
        guard let callSymbol, let symbols, let symbol = symbols.symbol(callSymbol),
              (symbol.kind == .function || symbol.kind == .constructor),
              symbols.isSourceBackedSymbol(callSymbol)
        else {
            return false
        }
        guard let linkName = symbols.externalLinkName(for: callSymbol), !linkName.isEmpty else {
            return true
        }
        return linkName.hasPrefix("kk_fn_")
    }

    /// True when a `kk_array_get` receiver is the generic `kotlin.Array` class
    /// (whose elements are stored boxed) rather than one of the primitive array
    /// classes (`DoubleArray`, `IntArray`, ...) which store raw values.
    func isGenericArrayReceiver(
        _ receiver: KIRExprID?,
        module: KIRModule,
        types: TypeSystem?,
        symbols: SymbolTable?,
        interner: StringInterner
    ) -> Bool {
        guard let receiver, let types, let symbols,
              let receiverType = module.arena.exprType(receiver),
              case let .classType(classType) = types.kind(of: types.makeNonNullable(receiverType)),
              let symbol = symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return interner.resolve(symbol.name) == "Array"
    }

    func boxingCallee(
        argType: TypeID,
        paramType: TypeID,
        callee: InternedString?,
        types: TypeSystem,
        interner: StringInterner,
        boxingCalleeTable: BoxingCalleeTable,
        symbols: SymbolTable? = nil,
        boxTypeParamBoundary: Bool = false
    ) -> InternedString? {
        let rawArgKind = types.kind(of: argType)
        let argKind = resolveValueClassKind(rawArgKind, types: types, symbols: symbols)
        // Resolve the parameter's value-class type to its underlying kind too —
        // otherwise a parameter declared as a value class (e.g. `s: SecondsXYZ`)
        // looks like any other `.classType` reference boundary and gets boxed,
        // even though the callee (post-ValueClassUnboxingPass) expects the raw
        // unboxed underlying value. That mismatch corrupted arithmetic: a boxed
        // Double pointer fed into `kk_op_dmul` as if it were the raw bit pattern.
        let rawParamKind = types.kind(of: paramType)
        let paramKind = resolveValueClassKind(rawParamKind, types: types, symbols: symbols)

        // Treat Any/Any?, reference types, and type parameters as boxing boundaries.
        // Type parameters are erased to Any at runtime, so primitives must be boxed.
        let isReferenceBoxingBoundary: Bool = {
            if isAnyOrNullableAny(paramKind) {
                return true
            }
            if case .classType = paramKind {
                return true
            }
            if case .typeParam = paramKind {
                // Type parameters are erased to Any at runtime, so a primitive stored
                // into a generic container must be boxed. Otherwise its raw value is
                // indistinguishable from an Int code point — e.g. a Char added to a
                // MutableList would be stored as a bare code point and print as a
                // number rather than the character. We box for the generic containers
                // whose runtime helpers store the element verbatim (Pair/Triple
                // constructors and the mutable-collection element-insertion helpers),
                // keeping `add`/`set` consistent with how `listOf(...)` / `setOf(...)`
                // / `toMutableList()` already box every element.
                // A call to a Kotlin-source declaration (bundled stdlib source
                // or the same declaration imported from a library artifact)
                // always uses the erased boxed representation for its generic
                // parameters, so e.g. `Array<T>.fold(initial: R, ...)` must
                // receive `0.0` as a `kk_box_double` handle rather than the raw
                // bit pattern the callee would then reinterpret as a pointer.
                if boxTypeParamBoundary {
                    return true
                }
                if let callee {
                    let calleeName = interner.resolve(callee)
                    if ABILoweringPass.typeParamBoxingBoundaryCallees.contains(calleeName) {
                        return true
                    }
                }
                // Floating-point arguments must be boxed at every erased `T`
                // parameter, not just the containers above: a raw Double word
                // is indistinguishable from an Int of the same bits, and -0.0
                // is bit-identical to the null sentinel, so an unboxed value
                // reaching a generic callee compares unequal to the boxed
                // elements it is matched against (e.g. Array<Double>.contains).
                if case let .primitive(argPrimitive, .nonNull) = argKind,
                   argPrimitive == .double || argPrimitive == .float
                {
                    return true
                }
                return false
            }
            return false
        }()

        guard isReferenceBoxingBoundary else {
            if case let .primitive(paramPrimitive, .nullable) = paramKind,
               case let .primitive(argPrimitive, .nonNull) = argKind,
               paramPrimitive == argPrimitive
            {
                return boxingCalleeTable.boxCallee(
                    for: .primitive(argPrimitive, .nonNull),
                    requireNonNull: true
                )
            }
            return nil
        }

        return boxingCalleeTable.boxCallee(for: argKind, requireNonNull: false)
    }

    func unboxingCallee(
        sourceKind: TypeKind,
        targetKind: TypeKind,
        boxingCalleeTable: BoxingCalleeTable,
        types: TypeSystem? = nil,
        symbols: SymbolTable? = nil
    ) -> InternedString? {
        let resolvedTargetKind: TypeKind = if let types, let symbols {
            resolveValueClassKind(targetKind, types: types, symbols: symbols)
        } else {
            targetKind
        }
        guard needsUnboxing(sourceKind: sourceKind, targetKind: resolvedTargetKind, symbols: symbols) else {
            return nil
        }

        return boxingCalleeTable.unboxCallee(for: resolvedTargetKind, requireNonNull: true)
    }

    func intrinsicArgType(
        _ argExprID: KIRExprID,
        arena: KIRArena,
        types: TypeSystem
    ) -> TypeID? {
        if let kind = arena.expr(argExprID) {
            switch kind {
            case .intLiteral:
                return types.make(.primitive(.int, .nonNull))
            case .longLiteral:
                return types.make(.primitive(.long, .nonNull))
            case .uintLiteral:
                return types.make(.primitive(.uint, .nonNull))
            case .ulongLiteral:
                return types.make(.primitive(.ulong, .nonNull))
            case .floatLiteral:
                return types.make(.primitive(.float, .nonNull))
            case .doubleLiteral:
                return types.make(.primitive(.double, .nonNull))
            case .charLiteral:
                return types.make(.primitive(.char, .nonNull))
            case .boolLiteral:
                return types.make(.primitive(.boolean, .nonNull))
            case .stringLiteral:
                return types.stringType
            default:
                break
            }
        }
        return arena.exprType(argExprID)
    }

    func isAnyOrNullableAny(_ kind: TypeKind) -> Bool {
        if case .any = kind {
            return true
        }
        return false
    }

    func isNonNullableStringStruct(_ kind: TypeKind) -> Bool {
        if case let .stringStruct(nullability) = kind {
            return nullability == .nonNull
        }
        return false
    }

    func isNonValueClassReference(_ kind: TypeKind, symbols: SymbolTable?) -> Bool {
        guard case let .classType(classType) = kind else { return false }
        // Non-null enum values use their raw ordinal representation outside
        // Any-erased and nullable slots, just like value classes use their
        // underlying primitive. Keep an enum-typed copy from being mistaken
        // for a reference boundary and boxed unnecessarily.
        if let symbols, let sym = symbols.symbol(classType.classSymbol) {
            if classType.nullability == .nonNull, sym.kind == .enumClass {
                return false
            }
            // Exclude value classes — they are unboxed to their underlying
            // primitive.
            if sym.flags.contains(.valueType) {
                return false
            }
        }
        return true
    }

    func needsUnboxing(
        sourceKind: TypeKind,
        targetKind: TypeKind,
        symbols: SymbolTable? = nil
    ) -> Bool {
        if isAnyOrNullableAny(sourceKind) {
            if case .primitive(_, .nonNull) = targetKind {
                return true
            }
            if isNonNullableStringStruct(targetKind) {
                return true
            }
            return false
        }
        // Non-value-class reference type → primitive: unbox (e.g. interface → value class)
        if isNonValueClassReference(sourceKind, symbols: symbols) {
            if case .primitive(_, .nonNull) = targetKind {
                return true
            }
            return false
        }
        if case .typeParam = sourceKind,
           case .primitive(_, .nonNull) = targetKind
        {
            return true
        }

        // Nullable → non-null always needs unboxing (box pointer or null sentinel).
        if case let .primitive(sourcePrimitive, .nullable) = sourceKind,
           case let .primitive(targetPrimitive, .nonNull) = targetKind,
           sourcePrimitive == targetPrimitive
        {
            return true
        }
        // Non-null → non-null: skip unboxing only for Double and Float.
        // kk_unbox_double/kk_unbox_float treat the null sentinel (Int.min) as null
        // and return 0, which corrupts -0.0 whose bit pattern equals Int.min.
        // Boolean, Int, Long, Char do not share a valid value with the null sentinel,
        // so their non-null → non-null unboxing is still safe and necessary.
        if case let .primitive(sourcePrimitive, .nonNull) = sourceKind,
           case let .primitive(targetPrimitive, .nonNull) = targetKind,
           sourcePrimitive == targetPrimitive,
           sourcePrimitive != .double, sourcePrimitive != .float
        {
            return true
        }
        return false
    }

    func needsBoxingForCopy(sourceKind: TypeKind, targetKind: TypeKind) -> Bool {
        if case let .primitive(sourcePrimitive, .nonNull) = sourceKind,
           case let .primitive(targetPrimitive, .nullable) = targetKind,
           sourcePrimitive == targetPrimitive
        {
            return true
        }
        return false
    }

    /// Unbox a binary operand if its intrinsic type is Any/reference but the
    /// result expression expects a primitive (smart-cast scenario).
    func unboxBinaryOperandIfNeeded(
        operand: KIRExprID,
        resultExpr: KIRExprID,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        boxingCalleeTable: BoxingCalleeTable,
        newBody: inout [KIRInstruction]
    ) -> KIRExprID {
        // Literal expressions hold raw (never-boxed) values. Inserting kk_unbox_long
        // on a raw Long.MIN_VALUE literal would hit the null-sentinel path and return 0.
        if let expr = module.arena.expr(operand) {
            switch expr {
            case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
                 .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral:
                return operand
            default:
                break
            }
        }
        guard let operandType = intrinsicArgType(operand, arena: module.arena, types: types),
              let resultType = module.arena.exprType(resultExpr)
        else {
            return operand
        }
        let operandKind = resolveValueClassKind(types.kind(of: operandType), types: types, symbols: symbols)
        let resultKind = resolveValueClassKind(types.kind(of: resultType), types: types, symbols: symbols)
        guard needsUnboxing(sourceKind: operandKind, targetKind: resultKind, symbols: symbols),
              let callee = unboxingCallee(
                  sourceKind: operandKind, targetKind: resultKind,
                  boxingCalleeTable: boxingCalleeTable, types: types, symbols: symbols
              )
        else {
            return operand
        }
        let unboxed = emitNonThrowingCall(
            callee: callee,
            arg: operand,
            resultType: resultType,
            arena: module.arena,
            into: &newBody
        )
        return unboxed
    }

    /// Unbox an operand to its own declared primitive type.
    /// Used for comparison operators (==, !=, <, etc.) where the result type is
    /// Boolean and cannot be used to infer the unboxing target.  If the operand's
    /// declared type is `.primitive(.int, .nonNull)` we emit `kk_unbox_int`;
    /// `kk_unbox_int` is idempotent for already-unboxed values (it checks the
    /// object-pointer registry and returns the raw value unchanged if not found).
    ///
    /// When the operand has no type info in the arena (e.g. the result of an
    /// arithmetic sub-expression whose Sema type was not recorded), `hint` is
    /// used as the target primitive kind instead.  This covers patterns like
    /// `x + 0 == x` where the `+` result has nil arena type but the `x` parameter
    /// has a known Int type.
    func unboxOperandToOwnType(
        _ operand: KIRExprID,
        hint: TypeKind? = nil,
        module: KIRModule,
        types: TypeSystem,
        symbols: SymbolTable?,
        boxingCalleeTable: BoxingCalleeTable,
        newBody: inout [KIRInstruction]
    ) -> KIRExprID {
        if let expr = module.arena.expr(operand) {
            switch expr {
            case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
                 .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral:
                return operand
            default:
                break
            }
        }
        let operandType = intrinsicArgType(operand, arena: module.arena, types: types)
        let rawOperandKind: TypeKind? = operandType.map { types.kind(of: $0) }
        let operandKind: TypeKind? = rawOperandKind.map {
            resolveValueClassKind($0, types: types, symbols: symbols)
        }
        // Determine the target kind:
        //   1. Use the operand's own concrete primitive type if available.
        //   2. Fall back to the hint (type of a sibling operand) when the
        //      operand has no type info — this handles arithmetic results whose
        //      Sema type was not recorded in the arena.
        let targetKind: TypeKind
        if let opKind = operandKind, case .primitive(_, .nonNull) = opKind {
            targetKind = opKind
        } else if let hintKind = hint, case .primitive(_, .nonNull) = hintKind {
            targetKind = hintKind
        } else if let opKind = operandKind {
            targetKind = opKind
        } else {
            return operand
        }
        let sourceKind = operandKind ?? targetKind
        guard needsUnboxing(sourceKind: sourceKind, targetKind: targetKind, symbols: symbols),
              let callee = unboxingCallee(
                  sourceKind: sourceKind, targetKind: targetKind,
                  boxingCalleeTable: boxingCalleeTable, types: types, symbols: symbols
              )
        else {
            return operand
        }
        let resultType = operandType ?? types.make(targetKind)
        let unboxed = emitNonThrowingCall(
            callee: callee,
            arg: operand,
            resultType: resultType,
            arena: module.arena,
            into: &newBody
        )
        return unboxed
    }

    func boxCalleeForPrimitive(
        _ kind: TypeKind,
        boxingCalleeTable: BoxingCalleeTable
    ) -> InternedString? {
        // Unit is a builtin value rather than a PrimitiveType, but it still
        // needs a heap representation when it crosses an erased Any boundary.
        boxingCalleeTable.boxCallee(for: kind, requireNonNull: true)
    }
}
