import Foundation

public struct KIRDeclID: Hashable {
    public let rawValue: Int32

    public init(rawValue: Int32 = invalidID) {
        self.rawValue = rawValue
    }
}

public struct KIRExprID: Hashable {
    public let rawValue: Int32

    public init(rawValue: Int32 = invalidID) {
        self.rawValue = rawValue
    }
}

public struct KIRTypeID: Hashable {
    public let rawValue: Int32

    public init(rawValue: Int32 = invalidID) {
        self.rawValue = rawValue
    }
}

public struct KIRParameter {
    public let symbol: SymbolID
    public let type: TypeID

    public init(symbol: SymbolID, type: TypeID) {
        self.symbol = symbol
        self.type = type
    }
}

public enum KIRInstruction {
    case nop
    case beginBlock
    case endBlock
    case returnUnit
    case returnValue(KIRExprID)
    case call(symbol: SymbolID, arguments: [KIRExprID], outThrown: Bool)
}

public struct KIRFunction {
    public let symbol: SymbolID
    public let name: InternedString
    public let params: [KIRParameter]
    public let returnType: TypeID
    public let body: [KIRInstruction]
    public let isSuspend: Bool
    public let isInline: Bool

    public init(
        symbol: SymbolID,
        name: InternedString,
        params: [KIRParameter],
        returnType: TypeID,
        body: [KIRInstruction],
        isSuspend: Bool,
        isInline: Bool
    ) {
        self.symbol = symbol
        self.name = name
        self.params = params
        self.returnType = returnType
        self.body = body
        self.isSuspend = isSuspend
        self.isInline = isInline
    }
}

public struct KIRGlobal {
    public let symbol: SymbolID
    public let type: TypeID

    public init(symbol: SymbolID, type: TypeID) {
        self.symbol = symbol
        self.type = type
    }
}

public struct KIRNominalType {
    public let symbol: SymbolID

    public init(symbol: SymbolID) {
        self.symbol = symbol
    }
}

public enum KIRDecl {
    case function(KIRFunction)
    case global(KIRGlobal)
    case nominalType(KIRNominalType)
}

public struct KIRFile {
    public let fileID: FileID
    public let decls: [KIRDeclID]

    public init(fileID: FileID, decls: [KIRDeclID]) {
        self.fileID = fileID
        self.decls = decls
    }
}

public final class KIRArena {
    public private(set) var declarations: [KIRDecl] = []

    public init() {}

    public func appendDecl(_ decl: KIRDecl) -> KIRDeclID {
        let id = KIRDeclID(rawValue: Int32(declarations.count))
        declarations.append(decl)
        return id
    }

    public func decl(_ id: KIRDeclID) -> KIRDecl? {
        let index = Int(id.rawValue)
        guard index >= 0 && index < declarations.count else {
            return nil
        }
        return declarations[index]
    }
}

public final class KIRModule {
    public let files: [KIRFile]
    public let arena: KIRArena
    public private(set) var executedLowerings: [String]

    public init(files: [KIRFile], arena: KIRArena, executedLowerings: [String] = []) {
        self.files = files
        self.arena = arena
        self.executedLowerings = executedLowerings
    }

    public var functionCount: Int {
        arena.declarations.reduce(0) { partial, decl in
            if case .function = decl {
                return partial + 1
            }
            return partial
        }
    }

    public var symbolCount: Int {
        var seen: Set<SymbolID> = []
        for decl in arena.declarations {
            switch decl {
            case .function(let fn):
                seen.insert(fn.symbol)
            case .global(let global):
                seen.insert(global.symbol)
            case .nominalType(let nominal):
                seen.insert(nominal.symbol)
            }
        }
        return seen.count
    }

    public func recordLowering(_ name: String) {
        executedLowerings.append(name)
    }

    public func dump(interner: StringInterner, symbols: SymbolTable?) -> String {
        var lines: [String] = []
        for (index, decl) in arena.declarations.enumerated() {
            switch decl {
            case .function(let function):
                let name = interner.resolve(function.name)
                lines.append("decl[\(index)] function \(name) params=\(function.params.count) suspend=\(function.isSuspend) inline=\(function.isInline)")
            case .global:
                lines.append("decl[\(index)] global")
            case .nominalType(let nominal):
                if let symbol = symbols?.symbol(nominal.symbol) {
                    let name = interner.resolve(symbol.name)
                    lines.append("decl[\(index)] type \(name)")
                } else {
                    lines.append("decl[\(index)] type")
                }
            }
        }
        if !executedLowerings.isEmpty {
            lines.append("lowerings: \(executedLowerings.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}

public final class KIRContext {
    public let diagnostics: DiagnosticEngine
    public let options: CompilerOptions

    public init(diagnostics: DiagnosticEngine, options: CompilerOptions) {
        self.diagnostics = diagnostics
        self.options = options
    }
}

public protocol KIRPass {
    static var name: String { get }
    func run(module: KIRModule, ctx: KIRContext) throws
}
