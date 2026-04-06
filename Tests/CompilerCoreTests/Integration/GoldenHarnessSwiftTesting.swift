#if canImport(Testing)
import Foundation
import GoldenHarnessSupport
import Testing

private enum GoldenHarnessStaticCases {
    static let lexer = GoldenHarness.loadCasesOrCrash(suiteName: "Lexer")
    static let parser = GoldenHarness.loadCasesOrCrash(suiteName: "Parser")
    static let sema = GoldenHarness.loadCasesOrCrash(suiteName: "Sema")
    static let diagnostics = GoldenHarness.loadCasesOrCrash(suiteName: "Diagnostics")
}

@Suite("Golden.Lexer")
struct GoldenLexerGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.lexer)
    func matchesGolden(caseFile: GoldenHarnessCase) throws {
        let actual = try GoldenHarness.renderInSubprocess(suiteName: "Lexer", sourcePath: caseFile.sourcePath)
        if try GoldenHarness.persistIfUpdating(sourcePath: caseFile.sourcePath, actual: actual) {
            return
        }
        let expected = try GoldenHarness.loadExpectedGolden(sourcePath: caseFile.sourcePath)
        let basename = caseFile.basename
        #expect(actual == expected, Comment(rawValue: "Golden mismatch: \(basename)"))
    }
}

@Suite("Golden.Parser")
struct GoldenParserGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.parser)
    func matchesGolden(caseFile: GoldenHarnessCase) throws {
        let actual = try GoldenHarness.renderInSubprocess(suiteName: "Parser", sourcePath: caseFile.sourcePath)
        if try GoldenHarness.persistIfUpdating(sourcePath: caseFile.sourcePath, actual: actual) {
            return
        }
        let expected = try GoldenHarness.loadExpectedGolden(sourcePath: caseFile.sourcePath)
        let basename = caseFile.basename
        #expect(actual == expected, Comment(rawValue: "Golden mismatch: \(basename)"))
    }
}

@Suite("Golden.Sema")
struct GoldenSemaGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.sema)
    func matchesGolden(caseFile: GoldenHarnessCase) throws {
        let actual = try GoldenHarness.renderInSubprocess(suiteName: "Sema", sourcePath: caseFile.sourcePath)
        if try GoldenHarness.persistIfUpdating(sourcePath: caseFile.sourcePath, actual: actual) {
            return
        }
        let expected = try GoldenHarness.loadExpectedGolden(sourcePath: caseFile.sourcePath)
        let basename = caseFile.basename
        #expect(actual == expected, Comment(rawValue: "Golden mismatch: \(basename)"))
    }
}

@Suite("Golden.Diagnostics")
struct GoldenDiagnosticsGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.diagnostics)
    func matchesGolden(caseFile: GoldenHarnessCase) throws {
        let actual = try GoldenHarness.renderInSubprocess(suiteName: "Diagnostics", sourcePath: caseFile.sourcePath)
        if try GoldenHarness.persistIfUpdating(sourcePath: caseFile.sourcePath, actual: actual) {
            return
        }
        let expected = try GoldenHarness.loadExpectedGolden(sourcePath: caseFile.sourcePath)
        let basename = caseFile.basename
        #expect(actual == expected, Comment(rawValue: "Golden mismatch: \(basename)"))
    }
}
#endif
