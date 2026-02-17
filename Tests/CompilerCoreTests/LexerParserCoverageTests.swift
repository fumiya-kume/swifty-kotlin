import Foundation
import XCTest
@testable import CompilerCore

final class LexerParserCoverageTests: XCTestCase {
    func testLexerConsumesTriviaIdentifiersAndAllSymbols() {
        let source = """
        #!/usr/bin/env kotlin
        // line comment
        /* outer /* nested */ done */
        class `hello world` value by get set field receiver param setparam delegate file where init constructor out when
        && || == != <= >= += -= *= /= %= ++ -- ..< ?? ?. ?: ? !! :: => -> .. + - * / % ! = < > . , ; : ( ) [ ] { } @ #
        """

        let result = lex(source)
        let symbols = Set(result.tokens.compactMap { token -> Symbol? in
            if case .symbol(let symbol) = token.kind {
                return symbol
            }
            return nil
        })

        let expected: Set<Symbol> = [
            .ampAmp, .barBar, .equalEqual, .bangEqual, .lessOrEqual, .greaterOrEqual,
            .plusAssign, .minusAssign, .starAssign, .slashAssign, .percentAssign,
            .plusPlus, .minusMinus, .dotDotLt, .questionQuestion, .questionDot, .questionColon,
            .question, .bangBang, .doubleColon, .fatArrow, .arrow, .dotDot,
            .plus, .minus, .star, .slash, .percent, .bang, .assign,
            .lessThan, .greaterThan, .dot, .comma, .semicolon, .colon,
            .lParen, .rParen, .lBracket, .rBracket, .lBrace, .rBrace, .at, .hash
        ]
        XCTAssertEqual(symbols, expected)

        XCTAssertTrue(result.tokens.contains { token in
            if case .backtickedIdentifier = token.kind { return true }
            return false
        })

        XCTAssertTrue(result.tokens.contains { token in
            if case .softKeyword(.where) = token.kind { return true }
            return false
        })

        XCTAssertFalse(result.diagnostics.hasError)
        XCTAssertTrue(result.tokens.first?.leadingTrivia.contains { piece in
            if case .shebang = piece { return true }
            return false
        } ?? false)
    }

    func testLexerStringTemplateAndEscapeDiagnostics() {
        let source = """
        val a = \"ok\\n\\t\\r\\\"\\'\\\\\\$\"
        val b = \"value ${1 + 2} $name\"
        val c = \"\"\"raw ${name} block\"\"\"
        val d = \"bad\\q\"
        val e = \"bad unicode \\u{110000}\"
        val f = \"unterminated
        """

        let result = lex(source)
        let kinds = result.tokens.map(\.kind)

        XCTAssertTrue(kinds.contains(.stringQuote))
        XCTAssertTrue(kinds.contains(.rawStringQuote))
        XCTAssertTrue(kinds.contains(.templateExprStart))
        XCTAssertTrue(kinds.contains(.templateExprEnd))
        XCTAssertTrue(kinds.contains(.templateSimpleNameStart))
        XCTAssertTrue(kinds.contains { kind in
            if case .stringSegment = kind { return true }
            return false
        })

        let codes = Set(result.diagnostics.diagnostics.map(\.code))
        XCTAssertTrue(codes.contains("KSWIFTK-LEX-0002"))
        XCTAssertTrue(codes.contains("KSWIFTK-LEX-0003"))
        XCTAssertFalse(codes.isEmpty)
    }

