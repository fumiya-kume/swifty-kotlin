public final class TypeSystem {
    private var kindToID: [TypeKind: TypeID] = [:]
    private var idToKind: [TypeKind] = []
    private var nominalDirectSupertypes: [SymbolID: [SymbolID]] = [:]
    private var nominalTypeParameterVariancesMap: [SymbolID: [TypeVariance]] = [:]
    private var nominalTypeParameterSymbolsMap: [SymbolID: [SymbolID]] = [:]
    private var nominalSupertypeTypeArgsMap: [SymbolID: [SymbolID: [TypeArg]]] = [:]

    /// The symbol ID of the synthetic `kotlin.Comparable` interface, set during registration.
    public internal(set) var comparableInterfaceSymbol: SymbolID?

    /// Symbol table reference for SAM (fun interface) subtyping. Set during DataFlowSemaPhase.
    public weak var symbolTable: SymbolTable?

    public let errorType: TypeID
    public let unitType: TypeID
    public let nothingType: TypeID
    public let nullableNothingType: TypeID
    public let anyType: TypeID
    public let nullableAnyType: TypeID
    public let booleanType: TypeID
    public let charType: TypeID
    public let intType: TypeID
    public let longType: TypeID
    public let floatType: TypeID
    public let doubleType: TypeID
    public let stringType: TypeID
    public let uintType: TypeID
    public let ulongType: TypeID
    public let ubyteType: TypeID
    public let ushortType: TypeID

    public init() {
        errorType = TypeID(rawValue: 0)
        unitType = TypeID(rawValue: 1)
        nothingType = TypeID(rawValue: 2)
        nullableNothingType = TypeID(rawValue: 3)
        anyType = TypeID(rawValue: 4)
        nullableAnyType = TypeID(rawValue: 5)
        booleanType = TypeID(rawValue: 6)
        charType = TypeID(rawValue: 7)
        intType = TypeID(rawValue: 8)
        longType = TypeID(rawValue: 9)
        floatType = TypeID(rawValue: 10)
        doubleType = TypeID(rawValue: 11)
        stringType = TypeID(rawValue: 12)
        uintType = TypeID(rawValue: 13)
        ulongType = TypeID(rawValue: 14)
        ubyteType = TypeID(rawValue: 15)
        ushortType = TypeID(rawValue: 16)

        idToKind = [
            .error,
            .unit,
            .nothing(.nonNull),
            .nothing(.nullable),
            .any(.nonNull),
            .any(.nullable),
            .primitive(.boolean, .nonNull),
            .primitive(.char, .nonNull),
            .primitive(.int, .nonNull),
            .primitive(.long, .nonNull),
            .primitive(.float, .nonNull),
            .primitive(.double, .nonNull),
            .primitive(.string, .nonNull),
            .primitive(.uint, .nonNull),
            .primitive(.ulong, .nonNull),
            .primitive(.ubyte, .nonNull),
            .primitive(.ushort, .nonNull),
        ]
        kindToID = [
            .error: errorType,
            .unit: unitType,
            .nothing(.nonNull): nothingType,
            .nothing(.nullable): nullableNothingType,
            .any(.nonNull): anyType,
            .any(.nullable): nullableAnyType,
            .primitive(.boolean, .nonNull): booleanType,
            .primitive(.char, .nonNull): charType,
            .primitive(.int, .nonNull): intType,
            .primitive(.long, .nonNull): longType,
            .primitive(.float, .nonNull): floatType,
            .primitive(.double, .nonNull): doubleType,
            .primitive(.string, .nonNull): stringType,
            .primitive(.uint, .nonNull): uintType,
            .primitive(.ulong, .nonNull): ulongType,
            .primitive(.ubyte, .nonNull): ubyteType,
            .primitive(.ushort, .nonNull): ushortType,
        ]
    }

    /// Returns `true` when the type is definitely non-nullable, either because
    /// it is inherently non-null or because it is an intersection containing `Any`.
    /// `T & Any` is Kotlin's "definitely non-nullable" type – even when T's upper
    /// bound is nullable, the intersection guarantees non-nullability.
    public func isDefinitelyNonNull(_ type: TypeID) -> Bool {
        switch kind(of: type) {
        case .error:
            false
        case .unit:
            true
        case let .nothing(n):
            n == .nonNull
        case let .any(n):
            n == .nonNull
        case let .primitive(_, n):
            n == .nonNull
        case let .classType(ct):
            ct.nullability == .nonNull
        case let .functionType(ft):
            ft.nullability == .nonNull
        case let .typeParam(tp):
            tp.nullability == .nonNull
        case let .intersection(parts):
            // T & Any is definitely non-null; any part being non-null suffices
            parts.contains { isDefinitelyNonNull($0) }
        }
    }

    /// Nullability of an intersection type.
    /// An intersection that contains `Any` (non-null) is definitely non-nullable.
    public func nullability(of type: TypeID) -> Nullability {
        switch kind(of: type) {
        case .error, .unit:
            .nonNull
        case let .nothing(n), let .any(n), let .primitive(_, n):
            n
        case let .classType(ct):
            ct.nullability
        case let .functionType(ft):
            ft.nullability
        case let .typeParam(tp):
            tp.nullability
        case let .intersection(parts):
            parts.contains { nullability(of: $0) == .nonNull } ? .nonNull : .nullable
        }
    }

    public func isSignedInteger(_ type: TypeID) -> Bool {
        switch kind(of: type) {
        case .primitive(.int, _), .primitive(.long, _), .primitive(.char, _),
             .primitive(.ubyte, _), .primitive(.ushort, _):
            // In Kotlin, Char, UByte, UShort undergo widening to Int for arithmetic, so we treat them as signed
            // or we only explicitly mark Int and Long as signed. Wait, UByte and UShort are unsigned logically,
            // but for binary operations they might already be promoted to Int unless we are strict.
            // Let's rely strictly on Int, Long for signed integer type.
            type == intType || type == longType || type == charType ||
                type == makeNullable(intType) || type == makeNullable(longType) || type == makeNullable(charType)
        default:
            false
        }
    }

    public func isSigned(_ type: TypeID) -> Bool {
        switch kind(of: type) {
        case .primitive(.int, _), .primitive(.long, _):
            true
        default:
            false
        }
    }

    public func isUnsigned(_ type: TypeID) -> Bool {
        switch kind(of: type) {
        case .primitive(.uint, _), .primitive(.ulong, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            true
        default:
            false
        }
    }

    public func withNullability(_ nullability: Nullability, for type: TypeID) -> TypeID {
        switch kind(of: type) {
        case .error, .unit:
            return type
        case let .intersection(parts):
            // For intersection types, apply nullability to each part
            if nullability == .nonNull {
                // If intersection is already definitely non-null, return as-is
                if parts.contains(where: { isDefinitelyNonNull($0) }) {
                    return type
                }
                // Add Any to make it definitely non-null
                return make(.intersection(parts + [anyType]))
            }
            return type // intersections don't become nullable directly
        case let .nothing(existing):
            let normalized: Nullability = (nullability == .platformType) ? .nullable : nullability
            if existing == normalized { return type }
            return make(.nothing(normalized))
        case let .any(existing):
            if existing == nullability { return type }
            return make(.any(nullability))
        case let .primitive(prim, existing):
            if existing == nullability { return type }
            return make(.primitive(prim, nullability))
        case let .classType(ct):
            if ct.nullability == nullability { return type }
            return make(.classType(ClassType(classSymbol: ct.classSymbol, args: ct.args, nullability: nullability)))
        case let .typeParam(tp):
            if tp.nullability == nullability { return type }
            return make(.typeParam(TypeParamType(symbol: tp.symbol, nullability: nullability)))
        case let .functionType(ft):
            if ft.nullability == nullability { return type }
            return make(.functionType(FunctionType(receiver: ft.receiver, params: ft.params, returnType: ft.returnType, isSuspend: ft.isSuspend, nullability: nullability)))
        }
    }

    public func makeNullable(_ type: TypeID) -> TypeID {
        withNullability(.nullable, for: type)
    }

    public func makeNonNullable(_ type: TypeID) -> TypeID {
        withNullability(.nonNull, for: type)
    }

    public func make(_ kind: TypeKind) -> TypeID {
        // Keep Nothing as a two-state type; Nothing! is normalized to Nothing?.
        let normalizedKind: TypeKind = switch kind {
        case .nothing(.platformType):
            .nothing(.nullable)
        default:
            kind
        }
        if let existing = kindToID[normalizedKind] {
            return existing
        }
        let id = TypeID(rawValue: Int32(idToKind.count))
        idToKind.append(normalizedKind)
        kindToID[normalizedKind] = id
        return id
    }

    public func kind(of id: TypeID) -> TypeKind {
        let index = Int(id.rawValue)
        guard index >= 0, index < idToKind.count else {
            return .error
        }
        return idToKind[index]
    }

    public func setNominalDirectSupertypes(_ supertypes: [SymbolID], for symbol: SymbolID) {
        let unique = Array(Set(supertypes)).sorted(by: { $0.rawValue < $1.rawValue })
        nominalDirectSupertypes[symbol] = unique
    }

    public func directNominalSupertypes(for symbol: SymbolID) -> [SymbolID] {
        nominalDirectSupertypes[symbol] ?? []
    }

    public func setNominalTypeParameterVariances(_ variances: [TypeVariance], for symbol: SymbolID) {
        nominalTypeParameterVariancesMap[symbol] = variances
    }

    public func nominalTypeParameterVariances(for symbol: SymbolID) -> [TypeVariance] {
        nominalTypeParameterVariancesMap[symbol] ?? []
    }

    public func setNominalTypeParameterSymbols(_ symbols: [SymbolID], for nominal: SymbolID) {
        nominalTypeParameterSymbolsMap[nominal] = symbols
    }

    public func nominalTypeParameterSymbols(for nominal: SymbolID) -> [SymbolID] {
        nominalTypeParameterSymbolsMap[nominal] ?? []
    }

    /// Returns `true` when `type` structurally contains a reference to the
    /// type parameter identified by `symbol`.
    public func typeContainsTypeParam(_ type: TypeID, symbol: SymbolID) -> Bool {
        switch kind(of: type) {
        case let .typeParam(tp):
            return tp.symbol == symbol
        case let .classType(ct):
            return ct.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    typeContainsTypeParam(inner, symbol: symbol)
                case .star:
                    false
                }
            }
        case let .functionType(ft):
            if let receiver = ft.receiver, typeContainsTypeParam(receiver, symbol: symbol) {
                return true
            }
            if ft.params.contains(where: { typeContainsTypeParam($0, symbol: symbol) }) {
                return true
            }
            return typeContainsTypeParam(ft.returnType, symbol: symbol)
        case let .intersection(parts):
            return parts.contains { typeContainsTypeParam($0, symbol: symbol) }
        default:
            return false
        }
    }

    public func setNominalSupertypeTypeArgs(_ args: [TypeArg], for child: SymbolID, supertype parent: SymbolID) {
        nominalSupertypeTypeArgsMap[child, default: [:]][parent] = args
    }

    public func nominalSupertypeTypeArgs(for child: SymbolID, supertype parent: SymbolID) -> [TypeArg] {
        nominalSupertypeTypeArgsMap[child]?[parent] ?? []
    }
}
