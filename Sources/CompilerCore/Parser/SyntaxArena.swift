public enum SyntaxKind: Equatable {
    case kotlinFile
    case script
    case packageHeader
    case importList
    case importHeader
    case classDecl
    case objectDecl
    case interfaceDecl
    case funDecl
    case propertyDecl
    case propertyAccessor
    case typeAliasDecl
    case enumEntry
    case constructorDecl
    case statement
    case block
    case loopStmt
    case tryExpr
    case ifExpr
    case whenExpr
    case whenEntry
    case whenConditionList
    case whenCondition
    case callExpr
    case binaryExpr
    case unaryExpr
    case lambdaLiteral
    case objectLiteral
    case stringTemplate
    case callableRef
    case typeRef
    case nullableType
    case functionType
    case suspendFunctionType
    case typeArgs
    case typeProjection
}

public enum SyntaxChild: Equatable {
    case node(NodeID)
    case token(TokenID)
}

public struct SyntaxNode: Equatable {
    public let kind: SyntaxKind
    public let range: SourceRange
    public let firstChildIndex: Int32
    public let childCount: Int16
}

/// Concurrency model:
/// single-owner lifecycle (`KotlinParser` build, then one AST build task reads it).
public final class SyntaxArena: @unchecked Sendable {
    public private(set) var nodes: [SyntaxNode] = []
    public private(set) var children: [SyntaxChild] = []
    public private(set) var tokens: [Token] = []

    public init() {}

    public func appendToken(_ token: Token) -> TokenID {
        let id = Int32(tokens.count)
        tokens.append(token)
        return TokenID(rawValue: id)
    }

    public func appendNode(kind: SyntaxKind, range: SourceRange, _ children: [SyntaxChild]) -> NodeID {
        let start = Int32(self.children.count)
        self.children.append(contentsOf: children)
        let childCount = Int16(children.count)
        let nodeID = Int32(nodes.count)
        let node = SyntaxNode(
            kind: kind,
            range: range,
            firstChildIndex: start,
            childCount: childCount
        )
        nodes.append(node)
        return NodeID(rawValue: nodeID)
    }

    public func node(_ id: NodeID) -> SyntaxNode {
        let index = Int(id.rawValue)
        if index < 0 || index >= nodes.count {
            let invalidRange = SourceRange(
                start: SourceLocation(file: FileID.invalid, offset: 0),
                end: SourceLocation(file: FileID.invalid, offset: 0)
            )
            return SyntaxNode(kind: .statement, range: invalidRange, firstChildIndex: 0, childCount: 0)
        }
        return nodes[index]
    }

    public func token(_ id: TokenID) -> Token? {
        let index = Int(id.rawValue)
        guard index >= 0, index < tokens.count else { return nil }
        return tokens[index]
    }

    public func children(of id: NodeID) -> ArraySlice<SyntaxChild> {
        let node = node(id)
        if node.firstChildIndex < 0 || node.childCount < 0 {
            return []
        }
        let start = Int(node.firstChildIndex)
        let end = start + Int(node.childCount)
        if start >= children.count {
            return []
        }
        let safeEnd = min(end, children.count)
        return children[start ..< safeEnd]
    }
}
