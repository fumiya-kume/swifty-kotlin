import CompilerCore

/// Maps byte offsets within a file to the AST nodes that enclose them.
/// Used by hover and go-to-definition to find the entity under the cursor.
public struct PositionResolver {
    private let arena: ASTArena
    private let fileID: FileID

    public init(ast: ASTModule, fileID: FileID) {
        arena = ast.arena
        self.fileID = fileID
    }

    /// Returns the narrowest expression whose source range contains `offset`
    /// within this file, or `nil` when no expression matches.
    public func innermostExpr(at offset: Int) -> ExprID? {
        let exprs = arena.exprs
        var best: ExprID?
        var bestWidth = Int.max
        for index in exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = arena.exprRange(id), range.start.file == fileID else {
                continue
            }
            let start = range.start.offset
            let end = range.end.offset
            guard start <= offset, offset <= end else { continue }
            let width = end - start
            if width < bestWidth {
                bestWidth = width
                best = id
            }
        }
        return best
    }

    /// Returns the narrowest declaration whose source range contains `offset`
    /// within this file, or `nil` when no declaration matches.
    public func enclosingDecl(at offset: Int) -> DeclID? {
        let decls = arena.decls
        var best: DeclID?
        var bestWidth = Int.max
        for index in decls.indices {
            let id = DeclID(rawValue: Int32(index))
            guard let range = arena.declRange(id), range.start.file == fileID else {
                continue
            }
            let start = range.start.offset
            let end = range.end.offset
            guard start <= offset, offset <= end else { continue }
            let width = end - start
            if width < bestWidth {
                bestWidth = width
                best = id
            }
        }
        return best
    }
}