    func testLexerNumericAndCharLiteralsCoverErrorAndSuffixPaths() {
        let source = """
        0x1F 0X 0b101 0b 0o77 0o
        1_ 1.0 1. 1e 1e+2 10L 11f 12D
        'a' '\\n' '\\u0041' '\\u{1F600}' '\\q' 'x
        """

        let result = lex(source)

        XCTAssertTrue(result.tokens.contains { token in
            if case .intLiteral("0x1F") = token.kind { return true }
            return false
        })
        XCTAssertTrue(result.tokens.contains { token in
            if case .intLiteral("0b101") = token.kind { return true }
            return false
        })
        XCTAssertTrue(result.tokens.contains { token in
            if case .longLiteral("10L") = token.kind { return true }
            return false
        })
        XCTAssertTrue(result.tokens.contains { token in
            if case .floatLiteral("11f") = token.kind { return true }
            return false
        })
        XCTAssertTrue(result.tokens.contains { token in
            if case .doubleLiteral("12D") = token.kind { return true }
            return false
        })
        XCTAssertTrue(result.tokens.contains { token in
            if case .charLiteral(97) = token.kind { return true }
            return false
        })

        let codeCounts = Dictionary(grouping: result.diagnostics.diagnostics, by: \.code).mapValues(\.count)
        XCTAssertTrue((codeCounts["KSWIFTK-LEX-0002"] ?? 0) >= 1)
        XCTAssertTrue((codeCounts["KSWIFTK-LEX-0003"] ?? 0) >= 1)
        XCTAssertTrue((codeCounts["KSWIFTK-LEX-0006"] ?? 0) >= 1)
    }

    func testParserParsesDeclarationsTypeArgsAndEmitsWarningsForBrokenInput() {
        let source = """
        package demo.pkg
        import kotlin.collections.*

        public inline class Box<T>(value: T)
        companion object C
        interface I
        object O
        typealias Alias = Int
        enum class E { A, B, C }
        fun <T> id(x: T) = x
        fun broken(
        fun ()
        package
        """

        let parsed = parse(source)
        let arena = parsed.arena
        let rootChildren = arena.children(of: parsed.root)
        XCTAssertFalse(rootChildren.isEmpty)

        let kinds = Set(arena.nodes.map(\.kind))
        XCTAssertTrue(kinds.contains(.packageHeader))
        XCTAssertTrue(kinds.contains(.importHeader))
        XCTAssertTrue(kinds.contains(.classDecl))
        XCTAssertTrue(kinds.contains(.objectDecl))
        XCTAssertTrue(kinds.contains(.funDecl))
        XCTAssertTrue(kinds.contains(.statement))
        XCTAssertTrue(kinds.contains(.typeArgs) || kinds.contains(.enumEntry))

        let warningCodes = Set(parsed.diagnostics.diagnostics.map(\.code))
        XCTAssertTrue(warningCodes.contains("KSWIFTK-PARSE-0002"))
        XCTAssertFalse(warningCodes.isEmpty)

        let parserForTypeArgs = KotlinParser(tokens: parsed.tokens, interner: parsed.interner, diagnostics: DiagnosticEngine())
        _ = parserForTypeArgs.parseFile()
        let trailingToken = parsed.tokens.first(where: { token in
            if case .keyword(.class) = token.kind { return true }
            return false
        }) ?? makeToken(kind: .keyword(.class))
        _ = parserForTypeArgs.canStartTypeArguments(after: trailingToken)
        _ = parserForTypeArgs.canStartTypeArguments(after: NodeID(rawValue: -1))
    }

    func testLexerTemplateExpressionCoversNestedInvalidAndUnterminatedPaths() {
        let source = """
        val a = "${{1 + 2}}"
        val b = "${'a'}"
        val c = "${"inner"}"
        val d = "${\"\"\"raw\"\"\"}"
        val e = "${${1}}"
        val f = "${~}"
        val g = "${1 + "
        """

        let result = lex(source)
        let templateStarts = result.tokens.filter { $0.kind == .templateExprStart }
        let templateEnds = result.tokens.filter { $0.kind == .templateExprEnd }
        XCTAssertGreaterThanOrEqual(templateStarts.count, 6)
        XCTAssertGreaterThanOrEqual(templateEnds.count, 4)

        let codes = Set(result.diagnostics.diagnostics.map(\.code))
        XCTAssertTrue(codes.contains("KSWIFTK-LEX-0001"))
        XCTAssertTrue(codes.contains("KSWIFTK-LEX-0002"))
    }

