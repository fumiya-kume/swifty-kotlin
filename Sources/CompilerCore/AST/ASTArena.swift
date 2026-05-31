import Foundation

public struct ASTArenaSnapshot: Codable {
    public let declarations: [Decl]
    public let expressions: [Expr]
    public let typeRefs: [TypeRef]
    public let loopLabels: [ExprID: InternedString]
    public let whenSubjectVarNames: [ExprID: InternedString]

    public init(
        declarations: [Decl],
        expressions: [Expr],
        typeRefs: [TypeRef],
        loopLabels: [ExprID: InternedString],
        whenSubjectVarNames: [ExprID: InternedString]
    ) {
        self.declarations = declarations
        self.expressions = expressions
        self.typeRefs = typeRefs
        self.loopLabels = loopLabels
        self.whenSubjectVarNames = whenSubjectVarNames
    }
}

public final class ASTArena: @unchecked Sendable {
    private let lock = NSLock()
    private var _decls: [Decl] = []
    private var _exprs: [Expr] = []
    private var _typeRefs: [TypeRef] = []
    /// Maps loop expression IDs (forExpr/whileExpr/doWhileExpr) to their user-defined label.
    private var _loopLabels: [ExprID: InternedString] = [:]
    /// Maps whenExpr IDs to their subject variable name for `when (val x = expr)` syntax.
    private var _whenSubjectVarNames: [ExprID: InternedString] = [:]

    public var decls: [Decl] {
        lock.lock()
        defer { lock.unlock() }
        return _decls
    }

    public var exprs: [Expr] {
        lock.lock()
        defer { lock.unlock() }
        return _exprs
    }

    public var typeRefs: [TypeRef] {
        lock.lock()
        defer { lock.unlock() }
        return _typeRefs
    }

    public var loopLabels: [ExprID: InternedString] {
        lock.lock()
        defer { lock.unlock() }
        return _loopLabels
    }

    public init() {}

    public init(snapshot: ASTArenaSnapshot) {
        _decls = snapshot.declarations
        _exprs = snapshot.expressions
        _typeRefs = snapshot.typeRefs
        _loopLabels = snapshot.loopLabels
        _whenSubjectVarNames = snapshot.whenSubjectVarNames
    }

