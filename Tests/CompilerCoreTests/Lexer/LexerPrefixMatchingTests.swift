@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LexerPrefixMatchingTests {
    @Test(arguments: [
        ("====", [Symbol.tripleEqual, .assign]),
        ("!===", [Symbol.notTripleEqual, .assign]),
        ("!!=", [Symbol.bangBang, .assign]),
        ("..<=..", [Symbol.dotDotLt, .assign, .dotDot]),
        ("???...", [Symbol.questionQuestion, .questionDot, .dotDot]),
        ("->--=-", [Symbol.arrow, .minusMinus, .assign, .minus]),
        (":::", [Symbol.doubleColon, .colon]),
        ("&", [Symbol.amp]),
        (".", [Symbol.dot]),
        ("?", [Symbol.question]),
    ])
    func adjacentSymbolsKeepLongestMatchAndByteRanges(source: String, expected: [Symbol]) {
        let diagnostics = DiagnosticEngine()
        let lexer = KotlinLexer(
            file: FileID(rawValue: 0), source: Data(source.utf8),
            interner: StringInterner(), diagnostics: diagnostics
        )
        let tokens = lexer.lexAll()
        #expect(tokens.map(\.kind) == expected.map { .symbol($0) } + [.eof])
        #expect(!diagnostics.hasError)
        var start = 0
        for (token, symbol) in zip(tokens, expected) {
            let end = start + symbol.rawValue.utf8.count
            #expect(token.range.start.offset == start)
            #expect(token.range.end.offset == end)
            #expect(token.leadingTrivia.isEmpty)
            #expect(token.trailingTrivia.isEmpty)
            start = end
        }
        #expect(tokens.last?.range.start.offset == source.utf8.count)
        #expect(tokens.last?.range.end.offset == source.utf8.count)
    }

    @Test
    func prefixComparisonHandlesUTF8AndEndOfInput() {
        let source = "xé🙂//"
        let lexer = KotlinLexer(
            file: FileID(rawValue: 0), source: Data(source.utf8),
            interner: StringInterner(), diagnostics: DiagnosticEngine()
        )
        #expect(lexer.starts(with: "é🙂", at: 1))
        #expect(!lexer.starts(with: "é🙂", at: 2))
        #expect(lexer.starts(with: "//", at: 7))
        #expect(!lexer.starts(with: "//", at: 8))
        #expect(!lexer.starts(with: "/", at: 9))
        #expect(lexer.starts(with: "", at: 9))
        #expect(!lexer.starts(with: "", at: 10))
        #expect(!lexer.starts(with: "x", at: -1))
    }
}