    func testParserCanStartTypeArgumentsLookaheadVariants() {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let anchor = makeToken(kind: .keyword(.fun))

        let parserA = KotlinParser(
            tokens: [
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .symbol(.lParen))
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        XCTAssertTrue(parserA.canStartTypeArguments(after: anchor))

        let parserB = KotlinParser(
            tokens: [
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .keyword(.in)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.comma)),
                makeToken(kind: .softKeyword(.out)),
                makeToken(kind: .identifier(interner.intern("R"))),
                makeToken(kind: .symbol(.comma)),
                makeToken(kind: .symbol(.star)),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .symbol(.colon))
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        XCTAssertTrue(parserB.canStartTypeArguments(after: anchor))

        let parserB2 = KotlinParser(
            tokens: [
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .keyword(.in)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.comma)),
                makeToken(kind: .softKeyword(.out)),
                makeToken(kind: .identifier(interner.intern("R"))),
                makeToken(kind: .symbol(.comma)),
                makeToken(kind: .symbol(.star)),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .symbol(.colon))
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        XCTAssertFalse(parserB2.canStartTypeArguments(after: anchor))

        let parserC = KotlinParser(
            tokens: [
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .symbol(.lParen))
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        XCTAssertFalse(parserC.canStartTypeArguments(after: anchor))

        let parserD = KotlinParser(
            tokens: [
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .symbol(.dot)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .symbol(.lParen))
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        XCTAssertFalse(parserD.canStartTypeArguments(after: anchor))

        let parserE = KotlinParser(
            tokens: [
                makeToken(kind: .keyword(.fun)),
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .identifier(interner.intern("id"))),
                makeToken(kind: .symbol(.lParen)),
                makeToken(kind: .identifier(interner.intern("x"))),
                makeToken(kind: .symbol(.colon)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.rParen)),
                makeToken(kind: .symbol(.assign)),
                makeToken(kind: .identifier(interner.intern("x"))),
                makeToken(kind: .eof)
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        let parsed = parserE.parseFile()
        let kinds = Set(parsed.arena.nodes.map(\.kind))
        XCTAssertTrue(kinds.contains(.typeArgs))
    }

    func testParserCoversRareDeclarationEnumAndMissingNameBranches() {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        var offset = 0

        func token(_ kind: TokenKind, leadingNewline: Bool = false) -> Token {
            defer { offset += 1 }
            return Token(
                kind: kind,
                range: makeRange(file: FileID(rawValue: 0), start: offset, end: offset + 1),
                leadingTrivia: leadingNewline ? [.newline] : [],
                trailingTrivia: []
            )
        }

        let tokens: [Token] = [
            token(.keyword(.public)),
            token(.keyword(.package)),
            token(.identifier(interner.intern("pkg"))),
            token(.symbol(.semicolon)),

            token(.keyword(.private), leadingNewline: true),
            token(.keyword(.import)),
            token(.identifier(interner.intern("pkg"))),
            token(.symbol(.dot)),
            token(.symbol(.star)),
            token(.symbol(.semicolon)),

            token(.keyword(.companion), leadingNewline: true),
            token(.keyword(.class)),
            token(.identifier(interner.intern("CompanionHost"))),
            token(.symbol(.semicolon)),

            token(.keyword(.object), leadingNewline: true),
            token(.identifier(interner.intern("StandaloneObject"))),

            token(.keyword(.class), leadingNewline: true),
            token(.symbol(.lessThan)),
            token(.identifier(interner.intern("T"))),
            token(.symbol(.greaterThan)),
            token(.symbol(.lBrace)),
            token(.symbol(.rBrace)),

            token(.keyword(.val), leadingNewline: true),
            token(.symbol(.lBrace)),
            token(.symbol(.rBrace)),

            token(.keyword(.typealias), leadingNewline: true),
            token(.symbol(.assign)),
            token(.identifier(interner.intern("AliasTarget"))),

            token(.keyword(.fun), leadingNewline: true),
            token(.identifier(interner.intern("top"))),
            token(.symbol(.lParen)),
            token(.symbol(.rParen)),
            token(.symbol(.lBrace)),
            token(.symbol(.rBrace)),

            token(.keyword(.enum), leadingNewline: true),
            token(.identifier(interner.intern("NoBody"))),
            token(.symbol(.assign)),
            token(.intLiteral("1")),

            token(.keyword(.enum), leadingNewline: true),
            token(.keyword(.class)),
            token(.identifier(interner.intern("E"))),
            token(.symbol(.lBrace)),
            token(.identifier(interner.intern("A"))),
            token(.symbol(.lParen)),
            token(.intLiteral("1")),
            token(.symbol(.rParen)),
            token(.symbol(.comma)),
            token(.keyword(.fun)),
            token(.identifier(interner.intern("f"))),
            token(.symbol(.lParen)),
            token(.symbol(.rParen)),
            token(.symbol(.assign)),
            token(.intLiteral("1")),
            token(.symbol(.semicolon)),
            token(.intLiteral("2")),
            token(.symbol(.rBrace)),
            token(.eof)
        ]

        let parser = KotlinParser(tokens: tokens, interner: interner, diagnostics: diagnostics)
        let parsed = parser.parseFile()

        XCTAssertFalse(parsed.arena.nodes.isEmpty)
        let kinds = Set(parsed.arena.nodes.map(\.kind))
        XCTAssertTrue(kinds.contains(.packageHeader))
        XCTAssertTrue(kinds.contains(.importHeader))
        XCTAssertTrue(kinds.contains(.classDecl))
        XCTAssertTrue(kinds.contains(.objectDecl))
        XCTAssertTrue(kinds.contains(.propertyDecl))
        XCTAssertTrue(kinds.contains(.typeAliasDecl))
        XCTAssertTrue(kinds.contains(.funDecl))
        XCTAssertTrue(kinds.contains(.enumEntry))
        XCTAssertTrue(kinds.contains(.block))
        XCTAssertTrue(kinds.contains(.statement))

        let codes = Set(diagnostics.diagnostics.map(\.code))
        XCTAssertTrue(codes.contains("KSWIFTK-PARSE-0002"))
    }

    func testParserWarnsForUnterminatedTypeArgsAndParameterGroup() {
        let interner = StringInterner()

        let typeArgDiagnostics = DiagnosticEngine()
        let typeArgTokens: [Token] = [
            makeToken(kind: .keyword(.fun)),
            makeToken(kind: .symbol(.lessThan)),
            makeToken(kind: .identifier(interner.intern("T"))),
            makeToken(kind: .identifier(interner.intern("broken"))),
            makeToken(kind: .symbol(.lParen)),
            makeToken(kind: .identifier(interner.intern("x"))),
            makeToken(kind: .symbol(.colon)),
            makeToken(kind: .identifier(interner.intern("T"))),
            makeToken(kind: .symbol(.rParen)),
            makeToken(kind: .symbol(.assign)),
            makeToken(kind: .identifier(interner.intern("x"))),
            makeToken(kind: .eof)
        ]
        let typeArgParser = KotlinParser(tokens: typeArgTokens, interner: interner, diagnostics: typeArgDiagnostics)
        let typeArgParsed = typeArgParser.parseFile()
        XCTAssertTrue(typeArgParsed.arena.nodes.contains { $0.kind == .typeArgs })
        XCTAssertTrue(typeArgDiagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0005" })

        let groupDiagnostics = DiagnosticEngine()
        let groupTokens: [Token] = [
            makeToken(kind: .keyword(.fun)),
            makeToken(kind: .identifier(interner.intern("broken"))),
            makeToken(kind: .symbol(.lParen)),
            makeToken(kind: .identifier(interner.intern("x"))),
            makeToken(kind: .symbol(.colon)),
            makeToken(kind: .identifier(interner.intern("Int"))),
            makeToken(kind: .eof)
        ]
        let groupParser = KotlinParser(tokens: groupTokens, interner: interner, diagnostics: groupDiagnostics)
        _ = groupParser.parseFile()
        XCTAssertTrue(groupDiagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0004" })
    }

    func testFrontendPhasesBuildASTForMixedDeclarations() throws {
        let source = """
        package demo
        import demo.util.*

        public inline suspend fun hello(name: String) = "hi" + name
        val answer = 42
        var status = 1
        class C<T>(x: T)
        interface I
        object O
        typealias Alias = String
        enum class Colors { Red, Green }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            XCTAssertNotNil(ctx.syntaxTree)
            XCTAssertNotNil(ctx.ast)
            XCTAssertFalse(ctx.tokens.isEmpty)

            let ast = try XCTUnwrap(ctx.ast)
            XCTAssertEqual(ast.files.count, 1)
            XCTAssertGreaterThanOrEqual(ast.declarationCount, 6)
            XCTAssertFalse(ctx.diagnostics.hasError)
        }
    }

    func testParserKeepsFollowingDeclarationAfterBrokenFunctionHeader() throws {
        let source = """
        fun ()
        fun good(): Int = 1
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let declarations = ast.arena.declarations()
            XCTAssertGreaterThanOrEqual(declarations.count, 2)

            let names: [String] = declarations.compactMap { decl in
                guard case .funDecl(let funDecl) = decl else {
                    return nil
                }
                return ctx.interner.resolve(funDecl.name)
            }
            XCTAssertTrue(names.contains("good"))
        }
    }

    func testParserUsesScriptRootForTopLevelStatementsOnly() {
        let parsed = parse(
            """
            1 + 2
            """
        )
        XCTAssertEqual(parsed.arena.node(parsed.root).kind, .script)
    }

    func testSemaCollectsNestedTypeAliasSymbolsInClassAndObject() throws {
        let source = """
        class Box {
            typealias Elem = Int
        }
        object Holder {
            typealias Value = String
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let all = sema.symbols.allSymbols()
            let elem = all.first(where: { symbol in
                symbol.kind == .typeAlias &&
                ctx.interner.resolve(symbol.name) == "Elem" &&
                symbol.fqName.count >= 2 &&
                ctx.interner.resolve(symbol.fqName[symbol.fqName.count - 2]) == "Box"
            })
            let value = all.first(where: { symbol in
                symbol.kind == .typeAlias &&
                ctx.interner.resolve(symbol.name) == "Value" &&
                symbol.fqName.count >= 2 &&
                ctx.interner.resolve(symbol.fqName[symbol.fqName.count - 2]) == "Holder"
            })

            XCTAssertNotNil(elem)
            XCTAssertNotNil(value)
        }
    }

    func testExpressionBodyParsesReturnIfTryWithoutTypeDiagnostics() throws {
        let source = """
        fun demo(flag: Boolean): Int = if (flag) return 1 else try 2 catch (e: Throwable) 3
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
        }
    }

    func testUnaryExpressionsParseAndTypeCheckWithoutErrors() throws {
        let source = """
        fun demo(x: Int): Int = if (!false) -x + +x else 0
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
        }
    }

    func testComparisonAndLogicalExpressionsParseAndTypeCheckWithoutErrors() throws {
        let source = """
        fun demoA(x: Int): Int = if (x != 0 && x < 10 || x >= 100) 1 else 2
        fun demoB(x: Int): Int = if (x <= 20 && x > 3) 2 else 3
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
        }
    }

