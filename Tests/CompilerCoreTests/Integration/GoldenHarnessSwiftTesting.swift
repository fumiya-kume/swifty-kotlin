#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

private enum GoldenHarnessStaticCases {
    static let lexer: [GoldenHarnessCaseFile] = loadCasesOrCrash(suite: .lexer)
    static let parser: [GoldenHarnessCaseFile] = loadCasesOrCrash(suite: .parser)
    static let sema: [GoldenHarnessCaseFile] = loadCasesOrCrash(suite: .sema)
    static let diagnostics: [GoldenHarnessCaseFile] = loadCasesOrCrash(suite: .diagnostics)

    private static func loadCasesOrCrash(suite: GoldenHarnessGoldenSuite) -> [GoldenHarnessCaseFile] {
        do {
            return try GoldenHarnessCaseDiscovery.loadCases(suite: suite)
        } catch {
            preconditionFailure("GoldenHarness case discovery failed for \(suite.rawValue): \(error)")
        }
    }
}

@MainActor
@Suite("Golden.Lexer", .serialized)
struct GoldenLexerGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.lexer)
    func matchesGolden(caseFile: GoldenHarnessCaseFile) throws {
        let actual = try GoldenHarnessDump.dumpLexer(sourcePath: caseFile.sourcePath)
        if try GoldenHarnessGoldenFileIO.persistIfUpdating(caseFile: caseFile, actual: actual) {
            return
        }
        let expected = try GoldenHarnessGoldenFileIO.loadExpectedGolden(caseFile: caseFile)
        let basename = caseFile.basename
        #expect(actual == expected, Comment(rawValue: "Golden mismatch: \(basename)"))
    }
}

@MainActor
@Suite("Golden.Parser", .serialized)
struct GoldenParserGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.parser)
    func matchesGolden(caseFile: GoldenHarnessCaseFile) throws {
        let actual = try GoldenHarnessDump.dumpParser(sourcePath: caseFile.sourcePath)
        if try GoldenHarnessGoldenFileIO.persistIfUpdating(caseFile: caseFile, actual: actual) {
            return
        }
        let expected = try GoldenHarnessGoldenFileIO.loadExpectedGolden(caseFile: caseFile)
        let basename = caseFile.basename
        #expect(actual == expected, Comment(rawValue: "Golden mismatch: \(basename)"))
    }
}

@MainActor
@Suite("Golden.Sema", .serialized)
struct GoldenSemaGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.sema)
    func matchesGolden(caseFile: GoldenHarnessCaseFile) throws {
        let actual = try GoldenHarnessDump.dumpSema(sourcePath: caseFile.sourcePath)
        if try GoldenHarnessGoldenFileIO.persistIfUpdating(caseFile: caseFile, actual: actual) {
            return
        }
        let expected = try GoldenHarnessGoldenFileIO.loadExpectedGolden(caseFile: caseFile)
        let basename = caseFile.basename
        #expect(actual == expected, Comment(rawValue: "Golden mismatch: \(basename)"))
    }
}

@MainActor
@Suite("Golden.Diagnostics", .serialized)
struct GoldenDiagnosticsGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.diagnostics)
    func matchesGolden(caseFile: GoldenHarnessCaseFile) throws {
        let actual = try GoldenHarnessDump.dumpDiagnostics(sourcePath: caseFile.sourcePath)
        if try GoldenHarnessGoldenFileIO.persistIfUpdating(caseFile: caseFile, actual: actual) {
            return
        }
        let expected = try GoldenHarnessGoldenFileIO.loadExpectedGolden(caseFile: caseFile)
        let basename = caseFile.basename
        #expect(actual == expected, Comment(rawValue: "Golden mismatch: \(basename)"))
    }
}
#endif
