#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CharSyntheticMemberLinkTests {
    private func externalLink(
        for member: String,
        parameterCount: Int = 0,
        sema: SemaModule,
        interner: StringInterner,
        receiverType: TypeID? = nil
    ) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        let targetReceiverType = receiverType ?? sema.types.charType
        let sym = sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == targetReceiverType
                && signature.parameterTypes.count == parameterCount
        } ?? sema.symbols.lookup(fqName: fq)
        guard let sym else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    @Test func testCharPredicateStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try sharedSema()

        // KSP-661: isDigit/isLetter/isLetterOrDigit/isWhitespace/isDefined は
        // bundled Kotlin へ移行済みのため合成スタブの外部リンクを持たない。
        // KSP-662: The same applies to digitToInt(OrNull), uppercaseChar,
        // lowercaseChar, and titlecaseChar.
        let expected: [String: String] = [
            "isIdentifierIgnorable": "kk_char_isIdentifierIgnorable",
            // New numeric conversion functions (Char numeric conversions are
            // source-backed in kotlin.Numbers).
            "toDouble": "kk_char_toDouble",
            "toIntOrNull": "kk_char_toIntOrNull",
            "toDoubleOrNull": "kk_char_toDoubleOrNull",
            // Code point and Unicode properties
            "code": "kk_char_code",
            "category": "kk_char_category",
            "directionality": "kk_char_directionality",
        ]

        for (member, expectedLink) in expected {
            #expect(externalLink(for: member, sema: sema, interner: interner) == expectedLink, "Char.\(member) should link to \(expectedLink)")
        }
    }

    // KSP-662: Int.digitToChar() / Int.digitToChar(radix) live in bundled Kotlin
    // (kotlin.text.CharConversions) and therefore have no synthetic external link.
    @Test func testIntDigitToCharStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try sharedSema()

        for parameterCount in [0, 1] {
            #expect(externalLink(
                    for: "digitToChar",
                    parameterCount: parameterCount,
                    sema: sema,
                    interner: interner,
                    receiverType: sema.types.intType
                ) == nil, "Int.digitToChar overload with \(parameterCount) parameter(s) should resolve from bundled Kotlin")
        }
    }

    @Test func testKotlinTextPackageIsParentedUnderKotlinPackage() throws {
        let (sema, interner) = try sharedSema()

        let kotlinSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin")]))
        let kotlinTextSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("text")]))

        #expect(sema.symbols.parentSymbol(for: kotlinTextSymbol) == kotlinSymbol)
    }

    @Test func testCharCategoryEnumSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let charCategorySymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("CharCategory"),
        ]))
        #expect(sema.symbols.symbol(charCategorySymbol)?.kind == .enumClass)

        let charCategoryType = sema.types.make(.classType(ClassType(
            classSymbol: charCategorySymbol,
            args: [],
            nullability: .nonNull
        )))
        let entries = [
            "UNASSIGNED",
            "UPPERCASE_LETTER",
            "LOWERCASE_LETTER",
            "TITLECASE_LETTER",
            "MODIFIER_LETTER",
            "OTHER_LETTER",
            "NON_SPACING_MARK",
            "ENCLOSING_MARK",
            "COMBINING_SPACING_MARK",
            "DECIMAL_DIGIT_NUMBER",
            "LETTER_NUMBER",
            "OTHER_NUMBER",
            "SPACE_SEPARATOR",
            "LINE_SEPARATOR",
            "PARAGRAPH_SEPARATOR",
            "CONTROL",
            "FORMAT",
            "PRIVATE_USE",
            "SURROGATE",
            "DASH_PUNCTUATION",
            "START_PUNCTUATION",
            "END_PUNCTUATION",
            "CONNECTOR_PUNCTUATION",
            "OTHER_PUNCTUATION",
            "MATH_SYMBOL",
            "CURRENCY_SYMBOL",
            "MODIFIER_SYMBOL",
            "OTHER_SYMBOL",
            "INITIAL_QUOTE_PUNCTUATION",
            "FINAL_QUOTE_PUNCTUATION",
        ]

        for entry in entries {
            let entrySymbol = try #require(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("text"),
                interner.intern("CharCategory"),
                interner.intern(entry),
            ]), "CharCategory.\(entry) must be registered")
            #expect(sema.symbols.propertyType(for: entrySymbol) == charCategoryType)
        }
    }

    @Test func testCharCategoryCompanionObjectIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let charCategorySymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("CharCategory"),
        ]))
        let companionSymbol = try #require(
            sema.symbols.companionObjectSymbol(for: charCategorySymbol)
        )
        let companionInfo = try #require(sema.symbols.symbol(companionSymbol))

        #expect(companionInfo.kind == .object)
        #expect(companionInfo.visibility == .public)
        #expect(companionInfo.flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: companionSymbol) == charCategorySymbol)
    }

    @Test func testCharCategoryPropertyReturnsCharCategoryEnum() throws {
        let (sema, interner) = try sharedSema()

        let charCategorySymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("CharCategory"),
        ]))
        let categoryFunction = try #require(sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("category"),
        ]).first { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.receiverType == sema.types.charType
        })
        let signature = try #require(sema.symbols.functionSignature(for: categoryFunction))
        guard case let .classType(categoryClassType) = sema.types.kind(of: signature.returnType) else {
            Issue.record("Char.category should return kotlin.text.CharCategory"); return
        }
        #expect(categoryClassType.classSymbol == charCategorySymbol)
    }

    @Test func testCharDirectionalityReturnsEnumType() throws {
        let (sema, interner) = try sharedSema()

        let enumFQName = ["kotlin", "text", "CharDirectionality"].map { interner.intern($0) }
        let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        let directionalityFQName = ["kotlin", "text", "directionality"].map { interner.intern($0) }
        let directionalitySymbol = try #require(sema.symbols.lookupAll(fqName: directionalityFQName).first { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.receiverType == sema.types.charType
        })
        #expect(sema.symbols.functionSignature(for: directionalitySymbol)?.returnType == enumType)

        for entry in ["UNDEFINED", "LEFT_TO_RIGHT", "RIGHT_TO_LEFT_ARABIC", "COMMON_NUMBER_SEPARATOR", "WHITESPACE"] {
            let entrySymbol = try #require(sema.symbols.lookup(fqName: enumFQName + [interner.intern(entry)]))
            #expect(sema.symbols.propertyType(for: entrySymbol) == enumType)
        }
    }

    @Test func testNativeCharCompanionHelpersAreRegistered() throws {
        let (sema, interner) = try sharedSema()

        let charSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("Char"),
        ]))
        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: charSymbol))
        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let charArraySymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("CharArray"),
        ]))
        let charArrayType = sema.types.make(.classType(ClassType(
            classSymbol: charArraySymbol,
            args: [],
            nullability: .nonNull
        )))

        // KSP-663: Char.Companion surrogate/code-point helpers are now bundled Kotlin
        // source extension functions at package scope, not synthetic companion members.
        let expected: [(name: String, params: [TypeID], returnType: TypeID)] = [
            (
                name: "isSupplementaryCodePoint",
                params: [sema.types.intType],
                returnType: sema.types.booleanType
            ),
            (
                name: "isSurrogatePair",
                params: [sema.types.charType, sema.types.charType],
                returnType: sema.types.booleanType
            ),
            (
                name: "toChars",
                params: [sema.types.intType],
                returnType: charArrayType
            ),
            (
                name: "toCodePoint",
                params: [sema.types.charType, sema.types.charType],
                returnType: sema.types.intType
            ),
        ]

        for item in expected {
            let packageFQName = ["kotlin", "text", item.name].map { interner.intern($0) }
            let functionSymbol = try #require(sema.symbols.lookupAll(fqName: packageFQName).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == companionType
                    && signature.parameterTypes == item.params
                    && signature.returnType == item.returnType
            }, "Char.Companion.\(item.name) should be a Kotlin source extension function at kotlin.text scope")
            #expect(sema.symbols.symbol(functionSymbol)?.declSite != nil, "Char.Companion.\(item.name) should have a declSite (Kotlin source)")
            #expect(sema.symbols.externalLinkName(for: functionSymbol) == nil, "Char.Companion.\(item.name) should have no C external link (Kotlin source)")
            #expect(sema.symbols.annotations(for: functionSymbol).contains {
                    $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
                }, "Char.Companion.\(item.name) should require ExperimentalNativeApi")
        }
    }

    // KSP-662: Locale-aware and radix overloads are also defined in bundled Kotlin
    // without synthetic external links; locale conversion uses __kk_char_*_locale bridges.
    @Test func testCharLocaleCaseStubHasCorrectExternalLink() throws {
        let (sema, interner) = try sharedSema()

        #expect(externalLink(for: "lowercase", parameterCount: 1, sema: sema, interner: interner) == nil)
        #expect(externalLink(for: "uppercase", parameterCount: 1, sema: sema, interner: interner) == nil)
    }

    @Test func testCharDigitToIntOrNullRadixStubHasCorrectExternalLink() throws {
        let (sema, interner) = try sharedSema()
        #expect(externalLink(for: "digitToIntOrNull", parameterCount: 1, sema: sema, interner: interner) == nil)
    }

    @Test func testCharDigitToIntOrNullRadixResolvesInCallExpressions() throws {
        let source = """
        fun probe(ch: Char) { ch.digitToIntOrNull(16) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError))
        }
    }

    @Test func testCharPredicateMembersResolveInCallExpressions() throws {
        let source = """
        fun probe(ch: Char) {
            ch.isDigit()
            ch.isLetter()
            ch.isLetterOrDigit()
            ch.isWhitespace()
            ch.isDefined()
            ch.isIdentifierIgnorable()
            ch.digitToInt()
            ch.digitToIntOrNull()
            ch.uppercase()
            ch.uppercaseChar()
            ch.lowercase()
            ch.lowercaseChar()
            ch.titlecase()
            ch.titlecaseChar()
            // New numeric conversion functions
            ch.toInt()
            ch.toDouble()
            ch.toIntOrNull()
            ch.toDoubleOrNull()
            // Code point and Unicode properties
            ch.code
            ch.category
            ch.directionality
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let expectedFunctionLinks: [String: String] = [
                "isIdentifierIgnorable": "kk_char_isIdentifierIgnorable",
                "toDouble": "kk_char_toDouble",
                "toIntOrNull": "kk_char_toIntOrNull",
                "toDoubleOrNull": "kk_char_toDoubleOrNull",
            ]
            let expectedPropertyLinks: [String: String] = [
                "code": "kk_char_code",
                "category": "kk_char_category",
                "directionality": "kk_char_directionality",
            ]

            for (memberName, externalLinkName) in expectedFunctionLinks {
                let callExpr = try #require(firstExprID(in: ast) { exprID, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr,
                          ctx.interner.resolve(callee) == memberName,
                          let range = ast.arena.exprRange(exprID)
                    else { return false }
                    return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                }, "Expected member call to \(memberName) in AST")
                #expect(sema.bindings.exprTypes[callExpr] != sema.types.errorType)
                if let chosenCallee = sema.bindings.callBinding(for: callExpr)?.chosenCallee
                    ?? sema.bindings.identifierSymbol(for: callExpr)
                {
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                }
            }

            for (memberName, externalLinkName) in expectedPropertyLinks {
                let propertyExpr = try #require(firstExprID(in: ast) { exprID, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr,
                          ctx.interner.resolve(callee) == memberName,
                          args.isEmpty,
                          let range = ast.arena.exprRange(exprID)
                    else { return false }
                    return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                }, "Expected property access to \(memberName) in AST")
                #expect(sema.bindings.exprTypes[propertyExpr] != sema.types.errorType)
                if let chosenSymbol = sema.bindings.identifierSymbol(for: propertyExpr) {
                    #expect(sema.symbols.externalLinkName(for: chosenSymbol) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                }
            }
        }
    }

    @Test
    func testCharNumericConversionsResolveToBundledKotlinSource() throws {
        let source = """
        fun probe(ch: Char) {
            ch.toByte()
            ch.toShort()
            ch.toInt()
            ch.toLong()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, "Expected Char numeric conversions to resolve, got: \(diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedMembers = Set(["toByte", "toShort", "toInt", "toLong"])
            var observedMembers = Set<String>()

            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .memberCall(_, callee, _, args, range) = ast.arena.expr(exprID),
                      args.isEmpty,
                      expectedMembers.contains(ctx.interner.resolve(callee)),
                      !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_"),
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee
                else { continue }

                let memberName = ctx.interner.resolve(callee)
                observedMembers.insert(memberName)
                #expect(
                    sema.symbols.isSourceBackedSymbol(chosenCallee),
                    "Expected Char.\(memberName) to resolve to bundled Kotlin source"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == nil,
                    "Expected Char.\(memberName) to have no public runtime link"
                )
            }

            #expect(observedMembers == expectedMembers, "Unexpected Char numeric members: \(observedMembers)")
        }
    }

    @Test func testNativeCharCompanionHelpersResolveInCallExpressions() throws {
        let source = #"""
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        fun probe() {
            Char.isSupplementaryCodePoint(0x10000)
            Char.isSurrogatePair('\uD800', '\uDC00')
            Char.toChars(0x10000)
            Char.toCodePoint('\uD800', '\uDC00')
        }
        """#

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for memberName in [
                "isSupplementaryCodePoint",
                "isSurrogatePair",
                "toChars",
                "toCodePoint",
            ] {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected companion call to \(memberName) in AST")
                #expect(sema.bindings.exprTypes[callExpr] != sema.types.errorType)
                let callBinding = try #require(sema.bindings.callBinding(for: callExpr), "Expected call binding for \(memberName)")
                #expect(sema.symbols.symbol(callBinding.chosenCallee)?.declSite != nil, "\(memberName) should resolve to a Kotlin source function")
                #expect(sema.symbols.externalLinkName(for: callBinding.chosenCallee) == nil, "\(memberName) should not resolve to a C external link")
            }
        }
    }
}
#endif
