import Foundation

extension ABILoweringPass {
    func resolveValueClassKind(
        _ kind: TypeKind,
        types: TypeSystem,
        symbols: SymbolTable?
    ) -> TypeKind {
        guard let symbols else { return kind }
        if case let .classType(ct) = kind {
            // Do not resolve nullable value class types — they are boxed at the ABI level.
            guard ct.nullability == .nonNull else { return kind }
            let sym = symbols.symbol(ct.classSymbol)
            if let sym, sym.flags.contains(.valueType),
               let underlyingType = symbols.valueClassUnderlyingType(for: ct.classSymbol)
            {
                return types.kind(of: underlyingType)
            }
        }
        return kind
    }

    func boxingCallee(
        argType: TypeID,
        paramType: TypeID,
        types: TypeSystem,
        boxIntCallee: InternedString,
        boxBoolCallee: InternedString,
        boxLongCallee: InternedString,
        boxFloatCallee: InternedString,
        boxDoubleCallee: InternedString,
        boxCharCallee: InternedString,
        symbols: SymbolTable? = nil
    ) -> InternedString? {
        let rawArgKind = types.kind(of: argType)
        let argKind = resolveValueClassKind(rawArgKind, types: types, symbols: symbols)
        let paramKind = types.kind(of: paramType)

        // Treat Any/Any? and non-value-class reference types as boxing boundaries.
        let isReferenceBoxingBoundary: Bool = {
            if isAnyOrNullableAny(paramKind) {
                return true
            }
            if case let .classType(ct) = paramKind {
                // If we know this is a non-null value class, do not treat it as a boxing boundary.
                // Nullable value class types (e.g. Meter?) are boxed at ABI level and ARE boundaries.
                if let symbols,
                   let sym = symbols.symbol(ct.classSymbol),
                   sym.flags.contains(.valueType),
                   ct.nullability == .nonNull
                {
                    return false
                }
                // Otherwise, any non-value-class reference type is a boxing boundary.
                return true
            }
            return false
        }()

        guard isReferenceBoxingBoundary else {
            if case let .primitive(paramPrimitive, .nullable) = paramKind,
               case let .primitive(argPrimitive, .nonNull) = argKind,
               paramPrimitive == argPrimitive
            {
                switch argPrimitive {
                case .int:
                    return boxIntCallee
                case .long:
                    return boxLongCallee
                case .boolean:
                    return boxBoolCallee
                case .float:
                    return boxFloatCallee
                case .double:
                    return boxDoubleCallee
                case .char:
                    return boxCharCallee
                case .uint, .ubyte, .ushort:
                    return boxIntCallee
                case .ulong:
                    return boxLongCallee
                default:
                    return nil
                }
            }
            return nil
        }

        switch argKind {
        case .primitive(.int, _):
            return boxIntCallee
        case .primitive(.long, _):
            return boxLongCallee
        case .primitive(.boolean, _):
            return boxBoolCallee
        case .primitive(.float, _):
            return boxFloatCallee
        case .primitive(.double, _):
            return boxDoubleCallee
        case .primitive(.char, _):
            return boxCharCallee
        case .primitive(.uint, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return boxIntCallee
        case .primitive(.ulong, _):
            return boxLongCallee
        default:
            return nil
        }
    }

    func unboxingCallee(
        sourceKind: TypeKind,
        targetKind: TypeKind,
        unboxIntCallee: InternedString,
        unboxBoolCallee: InternedString,
        unboxLongCallee: InternedString,
        unboxFloatCallee: InternedString,
        unboxDoubleCallee: InternedString,
        unboxCharCallee: InternedString,
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

        switch resolvedTargetKind {
        case .primitive(.int, _):
            return unboxIntCallee
        case .primitive(.long, _):
            return unboxLongCallee
        case .primitive(.boolean, _):
            return unboxBoolCallee
        case .primitive(.float, _):
            return unboxFloatCallee
        case .primitive(.double, _):
            return unboxDoubleCallee
        case .primitive(.char, _):
            return unboxCharCallee
        case .primitive(.uint, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return unboxIntCallee
        case .primitive(.ulong, _):
            return unboxLongCallee
        default:
            return nil
        }
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
                return types.make(.primitive(.string, .nonNull))
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

    func isNonValueClassReference(_ kind: TypeKind, symbols: SymbolTable?) -> Bool {
        if case let .classType(ct) = kind {
            if let symbols,
               let sym = symbols.symbol(ct.classSymbol),
               sym.flags.contains(.valueType),
               ct.nullability == .nonNull
            {
                return false
            }
            return true
        }
        return false
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
            return false
        }
        // Non-value-class reference type → primitive: unbox (e.g. interface → value class)
        if isNonValueClassReference(sourceKind, symbols: symbols) {
            if case .primitive(_, .nonNull) = targetKind {
                return true
            }
            return false
        }
        if case let .primitive(sourcePrimitive, .nullable) = sourceKind,
           case let .primitive(targetPrimitive, .nonNull) = targetKind,
           sourcePrimitive == targetPrimitive
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

    func boxCalleeForPrimitive(
        _ kind: TypeKind,
        boxIntCallee: InternedString,
        boxBoolCallee: InternedString,
        boxLongCallee: InternedString,
        boxFloatCallee: InternedString,
        boxDoubleCallee: InternedString,
        boxCharCallee: InternedString
    ) -> InternedString? {
        switch kind {
        case .primitive(.int, .nonNull):
            boxIntCallee
        case .primitive(.long, .nonNull):
            boxLongCallee
        case .primitive(.boolean, .nonNull):
            boxBoolCallee
        case .primitive(.float, .nonNull):
            boxFloatCallee
        case .primitive(.double, .nonNull):
            boxDoubleCallee
        case .primitive(.char, .nonNull):
            boxCharCallee
        case .primitive(.uint, .nonNull), .primitive(.ubyte, .nonNull), .primitive(.ushort, .nonNull):
            boxIntCallee
        case .primitive(.ulong, .nonNull):
            boxLongCallee
        default:
            nil
        }
    }
}
