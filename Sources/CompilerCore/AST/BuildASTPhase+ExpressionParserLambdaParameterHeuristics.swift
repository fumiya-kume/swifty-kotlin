import Foundation

extension BuildASTPhase.ExpressionParser {
    func isPotentialLambdaParameterList(_ tokens: [Token]) -> Bool {
        var depth = BuildASTPhase.BracketDepth()
        for token in tokens {
            if depth.isAtTopLevel {
                switch token.kind {
                case .keyword(.val), .keyword(.var), .keyword(.fun), .keyword(.return),
                     .keyword(.if), .keyword(.when), .keyword(.for), .keyword(.while),
                     .keyword(.do), .keyword(.try), .keyword(.throw),
                     .keyword(.class), .keyword(.object), .keyword(.interface):
                    return false
                case .symbol(.assign), .symbol(.plusAssign), .symbol(.minusAssign),
                     .symbol(.starAssign), .symbol(.slashAssign), .symbol(.percentAssign),
                     .symbol(.semicolon):
                    return false
                default:
                    break
                }
            }
            depth.track(token.kind)
        }
        return true
    }
}
