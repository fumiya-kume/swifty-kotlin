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
            "trimIndent": "kk_string_trimIndent",
        ]

        for (member, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: member, sema: sema, interner: interner),
                expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
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

    func testTrimPredicateStubsHaveCorrectSignatures() throws {
        let (sema, interner) = try makeSema()
        let charType = sema.types.make(.primitive(.char, .nonNull))
        let booleanType = sema.types.booleanType

        let expectedLinks: [String: String] = [
            "trim": "kk_string_trim_predicate",
            "trimStart": "kk_string_trimStart_predicate",
            "trimEnd": "kk_string_trimEnd_predicate",
        ]

        for (member, expectedLink) in expectedLinks {
            let fqName = ["kotlin", "text", member].map { interner.intern($0) }
            let symbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: fqName).first {
                    sema.symbols.externalLinkName(for: $0) == expectedLink
                },
                "String.\(member) predicate overload should link to \(expectedLink)"
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.receiverType, sema.types.stringType)
            XCTAssertEqual(signature.parameterTypes.count, 1)
            XCTAssertEqual(signature.returnType, sema.types.stringType)

            guard case let .functionType(predicateType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                return XCTFail("Expected \(member) predicate parameter to be a function type")
            }
            XCTAssertEqual(predicateType.params, [charType])
            XCTAssertEqual(predicateType.returnType, booleanType)
            XCTAssertFalse(predicateType.isSuspend)
        }
    }

    func testTrimPredicateMembersResolveInCallExpressions() throws {
        let source = """
        fun process(s: String): String {
            return s.trim { it == 'x' } +
                s.trimStart { it == 'x' } +
                s.trimEnd { it == 'x' }
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
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testByteArrayDecodeRangeStubsHaveCorrectSignatures() throws {
        let (sema, interner) = try makeSema()
        let decodeFQName = ["kotlin", "text", "decodeToString"].map { interner.intern($0) }
        let byteArraySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: ["kotlin", "ByteArray"].map { interner.intern($0) }))
        let byteArrayType = try XCTUnwrap(sema.symbols.propertyType(for: byteArraySymbol))

        let expected: [(link: String, params: [TypeID])] = [
            ("kk_bytearray_decodeToString_range_default", [sema.types.intType, sema.types.intType]),
            ("kk_bytearray_decodeToString_range", [sema.types.intType, sema.types.intType, sema.types.booleanType]),
        ]

        for item in expected {
            let symbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: decodeFQName).first {
                    guard sema.symbols.externalLinkName(for: $0) == item.link,
                          let signature = sema.symbols.functionSignature(for: $0)
                    else { return false }
                    return signature.receiverType == byteArrayType
                },
                "ByteArray.decodeToString overload should link to \(item.link)"
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.parameterTypes, item.params)
            XCTAssertEqual(signature.returnType, sema.types.stringType)
        }
    }

    func testByteArrayDecodeRangeMembersResolveInCallExpressions() throws {
        let source = """
        fun decode(bytes: ByteArray): String {
            val middle = bytes.decodeToString(1, 3)
            val strict = bytes.decodeToString(1, 3, true)
            return middle + strict
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let expectedLinksByArgCount: [Int: String] = [
                2: "kk_bytearray_decodeToString_range_default",
                3: "kk_bytearray_decodeToString_range",
            ]

            for (argCount, expectedLink) in expectedLinksByArgCount {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "decodeToString" && args.count == argCount
                }, "Expected decodeToString call with \(argCount) args")
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for decodeToString with \(argCount) args"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    expectedLink
                )
            }
        }
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
}
