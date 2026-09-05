// swiftlint:disable file_length

/// `RuntimeABISpec.regexFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let regexFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_regex_create_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_matches_regex_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_contains_regex_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_regex_find_flat",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_regex_findAll_flat",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_replace_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "replacement", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_split_regex_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-105: String.toRegex(option) / String.toRegex(options)
        RuntimeABIFunctionSpec(
            name: "__kk_string_toRegex_with_option_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "optionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toRegex_with_options_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "optionsRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toRegex_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // KSP-486: raw regex data bridges backing the Kotlin Regex accessors.
        RuntimeABIFunctionSpec(
            name: "__kk_regex_pattern",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_regex_option_mask",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-351: Regex.replace lambda / STDLIB-350: Regex.matchEntire
        RuntimeABIFunctionSpec(
            name: "__kk_regex_replace_lambda",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_regex_matchEntire_flat",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-480: Regex(pattern, option) constructor
        RuntimeABIFunctionSpec(
            name: "__kk_regex_create_with_option_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "optionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-480: Regex(pattern, options: Set<RegexOption>) constructor
        RuntimeABIFunctionSpec(
            name: "__kk_regex_create_with_options_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "optionsSetRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-480: Regex.containsMatchIn(input)
        RuntimeABIFunctionSpec(
            name: "__kk_regex_containsMatchIn_flat",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_regex_matches_flat",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // KSP-486: raw match data bridges backing the Kotlin MatchResult layer.
        RuntimeABIFunctionSpec(
            name: "__kk_match_result_group_count",
            parameters: [
                RuntimeABIParameter(name: "matchRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_match_result_group_value",
            parameters: [
                RuntimeABIParameter(name: "matchRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_match_result_group_start",
            parameters: [
                RuntimeABIParameter(name: "matchRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_match_result_group_end",
            parameters: [
                RuntimeABIParameter(name: "matchRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_match_result_group_index_of_name",
            parameters: [
                RuntimeABIParameter(name: "matchRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_match_result_group_index_of_name_flat",
            parameters: [
                RuntimeABIParameter(name: "matchRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_match_result_has_named_group",
            parameters: [
                RuntimeABIParameter(name: "matchRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-REGEX-094: Regex.matches(input)
        // STDLIB-REGEX-094: Regex.fromLiteral
        // First param is the Companion object receiver (ignored at runtime).
        RuntimeABIFunctionSpec(
            name: "__kk_regex_from_literal_flat",
            parameters: [
                RuntimeABIParameter(name: "companionRef", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-REGEX-094: String.replaceFirst(Regex, replacement)
        RuntimeABIFunctionSpec(
            name: "__kk_string_replaceFirst_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "replacement", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-317: String.asSequence / asIterable
        RuntimeABIFunctionSpec(
            name: "kk_string_asSequence_flat",
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
    ]
}
