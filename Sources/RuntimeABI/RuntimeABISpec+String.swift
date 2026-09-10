// swiftlint:disable file_length

/// `RuntimeABISpec.stringFunctions` extracted from `RuntimeABISpec.swift`.
///
/// Mirrors the existing per-section split convention used elsewhere in
/// `Sources/RuntimeABI/` (`+Collection.swift`, `+Sequence.swift`, etc.).
public extension RuntimeABISpec {
    static let stringFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_string_from_utf8",
            parameters: [
                RuntimeABIParameter(name: "ptr", type: .constUInt8Pointer),
                RuntimeABIParameter(name: "len", type: .int32),
            ],
            returnType: .opaquePointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_from_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_to_flat",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_concat_flat",
            parameters: [
                RuntimeABIParameter(name: "lhsData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "lhsLength", type: .intptr),
                RuntimeABIParameter(name: "lhsByteCount", type: .intptr),
                RuntimeABIParameter(name: "lhsHash", type: .intptr),
                RuntimeABIParameter(name: "rhsData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "rhsLength", type: .intptr),
                RuntimeABIParameter(name: "rhsByteCount", type: .intptr),
                RuntimeABIParameter(name: "rhsHash", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trim_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimStart_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimEnd_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lowercase_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_uppercase_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_reversed_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replace_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "oldData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "oldLength", type: .intptr),
                RuntimeABIParameter(name: "oldByteCount", type: .intptr),
                RuntimeABIParameter(name: "oldHash", type: .intptr),
                RuntimeABIParameter(name: "newData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "newLength", type: .intptr),
                RuntimeABIParameter(name: "newByteCount", type: .intptr),
                RuntimeABIParameter(name: "newHash", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        flatStringReturnSpec(
            name: "kk_string_replaceFirst_flat",
            trailingStringPrefixes: ["old", "new"]
        ),
        // KSP-406: substring/subSequence/removeRange/replaceRange flat entries removed;
        // now bundled Kotlin source (StringSubstringSlice.kt).
        RuntimeABIFunctionSpec(
            name: "kk_string_padStart_default_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "lengthRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_padEnd_default_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "lengthRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_padStart_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "lengthRaw", type: .intptr),
                RuntimeABIParameter(name: "padCharRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_padEnd_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "lengthRaw", type: .intptr),
                RuntimeABIParameter(name: "padCharRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_repeat_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "countRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        // KSP-407: substringBefore/After/BeforeLast/AfterLast and
        // replaceBefore/After/BeforeLast/AfterLast are bundled Kotlin source
        // (StringSearchReplace.kt); their flat ABI entries were removed.
        // KSP-405: take/takeLast/drop/dropLast are bundled Kotlin source
        // (StringTakeDrop.kt); their flat ABI entries were removed.
        RuntimeABIFunctionSpec(
            name: "kk_string_compareTo_flat",
            parameters: [
                RuntimeABIParameter(name: "lhsData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "lhsLength", type: .intptr),
                RuntimeABIParameter(name: "lhsByteCount", type: .intptr),
                RuntimeABIParameter(name: "lhsHash", type: .intptr),
                RuntimeABIParameter(name: "rhsData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "rhsLength", type: .intptr),
                RuntimeABIParameter(name: "rhsByteCount", type: .intptr),
                RuntimeABIParameter(name: "rhsHash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // KSP-404: kk_string_startsWith_flat / kk_string_endsWith_flat removed;
        // startsWith/endsWith are bundled Kotlin source (StringPrefixSuffix.kt).
        // KSP-408: kk_string_contains_str_flat / kk_string_contains_ignoreCase_flat /
        // kk_string_indexOf_flat / kk_string_indexOf_from_flat /
        // kk_string_lastIndexOf_flat / kk_string_indexOf_ignoreCase_flat /
        // kk_string_indexOf_char_flat / kk_string_lastIndexOf_ignoreCase_flat /
        // kk_string_lastIndexOf_char_flat removed; contains/indexOf/lastIndexOf are
        // bundled Kotlin source (StringIndexOf.kt).
        // KSP-413: kk_string_compareToIgnoreCase_flat / kk_string_equalsIgnoreCase_flat /
        // kk_string_contentEquals_flat / kk_string_contentEquals_ignoreCase_flat removed;
        // compareTo(ignoreCase) / equals(ignoreCase) / contentEquals are bundled Kotlin
        // source (StringComparison.kt).
        RuntimeABIFunctionSpec(
            name: "kk_string_equals_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "otherData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "otherLength", type: .intptr),
                RuntimeABIParameter(name: "otherByteCount", type: .intptr),
                RuntimeABIParameter(name: "otherHash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isEmpty_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNotEmpty_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isBlank_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNotBlank_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNullOrEmpty_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNullOrBlank_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_first_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_last_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_single_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_firstOrNull_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lastOrNull_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_singleOrNull_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_getOrNull_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // KSP-408: kk_string_indexOfFirst_flat / kk_string_indexOfLast_flat removed;
        // indexOfFirst/indexOfLast are bundled Kotlin source (StringIndexOf.kt).
        // KSP-410: kk_string_count_flat / kk_string_any_flat / kk_string_all_flat /
        // kk_string_none_flat removed; count/any/all/none are bundled Kotlin source
        // (StringHOF.kt).
        RuntimeABIFunctionSpec(
            name: "kk_compare_any",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_sequence_length",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_sequence_get",
            parameters: [
                RuntimeABIParameter(name: "sequenceRaw", type: .intptr),
                RuntimeABIParameter(name: "indexRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        flatStringHOFReturnSpec(name: "kk_string_trim_predicate_flat"),
        RuntimeABIFunctionSpec(
            name: "kk_string_lowercase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_uppercase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_new_flat",
            parameters: [
                RuntimeABIParameter(name: "identifierData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "identifierLength", type: .intptr),
                RuntimeABIParameter(name: "identifierByteCount", type: .intptr),
                RuntimeABIParameter(name: "identifierHash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_new_language_country_flat",
            parameters: [
                RuntimeABIParameter(name: "languageData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "languageLength", type: .intptr),
                RuntimeABIParameter(name: "languageByteCount", type: .intptr),
                RuntimeABIParameter(name: "languageHash", type: .intptr),
                RuntimeABIParameter(name: "countryData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "countryLength", type: .intptr),
                RuntimeABIParameter(name: "countryByteCount", type: .intptr),
                RuntimeABIParameter(name: "countryHash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_lowercase_locale_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uppercase_locale_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_compareTo_locale_flat",
            parameters: [
                RuntimeABIParameter(name: "lhsData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "lhsLength", type: .intptr),
                RuntimeABIParameter(name: "lhsByteCount", type: .intptr),
                RuntimeABIParameter(name: "lhsHash", type: .intptr),
                RuntimeABIParameter(name: "rhsData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "rhsLength", type: .intptr),
                RuntimeABIParameter(name: "rhsByteCount", type: .intptr),
                RuntimeABIParameter(name: "rhsHash", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_format_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "argsArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_format_locale_flat",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "argsArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        // STDLIB-TEXT-FN-012: CharSequence.contains(other, ignoreCase)
        RuntimeABIFunctionSpec(
            name: "kk_string_replace_char_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "oldCharRaw", type: .intptr),
                RuntimeABIParameter(name: "newCharRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replace_ignoreCase_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "oldData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "oldLength", type: .intptr),
                RuntimeABIParameter(name: "oldByteCount", type: .intptr),
                RuntimeABIParameter(name: "oldHash", type: .intptr),
                RuntimeABIParameter(name: "newData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "newLength", type: .intptr),
                RuntimeABIParameter(name: "newByteCount", type: .intptr),
                RuntimeABIParameter(name: "newHash", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replace_char_ignoreCase_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "oldCharRaw", type: .intptr),
                RuntimeABIParameter(name: "newCharRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_to_string",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "tag", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_to_string_nullable",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "tag", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_hashCode",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "tag", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_equals",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "lhsTag", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
                RuntimeABIParameter(name: "rhsTag", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_member_to_string",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_member_hashCode",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_member_equals",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_structural_eq",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collections",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_split",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_split_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "delimiterData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "delimiterLength", type: .intptr),
                RuntimeABIParameter(name: "delimiterByteCount", type: .intptr),
                RuntimeABIParameter(name: "delimiterHash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_split_limit",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
                RuntimeABIParameter(name: "limitRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_split_limit_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "delimiterData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "delimiterLength", type: .intptr),
                RuntimeABIParameter(name: "delimiterByteCount", type: .intptr),
                RuntimeABIParameter(name: "delimiterHash", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
                RuntimeABIParameter(name: "limitRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toInt",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toInt_radix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toIntOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toIntOrNull_radix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // SPEC-NUM-0007: no-arg unsigned parsers
        RuntimeABIFunctionSpec(
            name: "__kk_string_toUByteOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toUShortOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toUIntOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toULongOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toUByteOrNull_radix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toUShortOrNull_radix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toUIntOrNull_radix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toULongOrNull_radix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toDouble",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toDoubleOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toLong",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toLongOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toFloat",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toFloatOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toInt_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toInt_radix_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-020: CharSequence.indexOf(Char, startIndex, ignoreCase)
        // STDLIB-TEXT-EDGE-003: indexOf / lastIndexOf with ignoreCase
        RuntimeABIFunctionSpec(
            name: "__kk_string_toIntOrNull_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-034: CharSequence.lastIndexOf(Char, startIndex, ignoreCase)
        RuntimeABIFunctionSpec(
            name: "__kk_string_toIntOrNull_radix_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toUByteOrNull_radix_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toUShortOrNull_radix_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toUIntOrNull_radix_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toULongOrNull_radix_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toDouble_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toDoubleOrNull_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toLong_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toLongOrNull_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toFloat_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toFloatOrNull_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // KSP-408: kk_string_indexOfAny_chars_flat / kk_string_indexOfAny_strings_flat /
        // kk_string_lastIndexOfAny_chars_flat / kk_string_lastIndexOfAny_strings_flat /
        // kk_string_findAnyOf_flat / kk_string_findLastAnyOf_flat removed; indexOfAny/
        // lastIndexOfAny/findAnyOf/findLastAnyOf are bundled Kotlin source (StringIndexOf.kt).
        RuntimeABIFunctionSpec(
            name: "kk_string_get_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "indexRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-141: String.compareTo
        RuntimeABIFunctionSpec(
            name: "kk_enum_valueOf_throw",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        // STDLIB-171: enumValues<T>() / T.values() — returns Array<T>
        RuntimeABIFunctionSpec(
            name: "kk_enum_make_values_array",
            parameters: [
                RuntimeABIParameter(name: "valuesRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Enum",
            isThrowing: false
        ),
        // ENUM-002: T.entries — returns EnumEntries<T> (List)
        RuntimeABIFunctionSpec(
            name: "kk_enum_make_entries_list",
            parameters: [
                RuntimeABIParameter(name: "valuesRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Enum",
            isThrowing: false
        ),
        // KSP-1156: cached EnumEntries shared by T.entries and enumEntries<T>().
        RuntimeABIFunctionSpec(
            name: "kk_enum_make_entries_list_cached",
            parameters: [
                RuntimeABIParameter(name: "valuesRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
                RuntimeABIParameter(name: "classID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Enum",
            isThrowing: false
        ),
        // KSP-1156: source-backed internal Array/provider overloads retain the
        // supplied Array as the EnumEntries backing view.
        RuntimeABIFunctionSpec(
            name: "__kk_enum_entries_from_array",
            parameters: [
                RuntimeABIParameter(name: "valuesRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Enum",
            isThrowing: false
        ),
        // BUG-177: boxes a values()/entries element as a genuine ordinal Int
        // (tagged with its declared name for generic Any-printing) instead of
        // a pre-baked name string. BUG-182: also carries the enum class's
        // stable nominal type ID so `is`/`as`/`KClass.isInstance` work after
        // widening to `Any`.
        RuntimeABIFunctionSpec(
            name: "kk_enum_box_ordinal",
            parameters: [
                RuntimeABIParameter(name: "ordinal", type: .intptr),
                RuntimeABIParameter(name: "namePtr", type: .intptr),
                RuntimeABIParameter(name: "classID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Enum",
            isThrowing: false
        ),
        // STDLIB-142: String.toBoolean
        RuntimeABIFunctionSpec(
            name: "__kk_string_toBoolean_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toBooleanStrict_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-144: String.trimStart/trimEnd
        flatStringHOFReturnSpec(name: "kk_string_trimStart_predicate_flat"),
        flatStringHOFReturnSpec(name: "kk_string_trimEnd_predicate_flat"),
        // STDLIB-145: String.toByteArray
        RuntimeABIFunctionSpec(
            name: "__kk_string_toByteArray_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-581: String.toByteArray(charset: Charset)
        RuntimeABIFunctionSpec(
            name: "__kk_string_toByteArray_charset_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "charsetTag", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charset_utf_8",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charset_iso_8859_1",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charset_us_ascii",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charset_utf_16",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charset_utf_16be",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charset_utf_16le",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charset_utf_32",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charset_utf_32be",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_charset_utf_32le",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        // STDLIB-573: String.encodeToByteArray
        RuntimeABIFunctionSpec(
            name: "__kk_string_encodeToByteArray_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-573: String.encodeToByteArray(startIndex, endIndex)
        RuntimeABIFunctionSpec(
            name: "__kk_string_encodeToByteArray_range_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-573: String.encodeToByteArray(charset)
        RuntimeABIFunctionSpec(
            name: "__kk_string_encodeToByteArray_charset_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "charsetID", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-574: ByteArray.decodeToString
        RuntimeABIFunctionSpec(
            name: "__kk_bytearray_decodeToString",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "ByteArray",
            isThrowing: false
        ),
        // STDLIB-574: ByteArray.decodeToString(charset)
        RuntimeABIFunctionSpec(
            name: "__kk_bytearray_decodeToString_charset",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
                RuntimeABIParameter(name: "charsetId", type: .intptr),
            ],
            returnType: .intptr,
            section: "ByteArray",
            isThrowing: false
        ),
        // STDLIB-TEXT-EDGE-006: ByteArray.decodeToString(startIndex, endIndex, ...)
        RuntimeABIFunctionSpec(
            name: "__kk_bytearray_decodeToString_range",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ByteArray"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_bytearray_decodeToString_range_throw",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "throwOnInvalidSequence", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ByteArray"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_isIdentifierIgnorable",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // KSP-662: Bridges retained for Unicode case mapping, locale-aware
        // conversion, and digitOf table lookup after moving Char conversions to Kotlin.
        RuntimeABIFunctionSpec(
            name: "__kk_char_uppercase_string",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_char_lowercase_string",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_char_titlecase_string",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_char_uppercase_code",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_char_lowercase_code",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_char_titlecase_code",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_char_uppercase_locale",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_char_lowercase_locale",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_char_digit_value",
            parameters: [
                RuntimeABIParameter(name: "code", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-PROP-009: Char.isJavaIdentifierPart
        RuntimeABIFunctionSpec(
            name: "kk_char_isJavaIdentifierPart",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-PROP-010: Char.isJavaIdentifierStart
        RuntimeABIFunctionSpec(
            name: "kk_char_isJavaIdentifierStart",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-640: CharArray.concatToString()
        RuntimeABIFunctionSpec(
            name: "kk_chararray_concatToString",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // KSP-404: removePrefix/removeSuffix/removeSurrounding flat bridges removed;
        // implemented in bundled Kotlin source (StringPrefixSuffix.kt).
        // STDLIB-191
        // STDLIB-192
        // STDLIB-190
        // STDLIB-187
        flatStringHOFReturnSpec(name: "kk_string_ifBlank_flat"),
        flatStringHOFReturnSpec(name: "kk_string_ifEmpty_flat"),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toBigDecimal_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_bignum_toString",
            parameters: [
                RuntimeABIParameter(name: "numRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // KSP-410: map/mapIndexed/mapNotNull/firstNotNullOf(OrNull)/
        // filterIndexed/onEachIndexed/reduce family are bundled Kotlin source
        // (StringHOF.kt); their flat ABI entries were removed.
        // KSP-405: takeWhile/takeLastWhile/dropWhile are bundled Kotlin source
        // (StringTakeDrop.kt); their flat ABI entries were removed.
        RuntimeABIFunctionSpec(
            name: "__kk_string_splitToSequence",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_joinToString",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "separatorRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
                RuntimeABIParameter(name: "postfixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_splitToSequence_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "delimiterData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "delimiterLength", type: .intptr),
                RuntimeABIParameter(name: "delimiterByteCount", type: .intptr),
                RuntimeABIParameter(name: "delimiterHash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-FN-077: String.substringBeforeLast(delimiter, missingDelimiterValue)
        // STDLIB-TEXT-FN-075: String.substringAfterLast(delimiter, missingDelimiterValue)
        // STDLIB-TEXT-PROP-017: Char.isUnicodeIdentifierPart
        RuntimeABIFunctionSpec(
            name: "kk_char_isUnicodeIdentifierPart",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-534: String?.orEmpty()
        RuntimeABIFunctionSpec(
            name: "kk_string_orEmpty_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String"
        ),
        // MIGRATION-TEXT-006: Internal bridge functions for Kotlin stdlib source

        RuntimeABIFunctionSpec(
            name: "__kk_string_format_locale",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "argsArrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_codePointCount",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_codePointCount_from",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_codePointCount_range",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_compareTo_member",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_intern",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_plus",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // KSP-406: replaceRange_indices/slice_iterable/slice_range removed;
        // now bundled Kotlin source (StringSubstringSlice.kt).
    ]

    private static func flatStringHOFReturnSpec(name: String) -> RuntimeABIFunctionSpec {
        var parameters = flatStringParameters(prefix: "")
        parameters.append(contentsOf: [
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
        ])
        parameters.append(contentsOf: flatStringOutParameters())
        parameters.append(RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer))
        return RuntimeABIFunctionSpec(
            name: name,
            parameters: parameters,
            returnType: .nullableUInt8Pointer,
            section: "String"
        )
    }

    private static func flatStringReturnSpec(
        name: String,
        delimiterParameter: RuntimeABIParameter? = nil,
        trailingStringPrefixes: [String]
    ) -> RuntimeABIFunctionSpec {
        var parameters = flatStringParameters(prefix: "")
        if let delimiterParameter {
            parameters.append(delimiterParameter)
        }
        for prefix in trailingStringPrefixes {
            parameters.append(contentsOf: flatStringParameters(prefix: prefix))
        }
        parameters.append(contentsOf: flatStringOutParameters())
        return RuntimeABIFunctionSpec(
            name: name,
            parameters: parameters,
            returnType: .nullableUInt8Pointer,
            section: "String"
        )
    }

    private static func flatStringParameters(prefix: String) -> [RuntimeABIParameter] {
        let dataName = prefix.isEmpty ? "data" : "\(prefix)Data"
        let lengthName = prefix.isEmpty ? "length" : "\(prefix)Length"
        let byteCountName = prefix.isEmpty ? "byteCount" : "\(prefix)ByteCount"
        let hashName = prefix.isEmpty ? "hash" : "\(prefix)Hash"
        return [
            RuntimeABIParameter(name: dataName, type: .nullableConstUInt8Pointer),
            RuntimeABIParameter(name: lengthName, type: .intptr),
            RuntimeABIParameter(name: byteCountName, type: .intptr),
            RuntimeABIParameter(name: hashName, type: .intptr),
        ]
    }

    private static func flatStringOutParameters() -> [RuntimeABIParameter] {
        [
            RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
            RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
            RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
        ]
    }
}
