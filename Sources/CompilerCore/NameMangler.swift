import Foundation

public final class NameMangler {
    public init() {}

    public func mangle(
        moduleName: String,
        symbol: SemanticSymbol,
        signature: String
    ) -> String {
        let fqPart = symbol.fqName.map { encode(component: $0.rawValue) }.joined(separator: "_")
        let kind = kindCode(symbol.kind)
        let base = "_KK_\(moduleName)__\(fqPart)__\(kind)__\(signature)"
        let hash = fnv1a32Hex(base)
        return "\(base)__\(hash)"
    }

    private func encode(component: Int32) -> String {
        let raw = String(component)
        return "\(raw.count)\(raw)"
    }

    private func kindCode(_ kind: SymbolKind) -> String {
        switch kind {
        case .function:
            return "F"
        case .class:
            return "C"
        case .property:
            return "P"
        case .constructor:
            return "K"
        case .object:
            return "O"
        case .typeAlias:
            return "T"
        case .interface:
            return "I"
        case .enumClass:
            return "E"
        case .annotationClass:
            return "A"
        case .package:
            return "N"
        case .field:
            return "D"
        case .typeParameter:
            return "Y"
        case .valueParameter:
            return "V"
        case .local:
            return "L"
        case .label:
            return "B"
        }
    }

    private func fnv1a32Hex(_ value: String) -> String {
        let prime: UInt32 = 16777619
        var hash: UInt32 = 2166136261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash &*= prime
        }
        return String(format: "%08x", hash)
    }
}
