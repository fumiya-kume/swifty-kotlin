@testable import CompilerCore
import Foundation
import Testing

/// Verifies that String text APIs are source-backed while their deliberately
/// retained runtime bridges keep the expected external link names.
@Suite
struct StringSyntheticMemberLinkTests {
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

    private func externalLink(
        for member: String,
        receiverType: TypeID,
        parameterCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookupAll(fqName: fq).first(where: { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.count == parameterCount
        }) else {
            return nil
        }
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

    // BUG-211: CharSequence.length must be represented as an interface
    // property so bundled Kotlin reads can use the normal itable path.
    // KSP-724: The property is now source-backed from bundled Kotlin, not a
    // synthetic stub, but it remains abstract and parented to CharSequence.
    @Test
    func testBug211CharSequenceLengthIsInterfaceProperty() throws {
        let (sema, interner) = try sharedSema()
        let charSequenceFQ = ["kotlin", "CharSequence"].map { interner.intern($0) }
        let lengthFQ = charSequenceFQ + [interner.intern("length")]
        let charSequenceSymbol = try #require(sema.symbols.lookup(fqName: charSequenceFQ))
        let lengthSymbol = try #require(sema.symbols.lookup(fqName: lengthFQ))
        let lengthInfo = try #require(sema.symbols.symbol(lengthSymbol))

        #expect(lengthInfo.kind == .property)
        #expect(!lengthInfo.flags.contains(.synthetic))
        #expect(lengthInfo.flags.contains(.abstractType))
        #expect(sema.symbols.parentSymbol(for: lengthSymbol) == charSequenceSymbol)
        #expect(sema.symbols.propertyType(for: lengthSymbol) == sema.types.intType)
    }

    @Test func testStringSyntheticMemberLinkRegistrations() throws {
        let (sema, interner) = try sharedSema()

        do {
            // Originally testExistingStringStubsRetainCorrectExternalLinks
            // KSP-414: String.toInt is now bundled Kotlin source (StringNumberParsing.kt)
            // and no longer exposes a public kk_ runtime link.
            let toIntLinks = externalLinks(for: "toInt", sema: sema, interner: interner)
            #expect(
                !toIntLinks.contains("kk_string_toInt") && !toIntLinks.contains("__kk_string_toInt"),
                "String.toInt should be source-backed after KSP-414, got \(toIntLinks.sorted())"
            )
            #expect(
                externalLink(for: "toInt", receiverType: sema.types.stringType, parameterCount: 0, sema: sema, interner: interner) == nil,
                "String.toInt() should have no C external link"
            )
            #expect(
                externalLink(for: "toInt", receiverType: sema.types.stringType, parameterCount: 1, sema: sema, interner: interner) == nil,
                "String.toInt(radix) should have no C external link"
            )
            #expect(
                externalLink(for: "__kk_string_toInt", sema: sema, interner: interner) == "__kk_string_toInt",
                "Private __kk_string_toInt bridge should be registered"
            )
            #expect(
                externalLink(for: "__kk_string_toInt_radix", sema: sema, interner: interner) == "__kk_string_toInt_radix",
                "Private __kk_string_toInt_radix bridge should be registered"
            )
            // KSP-404: startsWith/endsWith/removePrefix/removeSuffix/removeSurrounding are
            // bundled Kotlin source (StringPrefixSuffix.kt) and carry no runtime link.
            for member in ["startsWith", "endsWith", "removePrefix", "removeSuffix", "removeSurrounding"] {
                let links = externalLinks(for: member, sema: sema, interner: interner)
                #expect(
                    !links.contains("kk_string_\(member)_flat") && !links.contains("kk_string_\(member)"),
                    "String.\(member) should be source-backed after KSP-404, got \(links.sorted())"
                )
            }
            #expect(
                !externalLinks(for: "split", sema: sema, interner: interner)
                    .contains("kk_string_split_flat"),
                "String.split(String) should be source-backed after RF-STDLIB-005"
            )
            #expect(
                externalLinks(for: "__kk_string_split", sema: sema, interner: interner)
                    .contains("__kk_string_split"),
                "String.__kk_string_split should bridge through the private __kk_string_split ABI alias"
            )
            #expect(
                externalLinks(for: "__kk_string_split_limit", sema: sema, interner: interner)
                    .contains("__kk_string_split_limit"),
                "String.__kk_string_split_limit should bridge through the private __kk_string_split_limit ABI alias"
            )
            #expect(
                externalLinks(for: "__kk_string_splitToSequence", sema: sema, interner: interner)
                    .contains("__kk_string_splitToSequence"),
                "String.__kk_string_splitToSequence should bridge through the private __kk_string_splitToSequence ABI alias"
            )
            #expect(
                externalLink(for: "findAnyOf", sema: sema, interner: interner) == nil,
                "CharSequence.findAnyOf should be source-backed after KSP-408"
            )
            #expect(
                externalLink(for: "findLastAnyOf", sema: sema, interner: interner) == nil,
                "CharSequence.findLastAnyOf should be source-backed after KSP-408"
            )
            // KSP-407: substringBefore/After/BeforeLast/AfterLast and
            // replaceBefore/After/BeforeLast/AfterLast are now bundled Kotlin source
            // (StringSearchReplace.kt) and carry no runtime link.
            // KSP-408: indexOfAny/lastIndexOfAny/findAnyOf/findLastAnyOf are now
            // bundled Kotlin source (StringIndexOf.kt) and carry no runtime link.
            for member in [
                "substringBefore", "substringAfter", "substringBeforeLast", "substringAfterLast",
                "replaceAfter", "replaceAfterLast", "replaceBefore", "replaceBeforeLast",
                "indexOfAny", "lastIndexOfAny",
            ] {
                let links = externalLinks(for: member, sema: sema, interner: interner)
                #expect(
                    links.isEmpty,
                    "String.\(member) should be source-backed after KSP-407/KSP-408, got \(links.sorted())"
                )
            }
            // STDLIB-TEXT-FN-043: plus overloads (String and String? receiver)
            #expect(
                externalLinks(for: "plus", sema: sema, interner: interner)
                    .contains("kk_string_plus"),
                "String?.plus(other: Any?) should link to kk_string_plus"
            )
            // KSP-303: replace overloads are now bundled Kotlin source, not public runtime stubs.
            let replaceLinks = externalLinks(for: "replace", sema: sema, interner: interner)
            #expect(
                !replaceLinks.contains("kk_string_replace_flat")
                    && !replaceLinks.contains("kk_string_replace_char_flat")
                    && !replaceLinks.contains("kk_string_replace_ignoreCase_flat")
                    && !replaceLinks.contains("kk_string_replace_char_ignoreCase_flat")
                    && !replaceLinks.contains("__kk_string_replace_regex"),
                "String.replace overloads should be source-backed; got \(replaceLinks.sorted())"
            )
        }

        do {
            // Originally testNewCaseConversionStubsHaveCorrectExternalLinks
                    // lowercase() and uppercase() are now bundled Kotlin functions (MIGRATION-TEXT-005) — no C external link.
                    // The `externalLink(for:)` helper returns the first match in the symbol table; since
                    // Char.lowercase / Char.uppercase share the same FQN prefix, we verify via the String-receiver
                    // overloads specifically.
                    let lowercaseLinks = externalLinks(for: "lowercase", sema: sema, interner: interner)
                    #expect(
                        !lowercaseLinks.contains("kk_string_lowercase"),
                        "String.lowercase should be a bundled Kotlin function with no C external link (MIGRATION-TEXT-005)"
                    )
                    let uppercaseLinks = externalLinks(for: "uppercase", sema: sema, interner: interner)
                    #expect(
                        !uppercaseLinks.contains("kk_string_uppercase"),
                        "String.uppercase should be a bundled Kotlin function with no C external link (MIGRATION-TEXT-005)"
                    )
                    // capitalize() is now a bundled Kotlin function (MIGRATION-TEXT-005) — no C external link.
                    #expect(
                        externalLink(for: "capitalize", sema: sema, interner: interner) == nil,
                        "String.capitalize should be a bundled Kotlin function with no C external link"
                    )

                    #expect(
                        externalLink(for: "__kk_lowercase_locale", sema: sema, interner: interner) == "__kk_lowercase_locale",
                        "String.lowercase(Locale) wrapper should call the private locale primitive"
                    )
                    #expect(
                        externalLink(for: "__kk_uppercase_locale", sema: sema, interner: interner) == "__kk_uppercase_locale",
                        "String.uppercase(Locale) wrapper should call the private locale primitive"
                    )
        }

        do {
            // Originally testCodePointCountStubsHaveCorrectExternalLinks
                    let codePointCountLinks = externalLinks(for: "codePointCount", sema: sema, interner: interner)
                    #expect(
                        codePointCountLinks.contains("__kk_string_codePointCount"),
                        "CharSequence.codePointCount() should link to __kk_string_codePointCount"
                    )
                    #expect(
                        codePointCountLinks.contains("__kk_string_codePointCount_from"),
                        "CharSequence.codePointCount(startIndex) should link to __kk_string_codePointCount_from"
                    )
                    #expect(
                        codePointCountLinks.contains("__kk_string_codePointCount_range"),
                        "CharSequence.codePointCount(startIndex, endIndex) should link to __kk_string_codePointCount_range"
                    )
        }

        do {
            // Originally testStringNormalizationStubsHaveCorrectExternalLinks
                    #expect(
                        externalLink(for: "normalize", sema: sema, interner: interner) == "__kk_string_normalize_flat",
                        "String.normalize should link to __kk_string_normalize_flat"
                    )
                    #expect(
                        externalLink(for: "isNormalized", sema: sema, interner: interner) == "__kk_string_isNormalized_flat",
                        "String.isNormalized should link to __kk_string_isNormalized_flat"
                    )
        }

        do {
            // Originally testChunkedSequenceStubsHaveCorrectExternalLinks
                    let links = externalLinks(for: "chunkedSequence", sema: sema, interner: interner)
                    #expect(
                        links.isEmpty,
                        "CharSequence.chunkedSequence(size, transform) should be bundled Kotlin source"
                    )
                    #expect(
                        links.isEmpty,
                        "CharSequence.chunkedSequence should be bundled Kotlin source"
                    )
        }

        do {
            // Originally testNewNullableConversionStubsHaveCorrectExternalLinks
            // KSP-414: integer and boolean parse members are now bundled Kotlin source
            // (StringNumberParsing.kt) and bridge through private __kk_string_to* symbols.

            let sourceBackedMembers: [(member: String, parameterCount: Int)] = [
                ("toIntOrNull", 0),
                ("toIntOrNull", 1),
                ("toLong", 0),
                ("toLongOrNull", 0),
                ("toShort", 0),
                ("toShortOrNull", 0),
                ("toByte", 0),
                ("toByte", 1),
                ("toByteOrNull", 0),
                ("toUByteOrNull", 0),
                ("toUByteOrNull", 1),
                ("toUShortOrNull", 0),
                ("toUShortOrNull", 1),
                ("toUIntOrNull", 0),
                ("toUIntOrNull", 1),
                ("toULongOrNull", 0),
                ("toULongOrNull", 1),
                ("toBooleanStrict", 0),
                ("toBooleanStrictOrNull", 0),
            ]
            for item in sourceBackedMembers {
                #expect(
                    externalLink(for: item.member, receiverType: sema.types.stringType, parameterCount: item.parameterCount, sema: sema, interner: interner) == nil,
                    "String.\(item.member)/\(item.parameterCount) should be source-backed after KSP-414"
                )
            }

            // toBoolean has a nullable String receiver, so the generic receiverType match
            // does not apply; verify through externalLinks instead.
            let booleanLinks = externalLinks(for: "toBoolean", sema: sema, interner: interner)
            #expect(
                !booleanLinks.contains("kk_string_toBoolean") && !booleanLinks.contains("__kk_string_toBoolean"),
                "String?.toBoolean should be source-backed after KSP-414, got \(booleanLinks.sorted())"
            )

            let privateBridges = [
                "__kk_string_toIntOrNull",
                "__kk_string_toIntOrNull_radix",
                "__kk_string_toLong",
                "__kk_string_toLongOrNull",
                "__kk_string_toShort",
                "__kk_string_toShortOrNull",
                "__kk_string_toByte",
                "__kk_string_toByte_radix",
                "__kk_string_toByteOrNull",
                "__kk_string_toUByteOrNull",
                "__kk_string_toUByteOrNull_radix",
                "__kk_string_toUShortOrNull",
                "__kk_string_toUShortOrNull_radix",
                "__kk_string_toUIntOrNull",
                "__kk_string_toUIntOrNull_radix",
                "__kk_string_toULongOrNull",
                "__kk_string_toULongOrNull_radix",
                "__kk_string_toBoolean",
                "__kk_string_toBooleanStrict",
                "__kk_string_toBooleanStrictOrNull",
            ]
            for bridge in privateBridges {
                #expect(
                    externalLink(for: bridge, sema: sema, interner: interner) == bridge,
                    "\(bridge) private bridge should be registered"
                )
            }

            #expect(
                !externalLinks(for: "toDoubleOrNull", sema: sema, interner: interner)
                    .contains("__kk_string_toDoubleOrNull"),
                "String.toDoubleOrNull should be source-backed and not have a direct external link"
            )
            #expect(
                externalLink(for: "__kk_string_toDoubleOrNull", sema: sema, interner: interner) == "__kk_string_toDoubleOrNull"
            )
            #expect(
                externalLink(for: "__kk_string_toDouble", sema: sema, interner: interner) == "__kk_string_toDouble"
            )
            #expect(
                externalLink(for: "__kk_string_toFloat", sema: sema, interner: interner) == "__kk_string_toFloat"
            )
            #expect(
                externalLink(for: "__kk_string_toFloatOrNull", sema: sema, interner: interner) == "__kk_string_toFloatOrNull"
            )
            #expect(
                externalLink(for: "__kk_string_toBigDecimal", sema: sema, interner: interner) == "__kk_string_toBigDecimal"
            )
            #expect(
                externalLink(for: "__kk_string_toBigDecimalOrNull", sema: sema, interner: interner) == "__kk_string_toBigDecimalOrNull"
            )
        }

        do {
            // Originally testNewTransformStubsHaveCorrectExternalLinks
                    // repeat and reversed are now bundled Kotlin functions — no C external link.
                    let bundledMembers = ["repeat", "reversed"]
                    for member in bundledMembers {
                        let fq = ["kotlin", "text", member].map { interner.intern($0) }
                        #expect(
                            !sema.symbols.lookupAll(fqName: fq).isEmpty,
                            "String.\(member) should be registered as a bundled Kotlin symbol"
                        )
                        #expect(
                            externalLink(for: member, sema: sema, interner: interner) == nil,
                            "String.\(member) must not have a C external link after migration to Kotlin source"
                        )
                    }

                    let sourceBackedMembers = [
                        "toList", "toMutableList", "toCharArray", "toTypedArray",
                        "toCollection", "toSortedSet", "asIterable", "asSequence", "withIndex",
                    ]
                    for member in sourceBackedMembers {
                        #expect(
                            externalLink(for: member, sema: sema, interner: interner) == nil,
                            "String.\(member) must resolve to bundled Kotlin source"
                        )
                    }
        }

        do {
            // Originally testSourceBackedStringStubsHaveNoExternalLinks
                    // These bundled Kotlin source extensions should not have any C external link.
                    for member in ["padStart", "padEnd", "lines", "lineSequence"] {
                        let fq = ["kotlin", "text", member].map { interner.intern($0) }
                        let symbols = sema.symbols.lookupAll(fqName: fq)
                        #expect(!symbols.isEmpty, "String.\(member) should be registered as a bundled Kotlin symbol")
                        let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
                        #expect(links.isEmpty, "String.\(member) must not have C external links after migration to Kotlin source")
                    }
        }

        do {
                    // Originally testStringCollectionAndSequenceResultStubsUseFlatExternalLinks
                    // toByteArray / encodeToByteArray are bundled Kotlin source that bridge through
                    // private `__kk_string_*_flat` primitives, so the public members carry no link.
                    let sourceBacked: [(member: String, parameterCount: Int)] = [
                        ("toByteArray", 0),
                        ("toByteArray", 1),
                        ("toByteArray", 2),
                        ("encodeToByteArray", 0),
                        ("encodeToByteArray", 1),
                        ("encodeToByteArray", 2),
                    ]
                    for item in sourceBacked {
                        #expect(
                            externalLink(
                                for: item.member,
                                receiverType: sema.types.stringType,
                                parameterCount: item.parameterCount,
                                sema: sema,
                                interner: interner
                            ) == nil,
                            "String.\(item.member)/\(item.parameterCount) should be source-backed with no C external link"
                        )
                    }
        }

        do {
            // Originally testKSP401StringHelpersAreBundledKotlinMembers
                    for member in [
                        "isEmpty",
                        "isNotEmpty",
                        "isBlank",
                        "isNotBlank",
                        "isNullOrEmpty",
                        "isNullOrBlank",
                        "ifEmpty",
                        "ifBlank",
                        "orEmpty",
                        "lines",
                        "lineSequence",
                    ] {
                        let fq = ["kotlin", "text", member].map { interner.intern($0) }
                        let symbols = sema.symbols.lookupAll(fqName: fq)
                        #expect(!symbols.isEmpty, "kotlin.text.\(member) should be registered as a bundled Kotlin symbol")
                        let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
                        #expect(
                            links.isEmpty,
                            "kotlin.text.\(member) must not have C external links after KSP-401 migration, got \(links.sorted())"
                        )
                    }
        }

        do {
            // Originally testTakeDropMembersAreBundledKotlin
                    // KSP-405: take/takeLast/drop/dropLast are bundled Kotlin source
                    // (StringTakeDrop.kt) and carry no runtime link.
                    for member in ["take", "takeLast", "drop", "dropLast"] {
                        let links = externalLinks(for: member, sema: sema, interner: interner)
                        #expect(
                            !links.contains("kk_string_\(member)_flat") && !links.contains("kk_string_\(member)"),
                            "String.\(member) should be source-backed after KSP-405, got \(links.sorted())"
                        )
                    }
        }

        do {
            // Originally testStringHOFMembersAreBundledKotlin
                    // KSP-410: filter/filterNot/any/all/none/count/find/findLast/
                    // onEach/partition/sumBy/sumByDouble/filterIndexed/onEachIndexed/
                    // reduce family/fold family are bundled Kotlin source
                    // (StringHOF.kt) and carry no runtime link. map/mapIndexed are
                    // excluded (BUG-176 keeps them Swift-backed).
                    for member in [
                        "filter", "filterNot", "any", "all", "none", "count",
                        "find", "findLast", "onEach", "partition", "sumBy", "sumByDouble",
                        "filterIndexed", "onEachIndexed",
                        "reduce", "reduceOrNull", "reduceIndexed", "reduceIndexedOrNull",
                        "reduceRight", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull",
                        "fold", "foldIndexed", "foldRight", "foldRightIndexed",
                    ] {
                        let links = externalLinks(for: member, sema: sema, interner: interner)
                        #expect(
                            !links.contains("kk_string_\(member)_flat") && !links.contains("kk_string_\(member)"),
                            "String.\(member) should be source-backed after KSP-410, got \(links.sorted())"
                        )
                    }
        }

        do {
            // Originally testIfBlankStubIsBundledKotlin
                    #expect(
                        externalLink(for: "ifBlank", sema: sema, interner: interner) == nil,
                        "CharSequence.ifBlank should be bundled Kotlin without a C external link"
                    )
        }

        do {
            // Originally testIfEmptyStubIsBundledKotlin
                    #expect(
                        externalLink(for: "ifEmpty", sema: sema, interner: interner) == nil,
                        "CharSequence.ifEmpty should be bundled Kotlin without a C external link"
                    )
        }

        do {
            // Originally testChunkedSequenceStubHasCorrectExternalLink
                    let links = externalLinks(for: "chunkedSequence", sema: sema, interner: interner)
                    #expect(
                        links.isEmpty,
                        "CharSequence.chunkedSequence should be bundled Kotlin source, got \(links.sorted())"
                    )
                    #expect(
                        links.isEmpty,
                        "CharSequence.chunkedSequence(size, transform) should be bundled Kotlin source"
                    )
        }

        do {
            // Originally testWindowedSequenceStubHasCorrectExternalLink
                    let windowedLinks = externalLinks(for: "windowedSequence", sema: sema, interner: interner)
                    #expect(
                        windowedLinks.isEmpty,
                        "CharSequence.windowedSequence should be bundled Kotlin source, got \(windowedLinks.sorted())"
                    )
                    #expect(
                        windowedLinks.isEmpty,
                        "CharSequence.windowedSequence transform should be bundled Kotlin source"
                    )
        }

        do {
            // Originally testTrimMembersAreBundledKotlinFunctionsWithoutExternalLinks
                    for member in ["trim", "trimStart", "trimEnd"] {
                        #expect(
                            externalLinks(for: member, sema: sema, interner: interner).isEmpty,
                            "String.\(member) should be a bundled Kotlin function with no C external link"
                        )
                    }
        }
    }

    // MARK: - Path-aware expression search helpers

    private func allExprIDs(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard let range = ast.arena.exprRange(exprID), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func firstExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard let range = ast.arena.exprRange(exprID), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    // MARK: - testStringSyntheticMemberLinkCleanCallExpressions

    @Test
    func testStringSyntheticMemberLinkCleanCallExpressions() throws {

        let sources: [String] = [
            """
            package sample0

                    fun formatIndent(value: String): String {
                        val a = value.trimIndent()
                        val b = value.trimMargin()
                        val c = value.trimMargin("|")
                        val d = value.prependIndent()
                        val e = value.prependIndent(">")
                        val f = value.replaceIndent()
                        val g = value.replaceIndent(">")
                        val h = value.replaceIndentByMargin()
                        val i = value.replaceIndentByMargin(">")
                        val j = value.replaceIndentByMargin(">", "|")
                        return a + b + c + d + e + f + g + h + i + j
                    }

            """,
            """
            package sample1

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

            """,
            """
            package sample2

                    import kotlin.text.Typography

                    fun typographyMarks(): Char {
                        val nbsp: Char = Typography.nbsp
                        val ellipsis: Char = Typography.ellipsis
                        val guillemet: Char = Typography.leftGuillemet
                        val legacyGuillemet: Char = Typography.leftGuillemete
                        return Typography.greaterOrEqual
                    }

            """,
            """
            package sample3

                    fun caseInsensitiveComparator(): Comparator<String> {
                        return String.CASE_INSENSITIVE_ORDER
                    }

                    fun compareIgnoringCase(): Int {
                        return String.CASE_INSENSITIVE_ORDER.compare("alpha", "ALPHA")
                    }

                    fun sortIgnoringCase(values: List<String>): List<String> {
                        return values.sortedWith(String.CASE_INSENSITIVE_ORDER)
                    }

            """,
            """
            package sample4

                    import kotlin.text.StringBuilder

                    fun deleteOne(): StringBuilder {
                        return StringBuilder("abc").deleteAt(1)
                    }

                    fun deleteWithReceiver(): String {
                        return with(StringBuilder("rust")) {
                            deleteAt(1)
                            toString()
                        }
                    }

            """,
            """
            package sample5

                    import kotlin.text.StringBuilder

                    fun deleteMiddle(): StringBuilder {
                        return StringBuilder("abcdef").deleteRange(1, 4)
                    }

                    fun deleteWithReceiver(): String {
                        return with(StringBuilder("abcdef")) {
                            deleteRange(2, 5)
                            toString()
                        }
                    }

            """,
            """
            package sample6

                    import kotlin.text.StringBuilder

                    fun appendMiddle(): StringBuilder {
                        return StringBuilder("ab").appendRange("WXYZ", 1, 3)
                    }

                    fun appendWithReceiver(): String {
                        return with(StringBuilder("ab")) {
                            appendRange("WXYZ", 0, 2)
                            toString()
                        }
                    }

            """,
            """
            package sample7

                    import kotlin.text.StringBuilder

                    fun insertMiddle(): StringBuilder {
                        return StringBuilder("ac").insert(1, "b")
                    }

                    fun insertWithReceiver(): String {
                        return with(StringBuilder("ac")) {
                            insert(1, "b")
                            toString()
                        }
                    }

            """,
            """
            package sample8

                    import kotlin.text.StringBuilder

                    fun insertMiddle(): StringBuilder {
                        return StringBuilder("ab").insertRange(1, "WXYZ", 1, 3)
                    }

                    fun insertWithReceiver(): String {
                        return with(StringBuilder("ab")) {
                            insertRange(2, "WXYZ", 0, 2)
                            toString()
                        }
                    }

            """,
            """
            package sample9

                    import kotlin.text.StringBuilder

                    fun setMiddle(): StringBuilder {
                        return StringBuilder("abcd").setRange(1, 3, "XYZ")
                    }

                    fun setWithReceiver(): String {
                        return with(StringBuilder("abcd")) {
                            setRange(0, 2, "XY")
                            toString()
                        }
                    }

            """,
            """
            package sample10

                    import kotlin.text.StringBuilder

                    fun replaceChar(): StringBuilder {
                        val sb = StringBuilder("abc")
                        sb.set(1, 'X')
                        return sb
                    }

            """,
            """
            package sample11

                    fun firstLabel(value: CharSequence): String {
                        return value.firstNotNullOf<String> { ch -> if (ch == 'b') "bee" else null }
                    }

                    fun firstFromString(value: String): String {
                        return value.firstNotNullOf<String> { ch -> if (ch == 'c') "see" else null }
                    }

            """,
            """
            package sample12

                    fun firstLabel(value: CharSequence): String? {
                        return value.firstNotNullOfOrNull<String> { ch -> if (ch == 'b') "bee" else null }
                    }

                    fun firstFromString(value: String): String? {
                        return value.firstNotNullOfOrNull<String> { ch -> if (ch == 'c') "see" else null }
                    }

            """,
            """
            package sample13

                    fun reduceFromSequence(value: CharSequence): Char {
                        return value.reduceRightIndexed { index, ch, acc -> if (index == 1) ch else acc }
                    }

                    fun reduceFromString(value: String): Char {
                        return value.reduceRightIndexed { index, ch, acc -> if (index == 0) ch else acc }
                    }

            """,
            """
            package sample14

                    fun reduceFromSequence(value: CharSequence): Char? {
                        return value.reduceRightIndexedOrNull { index, ch, acc -> if (index == 1) ch else acc }
                    }

                    fun reduceFromString(value: String): Char? {
                        return value.reduceRightIndexedOrNull { index, ch, acc -> if (index == 0) ch else acc }
                    }

            """,
            """
            package sample15

                    fun reduceFromSequence(value: CharSequence): Char? {
                        return value.reduceRightOrNull { ch, acc -> if (ch == 'b') ch else acc }
                    }

                    fun reduceFromString(value: String): Char? {
                        return value.reduceRightOrNull { ch, acc -> if (ch == 'a') ch else acc }
                    }

            """,
            """
            package sample16

                    fun sumFromSequence(value: CharSequence): Int {
                        return value.sumBy { if (it == 'a') 10 else 1 }
                    }

                    fun sumFromString(value: String): Int {
                        return value.sumBy { ch -> if (ch == 'b') 20 else 2 }
                    }

            """,
            """
            package sample17

                    fun sumFromSequence(value: CharSequence): Double {
                        return value.sumByDouble { if (it == 'a') 1.5 else 0.25 }
                    }

                    fun sumFromString(value: String): Double {
                        return value.sumByDouble { ch -> if (ch == 'b') 2.0 else 0.5 }
                    }

            """,
            """
            package sample18

                    fun indexed(value: CharSequence) = value.withIndex()

            """,
            """
            package sample19

                    fun reduceFromSequence(value: CharSequence): Char? {
                        return value.reduceOrNull { acc, ch -> if (ch == 'b') ch else acc }
                    }
                    fun reduceFromString(value: String): Char? {
                        return value.reduceOrNull { acc, ch -> if (acc == 'a') acc else ch }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Expected string synthetic member call tests to type-check without diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === testStringIndentFormatMembersResolveAsSourceBackedCalls ===

            do {

                let samplePath = paths[0]

                #expect(!(ctx.diagnostics.hasError), "indent-format members should resolve: \(ctx.diagnostics.diagnostics)")
                let expectedCounts = [
                    "trimIndent": 1,
                    "trimMargin": 2,
                    "prependIndent": 2,
                    "replaceIndent": 2,
                    "replaceIndentByMargin": 3,
                ]
                for (memberName, expectedCount) in expectedCounts {
                    let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == memberName
                    }
                    #expect(callExprs.count == expectedCount)
                    for callExpr in callExprs {
                        let chosenCallee = try #require(
                            sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                            "Expected call binding for \(memberName)"
                        )
                        #expect(
                            sema.symbols.symbol(chosenCallee)?.declSite != nil,
                            "Expected String.\(memberName) to be backed by bundled Kotlin source"
                        )
                        #expect(
                            sema.symbols.externalLinkName(for: chosenCallee) == nil,
                            "Expected String.\(memberName) to have no C external link"
                        )
                    }
                }

            }

            // === testAppendableInterfaceSurfaceResolves ===

            do {

                let samplePath = paths[1]

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected Appendable surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let appendableFQName = ["kotlin", "text", "Appendable"].map { interner.intern($0) }
                let appendableSymbol = try #require(sema.symbols.lookup(fqName: appendableFQName))
                #expect(sema.symbols.symbol(appendableSymbol)?.kind == .interface)

                let appendableType = sema.types.make(.classType(ClassType(
                    classSymbol: appendableSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                // Filter to only user code's append calls on Appendable receiver
                // (bundled stdlib also has StringBuilder.append calls)
                let allAppendCalls = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "append"
                }
                let appendCalls = allAppendCalls.filter { callExpr in
                    guard let binding = sema.bindings.callBinding(for: callExpr),
                          let signature = sema.symbols.functionSignature(for: binding.chosenCallee)
                    else { return false }
                    return signature.receiverType == appendableType
                }
                #expect(appendCalls.count == 3)
                for callExpr in appendCalls {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected Appendable.append call binding"
                    )
                    let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                    #expect(signature.receiverType == appendableType)
                    let symbolInfo = try #require(sema.symbols.symbol(chosenCallee))
                    #expect(symbolInfo.declSite != nil)
                    #expect(!symbolInfo.flags.contains(.synthetic))
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) != nil,
                        "Appendable.append must retain its private runtime dispatch bridge"
                    )
                }

            }

            // === testTypographyObjectSurfaceResolves ===

            do {

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected Typography surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let typographyFQName = ["kotlin", "text", "Typography"].map { interner.intern($0) }
                let typographySymbol = try #require(sema.symbols.lookup(fqName: typographyFQName))
                let typographyInfo = try #require(sema.symbols.symbol(typographySymbol))
                #expect(typographyInfo.kind == .object)
                #expect(typographyInfo.declSite != nil)
                #expect(!typographyInfo.flags.contains(.synthetic))

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
                    let propertyFQName = typographyFQName + [interner.intern(name)]
                    let propertySymbol = try #require(sema.symbols.lookup(fqName: propertyFQName))
                    let propertyInfo = try #require(sema.symbols.symbol(propertySymbol))
                    #expect(propertyInfo.declSite != nil)
                    #expect(!propertyInfo.flags.contains(.synthetic))
                    #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.make(.primitive(.char, .nonNull)))
                    #expect(sema.symbols.symbol(propertySymbol)?.flags.contains(.constValue) ?? false)
                    guard case let .charLiteral(value) = sema.symbols.constValueExprKind(for: propertySymbol) else {
                        Issue.record("Expected Typography.\(name) to carry a char literal constant")
                        continue
                    }
                    #expect(value == scalar, "Unexpected Typography.\(name) scalar")
                }

            }

            // === testStringByteConstructorsAreSourceBacked ===

            do {
                let constructorFQName = ["kotlin", "String"].map { interner.intern($0) }
                // KSP-711's byte-decoding overloads all take a `bytes` parameter; the
                // unrelated no-arg `String(): String = ""` factory (KSP-... empty String
                // factory) resolves to the same FQ name but isn't one of them.
                let constructorFunctions = sema.symbols.lookupAll(fqName: constructorFQName).filter {
                    sema.symbols.symbol($0)?.kind == .function
                        && !(sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty ?? true)
                }
                #expect(constructorFunctions.count == 4)
                for constructor in constructorFunctions {
                    let info = try #require(sema.symbols.symbol(constructor))
                    #expect(info.declSite != nil)
                    #expect(!info.flags.contains(.synthetic))
                    #expect(
                        sema.symbols.externalLinkName(for: constructor) != nil,
                        "String byte constructors must route through private runtime decoding bridges"
                    )
                }
                #expect(constructorFunctions.filter { sema.symbols.symbol($0)?.visibility == .public }.count == 2)
                #expect(constructorFunctions.filter { sema.symbols.symbol($0)?.visibility == .internal }.count == 2)

                let legacyConstructors = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("String"),
                    interner.intern("<init>"),
                ]).filter { sema.symbols.symbol($0)?.kind == .constructor }
                #expect(legacyConstructors.isEmpty)
            }

            // === testCaseInsensitiveOrderSurfaceResolves ===

            do {

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected String.CASE_INSENSITIVE_ORDER surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                // The property lives on String's companion object, not top-level kotlin.text.
                let companionPropertyFQName = ["kotlin", "String", "Companion", "CASE_INSENSITIVE_ORDER"]
                    .map { interner.intern($0) }
                let propertySymbol = try #require(sema.symbols.lookup(fqName: companionPropertyFQName))
                #expect(
                    sema.symbols.externalLinkName(for: propertySymbol) == "kk_string_case_insensitive_order"
                )
                let parentSymbol = try #require(sema.symbols.parentSymbol(for: propertySymbol))
                #expect(sema.symbols.symbol(parentSymbol)?.kind == .object)

                // The buggy top-level kotlin.text.CASE_INSENSITIVE_ORDER must not exist.
                let topLevelFQName = ["kotlin", "text", "CASE_INSENSITIVE_ORDER"].map { interner.intern($0) }
                #expect(sema.symbols.lookup(fqName: topLevelFQName) == nil)

                let comparatorFQName = ["kotlin", "Comparator"].map { interner.intern($0) }
                let comparatorSymbol = try #require(sema.symbols.lookup(fqName: comparatorFQName))
                let expectedType = sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(sema.types.stringType)],
                    nullability: .nonNull
                )))
                #expect(sema.symbols.propertyType(for: propertySymbol) == expectedType)

            }

            // === testStringBuilderDeleteAtResolvesInCallExpressions ===

            do {

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected StringBuilder.deleteAt surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let interner = interner
                let deleteAtSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("StringBuilder"),
                    interner.intern("deleteAt"),
                ])
                #expect(deleteAtSymbols.count == 1)
                #expect(deleteAtSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })

            }

            // === testStringBuilderDeleteRangeResolvesInCallExpressions ===

            do {

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected StringBuilder.deleteRange surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let interner = interner
                let deleteRangeSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("StringBuilder"),
                    interner.intern("deleteRange"),
                ])
                #expect(deleteRangeSymbols.count == 1)
                #expect(deleteRangeSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })

            }

            // === testStringBuilderAppendRangeResolvesInCallExpressions ===

            do {

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected StringBuilder.appendRange surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let interner = interner
                let appendRangeSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("StringBuilder"),
                    interner.intern("appendRange"),
                ])
                #expect(appendRangeSymbols.count == 2)
                #expect(appendRangeSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })

            }

            // === testStringBuilderInsertResolvesInCallExpressions ===

            do {

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected StringBuilder.insert surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let interner = interner
                let insertSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("StringBuilder"),
                    interner.intern("insert"),
                ])
                #expect(insertSymbols.count >= 1)
                #expect(insertSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })

            }

            // === testStringBuilderInsertRangeResolvesInCallExpressions ===

            do {

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected StringBuilder.insertRange surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let interner = interner
                let insertRangeSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("StringBuilder"),
                    interner.intern("insertRange"),
                ])
                #expect(insertRangeSymbols.count == 2)
                #expect(insertRangeSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })

            }

            // === testStringBuilderSetRangeResolvesInCallExpressions ===

            do {

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected StringBuilder.setRange surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let interner = interner
                let setRangeSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("StringBuilder"),
                    interner.intern("setRange"),
                ])
                #expect(setRangeSymbols.count == 1)
                #expect(setRangeSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })

            }

            // === testStringBuilderSetOperatorResolvesToSetCharAt ===

            do {

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected StringBuilder.set operator to resolve cleanly, got: \(diagnosticSummary)"
                )

                let interner = interner
                let setSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("StringBuilder"),
                    interner.intern("set"),
                ])
                #expect(setSymbols.count == 1)
                #expect(setSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })

            }

            // === testCharSequenceFirstNotNullOfResolvesInCallExpressions ===

            do {

                let samplePath = paths[11]

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected CharSequence.firstNotNullOf surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let callIDs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "firstNotNullOf"
                }
                #expect(callIDs.count == 2, "Expected two String.firstNotNullOf call sites")
                let firstNotNullOfBindings = callIDs.compactMap { sema.bindings.callBindings[$0] }
                #expect(firstNotNullOfBindings.count == 2)

            }

            // === testCharSequenceFirstNotNullOfOrNullResolvesInCallExpressions ===

            do {

                let samplePath = paths[12]

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected CharSequence.firstNotNullOfOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let callIDs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "firstNotNullOfOrNull"
                }
                #expect(callIDs.count == 2, "Expected two String.firstNotNullOfOrNull call sites")
                let bindings = callIDs.compactMap { sema.bindings.callBindings[$0] }
                #expect(bindings.count == 2)

            }

            // === testCharSequenceReduceRightIndexedResolvesInCallExpressions ===

            do {

                let samplePath = paths[13]

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected CharSequence.reduceRightIndexed surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let callIDs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "reduceRightIndexed"
                }
                #expect(callIDs.count == 2, "Expected two String.reduceRightIndexed call sites")
                let bindings = callIDs.compactMap { sema.bindings.callBindings[$0] }
                #expect(bindings.count == 2)

            }

            // === testCharSequenceReduceRightIndexedOrNullResolvesInCallExpressions ===

            do {

                let samplePath = paths[14]

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected CharSequence.reduceRightIndexedOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let callIDs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "reduceRightIndexedOrNull"
                }
                #expect(callIDs.count == 2, "Expected two String.reduceRightIndexedOrNull call sites")
                let bindings = callIDs.compactMap { sema.bindings.callBindings[$0] }
                #expect(bindings.count == 2)

            }

            // === testCharSequenceReduceRightOrNullResolvesInCallExpressions ===

            do {

                let samplePath = paths[15]

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected CharSequence.reduceRightOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let callIDs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "reduceRightOrNull"
                }
                #expect(callIDs.count == 2, "Expected two String.reduceRightOrNull call sites")
                let bindings = callIDs.compactMap { sema.bindings.callBindings[$0] }
                #expect(bindings.count == 2)

            }

            // === testCharSequenceSumByResolvesInCallExpressions ===

            do {

                let samplePath = paths[16]

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected CharSequence.sumBy surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let callIDs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "sumBy"
                }
                #expect(callIDs.count == 2, "Expected two String.sumBy call sites")
                let bindings = callIDs.compactMap { sema.bindings.callBindings[$0] }
                #expect(bindings.count == 2)
                let sumBySymbol = try #require(bindings.first?.chosenCallee)
                #expect(
                    sema.symbols.annotations(for: sumBySymbol).contains { KnownCompilerAnnotation.deprecated.matches($0.annotationFQName) },
                    "CharSequence.sumBy should carry Deprecated metadata"
                )

            }

            // === testCharSequenceSumByDoubleResolvesInCallExpressions ===

            do {

                let samplePath = paths[17]

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected CharSequence.sumByDouble surface to resolve cleanly, got: \(diagnosticSummary)"
                )

                let callIDs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "sumByDouble"
                }
                #expect(callIDs.count == 2, "Expected two String.sumByDouble call sites")
                let bindings = callIDs.compactMap { sema.bindings.callBindings[$0] }
                #expect(bindings.count == 2)
                let sumByDoubleSymbol = try #require(bindings.first?.chosenCallee)
                #expect(
                    sema.symbols.annotations(for: sumByDoubleSymbol).contains { KnownCompilerAnnotation.deprecated.matches($0.annotationFQName) },
                    "CharSequence.sumByDouble should carry Deprecated metadata"
                )

            }

            // === testCharSequenceWithIndexResolvesInCallExpressions ===

            do {

                #expect(
                    !ctx.diagnostics.hasError,
                    "Expected CharSequence.withIndex to resolve cleanly, got: \(ctx.diagnostics.diagnostics)"
                )

                let callExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, _) = expr,
                          interner.resolve(callee) == "withIndex"
                    else {
                        return nil
                    }
                    return exprID
                }

                let chosenCalleeCandidate = callExprIDs.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }.first
                let chosenCallee = try #require(chosenCalleeCandidate)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)

            }

            // === testCharSequenceReduceOrNullResolvesInCallExpressions ===

            do {

                let samplePath = paths[19]

                let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
                #expect(
                    !(ctx.diagnostics.hasError),
                    "Expected CharSequence.reduceOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
                )
                let callIDs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "reduceOrNull"
                }
                #expect(callIDs.count == 2, "Expected two String.reduceOrNull call sites")
                let bindings = callIDs.compactMap { sema.bindings.callBindings[$0] }
                #expect(bindings.count == 2)

            }

        }
    }

    // MARK: - testStringSyntheticMemberLinkErrorCallExpressions

    @Test
    func testStringSyntheticMemberLinkErrorCallExpressions() throws {

        let sources: [String] = [
            """
            package sample0

                    fun trimEdges(s: String): String {
                        val a = s.trim()
                        val b = s.trimStart()
                        val c = s.trimEnd()
                        val d = s.trim { it == 'x' }
                        val e = s.trimStart { it == 'x' }
                        val f = s.trimEnd { it == 'x' }
                        return a + b + c + d + e + f
                    }

            """,
            """
            package sample1

                    fun process(s: String): String {
                        val lower = s.lowercase()
                        val upper = s.uppercase()
                        val cap = s.capitalize()
                        val rep = s.repeat(3)
                        val rev = s.reversed()
                        val first = s.replaceFirstChar { it.uppercase() }
                        return lower + upper + cap + rep + rev + first
                    }

            """,
            """
            package sample2

                    fun normalizeText(s: String): String {
                        val normalized = s.normalize(NormalizationForms.NFC)
                        let stable = normalized.isNormalized(NormalizationForms.NFC)
                        return if (stable) normalized else s
                    }

            """,
            """
            package sample3

                    fun chunks(value: CharSequence): Sequence<String> {
                        return value.chunkedSequence(2)
                    }

                    fun stringChunks(value: String): Sequence<String> {
                        return value.chunkedSequence(3)
                    }

            """,
            """
            package sample4

                    fun chunks(value: CharSequence): Sequence<String> {
                        return value.chunkedSequence(2) { chunk -> "" + chunk + "!" }
                    }

                    fun stringChunks(value: String): Sequence<String> {
                        return value.chunkedSequence(3) { "" + it }
                    }

            """,
            """
            package sample5

                    fun windows(value: CharSequence): Sequence<String> {
                        return value.windowedSequence(3, 2, true)
                    }

                    fun stringWindows(value: String): Sequence<String> {
                        return value.windowedSequence(2, 1, false)
                    }

            """,
            """
            package sample6

                    fun windows(value: CharSequence): Sequence<Int> {
                        return value.windowedSequence(3, 2, true) { it.length }
                    }

                    fun stringWindows(value: String): Sequence<String> {
                        return value.windowedSequence(size = 2, step = 1, partialWindows = false) { window -> "" + window }
                    }

            """,
            """
            package sample7

                    fun chunkLengths(value: CharSequence): List<Int> {
                        return value.chunked(3) { it.length }
                    }

                    fun stringChunkLengths(value: String): List<Int> {
                        return value.chunked(3) { it.length }
                    }

            """,
            """
            package sample8

                    fun windowLengths(value: CharSequence): List<Int> {
                        return value.windowed(3, 2, true) { it.length }
                    }

                    fun stringWindowLengths(value: String): List<Int> {
                        return value.windowed(size = 3, step = 2, partialWindows = true) { window -> window.length }
                    }

            """,
            """
            package sample9

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

            """,
            """
            package sample10

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

            """,
            """
            package sample11

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

            """,
            """
            package sample12

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

            """,
            """
            package sample13

                    import kotlin.text.CASE_INSENSITIVE_ORDER

                    fun caseInsensitiveComparator(): Comparator<String> {
                        return CASE_INSENSITIVE_ORDER
                    }

            """,
            """
            package sample14

                    fun pairs(value: CharSequence): List<Pair<Char, Char>> {
                        return value.zipWithNext()
                    }

                    fun labels(value: CharSequence): List<String> {
                        return value.zipWithNext { a, b -> "" + a + b }
                    }

            """,
            """
            package sample15

                    fun decode(bytes: ByteArray): String {
                        val sliced = bytes.decodeToString(1, 4)
                        val strict = bytes.decodeToString(0, 4, true)
                        return sliced + strict
                    }

            """,
            """
            package sample16

                    fun pairs(value: CharSequence, other: CharSequence): List<Pair<Char, Char>> {
                        return value.zip(other)
                    }

                    fun labels(value: CharSequence, other: CharSequence): List<String> {
                        return value.zip(other) { a, b -> "" + a + b }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === testTrimMembersResolveInCallExpressionsWithoutExternalLinks ===

            do {

                let samplePath = paths[0]

                for memberName in ["trim", "trimStart", "trimEnd"] {
                    let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == memberName
                    }
                    #expect(!callExprs.isEmpty, "Expected member call to \(memberName) in AST")
                    for callExpr in callExprs {
                        let chosenCallee = try #require(
                            sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                            "Expected call binding for \(memberName)"
                        )
                        #expect(
                            sema.symbols.externalLinkName(for: chosenCallee) == nil,
                            "Expected \(memberName) overload to resolve to bundled Kotlin source"
                        )
                    }
                }

            }

            // === testNewStringMembersResolveInCallExpressions ===

            do {

                let samplePath = paths[1]

                // lowercase, uppercase, capitalize, replaceFirstChar, repeat, reversed are now all
                // bundled Kotlin functions (MIGRATION-TEXT-005) — no C external link.
                // Use allExprIDs and filter by String receiver to avoid picking up internal
                // Char.lowercase/Char.uppercase calls that the bundled implementations use.
                for memberName in ["lowercase", "uppercase", "capitalize", "replaceFirstChar", "repeat", "reversed"] {
                    // Find a call that resolves to a callee with String receiver type.
                    let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == memberName
                    }
                    let stringReceiverCallee = callExprs.compactMap { callExpr -> SymbolID? in
                        guard let binding = sema.bindings.callBinding(for: callExpr) else { return nil }
                        let sig = sema.symbols.functionSignature(for: binding.chosenCallee)
                        guard sig?.receiverType == sema.types.stringType else { return nil }
                        return binding.chosenCallee
                    }.first
                    let chosenCallee = try #require(
                        stringReceiverCallee,
                        "Expected a call to String.\(memberName) in AST"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "Expected String.\(memberName) to be a bundled Kotlin function with no C external link"
                    )
                }

            }

            // === testStringNormalizationMembersResolveInCallExpressions ===

            do {

                let samplePath = paths[2]

                let expectedLinks: [String: String] = [
                    "normalize": "__kk_string_normalize_flat",
                    "isNormalized": "__kk_string_isNormalized_flat",
                ]

                for (memberName, externalLinkName) in expectedLinks {
                    let callExpr = try #require(firstExprID(in: ast, path: samplePath, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == memberName
                    }, "Expected member call to \(memberName) in AST")
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for \(memberName)"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName,
                        "Expected \(memberName) to resolve to \(externalLinkName)"
                    )
                }

            }

            // === testChunkedSequenceResolvesInCallExpressions ===

            do {

                let samplePath = paths[3]

                let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "chunkedSequence"
                }
                #expect(callExprs.count == 2)
                for callExpr in callExprs {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for chunkedSequence"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "Expected chunkedSequence to resolve to bundled Kotlin source"
                    )
                }

            }

            // === testChunkedSequenceTransformResolvesInCallExpressions ===

            do {

                let samplePath = paths[4]

                let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "chunkedSequence"
                }
                #expect(callExprs.count == 2)
                for callExpr in callExprs {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for chunkedSequence"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "Expected chunkedSequence transform to resolve to bundled Kotlin source"
                    )
                }

            }

            // === testWindowedSequenceResolvesInCallExpressions ===

            do {

                let samplePath = paths[5]

                let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "windowedSequence"
                }
                #expect(callExprs.count == 2)
                for callExpr in callExprs {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for windowedSequence"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "Expected windowedSequence to resolve to bundled Kotlin source"
                    )
                }

            }

            // === testWindowedSequenceTransformResolvesInCallExpressions ===

            do {

                let samplePath = paths[6]

                let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "windowedSequence"
                }
                #expect(callExprs.count == 2)
                for callExpr in callExprs {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for windowedSequence"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "Expected windowedSequence transform to resolve to bundled Kotlin source"
                    )
                }

            }

            // === testChunkedTransformResolvesInCallExpressions ===

            do {

                let samplePath = paths[7]

                let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "chunked"
                }
                #expect(callExprs.count == 2)
                for callExpr in callExprs {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for chunked"
                    )
                    #expect(
                        sema.symbols.symbol(chosenCallee)?.declSite != nil,
                        "Expected chunked(size, transform) to resolve to bundled Kotlin source"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "Expected chunked(size, transform) to have no C external link"
                    )
                }

            }

            // === testWindowedTransformResolvesInCallExpressions ===

            do {

                let samplePath = paths[8]

                let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "windowed"
                }
                #expect(callExprs.count == 2)
                for callExpr in callExprs {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for windowed"
                    )
                    #expect(
                        sema.symbols.symbol(chosenCallee)?.declSite != nil,
                        "Expected windowed(size, step, partialWindows, transform) to resolve to bundled Kotlin source"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "Expected windowed(size, step, partialWindows, transform) to have no C external link"
                    )
                }

            }

            // === testReplaceAfterResolvesInCallExpressions ===

            do {

                let samplePath = paths[9]

                let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "replaceAfter"
                }
                #expect(callExprs.count == 4)
                for callExpr in callExprs {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for replaceAfter"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "Expected replaceAfter to resolve to bundled Kotlin source with no C external link"
                    )
                }

            }

            // === testReplaceAfterLastResolvesInCallExpressions ===

            do {

                let samplePath = paths[10]

                let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "replaceAfterLast"
                }
                #expect(callExprs.count == 4)
                for callExpr in callExprs {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for replaceAfterLast"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "Expected replaceAfterLast to resolve to bundled Kotlin source with no C external link"
                    )
                }

            }

            // === testReplaceBeforeResolvesInCallExpressions ===

            do {

                let samplePath = paths[11]

                let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "replaceBefore"
                }
                #expect(callExprs.count == 4)
                for callExpr in callExprs {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for replaceBefore"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "Expected replaceBefore to resolve to bundled Kotlin source with no C external link"
                    )
                }

            }

            // === testReplaceBeforeLastResolvesInCallExpressions ===

            do {

                let samplePath = paths[12]

                let callExprs = allExprIDs(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "replaceBeforeLast"
                }
                #expect(callExprs.count == 4)
                for callExpr in callExprs {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for replaceBeforeLast"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "Expected replaceBeforeLast to resolve to bundled Kotlin source with no C external link"
                    )
                }

            }

            // === testTopLevelCaseInsensitiveOrderIsUnresolved ===

            do {

                #expect(
                    ctx.diagnostics.hasError,
                    "Expected bare top-level CASE_INSENSITIVE_ORDER to be rejected (no such top-level symbol in Kotlin)"
                )

            }

            // === testCharSequenceZipWithNextMembersResolveInCallExpressions ===

            do {

                var externalLinks: [String] = []
                for index in ast.arena.exprs.indices {
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, _) = expr,
                          interner.resolve(callee) == "zipWithNext",
                          let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                          let link = sema.symbols.externalLinkName(for: chosenCallee)
                    else {
                        continue
                    }
                    externalLinks.append(link)
                }

                #expect(
                    externalLinks.isEmpty
                )

            }

            // === testByteArrayDecodeToStringRangeMembersResolveInCallExpressions ===

            do {

                let callExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, _) = expr,
                          interner.resolve(callee) == "decodeToString"
                    else {
                        return nil
                    }
                    return exprID
                }
                // 2 user calls, plus 1 in bundled Base64.kt's decode(ByteArray)
                // overload (`source.decodeToString()`, KSP-482).
                #expect(callExprIDs.count == 3, "Expected two decodeToString range calls plus the bundled Base64 call")

                // After MIGRATION-TEXT-007, ByteArray.decodeToString range/range+throw variants are
                // defined in BundledStdlib Kotlin source (not synthetic stubs), so they have
                // no externalLinkName. The C bridge is called internally via __kk_decodeToString_range.
                for (index, callExprID) in callExprIDs.enumerated() {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExprID)?.chosenCallee,
                        "Expected call binding for decodeToString overload \(index)"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == nil,
                        "kotlin.text.decodeToString range overload \(index) should resolve to Kotlin-source (no externalLinkName after migration)"
                    )
                }

            }

            // === testCharSequenceZipMembersResolveInCallExpressions ===

            do {

                var externalLinks: [String] = []
                for index in ast.arena.exprs.indices {
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, _) = expr,
                          interner.resolve(callee) == "zip",
                          let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                          let link = sema.symbols.externalLinkName(for: chosenCallee)
                    else {
                        continue
                    }
                    externalLinks.append(link)
                }

                #expect(
                    externalLinks.isEmpty
                )

            }

        }
    }

}