    public func snapshot() -> ASTArenaSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return ASTArenaSnapshot(
            declarations: _decls,
            expressions: _exprs,
            typeRefs: _typeRefs,
            loopLabels: _loopLabels,
            whenSubjectVarNames: _whenSubjectVarNames
        )
    }

    public func appendDecl(_ decl: Decl) -> DeclID {
        lock.lock()
        defer { lock.unlock() }
        let id = Int32(_decls.count)
        _decls.append(decl)
        return DeclID(rawValue: id)
    }

    public func decl(_ id: DeclID) -> Decl? {
        let index = Int(id.rawValue)
        lock.lock()
        defer { lock.unlock() }
        guard _decls.indices.contains(index) else { return nil }
        return _decls[index]
    }

    public func declarations() -> [Decl] {
        lock.lock()
        defer { lock.unlock() }
        return _decls
    }

    /// The number of declarations in the arena (thread-safe).
    public var declCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _decls.count
    }

    public func appendExpr(_ expr: Expr) -> ExprID {
        lock.lock()
        defer { lock.unlock() }
        let id = ExprID(rawValue: Int32(_exprs.count))
        _exprs.append(expr)
        return id
    }

    public func expr(_ id: ExprID) -> Expr? {
        let index = Int(id.rawValue)
        lock.lock()
        defer { lock.unlock() }
        guard _exprs.indices.contains(index) else { return nil }
        return _exprs[index]
    }

    public func exprRange(_ id: ExprID) -> SourceRange? {
        guard let expr = expr(id) else {
            return nil
        }
        switch expr {
        case let .intLiteral(_, range),
             let .longLiteral(_, range),
             let .uintLiteral(_, range),
             let .ulongLiteral(_, range),
             let .floatLiteral(_, range),
             let .doubleLiteral(_, range),
             let .charLiteral(_, range),
             let .boolLiteral(_, range),
             let .stringLiteral(_, range),
             let .nameRef(_, range),
             let .forExpr(_, _, _, _, range),
             let .whileExpr(_, _, _, range),
             let .doWhileExpr(_, _, _, range),
             let .breakExpr(_, range),
             let .continueExpr(_, range),
             let .localDecl(_, _, _, _, _, range),
             let .localAssign(_, _, range),
             let .memberAssign(_, _, _, range),
             let .indexedAssign(_, _, _, range),
             let .call(_, _, _, range),
             let .memberCall(_, _, _, _, range),
             let .indexedAccess(_, _, range),
             let .indexedCompoundAssign(_, _, _, _, range),
             let .binary(_, _, _, range),
             let .whenExpr(_, _, _, range),
             let .returnExpr(_, _, range),
             let .ifExpr(_, _, _, range),
             let .tryExpr(_, _, _, range),
             let .unaryExpr(_, _, range),
             let .isCheck(_, _, _, range),
             let .asCast(_, _, _, range),
             let .nullAssert(_, range),
             let .safeMemberCall(_, _, _, _, range),
             let .compoundAssign(_, _, _, range),
             let .stringTemplate(_, range),
             let .throwExpr(_, range),
             let .lambdaLiteral(_, _, _, range),
             let .objectLiteral(_, _, range),
             let .callableRef(_, _, range),
             let .localFunDecl(_, _, _, _, _, range),
             let .blockExpr(_, _, range),
             let .superRef(_, range),
             let .thisRef(_, range),
             let .inExpr(_, _, range),
             let .notInExpr(_, _, range),
             let .destructuringDecl(_, _, _, range),
             let .forDestructuringExpr(_, _, _, range):
            return range
        }
    }

    /// Returns the source range of a declaration, mirroring `exprRange` for the
    /// expression arena. Used by IDE features to locate the declaration that
    /// encloses a cursor position.
    public func declRange(_ id: DeclID) -> SourceRange? {
        guard let decl = decl(id) else {
            return nil
        }
        switch decl {
        case let .classDecl(d): return d.range
        case let .interfaceDecl(d): return d.range
        case let .funDecl(d): return d.range
        case let .propertyDecl(d): return d.range
        case let .typeAliasDecl(d): return d.range
        case let .objectDecl(d): return d.range
        case let .enumEntryDecl(d): return d.range
        }
    }

    public func setLoopLabel(_ label: InternedString, for exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _loopLabels[exprID] = label
    }

    public func loopLabel(for exprID: ExprID) -> InternedString? {
        lock.lock()
        defer { lock.unlock() }
        return _loopLabels[exprID]
    }

    public func setWhenSubjectVarName(_ name: InternedString, for exprID: ExprID) {
        lock.lock()
        defer { lock.unlock() }
        _whenSubjectVarNames[exprID] = name
    }

    public func whenSubjectVarName(for exprID: ExprID) -> InternedString? {
        lock.lock()
        defer { lock.unlock() }
        return _whenSubjectVarNames[exprID]
    }

    public func appendTypeRef(_ typeRef: TypeRef) -> TypeRefID {
        lock.lock()
        defer { lock.unlock() }
        let id = TypeRefID(rawValue: Int32(_typeRefs.count))
        _typeRefs.append(typeRef)
        return id
    }

    public func typeRef(_ id: TypeRefID) -> TypeRef? {
        let index = Int(id.rawValue)
        lock.lock()
        defer { lock.unlock() }
        guard _typeRefs.indices.contains(index) else { return nil }
        return _typeRefs[index]
    }
}

public final class ASTModule {
    public let files: [ASTFile]
    public let arena: ASTArena
    public let declarationCount: Int
    public let tokenCount: Int
    public let activeDeclsByFileRawID: [Int32: [DeclID]]

    /// Files pre-sorted by fileID for stable iteration order.
    /// All callers that previously used `sortedFiles` now use this directly.
    public let sortedFiles: [ASTFile]

    public init(
        files: [ASTFile],
        arena: ASTArena,
        declarationCount: Int,
        tokenCount: Int,
        activeDeclsByFileRawID: [Int32: [DeclID]] = [:]
    ) {
        self.files = files
        self.arena = arena
        self.declarationCount = declarationCount
        self.tokenCount = tokenCount
        self.activeDeclsByFileRawID = activeDeclsByFileRawID
        sortedFiles = files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue })
    }

    public var activeDeclarationIDs: Set<DeclID> {
        let activeDecls = activeDeclsByFileRawID.values.flatMap { $0 }
        if !activeDecls.isEmpty {
            return Set(activeDecls)
        }
        return Set((0 ..< arena.declCount).map { DeclID(rawValue: Int32($0)) })
    }

    public convenience init(declarationCount: Int, tokenCount: Int) {
        self.init(files: [], arena: ASTArena(), declarationCount: declarationCount, tokenCount: tokenCount)
    }
}
