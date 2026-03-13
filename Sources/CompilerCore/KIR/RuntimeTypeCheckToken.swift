import Foundation

/// Classifies a type for runtime type checking token encoding.
/// Each case maps to one of the base-type constants in `RuntimeTypeCheckToken`.
enum RuntimeTypeCategory {
    case unknown
    case any
    case string
    case int
    case boolean
    case null
    case nominal(SymbolID)
    case uint
    case ulong
    case ubyte
    case ushort

    /// The base constant used in the runtime token encoding.
    var base: Int64 {
        switch self {
        case .unknown:  RuntimeTypeCheckToken.unknownBase
        case .any:      RuntimeTypeCheckToken.anyBase
        case .string:   RuntimeTypeCheckToken.stringBase
        case .int:      RuntimeTypeCheckToken.intBase
        case .boolean:  RuntimeTypeCheckToken.booleanBase
        case .null:     RuntimeTypeCheckToken.nullBase
        case .nominal:  RuntimeTypeCheckToken.nominalBase
        case .uint:     RuntimeTypeCheckToken.uintBase
        case .ulong:    RuntimeTypeCheckToken.ulongBase
        case .ubyte:    RuntimeTypeCheckToken.ubyteBase
        case .ushort:   RuntimeTypeCheckToken.ushortBase
        }
    }

    /// The Kotlin simple name for this category, or `nil` for unknown/nominal
    /// (nominal names require symbol resolution).
    var simpleName: String? {
        switch self {
        case .any:      "Any"
        case .null:     "Nothing"
        case .string:   PrimitiveType.string.kotlinName
        case .int:      PrimitiveType.int.kotlinName
        case .boolean:  PrimitiveType.boolean.kotlinName
        case .uint:     PrimitiveType.uint.kotlinName
        case .ulong:    PrimitiveType.ulong.kotlinName
        case .ubyte:    PrimitiveType.ubyte.kotlinName
        case .ushort:   PrimitiveType.ushort.kotlinName
        case .unknown, .nominal:  nil
        }
    }
}

/// Result of classifying a `TypeID` for runtime type checking.
struct RuntimeTypeDescriptor {
    let category: RuntimeTypeCategory
    let nullable: Bool
}

/// Shared runtime token encoding used by:
/// - reified hidden type token arguments
/// - `is`/`!is` runtime checks
/// - catch clause type matching
///
/// Keep these values in sync with Runtime's `kk_op_is` implementation.
enum RuntimeTypeCheckToken {
    static let unknownBase: Int64 = 0
    static let anyBase: Int64 = 1
    static let stringBase: Int64 = 2
    static let intBase: Int64 = 3
    static let booleanBase: Int64 = 4
    static let nullBase: Int64 = 5
    static let nominalBase: Int64 = 6
    static let uintBase: Int64 = 7
    static let ulongBase: Int64 = 8
    static let ubyteBase: Int64 = 9
    static let ushortBase: Int64 = 10

    static let baseMask: Int64 = 0xFF
    static let nullableFlag: Int64 = 1 << 8
    static let payloadShift: Int64 = 9
    static let payloadMask: Int64 = (1 << 55) - 1

    static func encode(base: Int64, nullable: Bool, payload: Int64 = 0) -> Int64 {
        var token = base & baseMask
        if nullable {
            token |= nullableFlag
        }
        let normalizedPayload = payload & payloadMask
        token |= (normalizedPayload << payloadShift)
        return token
    }

    /// Classifies a resolved `TypeID` into a `RuntimeTypeDescriptor`.
    static func classify(type: TypeID, sema: SemaModule, interner: StringInterner) -> RuntimeTypeDescriptor {
        let nullable = sema.types.nullability(of: type) == .nullable
        let category: RuntimeTypeCategory
        switch sema.types.kind(of: type) {
        case .any:                      category = .any
        case .primitive(.string, _):    category = .string
        case .primitive(.int, _):       category = .int
        case .primitive(.uint, _):      category = .uint
        case .primitive(.ulong, _):     category = .ulong
        case .primitive(.ubyte, _):     category = .ubyte
        case .primitive(.ushort, _):    category = .ushort
        case .primitive(.boolean, _):   category = .boolean
        case .nothing:                  category = nullable ? .null : .unknown
        case let .classType(classType): category = .nominal(classType.classSymbol)
        default:                        category = .unknown
        }
        return RuntimeTypeDescriptor(category: category, nullable: nullable)
    }

    static func encodeBuiltinTypeName(
        _ name: InternedString,
        nullable: Bool,
        builtinNames: BuiltinTypeNames
    ) -> Int64? {
        switch name {
        case builtinNames.any:
            encode(base: anyBase, nullable: nullable)
        case builtinNames.string:
            encode(base: stringBase, nullable: nullable)
        case builtinNames.int:
            encode(base: intBase, nullable: nullable)
        case builtinNames.uint:
            encode(base: uintBase, nullable: nullable)
        case builtinNames.ulong:
            encode(base: ulongBase, nullable: nullable)
        case builtinNames.ubyte:
            encode(base: ubyteBase, nullable: nullable)
        case builtinNames.ushort:
            encode(base: ushortBase, nullable: nullable)
        case builtinNames.boolean:
            encode(base: booleanBase, nullable: nullable)
        case builtinNames.nothing:
            nullable ? nullBase : unknownBase
        default:
            nil
        }
    }

    static func encode(type: TypeID, sema: SemaModule, interner: StringInterner) -> Int64 {
        let descriptor = classify(type: type, sema: sema, interner: interner)
        switch descriptor.category {
        case let .nominal(symbolID):
            let nominalTypeID = stableNominalTypeID(symbol: symbolID, sema: sema, interner: interner)
            return encode(base: descriptor.category.base, nullable: descriptor.nullable, payload: nominalTypeID)
        case .null:
            return nullBase
        default:
            return encode(base: descriptor.category.base, nullable: descriptor.nullable)
        }
    }

    /// Returns the simple (unqualified) type name for a given `TypeID`, or `nil`
    /// when the type is not representable as a Kotlin class name.
    static func simpleName(of type: TypeID, sema: SemaModule, interner: StringInterner) -> String? {
        let descriptor = classify(type: type, sema: sema, interner: interner)
        if let name = descriptor.category.simpleName {
            return name
        }
        // Handle primitives not covered by RuntimeTypeCategory (char, long, float, double)
        // and nominal types that need symbol resolution.
        switch sema.types.kind(of: type) {
        case .nothing:
            return "Nothing"
        case .primitive(.long, _):
            return PrimitiveType.long.kotlinName
        case .primitive(.char, _):
            return PrimitiveType.char.kotlinName
        case .primitive(.float, _):
            return PrimitiveType.float.kotlinName
        case .primitive(.double, _):
            return PrimitiveType.double.kotlinName
        case let .classType(classType):
            guard let symbol = sema.symbols.symbol(classType.classSymbol) else {
                return nil
            }
            return interner.resolve(symbol.name)
        default:
            return nil
        }
    }

    static func stableNominalTypeID(symbol: SymbolID, sema: SemaModule, interner: StringInterner) -> Int64 {
        guard let semanticSymbol = sema.symbols.symbol(symbol) else {
            return 0
        }
        let fqName = semanticSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
        guard !fqName.isEmpty else {
            return 0
        }
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in fqName.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
        }
        let payload = Int64(bitPattern: hash) & payloadMask
        return payload == 0 ? 1 : payload
    }
}
