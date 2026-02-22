import Foundation

public struct KIRDeclID: Hashable {
    public let rawValue: Int32

    public static let invalid = KIRDeclID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public struct KIRExprID: Hashable {
    public let rawValue: Int32

    public static let invalid = KIRExprID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public struct KIRTypeID: Hashable {
    public let rawValue: Int32

    public static let invalid = KIRTypeID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
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

public enum KIRBinaryOp: Equatable {
    case add
    case subtract
    case multiply
    case divide
    case modulo
    case equal
    case notEqual
    case lessThan
    case lessOrEqual
    case greaterThan
    case greaterOrEqual
    case logicalAnd
    case logicalOr
}

public enum KIRUnaryOp: Equatable {
    case not
    case unaryPlus
    case unaryMinus
}

public enum KIRExprKind: Equatable {
    case intLiteral(Int64)
    case longLiteral(Int64)
    case floatLiteral(Double)
    case doubleLiteral(Double)
    case charLiteral(UInt32)
    case boolLiteral(Bool)
    case stringLiteral(InternedString)
    case symbolRef(SymbolID)
    case temporary(Int32)
    case null
    case unit
}

public enum KIRInstruction: Equatable {
    case nop
    case beginBlock
    case endBlock
    case label(Int32)
    case jump(Int32)
    case jumpIfEqual(lhs: KIRExprID, rhs: KIRExprID, target: Int32)
    case constValue(result: KIRExprID, value: KIRExprKind)
    case binary(op: KIRBinaryOp, lhs: KIRExprID, rhs: KIRExprID, result: KIRExprID)
    case unary(op: KIRUnaryOp, operand: KIRExprID, result: KIRExprID)
    case nullAssert(operand: KIRExprID, result: KIRExprID)
    case select(condition: KIRExprID, thenValue: KIRExprID, elseValue: KIRExprID, result: KIRExprID)
    case call(symbol: SymbolID?, callee: InternedString, arguments: [KIRExprID], result: KIRExprID?, canThrow: Bool, thrownResult: KIRExprID?, isSuperCall: Bool = false)
    case jumpIfNotNull(value: KIRExprID, target: Int32)
    case copy(from: KIRExprID, to: KIRExprID)
    case rethrow(value: KIRExprID)
    case returnIfEqual(lhs: KIRExprID, rhs: KIRExprID)
    case returnUnit
    case returnValue(KIRExprID)
}

public struct KIRFunction {
    public let symbol: SymbolID
    public let name: InternedString
    public let params: [KIRParameter]
    public let returnType: TypeID
    public var body: [KIRInstruction]
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
    public let memberDecls: [KIRDeclID]

    public init(symbol: SymbolID, memberDecls: [KIRDeclID] = []) {
        self.symbol = symbol
        self.memberDecls = memberDecls
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
    public private(set) var expressions: [KIRExprKind] = []
    public private(set) var exprTypes: [KIRExprID: TypeID] = [:]

    public init() {}

    public func appendDecl(_ decl: KIRDecl) -> KIRDeclID {
        let id = KIRDeclID(rawValue: Int32(declarations.count))
        declarations.append(decl)
        return id
    }

    public func appendExpr(_ expr: KIRExprKind, type: TypeID? = nil) -> KIRExprID {
        let id = KIRExprID(rawValue: Int32(expressions.count))
        expressions.append(expr)
        if let type {
            exprTypes[id] = type
        }
        return id
    }

    public func decl(_ id: KIRDeclID) -> KIRDecl? {
        let index = Int(id.rawValue)
        guard index >= 0 && index < declarations.count else {
            return nil
        }
        return declarations[index]
    }

    public func expr(_ id: KIRExprID) -> KIRExprKind? {
        let index = Int(id.rawValue)
        guard index >= 0 && index < expressions.count else {
            return nil
        }
        return expressions[index]
    }

    public func setExprType(_ type: TypeID, for id: KIRExprID) {
        guard expr(id) != nil else {
            return
        }
        exprTypes[id] = type
    }

    public func exprType(_ id: KIRExprID) -> TypeID? {
        exprTypes[id]
    }

    public func transformFunctions(_ transform: (KIRFunction) -> KIRFunction) {
        for index in declarations.indices {
            guard case .function(let function) = declarations[index] else {
                continue
            }
            declarations[index] = .function(transform(function))
        }
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
                for instruction in function.body {
                    lines.append("  \(instructionDescription(instruction, interner: interner, arena: arena, symbols: symbols))")
                }
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

    private func instructionDescription(
        _ instruction: KIRInstruction,
        interner: StringInterner,
        arena: KIRArena,
        symbols: SymbolTable?
    ) -> String {
        switch instruction {
        case .nop:
            return "nop"
        case .beginBlock:
            return "beginBlock"
        case .endBlock:
            return "endBlock"
        case .label(let id):
            return "label L\(id)"
        case .jump(let target):
            return "jump L\(target)"
        case .jumpIfEqual(let lhs, let rhs, let target):
            return "jumpIfEqual r\(lhs.rawValue), r\(rhs.rawValue) -> L\(target)"
        case .constValue(let result, let value):
            return "const r\(result.rawValue)=\(value)"
        case .binary(let op, let lhs, let rhs, let result):
            return "binary \(op) r\(lhs.rawValue), r\(rhs.rawValue) -> r\(result.rawValue)"
        case .unary(let op, let operand, let result):
            return "unary \(op) r\(operand.rawValue) -> r\(result.rawValue)"
        case .nullAssert(let operand, let result):
            return "nullAssert r\(operand.rawValue) -> r\(result.rawValue)"
        case .select(let condition, let thenValue, let elseValue, let result):
            return "select r\(condition.rawValue) ? r\(thenValue.rawValue) : r\(elseValue.rawValue) -> r\(result.rawValue)"
        case .call(let symbol, let callee, let arguments, let result, let canThrow, let thrownResult, let isSuperCall):
            let calleeName = interner.resolve(callee)
            let args = arguments.map { "r\($0.rawValue)" }.joined(separator: ", ")
            let symbolLabel: String
            if let symbol, let sym = symbols?.symbol(symbol) {
                symbolLabel = interner.resolve(sym.name)
            } else {
                symbolLabel = "_"
            }
            let ret = result.map { "r\($0.rawValue)" } ?? "_"
            let thrownRet = thrownResult.map { "r\($0.rawValue)" } ?? "_"
            let superTag = isSuperCall ? " super=1" : ""
            return "call \(calleeName) symbol=\(symbolLabel) args=[\(args)] ret=\(ret) thrown=\(canThrow) thrownResult=\(thrownRet)\(superTag)"
        case .jumpIfNotNull(let value, let target):
            return "jumpIfNotNull r\(value.rawValue) -> L\(target)"
        case .copy(let from, let to):
            return "copy r\(from.rawValue) -> r\(to.rawValue)"
        case .rethrow(let value):
            return "rethrow r\(value.rawValue)"
        case .returnIfEqual(let lhs, let rhs):
            return "returnIfEqual r\(lhs.rawValue), r\(rhs.rawValue)"
        case .returnUnit:
            return "returnUnit"
        case .returnValue(let value):
            return "return r\(value.rawValue)"
        }
    }
}

public final class KIRContext {
    public let diagnostics: DiagnosticEngine
    public let options: CompilerOptions
    public let interner: StringInterner
    public let sema: SemaModule?

    public init(
        diagnostics: DiagnosticEngine,
        options: CompilerOptions,
        interner: StringInterner,
        sema: SemaModule? = nil
    ) {
        self.diagnostics = diagnostics
        self.options = options
        self.interner = interner
        self.sema = sema
    }
}

public protocol KIRPass {
    static var name: String { get }
    func run(module: KIRModule, ctx: KIRContext) throws
}
