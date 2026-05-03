@testable import CompilerCore
import Foundation
import XCTest

/// Verifies that the new String stdlib extension stubs added in the PR
/// (STDLIB-006, STDLIB-009) are registered in the symbol table with the
/// correct runtime external link names.
final class StringSyntheticMemberLinkTests: XCTestCase {
    /// Resolve the `kotlin.text.<member>` symbol and return its external link name.
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func externalLinks(for member: String, sema: SemaModule, interner: StringInterner) -> Set<String> {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        return Set(sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) })
    }

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func allExprIDs(in ast: ASTModule, where predicate: (ExprID, Expr) -> Bool) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            if predicate(exprID, expr) {
                results.append(exprID)
            }
        }
        return results
    }

    func testExistingStringStubsRetainCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "trim": "kk_string_trim",
            "split": "kk_string_split",
            "replace": "kk_string_replace",
            "startsWith": "kk_string_startsWith",
            "endsWith": "kk_string_endsWith",
            "toInt": "kk_string_toInt",
            "toDouble": "kk_string_toDouble",
            "hexToUInt": "kk_string_hexToUInt",
            "trimIndent": "kk_string_trimIndent",
            "replaceIndentByMargin": "kk_string_replaceIndentByMargin",
        ]

        for (member, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: member, sema: sema, interner: interner),
                expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
        XCTAssertTrue(
            externalLinks(for: "indexOfAny", sema: sema, interner: interner)
                .contains("kk_string_indexOfAny_chars"),
            "CharSequence.indexOfAny(chars, startIndex, ignoreCase) should link to kk_string_indexOfAny_chars"
        )
        XCTAssertTrue(
            externalLinks(for: "indexOfAny", sema: sema, interner: interner)
                .contains("kk_string_indexOfAny_strings"),
            "CharSequence.indexOfAny(strings, startIndex, ignoreCase) should link to kk_string_indexOfAny_strings"
        )
        XCTAssertTrue(
            externalLinks(for: "lastIndexOfAny", sema: sema, interner: interner)
                .contains("kk_string_lastIndexOfAny_chars"),
            "CharSequence.lastIndexOfAny(chars, startIndex, ignoreCase) should link to kk_string_lastIndexOfAny_chars"
        )
        XCTAssertTrue(
            externalLinks(for: "lastIndexOfAny", sema: sema, interner: interner)
                .contains("kk_string_lastIndexOfAny_strings"),
            "CharSequence.lastIndexOfAny(strings, startIndex, ignoreCase) should link to kk_string_lastIndexOfAny_strings"
        )
        XCTAssertEqual(
            externalLink(for: "findAnyOf", sema: sema, interner: interner),
            "kk_string_findAnyOf",
            "CharSequence.findAnyOf(strings, startIndex, ignoreCase) should link to kk_string_findAnyOf"
        )
        XCTAssertEqual(
            externalLink(for: "findLastAnyOf", sema: sema, interner: interner),
            "kk_string_findLastAnyOf",
            "CharSequence.findLastAnyOf(strings, startIndex, ignoreCase) should link to kk_string_findLastAnyOf"
        )
        XCTAssertTrue(
            externalLinks(for: "replaceAfter", sema: sema, interner: interner)
                .contains("kk_string_replaceAfter"),
            "String.replaceAfter(String, replacement, missingDelimiterValue) should link to kk_string_replaceAfter"
        )
        XCTAssertTrue(
            externalLinks(for: "replaceAfter", sema: sema, interner: interner)
                .contains("kk_string_replaceAfter_char"),
            "String.replaceAfter(Char, replacement, missingDelimiterValue) should link to kk_string_replaceAfter_char"
        )
        XCTAssertTrue(
            externalLinks(for: "replaceAfterLast", sema: sema, interner: interner)
                .contains("kk_string_replaceAfterLast"),
            "String.replaceAfterLast(String, replacement, missingDelimiterValue) should link to kk_string_replaceAfterLast"
        )
        XCTAssertTrue(
            externalLinks(for: "replaceAfterLast", sema: sema, interner: interner)
                .contains("kk_string_replaceAfterLast_char"),
            "String.replaceAfterLast(Char, replacement, missingDelimiterValue) should link to kk_string_replaceAfterLast_char"
        )
        XCTAssertTrue(
            externalLinks(for: "replaceBefore", sema: sema, interner: interner)
                .contains("kk_string_replaceBefore"),
            "String.replaceBefore(String, replacement, missingDelimiterValue) should link to kk_string_replaceBefore"
        )
        XCTAssertTrue(
            externalLinks(for: "replaceBefore", sema: sema, interner: interner)
                .contains("kk_string_replaceBefore_char"),
            "String.replaceBefore(Char, replacement, missingDelimiterValue) should link to kk_string_replaceBefore_char"
        )
        XCTAssertTrue(
            externalLinks(for: "replaceBeforeLast", sema: sema, interner: interner)
                .contains("kk_string_replaceBeforeLast"),
            "String.replaceBeforeLast(String, replacement, missingDelimiterValue) should link to kk_string_replaceBeforeLast"
        )
        XCTAssertTrue(
            externalLinks(for: "replaceBeforeLast", sema: sema, interner: interner)
                .contains("kk_string_replaceBeforeLast_char"),
            "String.replaceBeforeLast(Char, replacement, missingDelimiterValue) should link to kk_string_replaceBeforeLast_char"
        )
    }

    func testNewCaseConversionStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "lowercase", sema: sema, interner: interner),
            "kk_string_lowercase",
            "String.lowercase should link to kk_string_lowercase"
        )
        XCTAssertEqual(
            externalLink(for: "uppercase", sema: sema, interner: interner),
            "kk_string_uppercase",
            "String.uppercase should link to kk_string_uppercase"
        )

        let lowercaseFQ = ["kotlin", "text", "lowercase"].map { interner.intern($0) }
        let lowercaseLinks = Set(
            sema.symbols.lookupAll(fqName: lowercaseFQ).compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(lowercaseLinks.contains("kk_string_lowercase"))
        XCTAssertTrue(lowercaseLinks.contains("kk_string_lowercase_locale"))

        let uppercaseFQ = ["kotlin", "text", "uppercase"].map { interner.intern($0) }
        let uppercaseLinks = Set(
            sema.symbols.lookupAll(fqName: uppercaseFQ).compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(uppercaseLinks.contains("kk_string_uppercase"))
        XCTAssertTrue(uppercaseLinks.contains("kk_string_uppercase_locale"))
    }

    func testStringNormalizationStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "normalize", sema: sema, interner: interner),
            "kk_string_normalize",
            "String.normalize should link to kk_string_normalize"
        )
        XCTAssertEqual(
            externalLink(for: "isNormalized", sema: sema, interner: interner),
            "kk_string_isNormalized",
            "String.isNormalized should link to kk_string_isNormalized"
        )
    }

    func testNewNullableConversionStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "toIntOrNull", sema: sema, interner: interner),
            "kk_string_toIntOrNull",
            "String.toIntOrNull should link to kk_string_toIntOrNull"
        )
        XCTAssertTrue(
            externalLinks(for: "toIntOrNull", sema: sema, interner: interner)
                .contains("kk_string_toIntOrNull_radix"),
            "String.toIntOrNull(radix) should link to kk_string_toIntOrNull_radix"
        )
        XCTAssertEqual(
            externalLink(for: "toDoubleOrNull", sema: sema, interner: interner),
            "kk_string_toDoubleOrNull",
            "String.toDoubleOrNull should link to kk_string_toDoubleOrNull"
        )
        XCTAssertEqual(
            externalLink(for: "toBigDecimal", sema: sema, interner: interner),
            "kk_string_toBigDecimal",
            "String.toBigDecimal should link to kk_string_toBigDecimal"
        )
        XCTAssertEqual(
            externalLink(for: "toBigInteger", sema: sema, interner: interner),
            "kk_string_toBigInteger",
            "String.toBigInteger should link to kk_string_toBigInteger"
        )
    }

    func testNewSubstringAndSearchStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "indexOf": "kk_string_indexOf",
            "lastIndexOf": "kk_string_lastIndexOf",
        ]
        for (member, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: member, sema: sema, interner: interner),
                expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
    }

    func testNewTransformStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "repeat": "kk_string_repeat",
            "reversed": "kk_string_reversed",
            "toList": "kk_string_toList",
            "toCharArray": "kk_string_toCharArray",
        ]
        for (member, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: member, sema: sema, interner: interner),
                expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
    }

    func testNewPaddingStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        // padStart / padEnd each have two overloads:
        //   1-arg (default padChar) -> kk_string_padStart_default / kk_string_padEnd_default
        //   2-arg (explicit padChar) -> kk_string_padStart / kk_string_padEnd
        // lookup(fqName:) returns .first, which is the 1-arg default overload.
        XCTAssertEqual(
            externalLink(for: "padStart", sema: sema, interner: interner),
            "kk_string_padStart_default",
            "String.padStart (1-arg default) should link to kk_string_padStart_default"
        )
        XCTAssertEqual(
            externalLink(for: "padEnd", sema: sema, interner: interner),
            "kk_string_padEnd_default",
            "String.padEnd (1-arg default) should link to kk_string_padEnd_default"
        )

        // Verify both overloads are registered via lookupAll and link to distinct ABI functions.
        let padStartFQ = ["kotlin", "text", "padStart"].map { interner.intern($0) }
        let padStartSymbols = sema.symbols.lookupAll(fqName: padStartFQ)
        XCTAssertEqual(padStartSymbols.count, 2, "padStart should have 2 overloads (default + explicit padChar)")
        let padStartLinks = Set(padStartSymbols.compactMap { sema.symbols.externalLinkName(for: $0) })
        XCTAssertTrue(padStartLinks.contains("kk_string_padStart_default"), "padStart should have a _default overload")
        XCTAssertTrue(padStartLinks.contains("kk_string_padStart"), "padStart should have a non-default overload")

        let padEndFQ = ["kotlin", "text", "padEnd"].map { interner.intern($0) }
        let padEndSymbols = sema.symbols.lookupAll(fqName: padEndFQ)
        XCTAssertEqual(padEndSymbols.count, 2, "padEnd should have 2 overloads (default + explicit padChar)")
        let padEndLinks = Set(padEndSymbols.compactMap { sema.symbols.externalLinkName(for: $0) })
        XCTAssertTrue(padEndLinks.contains("kk_string_padEnd_default"), "padEnd should have a _default overload")
        XCTAssertTrue(padEndLinks.contains("kk_string_padEnd"), "padEnd should have a non-default overload")
    }

    func testNewSlicingStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "drop": "kk_string_drop",
            "take": "kk_string_take",
            "dropLast": "kk_string_dropLast",
            "takeLast": "kk_string_takeLast",
        ]
        for (member, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: member, sema: sema, interner: interner),
                expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
    }

    func testIfBlankStubHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "ifBlank", sema: sema, interner: interner),
            "kk_string_ifBlank",
            "CharSequence.ifBlank should link to kk_string_ifBlank"
        )
    }

    func testIfEmptyStubHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "ifEmpty", sema: sema, interner: interner),
            "kk_string_ifEmpty",
            "CharSequence.ifEmpty should link to kk_string_ifEmpty"
        )
    }

    func testChunkedSequenceStubHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "chunkedSequence", sema: sema, interner: interner),
            "kk_string_chunkedSequence",
            "CharSequence.chunkedSequence should link to kk_string_chunkedSequence"
        )
        XCTAssertTrue(
            externalLinks(for: "chunkedSequence", sema: sema, interner: interner)
                .contains("kk_string_chunkedSequence_transform"),
            "CharSequence.chunkedSequence(size, transform) should link to kk_string_chunkedSequence_transform"
        )
    }

    func testWindowedSequenceStubHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "windowedSequence", sema: sema, interner: interner),
            "kk_string_windowedSequence_partial",
            "CharSequence.windowedSequence should link to kk_string_windowedSequence_partial"
        )
        XCTAssertTrue(
            externalLinks(for: "windowedSequence", sema: sema, interner: interner)
                .contains("kk_string_windowedSequence_transform"),
            "CharSequence.windowedSequence(size, step, partialWindows, transform) should link to kk_string_windowedSequence_transform"
        )
    }

    func testIfBlankResolvesInCallExpressions() throws {
        let source = """
        fun choose(value: CharSequence): String {
            return value.ifBlank { "fallback" }
        }

        fun chooseString(value: String): String {
            return value.ifBlank { "fallback" }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "ifBlank"
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for ifBlank"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_string_ifBlank",
                    "Expected ifBlank to resolve to kk_string_ifBlank"
                )
            }
        }
    }

    func testIfEmptyResolvesInCallExpressions() throws {
        let source = """
        fun choose(value: CharSequence): String {
            return value.ifEmpty { "fallback" }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "ifEmpty"
            }, "Expected member call to ifEmpty in AST")
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for ifEmpty"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_ifEmpty",
                "Expected ifEmpty to resolve to kk_string_ifEmpty"
            )
        }
    }

    func testTrimPredicateStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: Set<String>] = [
            "trim": ["kk_string_trim", "kk_string_trim_predicate"],
            "trimStart": ["kk_string_trimStart", "kk_string_trimStart_predicate"],
            "trimEnd": ["kk_string_trimEnd", "kk_string_trimEnd_predicate"],
        ]

        for (member, expectedLinks) in expected {
            XCTAssertTrue(
                externalLinks(for: member, sema: sema, interner: interner).isSuperset(of: expectedLinks),
                "String.\(member) should expose no-arg and predicate overload ABI links"
            )
        }
    }

    func testTrimPredicateMembersResolveInCallExpressions() throws {
        let source = """
        fun trimEdges(s: String): String {
            val a = s.trim { it == 'x' }
            val b = s.trimStart { it == 'x' }
            val c = s.trimEnd { it == 'x' }
            return a + b + c
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedLinks: [String: String] = [
                "trim": "kk_string_trim_predicate",
                "trimStart": "kk_string_trimStart_predicate",
                "trimEnd": "kk_string_trimEnd_predicate",
            ]

            for (memberName, externalLinkName) in expectedLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for \(memberName)"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) predicate overload to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testNewStringMembersResolveInCallExpressions() throws {
        let source = """
        fun process(s: String): String {
            val lower = s.lowercase()
            val upper = s.uppercase()
            val rep = s.repeat(3)
            val rev = s.reversed()
            return lower + upper + rep + rev
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedLinks: [String: String] = [
                "lowercase": "kk_string_lowercase",
                "uppercase": "kk_string_uppercase",
                "repeat": "kk_string_repeat",
                "reversed": "kk_string_reversed",
            ]

            for (memberName, externalLinkName) in expectedLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for \(memberName)"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testStringNormalizationMembersResolveInCallExpressions() throws {
        let source = """
        fun normalizeText(s: String): String {
            val normalized = s.normalize(NormalizationForms.NFC)
            let stable = normalized.isNormalized(NormalizationForms.NFC)
            return if (stable) normalized else s
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedLinks: [String: String] = [
                "normalize": "kk_string_normalize",
                "isNormalized": "kk_string_isNormalized",
            ]

            for (memberName, externalLinkName) in expectedLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for \(memberName)"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testChunkedSequenceResolvesInCallExpressions() throws {
        let source = """
        fun chunks(value: CharSequence): Sequence<String> {
            return value.chunkedSequence(2)
        }

        fun stringChunks(value: String): Sequence<String> {
            return value.chunkedSequence(3)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "chunkedSequence"
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for chunkedSequence"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_string_chunkedSequence",
                    "Expected chunkedSequence to resolve to kk_string_chunkedSequence"
                )
            }
        }
    }

    func testChunkedSequenceTransformResolvesInCallExpressions() throws {
        let source = """
        fun chunks(value: CharSequence): Sequence<String> {
            return value.chunkedSequence(2) { chunk -> "" + chunk + "!" }
        }

        fun stringChunks(value: String): Sequence<String> {
            return value.chunkedSequence(3) { "" + it }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "chunkedSequence"
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for chunkedSequence"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_string_chunkedSequence_transform",
                    "Expected chunkedSequence transform to resolve to kk_string_chunkedSequence_transform"
                )
            }
        }
    }

    func testWindowedSequenceResolvesInCallExpressions() throws {
        let source = """
        fun windows(value: CharSequence): Sequence<String> {
            return value.windowedSequence(3, 2, true)
        }

        fun stringWindows(value: String): Sequence<String> {
            return value.windowedSequence(2, 1, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "windowedSequence"
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for windowedSequence"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_string_windowedSequence_partial",
                    "Expected windowedSequence to resolve to kk_string_windowedSequence_partial"
                )
            }
        }
    }

    func testWindowedSequenceTransformResolvesInCallExpressions() throws {
        let source = """
        fun windows(value: CharSequence): Sequence<Int> {
            return value.windowedSequence(3, 2, true) { it.length }
        }

        fun stringWindows(value: String): Sequence<String> {
            return value.windowedSequence(size = 2, step = 1, partialWindows = false) { window -> "" + window }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "windowedSequence"
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for windowedSequence"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_string_windowedSequence_transform",
                    "Expected windowedSequence transform to resolve to kk_string_windowedSequence_transform"
                )
            }
        }
    }

    func testIndexOfAnyCharsResolvesInCallExpressions() throws {
        let source = """
        fun firstAny(value: CharSequence, chars: CharArray): Int {
            return value.indexOfAny(chars, 1, true)
        }

        fun stringFirstAny(value: String): Int {
            return value.indexOfAny(charArrayOf('x'), 0, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "indexOfAny"
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for indexOfAny"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_string_indexOfAny_chars",
                    "Expected indexOfAny(chars, startIndex, ignoreCase) to resolve to kk_string_indexOfAny_chars"
                )
            }
        }
    }

    func testIndexOfAnyStringsResolvesInCallExpressions() throws {
        let source = """
        fun firstAny(value: CharSequence, strings: Collection<String>): Int {
            return value.indexOfAny(strings, 1, true)
        }

        fun stringFirstAny(value: String): Int {
            return value.indexOfAny(listOf("x"), 0, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "indexOfAny"
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for indexOfAny"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_string_indexOfAny_strings",
                    "Expected indexOfAny(strings, startIndex, ignoreCase) to resolve to kk_string_indexOfAny_strings"
                )
            }
        }
    }

    func testLastIndexOfAnyCharsResolvesInCallExpressions() throws {
        let source = """
        fun lastAny(value: CharSequence, chars: CharArray): Int {
            return value.lastIndexOfAny(chars, 3, true)
        }

        fun stringLastAny(value: String): Int {
            return value.lastIndexOfAny(charArrayOf('x'), 2, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "lastIndexOfAny"
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for lastIndexOfAny"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_string_lastIndexOfAny_chars",
                    "Expected lastIndexOfAny(chars, startIndex, ignoreCase) to resolve to kk_string_lastIndexOfAny_chars"
                )
            }
        }
    }

    func testLastIndexOfAnyStringsResolvesInCallExpressions() throws {
        let source = """
        fun lastAny(value: CharSequence, strings: Collection<String>): Int {
            return value.lastIndexOfAny(strings, 3, true)
        }

        fun stringLastAny(value: String): Int {
            return value.lastIndexOfAny(listOf("x"), 2, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "lastIndexOfAny"
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for lastIndexOfAny"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_string_lastIndexOfAny_strings",
                    "Expected lastIndexOfAny(strings, startIndex, ignoreCase) to resolve to kk_string_lastIndexOfAny_strings"
                )
            }
        }
    }

    func testFindAnyOfStringsResolvesInCallExpressions() throws {
        let source = """
        fun findAny(value: CharSequence, strings: Collection<String>): Pair<Int, String>? {
            return value.findAnyOf(strings, 1, true)
        }

        fun stringFindAny(value: String): Pair<Int, String>? {
            return value.findAnyOf(listOf("x"), 0, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "findAnyOf"
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for findAnyOf"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_string_findAnyOf",
                    "Expected findAnyOf(strings, startIndex, ignoreCase) to resolve to kk_string_findAnyOf"
                )
            }
        }
    }

    func testFindLastAnyOfStringsResolvesInCallExpressions() throws {
        let source = """
        fun findLastAny(value: CharSequence, strings: Collection<String>): Pair<Int, String>? {
            return value.findLastAnyOf(strings, 3, true)
        }

        fun stringFindLastAny(value: String): Pair<Int, String>? {
            return value.findLastAnyOf(listOf("x"), 2, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "findLastAnyOf"
            }
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for findLastAnyOf"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_string_findLastAnyOf",
                    "Expected findLastAnyOf(strings, startIndex, ignoreCase) to resolve to kk_string_findLastAnyOf"
                )
            }
        }
    }

    func testReplaceAfterResolvesInCallExpressions() throws {
        let source = """
        fun replaceAfterString(value: String): String {
            return value.replaceAfter(":", "tail", "missing")
        }

        fun replaceAfterStringDefault(value: String): String {
            return value.replaceAfter(":", "tail")
        }

        fun replaceAfterChar(value: String): String {
            return value.replaceAfter(':', "tail", "missing")
        }

        fun replaceAfterCharDefault(value: String): String {
            return value.replaceAfter(':', "tail")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "replaceAfter"
            }
            XCTAssertEqual(callExprs.count, 4)
            let links = try callExprs.map { callExpr -> String in
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for replaceAfter"
                )
                return sema.symbols.externalLinkName(for: chosenCallee) ?? ""
            }
            XCTAssertEqual(links.filter { $0 == "kk_string_replaceAfter" }.count, 2)
            XCTAssertEqual(links.filter { $0 == "kk_string_replaceAfter_char" }.count, 2)
        }
    }

    func testReplaceAfterLastResolvesInCallExpressions() throws {
        let source = """
        fun replaceAfterLastString(value: String): String {
            return value.replaceAfterLast(":", "tail", "missing")
        }

        fun replaceAfterLastStringDefault(value: String): String {
            return value.replaceAfterLast(":", "tail")
        }

        fun replaceAfterLastChar(value: String): String {
            return value.replaceAfterLast(':', "tail", "missing")
        }

        fun replaceAfterLastCharDefault(value: String): String {
            return value.replaceAfterLast(':', "tail")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "replaceAfterLast"
            }
            XCTAssertEqual(callExprs.count, 4)
            let links = try callExprs.map { callExpr -> String in
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for replaceAfterLast"
                )
                return sema.symbols.externalLinkName(for: chosenCallee) ?? ""
            }
            XCTAssertEqual(links.filter { $0 == "kk_string_replaceAfterLast" }.count, 2)
            XCTAssertEqual(links.filter { $0 == "kk_string_replaceAfterLast_char" }.count, 2)
        }
    }

    func testReplaceBeforeResolvesInCallExpressions() throws {
        let source = """
        fun replaceBeforeString(value: String): String {
            return value.replaceBefore(":", "head", "missing")
        }

        fun replaceBeforeStringDefault(value: String): String {
            return value.replaceBefore(":", "head")
        }

        fun replaceBeforeChar(value: String): String {
            return value.replaceBefore(':', "head", "missing")
        }

        fun replaceBeforeCharDefault(value: String): String {
            return value.replaceBefore(':', "head")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "replaceBefore"
            }
            XCTAssertEqual(callExprs.count, 4)
            let links = try callExprs.map { callExpr -> String in
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for replaceBefore"
                )
                return sema.symbols.externalLinkName(for: chosenCallee) ?? ""
            }
            XCTAssertEqual(links.filter { $0 == "kk_string_replaceBefore" }.count, 2)
            XCTAssertEqual(links.filter { $0 == "kk_string_replaceBefore_char" }.count, 2)
        }
    }

    func testReplaceBeforeLastResolvesInCallExpressions() throws {
        let source = """
        fun replaceBeforeLastString(value: String): String {
            return value.replaceBeforeLast(":", "head", "missing")
        }

        fun replaceBeforeLastStringDefault(value: String): String {
            return value.replaceBeforeLast(":", "head")
        }

        fun replaceBeforeLastChar(value: String): String {
            return value.replaceBeforeLast(':', "head", "missing")
        }

        fun replaceBeforeLastCharDefault(value: String): String {
            return value.replaceBeforeLast(':', "head")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "replaceBeforeLast"
            }
            XCTAssertEqual(callExprs.count, 4)
            let links = try callExprs.map { callExpr -> String in
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for replaceBeforeLast"
                )
                return sema.symbols.externalLinkName(for: chosenCallee) ?? ""
            }
            XCTAssertEqual(links.filter { $0 == "kk_string_replaceBeforeLast" }.count, 2)
            XCTAssertEqual(links.filter { $0 == "kk_string_replaceBeforeLast_char" }.count, 2)
        }
    }

    func testReplaceIndentByMarginResolvesInCallExpressions() throws {
        let source = """
        fun replaceIndentByMarginDefault(value: String): String {
            return value.replaceIndentByMargin()
        }

        fun replaceIndentByMarginNewIndent(value: String): String {
            return value.replaceIndentByMargin(">")
        }

        fun replaceIndentByMarginFull(value: String): String {
            return value.replaceIndentByMargin(">", "|")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "replaceIndentByMargin"
            }
            XCTAssertEqual(callExprs.count, 3)
            let links = try callExprs.map { callExpr -> String in
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for replaceIndentByMargin"
                )
                return sema.symbols.externalLinkName(for: chosenCallee) ?? ""
            }
            XCTAssertEqual(Set(links), ["kk_string_replaceIndentByMargin"])
        }
    }

    func testAppendableInterfaceSurfaceResolves() throws {
        let source = """
        import kotlin.text.Appendable
        import kotlin.text.StringBuilder

        fun appendPieces(target: Appendable): Appendable {
            target.append('a')
            target.append("bc")
            return target.append("def", 1, 3)
        }

        fun builderAsAppendable(): Appendable {
            return StringBuilder()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Appendable surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let appendableFQName = ["kotlin", "text", "Appendable"].map { ctx.interner.intern($0) }
            let appendableSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: appendableFQName))
            XCTAssertEqual(sema.symbols.symbol(appendableSymbol)?.kind, .interface)

            let appendCalls = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "append"
            }
            XCTAssertEqual(appendCalls.count, 3)
            let appendableType = sema.types.make(.classType(ClassType(
                classSymbol: appendableSymbol,
                args: [],
                nullability: .nonNull
            )))
            for callExpr in appendCalls {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected Appendable.append call binding"
                )
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: chosenCallee))
                XCTAssertEqual(signature.receiverType, appendableType)
            }
        }
    }

    func testTypographyObjectSurfaceResolves() throws {
        let source = """
        import kotlin.text.Typography

        fun typographyMarks(): Char {
            val nbsp: Char = Typography.nbsp
            val ellipsis: Char = Typography.ellipsis
            val guillemet: Char = Typography.leftGuillemet
            val legacyGuillemet: Char = Typography.leftGuillemete
            return Typography.greaterOrEqual
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Typography surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let typographyFQName = ["kotlin", "text", "Typography"].map { ctx.interner.intern($0) }
            let typographySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: typographyFQName))
            XCTAssertEqual(sema.symbols.symbol(typographySymbol)?.kind, .object)

            let expectedConstants: [String: UInt32] = [
                "almostEqual": 0x2248,
                "amp": 0x0026,
                "bullet": 0x2022,
                "cent": 0x00A2,
                "copyright": 0x00A9,
                "dagger": 0x2020,
                "degree": 0x00B0,
                "dollar": 0x0024,
                "doubleDagger": 0x2021,
                "doublePrime": 0x2033,
                "ellipsis": 0x2026,
                "euro": 0x20AC,
                "greater": 0x003E,
                "greaterOrEqual": 0x2265,
                "half": 0x00BD,
                "leftDoubleQuote": 0x201C,
                "leftGuillemet": 0x00AB,
                "leftGuillemete": 0x00AB,
                "leftSingleQuote": 0x2018,
                "less": 0x003C,
                "lessOrEqual": 0x2264,
                "lowDoubleQuote": 0x201E,
                "lowSingleQuote": 0x201A,
                "mdash": 0x2014,
                "middleDot": 0x00B7,
                "nbsp": 0x00A0,
                "ndash": 0x2013,
                "notEqual": 0x2260,
                "paragraph": 0x00B6,
                "plusMinus": 0x00B1,
                "pound": 0x00A3,
                "prime": 0x2032,
                "quote": 0x0022,
                "registered": 0x00AE,
                "rightDoubleQuote": 0x201D,
                "rightGuillemet": 0x00BB,
                "rightGuillemete": 0x00BB,
                "rightSingleQuote": 0x2019,
                "section": 0x00A7,
                "times": 0x00D7,
                "tm": 0x2122,
            ]

            for (name, scalar) in expectedConstants {
                let propertyFQName = typographyFQName + [ctx.interner.intern(name)]
                let propertySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: propertyFQName))
                XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), sema.types.make(.primitive(.char, .nonNull)))
                XCTAssertTrue(sema.symbols.symbol(propertySymbol)?.flags.contains(.constValue) ?? false)
                guard case let .charLiteral(value) = sema.symbols.constValueExprKind(for: propertySymbol) else {
                    XCTFail("Expected Typography.\(name) to carry a char literal constant")
                    continue
                }
                XCTAssertEqual(value, scalar, "Unexpected Typography.\(name) scalar")
            }
        }
    }

    func testCaseInsensitiveOrderSurfaceResolves() throws {
        let source = """
        import kotlin.text.CASE_INSENSITIVE_ORDER

        fun caseInsensitiveComparator(): Comparator<String> {
            return CASE_INSENSITIVE_ORDER
        }

        fun compareIgnoringCase(): Int {
            return CASE_INSENSITIVE_ORDER.compare("alpha", "ALPHA")
        }

        fun sortIgnoringCase(values: List<String>): List<String> {
            return values.sortedWith(CASE_INSENSITIVE_ORDER)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected CASE_INSENSITIVE_ORDER surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let propertyFQName = ["kotlin", "text", "CASE_INSENSITIVE_ORDER"].map { ctx.interner.intern($0) }
            let propertySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: propertyFQName))
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: propertySymbol),
                "kk_string_case_insensitive_order"
            )

            let comparatorFQName = ["kotlin", "Comparator"].map { ctx.interner.intern($0) }
            let comparatorSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: comparatorFQName))
            let expectedType = sema.types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.invariant(sema.types.stringType)],
                nullability: .nonNull
            )))
            XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), expectedType)
        }
    }

    func testCharSequenceZipWithNextMembersResolveInCallExpressions() throws {
        let source = """
        fun pairs(value: CharSequence): List<Pair<Char, Char>> {
            return value.zipWithNext()
        }

        fun labels(value: CharSequence): List<String> {
            return value.zipWithNext { a, b -> "" + a + b }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            var externalLinks: [String] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "zipWithNext",
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let link = sema.symbols.externalLinkName(for: chosenCallee)
                else {
                    continue
                }
                externalLinks.append(link)
            }

            XCTAssertEqual(
                externalLinks,
                ["kk_string_zipWithNext", "kk_string_zipWithNextTransform"]
            )
        }
    }

    func testByteArrayDecodeToStringRangeMembersResolveInCallExpressions() throws {
        let source = """
        fun decode(bytes: ByteArray): String {
            val sliced = bytes.decodeToString(1, 4)
            val strict = bytes.decodeToString(0, 4, true)
            return sliced + strict
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let expectedLinks = [
                "kk_bytearray_decodeToString_range",
                "kk_bytearray_decodeToString_range_throw",
            ]

            let callExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "decodeToString"
                else {
                    return nil
                }
                return exprID
            }
            XCTAssertEqual(callExprIDs.count, expectedLinks.count, "Expected two decodeToString range calls")

            for (index, callExprID) in callExprIDs.enumerated() {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExprID)?.chosenCallee,
                    "Expected call binding for decodeToString overload \(index)"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    expectedLinks[index],
                    "Expected decodeToString overload \(index) to resolve to \(expectedLinks[index])"
                )
            }
        }
    }
}