    func testMultiFileParseBoundaryProducesPerFileASTFiles() throws {
        let fileA = """
        package demo
        fun greet(name: String) = "Hello"
        class Greeter
        """
        let fileB = """
        package demo
        import demo.*
        fun farewell(name: String) = "Bye"
        object Singleton
        """

        try withTemporaryFiles(contents: [fileA, fileB]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            XCTAssertEqual(ast.files.count, 2)

            XCTAssertEqual(ctx.tokensByFile.count, 2)
            XCTAssertEqual(ctx.syntaxTrees.count, 2)

            for (_, fileTokens) in ctx.tokensByFile {
                XCTAssertTrue(fileTokens.last.map { $0.kind == .eof } ?? false)
            }

            let file0 = ast.files[0]
            let file1 = ast.files[1]
            XCTAssertNotEqual(file0.fileID, file1.fileID)

            let file0DeclNames = file0.topLevelDecls.compactMap { declID -> String? in
                guard let decl = ast.arena.decl(declID) else { return nil }
                switch decl {
                case .funDecl(let f): return ctx.interner.resolve(f.name)
                case .classDecl(let c): return ctx.interner.resolve(c.name)
                default: return nil
                }
            }
            let file1DeclNames = file1.topLevelDecls.compactMap { declID -> String? in
                guard let decl = ast.arena.decl(declID) else { return nil }
                switch decl {
                case .funDecl(let f): return ctx.interner.resolve(f.name)
                case .objectDecl(let o): return ctx.interner.resolve(o.name)
                default: return nil
                }
            }

            XCTAssertTrue(file0DeclNames.contains("greet"))
            XCTAssertTrue(file0DeclNames.contains("Greeter"))
            XCTAssertFalse(file0DeclNames.contains("farewell"))

            XCTAssertTrue(file1DeclNames.contains("farewell"))
            XCTAssertTrue(file1DeclNames.contains("Singleton"))
            XCTAssertFalse(file1DeclNames.contains("greet"))
        }
    }

