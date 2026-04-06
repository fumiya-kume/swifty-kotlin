@testable import CompilerCore
import Foundation

enum GoldenHarnessSyntaxFormat {
    static func renderRange(_ range: SourceRange) -> String {
        "f\(range.start.file.rawValue):\(range.start.offset)..\(range.end.offset)"
    }

    static func renderTokenKind(_ kind: TokenKind, interner: StringInterner) -> String {
        switch kind {
        case let .identifier(id):
            "identifier(\(interner.resolve(id)))"
        case let .backtickedIdentifier(id):
            "backtickedIdentifier(\(interner.resolve(id)))"
        case let .keyword(keyword):
            "keyword(\(keyword.rawValue))"
        case let .softKeyword(keyword):
            "softKeyword(\(keyword.rawValue))"
        case let .intLiteral(text):
            "intLiteral(\(text))"
        case let .longLiteral(text):
            "longLiteral(\(text))"
        case let .uintLiteral(text):
            "uintLiteral(\(text))"
        case let .ulongLiteral(text):
            "ulongLiteral(\(text))"
        case let .floatLiteral(text):
            "floatLiteral(\(text))"
        case let .doubleLiteral(text):
            "doubleLiteral(\(text))"
        case let .charLiteral(value):
            "charLiteral(\(value))"
        case let .stringSegment(id):
            "stringSegment(\(interner.resolve(id)))"
        case .stringQuote:
            "stringQuote"
        case .rawStringQuote:
            "rawStringQuote"
        case let .multiDollarStringQuote(dollarCount):
            "multiDollarStringQuote(\(dollarCount))"
        case let .multiDollarRawStringQuote(dollarCount):
            "multiDollarRawStringQuote(\(dollarCount))"
        case .templateExprStart:
            "templateExprStart"
        case .templateExprEnd:
            "templateExprEnd"
        case .templateSimpleNameStart:
            "templateSimpleNameStart"
        case let .symbol(symbol):
            "symbol(\(symbol.rawValue))"
        case .eof:
            "eof"
        case let .missing(expected):
            "missing(\(renderTokenKind(expected, interner: interner)))"
        }
    }

    static func dumpSyntaxNode(
        id: NodeID,
        syntax: SyntaxArena,
        interner: StringInterner,
        indent: String,
        lines: inout [String]
    ) {
        let node = syntax.node(id)
        lines.append("\(indent)node \(node.kind) \(renderRange(node.range))")
        for child in syntax.children(of: id) {
            switch child {
            case let .node(childID):
                dumpSyntaxNode(
                    id: childID,
                    syntax: syntax,
                    interner: interner,
                    indent: indent + "  ",
                    lines: &lines
                )
            case let .token(tokenID):
                let tokenIndex = Int(tokenID.rawValue)
                guard tokenIndex >= 0, tokenIndex < syntax.tokens.count else {
                    lines.append("\(indent)  tok <invalid>")
                    continue
                }
                let token = syntax.tokens[tokenIndex]
                lines.append("\(indent)  tok \(renderTokenKind(token.kind, interner: interner)) \(renderRange(token.range))")
            }
        }
    }
}
