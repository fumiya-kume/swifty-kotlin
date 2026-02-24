import Foundation

public final class ASTArena: @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var decls: [Decl] = []
    public private(set) var exprs: [Expr] = []
    public private(set) var typeRefs: [TypeRef] = []
    /// Maps loop expression IDs (forExpr/whileExpr/doWhileExpr) to their user-defined label.
    public private(set) var loopLabels: [ExprID: InternedString] = [:]

    public init() {}

    public func appendDecl(_ decl: Decl) -> DeclID {
        lock.lock()
        defer { lock.unlock() }
        let id = Int32(decls.count)
        decls.append(decl)
        return DeclID(rawValue: id)
    }

    public func decl(_ id: DeclID) -> Decl? {
        let index = Int(id.rawValue)
        lock.lock()
        defer { lock.unlock() }
        guard decls.indices.contains(index) else { return nil }
        return decls[index]
    }

    public func declarations() -> [Decl] {
        lock.lock()
        defer { lock.unlock() }
        return decls
    }

    /// The number of declarations in the arena (thread-safe).
    public var declCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return decls.count
    }

    public func appendExpr(_ expr: Expr) -> ExprID {
        lock.lock()
        defer { lock.unlock() }
        let id = ExprID(rawValue: Int32(exprs.count))
        exprs.append(expr)
        return id
    }

    public func expr(_ id: ExprID) -> Expr? {
        let index = Int(id.rawValue)
        lock.lock()
        defer { lock.unlock() }
        guard exprs.indices.contains(index) else { return nil }
        return exprs[index]
    }

    public func exprRange(_ id: ExprID) -> SourceRange? {
        guard let expr = expr(id) else {
            return nil
        }
        switch expr {
        case .intLiteral(_, let range),
             .longLiteral(_, let range),
             .floatLiteral(_, let range),
             .doubleLiteral(_, let range),
             .charLiteral(_, let range),
             .boolLiteral(_, let range),
             .stringLiteral(_, let range),
             .nameRef(_, let range),
             .forExpr(_, _, _, let range),
             .whileExpr(_, _, let range),
             .doWhileExpr(_, _, let range),
             .breakExpr(_, let range),
             .continueExpr(_, let range),
             .localDecl(_, _, _, _, let range),
             .localAssign(_, _, let range),
             .indexedAssign(_, _, _, let range),
             .call(_, _, _, let range),
             .memberCall(_, _, _, _, let range),
             .indexedAccess(_, _, let range),
             .indexedCompoundAssign(_, _, _, _, let range),
             .binary(_, _, _, let range),
             .whenExpr(_, _, _, let range),
             .returnExpr(_, let range),
             .ifExpr(_, _, _, let range),
             .tryExpr(_, _, _, let range),
             .unaryExpr(_, _, let range),
             .isCheck(_, _, _, let range),
             .asCast(_, _, _, let range),
             .nullAssert(_, let range),
             .safeMemberCall(_, _, _, _, let range),
             .compoundAssign(_, _, _, let range),
             .stringTemplate(_, let range),
             .throwExpr(_, let range),
             .lambdaLiteral(_, _, let range),
             .objectLiteral(_, let range),
             .callableRef(_, _, let range),
             .localFunDecl(_, _, _, _, let range),
             .blockExpr(_, _, let range),
             .superRef(let range),
             .thisRef(_, let range),
             .inExpr(_, _, let range),
             .notInExpr(_, _, let range):
            return range
        }
    }

    public func setLoopLabel(_ label: InternedString, for exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        loopLabels[exprID] = label
    }

    public func loopLabel(for exprID: ExprID) -> InternedString? {
        lock.lock()
        defer { lock.unlock() }
        return loopLabels[exprID]
    }

    public func appendTypeRef(_ typeRef: TypeRef) -> TypeRefID {
        lock.lock()
        defer { lock.unlock() }
        let id = TypeRefID(rawValue: Int32(typeRefs.count))
        typeRefs.append(typeRef)
        return id
    }

    public func typeRef(_ id: TypeRefID) -> TypeRef? {
        let index = Int(id.rawValue)
        lock.lock()
        defer { lock.unlock() }
        guard typeRefs.indices.contains(index) else { return nil }
        return typeRefs[index]
    }
}

public final class ASTModule {
    public let files: [ASTFile]
    public let arena: ASTArena
    public let declarationCount: Int
    public let tokenCount: Int

    /// Files pre-sorted by fileID for stable iteration order.
    /// All callers that previously used `sortedFiles` now use this directly.
    public let sortedFiles: [ASTFile]

    public init(files: [ASTFile], arena: ASTArena, declarationCount: Int, tokenCount: Int) {
        self.files = files
        self.arena = arena
        self.declarationCount = declarationCount
        self.tokenCount = tokenCount
        self.sortedFiles = files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue })
    }

    public convenience init(declarationCount: Int, tokenCount: Int) {
        self.init(files: [], arena: ASTArena(), declarationCount: declarationCount, tokenCount: tokenCount)
    }
}