    func testMultiFileCrossFileBoundaryDoesNotConcatenateStatements() throws {
        let fileA = """
        fun alpha() = 1
        """
        let fileB = """
        fun beta() = 2
        """

        try withTemporaryFiles(contents: [fileA, fileB]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            XCTAssertEqual(ast.files.count, 2)

            let allFunNames = ast.arena.declarations().compactMap { decl -> String? in
                guard case .funDecl(let f) = decl else { return nil }
                return ctx.interner.resolve(f.name)
            }
            XCTAssertTrue(allFunNames.contains("alpha"))
            XCTAssertTrue(allFunNames.contains("beta"))
            XCTAssertEqual(allFunNames.count, 2)

            XCTAssertEqual(ctx.syntaxTrees.count, 2)
            for (_, cst, root) in ctx.syntaxTrees {
                XCTAssertEqual(cst.node(root).kind, .kotlinFile)
            }

            XCTAssertFalse(ctx.diagnostics.hasError)
        }
    }

    func testMultiFilePerFileScriptAndKotlinFileDetermination() throws {
        let fileA = """
        fun helper() = 42
        class MyClass
        """
        let fileB = """
        1 + 2
        """

        try withTemporaryFiles(contents: [fileA, fileB]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            XCTAssertEqual(ast.files.count, 2)
            XCTAssertEqual(ctx.syntaxTrees.count, 2)

            let rootKinds = ctx.syntaxTrees.map { $0.1.node($0.2).kind }
            XCTAssertTrue(rootKinds.contains(.kotlinFile))
            XCTAssertTrue(rootKinds.contains(.script))

            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            XCTAssertNotNil(scriptFile)

            let kotlinFile = ast.files.first(where: { $0.scriptBody.isEmpty })
            XCTAssertNotNil(kotlinFile)
            let kotlinDeclNames = (kotlinFile?.topLevelDecls ?? []).compactMap { declID -> String? in
                guard let decl = ast.arena.decl(declID) else { return nil }
                switch decl {
                case .funDecl(let f): return ctx.interner.resolve(f.name)
                case .classDecl(let c): return ctx.interner.resolve(c.name)
                default: return nil
                }
            }
            XCTAssertTrue(kotlinDeclNames.contains("helper"))
            XCTAssertTrue(kotlinDeclNames.contains("MyClass"))

            XCTAssertFalse(ctx.diagnostics.hasError)
        }
    }

    private func lex(_ source: String) -> (tokens: [Token], interner: StringInterner, diagnostics: DiagnosticEngine) {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let lexer = KotlinLexer(
            file: FileID(rawValue: 0),
            source: Data(source.utf8),
            interner: interner,
            diagnostics: diagnostics
        )
        let tokens = lexer.lexAll()
        return (tokens, interner, diagnostics)
    }

    private func parse(_ source: String) -> (arena: SyntaxArena, root: NodeID, diagnostics: DiagnosticEngine, interner: StringInterner, tokens: [Token]) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let parsed = parser.parseFile()
        return (parsed.arena, parsed.root, lexed.diagnostics, lexed.interner, lexed.tokens)
    }
}
