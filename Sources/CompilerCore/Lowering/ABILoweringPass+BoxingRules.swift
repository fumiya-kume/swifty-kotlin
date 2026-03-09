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
        boxCallees: BoxingCalleeNames,
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
                    return boxCallees.int
                case .long:
                    return boxCallees.long
                case .boolean:
                    return boxCallees.bool
                case .float:
                    return boxCallees.float
                case .double:
                    return boxCallees.double
                case .char:
                    return boxCallees.char
                case .uint, .ubyte, .ushort:
                    return boxCallees.int
                case .ulong:
                    return boxCallees.long
                default:
                    return nil
                }
            }
            return nil
        }

        switch argKind {
        case .primitive(.int, _):
            return boxCallees.int
        case .primitive(.long, _):
            return boxCallees.long
        case .primitive(.boolean, _):
            return boxCallees.bool
        case .primitive(.float, _):
            return boxCallees.float
        case .primitive(.double, _):
            return boxCallees.double
        case .primitive(.char, _):
            return boxCallees.char
        case .primitive(.uint, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return boxCallees.int
        case .primitive(.ulong, _):
            return boxCallees.long
        default:
            return nil
        }
    }

    func unboxingCallee(
        sourceKind: TypeKind,
        targetKind: TypeKind,
        unboxCallees: UnboxingCalleeNames,
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
            return unboxCallees.int
        case .primitive(.long, _):
            return unboxCallees.long
        case .primitive(.boolean, _):
            return unboxCallees.bool
        case .primitive(.float, _):
            return unboxCallees.float
        case .primitive(.double, _):
            return unboxCallees.double
        case .primitive(.char, _):
            return unboxCallees.char
        case .primitive(.uint, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return unboxCallees.int
        case .primitive(.ulong, _):
            return unboxCallees.long
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
        if case .typeParam = sourceKind,
           case .primitive(_, .nonNull) = targetKind
        {
            return true
        }

        if case let .primitive(sourcePrimitive, _) = sourceKind,
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
        boxCallees: BoxingCalleeNames
    ) -> InternedString? {
        switch kind {
        case .primitive(.int, .nonNull):
            boxCallees.int
        case .primitive(.long, .nonNull):
            boxCallees.long
        case .primitive(.boolean, .nonNull):
            boxCallees.bool
        case .primitive(.float, .nonNull):
            boxCallees.float
        case .primitive(.double, .nonNull):
            boxCallees.double
        case .primitive(.char, .nonNull):
            boxCallees.char
        case .primitive(.uint, .nonNull), .primitive(.ubyte, .nonNull), .primitive(.ushort, .nonNull):
            boxCallees.int
        case .primitive(.ulong, .nonNull):
            boxCallees.long
        default:
            nil
        }
    }
}
