extension DataFlowSemaPhase {
    func registerSyntheticStringQueryStubs(context: SyntheticStringStubContext) -> TypeID {
        let (symbols, types, interner, kotlinTextPkg) = (context.symbols, context.types, context.interner, context.kotlinTextPkg); let (stringType, boolType, intType, charType) = (context.stringType, context.boolType, context.intType, context.charType); let (nullableCharType, listStringType) = (context.nullableCharType, context.listStringType)
        // --- STDLIB-192: equals(other) ---
        // KSP-413: equals(other, ignoreCase) is bundled Kotlin source
        // (Stdlib/kotlin/text/StringComparison.kt).
        let nullableStringType = types.make(.stringStruct(.nullable))
        registerSyntheticStringExtensionFunction(
            named: "equals",
            externalLinkName: "kk_string_equals_flat",
            receiverType: stringType,
            parameters: [
                ("other", nullableStringType, false, false),
            ],
            returnType: boolType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        // KSP-406: replaceRange/removeRange/slice are bundled Kotlin source
        // (Stdlib/kotlin/text/StringSubstringSlice.kt).
        let sequenceStringType = makeSequenceType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: stringType
        )

        // RF-STDLIB-005: Kotlin source in StringSplitJoin.kt owns the public
        // split/joinToString surface. These __kk_* bridge stubs are only called
        // from that source and lower to private runtime ABI aliases.
        registerSyntheticStringExtensionFunction(
            named: "__kk_string_split",
            externalLinkName: "__kk_string_split",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "__kk_string_split_limit",
            externalLinkName: "__kk_string_split_limit",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
                ("ignoreCase", boolType, false, false),
                ("limit", intType, false, false),
            ],
            returnType: listStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "__kk_string_splitToSequence",
            externalLinkName: "__kk_string_splitToSequence",
            receiverType: stringType,
            parameters: [
                ("delimiter", stringType, false, false),
            ],
            returnType: sequenceStringType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        // KSP-402: Public String query APIs are bundled Kotlin wrappers. These
        // private bridges keep UTF-16 string indexing semantics in the runtime.
        registerSyntheticStringExtensionFunction(
            named: "__kk_string_first",
            externalLinkName: "kk_string_first_flat",
            receiverType: stringType,
            parameters: [],
            returnType: charType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "__kk_string_last",
            externalLinkName: "kk_string_last_flat",
            receiverType: stringType,
            parameters: [],
            returnType: charType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "__kk_string_single",
            externalLinkName: "kk_string_single_flat",
            receiverType: stringType,
            parameters: [],
            returnType: charType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "__kk_string_firstOrNull",
            externalLinkName: "kk_string_firstOrNull_flat",
            receiverType: stringType,
            parameters: [],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "__kk_string_lastOrNull",
            externalLinkName: "kk_string_lastOrNull_flat",
            receiverType: stringType,
            parameters: [],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "__kk_string_singleOrNull",
            externalLinkName: "kk_string_singleOrNull_flat",
            receiverType: stringType,
            parameters: [],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticStringExtensionFunction(
            named: "__kk_string_getOrNull",
            externalLinkName: "kk_string_getOrNull_flat",
            receiverType: stringType,
            parameters: [
                ("index", intType, false, false),
            ],
            returnType: nullableCharType,
            packageFQName: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )

        // KSP-410: map/mapIndexed/mapNotNull/firstNotNullOf(OrNull),
        // filterIndexed/onEachIndexed and the whole reduce/fold family are
        // bundled Kotlin source (StringHOF.kt); no synthetic stub registration.

        // KSP-405: takeWhile/takeLastWhile/dropWhile are bundled Kotlin source
        // (StringTakeDrop.kt).
        // KSP-408: String/CharSequence.indexOfFirst / indexOfLast are bundled Kotlin
        // source (StringIndexOf.kt).
        // KSP-410: onEach/onEachIndexed/find/findLast are bundled Kotlin source
        // (StringHOF.kt).

        // --- STDLIB-315: String.replaceFirstChar — migrated to BundledStdlib (MIGRATION-TEXT-005) ---

        // --- STDLIB-142 / STDLIB-TEXT-FN-087 ---
        // `toBoolean` is bundled Kotlin source after KSP-414.

        // KSP-401: lines/lineSequence are bundled Kotlin source.

        return nullableStringType
    }
}
