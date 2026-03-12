import Foundation

/// Shared runtime token encoding used by:
/// - reified hidden type token arguments
/// - `is`/`!is` runtime checks
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
        let nullable = sema.types.nullability(of: type) == .nullable
        switch sema.types.kind(of: type) {
        case .any:
            return encode(base: anyBase, nullable: nullable)
        case .primitive(.string, _):
            return encode(base: stringBase, nullable: nullable)
        case .primitive(.int, _):
            return encode(base: intBase, nullable: nullable)
        case .primitive(.uint, _):
            return encode(base: uintBase, nullable: nullable)
        case .primitive(.ulong, _):
            return encode(base: ulongBase, nullable: nullable)
        case .primitive(.ubyte, _):
            return encode(base: ubyteBase, nullable: nullable)
        case .primitive(.ushort, _):
            return encode(base: ushortBase, nullable: nullable)
        case .primitive(.boolean, _):
            return encode(base: booleanBase, nullable: nullable)
        case .nothing:
            return nullable ? nullBase : unknownBase
        case let .classType(classType):
            let nominalTypeID = stableNominalTypeID(symbol: classType.classSymbol, sema: sema, interner: interner)
            return encode(base: nominalBase, nullable: nullable, payload: nominalTypeID)
        default:
            // Unsupported compound RTTI currently falls back to unknown token.
            // Nullable unknown keeps null-matching behavior.
            return encode(base: unknownBase, nullable: nullable)
        }
    }

    /// Returns the simple (unqualified) type name for a given `TypeID`, or `nil`
    /// when the type is not representable as a Kotlin class name.
    static func simpleName(of type: TypeID, sema: SemaModule, interner: StringInterner) -> String? {
        switch sema.types.kind(of: type) {
        case .any:
            return "Any"
        case .primitive(.string, _):
            return PrimitiveType.string.kotlinName
        case .primitive(.int, _):
            return PrimitiveType.int.kotlinName
        case .primitive(.long, _):
            return PrimitiveType.long.kotlinName
        case .primitive(.uint, _):
            return PrimitiveType.uint.kotlinName
        case .primitive(.ulong, _):
            return PrimitiveType.ulong.kotlinName
        case .primitive(.ubyte, _):
            return PrimitiveType.ubyte.kotlinName
        case .primitive(.ushort, _):
            return PrimitiveType.ushort.kotlinName
        case .primitive(.boolean, _):
            return PrimitiveType.boolean.kotlinName
        case .primitive(.char, _):
            return PrimitiveType.char.kotlinName
        case .primitive(.float, _):
            return PrimitiveType.float.kotlinName
        case .primitive(.double, _):
            return PrimitiveType.double.kotlinName
        case .nothing:
            return "Nothing"
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
