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

    static let baseMask: Int64 = 0xFF
    static let nullableFlag: Int64 = 1 << 8

    static func encode(base: Int64, nullable: Bool) -> Int64 {
        nullable ? (base | nullableFlag) : base
    }

    static func encodeBuiltinTypeName(_ name: String, nullable: Bool) -> Int64? {
        switch name {
        case "Any":
            return encode(base: anyBase, nullable: nullable)
        case "String":
            return encode(base: stringBase, nullable: nullable)
        case "Int":
            return encode(base: intBase, nullable: nullable)
        case "Boolean":
            return encode(base: booleanBase, nullable: nullable)
        case "Nothing":
            return nullable ? nullBase : unknownBase
        default:
            return nil
        }
    }

    static func encode(type: TypeID, sema: SemaModule) -> Int64 {
        let nullable = sema.types.nullability(of: type) == .nullable
        switch sema.types.kind(of: type) {
        case .any:
            return encode(base: anyBase, nullable: nullable)
        case .primitive(.string, _):
            return encode(base: stringBase, nullable: nullable)
        case .primitive(.int, _):
            return encode(base: intBase, nullable: nullable)
        case .primitive(.boolean, _):
            return encode(base: booleanBase, nullable: nullable)
        case .nothing:
            return nullable ? nullBase : unknownBase
        default:
            // Unsupported nominal/compound RTTI currently falls back to
            // unknown token. Nullable unknown keeps null-matching behavior.
            return encode(base: unknownBase, nullable: nullable)
        }
    }
}
