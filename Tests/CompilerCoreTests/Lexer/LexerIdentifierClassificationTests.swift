@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LexerIdentifierClassificationTests {
    @Test
    func repeatedNamesKeepTheirClassificationTriviaAndRanges() {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let tokens = KotlinLexer(
            file: FileID(rawValue: 0), source: Data("when by item\n\twhen by item".utf8),
            interner: interner, diagnostics: diagnostics
        ).lexAll()
        let expectedKinds: [TokenKind] = [.keyword(.when), .softKeyword(.by), .identifier(interner.intern("item"))]
        #expect(tokens.map(\.kind) == expectedKinds + expectedKinds + [.eof])
        #expect(tokens.map { $0.range.start.offset } == [0, 5, 8, 14, 19, 22, 26])
        #expect(tokens.map { $0.range.end.offset } == [4, 7, 12, 18, 21, 26, 26])
        #expect(tokens.map(\.leadingTrivia) == [[], [.spaces(1)], [.spaces(1)], [.newline, .tabs(1)], [.spaces(1)], [.spaces(1)], []])
        #expect(!diagnostics.hasError)
    }

    @Test
    func keywordSpellingRemainsAnIdentifierInBackticksAndSimpleTemplates() {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let tokens = KotlinLexer(
            file: FileID(rawValue: 0), source: Data("when by `when` `by` \"$when$by\" when by".utf8),
            interner: interner, diagnostics: diagnostics
        ).lexAll()
        let whenID = interner.intern("when")
        let byID = interner.intern("by")
        #expect(tokens.map(\.kind) == [
            .keyword(.when), .softKeyword(.by),
            .backtickedIdentifier(whenID), .backtickedIdentifier(byID),
            .stringQuote, .templateSimpleNameStart, .identifier(whenID),
            .templateSimpleNameStart, .identifier(byID), .stringQuote,
            .keyword(.when), .softKeyword(.by), .eof,
        ])
        #expect(!diagnostics.hasError)
    }

    @Test
    func repeatedIdentifiersUseTheirOwnInterner() {
        let firstInterner = StringInterner()
        let secondInterner = StringInterner()
        secondInterner.preload(["seed", "another"])
        var identifiers: [InternedString] = []
        for interner in [firstInterner, secondInterner] {
            let tokens = KotlinLexer(
                file: FileID(rawValue: 0), source: Data("item item".utf8),
                interner: interner, diagnostics: DiagnosticEngine()
            ).lexAll()
            let expected = interner.intern("item")
            #expect(tokens.map(\.kind) == [.identifier(expected), .identifier(expected), .eof])
            #expect(interner.resolve(expected) == "item")
            identifiers.append(expected)
        }
        #expect(identifiers[0] != identifiers[1])
    }
}
