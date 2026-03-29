import Foundation

// MARK: - Regex Runtime Types

final class RuntimeRegexBox {
    let regex: NSRegularExpression
    let pattern: String
    /// When true, input strings are NFC-normalized before matching to emulate
    /// Kotlin's `RegexOption.CANON_EQ` (Unicode canonical equivalence).
    /// The pattern itself is also NFC-normalized at creation time.
    let canonEq: Bool

    init(regex: NSRegularExpression, pattern: String, canonEq: Bool = false) {
        self.regex = regex
        self.pattern = pattern
        self.canonEq = canonEq
    }

    /// Returns the input string NFC-normalized if `canonEq` is enabled,
    /// otherwise returns it unchanged.
    ///
    /// **Limitation**: When `canonEq` is true, operations that return substrings
    /// of the input (replace, split, find, findAll, matchEntire) will operate on
    /// the NFC-normalized form. This means the returned strings may differ from
    /// the original input's Unicode representation (e.g., a decomposed sequence
    /// like U+0065 U+0301 becomes the precomposed U+00E9). Kotlin/JVM's
    /// `CANON_EQ` uses the ICU regex engine which matches canonically equivalent
    /// sequences without altering the input. A fully faithful implementation
    /// would require mapping match ranges back to the original string.
    func normalizeIfNeeded(_ str: String) -> String {
        canonEq ? str.precomposedStringWithCanonicalMapping : str
    }
}

final class RuntimeMatchResultBox {
    let value: String
    let groupValues: [String]
    /// Per-group MatchGroup data (index 0 = entire match, 1.. = capture groups).
    let groups: [RuntimeMatchGroupBox?]
    /// Named capture group name -> group index mapping.
    let namedGroups: [String: Int]
    /// The original input string (for next() iteration).
    let inputString: String?
    /// The end position in the input string where this match ended (UTF-16 offset, for next() iteration).
    let matchEndOffset: Int
    /// The regex box used to produce this match (for next() iteration).
    weak var regexBox: RuntimeRegexBox?

    init(
        value: String,
        groupValues: [String],
        groups: [RuntimeMatchGroupBox?] = [],
        namedGroups: [String: Int] = [:],
        inputString: String? = nil,
        matchEndOffset: Int = 0,
        regexBox: RuntimeRegexBox? = nil
    ) {
        self.value = value
        self.groupValues = groupValues
        self.groups = groups
        self.namedGroups = namedGroups
        self.inputString = inputString
        self.matchEndOffset = matchEndOffset
        self.regexBox = regexBox
    }
}

/// Runtime box for `kotlin.text.MatchGroup`.
/// Stores the matched value and the range as (start, endInclusive) indices.
final class RuntimeMatchGroupBox {
    let value: String
    let rangeStart: Int
    let rangeEnd: Int

    init(value: String, rangeStart: Int, rangeEnd: Int) {
        self.value = value
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }
}

/// Runtime box for `kotlin.text.MatchGroupCollection`.
/// Wraps the groups array and named-group mapping from a MatchResult.
final class RuntimeMatchGroupCollectionBox {
    let groups: [RuntimeMatchGroupBox?]
    let namedGroups: [String: Int]

    init(groups: [RuntimeMatchGroupBox?], namedGroups: [String: Int]) {
        self.groups = groups
        self.namedGroups = namedGroups
    }
}

// MARK: - Private Helpers

private func regexStringFromRaw(_ raw: Int) -> String? {
    if raw == runtimeNullSentinelInt { return nil }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return extractString(from: pointer)
}

private func regexMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func regexMakeListRaw(_ values: [Int]) -> Int {
    let box = RuntimeListBox(elements: values)
    return registerRuntimeObject(box)
}

private func regexMakeStringListRaw(_ values: [String]) -> Int {
    regexMakeListRaw(values.map(regexMakeStringRaw))
}

private func regexBoxFromRaw(_ raw: Int) -> RuntimeRegexBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeRegexBox.self)
}

private func matchResultBoxFromRaw(_ raw: Int) -> RuntimeMatchResultBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeMatchResultBox.self)
}

/// Extracts named capture group names from a regex pattern string.
/// Matches `(?<name>...)` syntax used by both Kotlin and NSRegularExpression.
private func extractNamedGroupNames(from pattern: String) -> [String] {
    guard let detector = try? NSRegularExpression(pattern: "\\(\\?<([a-zA-Z_][a-zA-Z0-9_]*)>", options: []) else {
        return []
    }
    let nsRange = NSRange(pattern.startIndex..., in: pattern)
    let matches = detector.matches(in: pattern, options: [], range: nsRange)
    return matches.compactMap { match -> String? in
        guard match.numberOfRanges >= 2 else { return nil }
        let nameRange = match.range(at: 1)
        guard nameRange.location != NSNotFound, let range = Range(nameRange, in: pattern) else { return nil }
        return String(pattern[range])
    }
}

private func makeMatchResult(from result: NSTextCheckingResult, in str: String, regexBox: RuntimeRegexBox? = nil) -> RuntimeMatchResultBox {
    let matchRange = Range(result.range, in: str)!
    let value = String(str[matchRange])

    var groupValues: [String] = []
    var groups: [RuntimeMatchGroupBox?] = []
    for i in 0 ..< result.numberOfRanges {
        let groupRange = result.range(at: i)
        if groupRange.location != NSNotFound, let range = Range(groupRange, in: str) {
            let groupValue = String(str[range])
            groupValues.append(groupValue)
            // Compute UTF-16 based indices matching Kotlin's String indexing
            let utf16Start = range.lowerBound.samePosition(in: str.utf16) ?? str.utf16.startIndex
            let startIndex = str.utf16.distance(from: str.utf16.startIndex, to: utf16Start)
            let endIndex = startIndex + str[range].utf16.count - 1
            groups.append(RuntimeMatchGroupBox(value: groupValue, rangeStart: startIndex, rangeEnd: endIndex))
        } else {
            groupValues.append("")
            groups.append(nil)
        }
    }

    // Build named group mapping
    var namedGroups: [String: Int] = [:]
    if let regexBox = regexBox {
        let names = extractNamedGroupNames(from: regexBox.pattern)
        for name in names {
            let namedRange = result.range(withName: name)
            guard namedRange.location != NSNotFound else { continue }
            for groupIndex in 1 ..< result.numberOfRanges where result.range(at: groupIndex) == namedRange {
                namedGroups[name] = groupIndex
                break
            }
        }
    }

    // Compute UTF-16 offset of the match end position for next() iteration
    let matchEnd: Int
    if let range = Range(result.range, in: str) {
        let utf16End = range.upperBound.samePosition(in: str.utf16) ?? str.utf16.endIndex
        matchEnd = str.utf16.distance(from: str.utf16.startIndex, to: utf16End)
    } else {
        matchEnd = 0
    }

    return RuntimeMatchResultBox(
        value: value,
        groupValues: groupValues,
        groups: groups,
        namedGroups: namedGroups,
        inputString: str,
        matchEndOffset: matchEnd,
        regexBox: regexBox
    )
}

// MARK: - STDLIB-100: Regex constructor, matches, contains

@_cdecl("kk_regex_create")
public func kk_regex_create(_ patternRaw: Int) -> Int {
    let pattern = regexStringFromRaw(patternRaw) ?? ""
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        // Return a regex that matches nothing on invalid pattern
        do {
            let fallback = try NSRegularExpression(pattern: "(?!)", options: [])
            return registerRuntimeObject(RuntimeRegexBox(regex: fallback, pattern: pattern))
        } catch {
            // If even the fallback fails, return an empty regex
            do {
                let emptyRegex = try NSRegularExpression(pattern: "", options: [])
                return registerRuntimeObject(RuntimeRegexBox(regex: emptyRegex, pattern: pattern))
            } catch {
                // Last resort: create a regex that matches an empty string
                do {
                    let lastResort = try NSRegularExpression(pattern: "^$", options: [])
                    return registerRuntimeObject(RuntimeRegexBox(regex: lastResort, pattern: pattern))
                } catch {
                    // This should never happen, but handle gracefully
                    fatalError("Failed to create any NSRegularExpression instance")
                }
            }
        }
    }
    return registerRuntimeObject(RuntimeRegexBox(regex: regex, pattern: pattern))
}

@_cdecl("kk_string_matches_regex")
public func kk_string_matches_regex(_ strRaw: Int, _ regexRaw: Int) -> Int {
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    let match = regexBox.regex.firstMatch(in: str, options: [.anchored], range: range)
    let fullMatch = match != nil && match!.range.length == range.length
    return kk_box_bool(fullMatch ? 1 : 0)
}

@_cdecl("kk_string_contains_regex")
public func kk_string_contains_regex(_ strRaw: Int, _ regexRaw: Int) -> Int {
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    let match = regexBox.regex.firstMatch(in: str, options: [], range: range)
    return kk_box_bool(match != nil ? 1 : 0)
}

// MARK: - STDLIB-101: Regex.find / Regex.findAll

@_cdecl("kk_regex_find")
public func kk_regex_find(_ regexRaw: Int, _ strRaw: Int) -> Int {
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return runtimeNullSentinelInt }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    guard let result = regexBox.regex.firstMatch(in: str, options: [], range: range) else {
        return runtimeNullSentinelInt
    }
    let matchResult = makeMatchResult(from: result, in: str, regexBox: regexBox)
    return registerRuntimeObject(matchResult)
}

@_cdecl("kk_regex_findAll")
public func kk_regex_findAll(_ regexRaw: Int, _ strRaw: Int) -> Int {
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return regexMakeListRaw([]) }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    let results = regexBox.regex.matches(in: str, options: [], range: range)
    let matchResults = results.map { result -> Int in
        let matchResult = makeMatchResult(from: result, in: str, regexBox: regexBox)
        return registerRuntimeObject(matchResult)
    }
    return regexMakeListRaw(matchResults)
}

// MARK: - STDLIB-102: String.replace(Regex) / String.split(Regex)

@_cdecl("kk_string_replace_regex")
public func kk_string_replace_regex(_ strRaw: Int, _ regexRaw: Int, _ replacementRaw: Int) -> Int {
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    let replacement = regexStringFromRaw(replacementRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return regexMakeStringRaw(rawStr) }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    let result = regexBox.regex.stringByReplacingMatches(in: str, options: [], range: range, withTemplate: replacement)
    return regexMakeStringRaw(result)
}

@_cdecl("kk_string_split_regex")
public func kk_string_split_regex(_ strRaw: Int, _ regexRaw: Int) -> Int {
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return regexMakeStringListRaw([rawStr]) }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    let matches = regexBox.regex.matches(in: str, options: [], range: range)
    if matches.isEmpty {
        return regexMakeStringListRaw([str])
    }
    var parts: [String] = []
    var lastEnd = str.startIndex
    for match in matches {
        let matchRange = Range(match.range, in: str)!
        parts.append(String(str[lastEnd ..< matchRange.lowerBound]))
        lastEnd = matchRange.upperBound
    }
    parts.append(String(str[lastEnd...]))
    return regexMakeStringListRaw(parts)
}

// MARK: - STDLIB-351: Regex.replace(input) { matchResult -> replacement }

@_cdecl("kk_regex_replace_lambda")
public func kk_regex_replace_lambda(
    _ regexRaw: Int,
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return strRaw }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    let matches = regexBox.regex.matches(in: str, options: [], range: range)
    if matches.isEmpty { return strRaw }
    var result = ""
    var lastEnd = str.startIndex
    for match in matches {
        let matchRange = Range(match.range, in: str)!
        result.append(String(str[lastEnd ..< matchRange.lowerBound]))
        let matchResult = makeMatchResult(from: match, in: str, regexBox: regexBox)
        let matchResultRaw = registerRuntimeObject(matchResult)
        var thrown = 0
        let replacementRaw = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: matchResultRaw, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return regexMakeStringRaw("")
        }
        let replacement = regexStringFromRaw(replacementRaw) ?? ""
        result.append(replacement)
        lastEnd = matchRange.upperBound
    }
    result.append(String(str[lastEnd...]))
    return regexMakeStringRaw(result)
}

// MARK: - STDLIB-350: Regex.matchEntire

@_cdecl("kk_regex_matchEntire")
public func kk_regex_matchEntire(_ regexRaw: Int, _ strRaw: Int) -> Int {
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return runtimeNullSentinelInt }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    guard let result = regexBox.regex.firstMatch(in: str, options: [], range: range) else {
        return runtimeNullSentinelInt
    }
    let matchRange = Range(result.range, in: str)!
    guard matchRange.lowerBound == str.startIndex && matchRange.upperBound == str.endIndex else {
        return runtimeNullSentinelInt
    }
    let matchResult = makeMatchResult(from: result, in: str, regexBox: regexBox)
    return registerRuntimeObject(matchResult)
}

// MARK: - STDLIB-480: Regex(pattern, option) / Regex.containsMatchIn

// Named constants for Kotlin `RegexOption` enum ordinals.
// These must stay in sync with the enum entry registration order in
// `HeaderHelpers+SyntheticRegexStubs.swift` (`ensureRegexOptionEnumClass`).
private let kRegexOptionOrdinalLiteral  = 3
private let kRegexOptionOrdinalCanonEq  = 6

/// Maps a Kotlin `RegexOption` enum ordinal to `NSRegularExpression.Options`.
///
/// **Coupling note**: The ordinal values here must stay in sync with the
/// enum entry registration order in
/// `HeaderHelpers+SyntheticRegexStubs.swift` (`ensureRegexOptionEnumClass`).
/// The canonical order is defined by Kotlin's `kotlin.text.RegexOption`:
///   0 = IGNORE_CASE, 1 = MULTILINE, 2 = DOT_MATCHES_ALL,
///   3 = LITERAL, 4 = UNIX_LINES, 5 = COMMENTS, 6 = CANON_EQ
/// If the compiler-side entry order changes, these ordinals must be updated
/// to match.
private func nsRegexOption(fromOrdinal ordinal: Int) -> NSRegularExpression.Options {
    switch ordinal {
    case 0: return .caseInsensitive          // IGNORE_CASE
    case 1: return .anchorsMatchLines        // MULTILINE
    case 2: return .dotMatchesLineSeparators  // DOT_MATCHES_ALL
    case kRegexOptionOrdinalLiteral: return []  // LITERAL (handled via escapedPattern)
    case 4: return .useUnixLineSeparators        // UNIX_LINES
    case 5: return .allowCommentsAndWhitespace   // COMMENTS
    case kRegexOptionOrdinalCanonEq: return []   // CANON_EQ (handled via NFC normalization)
    default:
        assertionFailure("KSwiftK: unknown RegexOption ordinal \(ordinal) – compiler/runtime enum mismatch?")
        return []
    }
}

// NOTE: kk_regex_create_with_option and kk_regex_create_with_options share the
// same "effective pattern + try compile + fallback + box" logic.  A shared
// private helper (e.g., createRegexBox(pattern:isLiteral:options:)) could
// reduce drift; kept inline for now as the two functions differ in how they
// collect options (single ordinal vs set iteration).
@_cdecl("kk_regex_create_with_option")
public func kk_regex_create_with_option(_ patternRaw: Int, _ optionRaw: Int) -> Int {
    let pattern = regexStringFromRaw(patternRaw) ?? ""
    let ordinal = kk_unbox_int(optionRaw)
    let isLiteral = Int(ordinal) == kRegexOptionOrdinalLiteral
    let isCanonEq = Int(ordinal) == kRegexOptionOrdinalCanonEq
    let normalizedPattern = isCanonEq ? pattern.precomposedStringWithCanonicalMapping : pattern
    let effectivePattern = isLiteral ? NSRegularExpression.escapedPattern(for: normalizedPattern) : normalizedPattern
    let options = nsRegexOption(fromOrdinal: Int(ordinal))
    guard let regex = try? NSRegularExpression(pattern: effectivePattern, options: options) else {
        do {
            let fallback = try NSRegularExpression(pattern: "(?!)", options: [])
            return registerRuntimeObject(RuntimeRegexBox(regex: fallback, pattern: pattern, canonEq: isCanonEq))
        } catch {
            fatalError("Failed to create fallback NSRegularExpression")
        }
    }
    return registerRuntimeObject(RuntimeRegexBox(regex: regex, pattern: pattern, canonEq: isCanonEq))
}

/// Creates a Regex from a pattern and a `Set<RegexOption>`.
/// Iterates the set elements, unboxes each as an ordinal, and combines the
/// corresponding `NSRegularExpression.Options`.
@_cdecl("kk_regex_create_with_options")
public func kk_regex_create_with_options(_ patternRaw: Int, _ optionsSetRaw: Int) -> Int {
    let pattern = regexStringFromRaw(patternRaw) ?? ""
    var combined: NSRegularExpression.Options = []
    var isLiteral = false
    var isCanonEq = false
    if let setBox = runtimeSetBox(from: optionsSetRaw) {
        for element in setBox.elements {
            let ordinal = Int(kk_unbox_int(element))
            if ordinal == kRegexOptionOrdinalLiteral { isLiteral = true }
            if ordinal == kRegexOptionOrdinalCanonEq { isCanonEq = true }
            combined.insert(nsRegexOption(fromOrdinal: ordinal))
        }
    }
    let normalizedPattern = isCanonEq ? pattern.precomposedStringWithCanonicalMapping : pattern
    let effectivePattern = isLiteral ? NSRegularExpression.escapedPattern(for: normalizedPattern) : normalizedPattern
    guard let regex = try? NSRegularExpression(pattern: effectivePattern, options: combined) else {
        do {
            let fallback = try NSRegularExpression(pattern: "(?!)", options: [])
            return registerRuntimeObject(RuntimeRegexBox(regex: fallback, pattern: pattern, canonEq: isCanonEq))
        } catch {
            fatalError("Failed to create fallback NSRegularExpression")
        }
    }
    return registerRuntimeObject(RuntimeRegexBox(regex: regex, pattern: pattern, canonEq: isCanonEq))
}

@_cdecl("kk_regex_containsMatchIn")
public func kk_regex_containsMatchIn(_ regexRaw: Int, _ inputRaw: Int) -> Int {
    let rawInput = regexStringFromRaw(inputRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let input = regexBox.normalizeIfNeeded(rawInput)
    let range = NSRange(input.startIndex..., in: input)
    let match = regexBox.regex.firstMatch(in: input, options: [], range: range)
    return kk_box_bool(match != nil ? 1 : 0)
}

// MARK: - STDLIB-103: String.toRegex() / Regex.pattern

@_cdecl("kk_string_toRegex")
public func kk_string_toRegex(_ strRaw: Int) -> Int {
    kk_regex_create(strRaw)
}

@_cdecl("kk_regex_pattern")
public func kk_regex_pattern(_ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return regexMakeStringRaw("") }
    return regexMakeStringRaw(regexBox.pattern)
}

// MARK: - STDLIB-101: MatchResult properties

@_cdecl("kk_match_result_value")
public func kk_match_result_value(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else { return regexMakeStringRaw("") }
    return regexMakeStringRaw(matchResult.value)
}

@_cdecl("kk_match_result_groupValues")
public func kk_match_result_groupValues(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else { return regexMakeStringListRaw([]) }
    return regexMakeStringListRaw(matchResult.groupValues)
}

// MARK: - MatchResult.groups / MatchGroupCollection / MatchGroup

@_cdecl("kk_match_result_groups")
public func kk_match_result_groups(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else {
        return registerRuntimeObject(RuntimeMatchGroupCollectionBox(groups: [], namedGroups: [:]))
    }
    let collection = RuntimeMatchGroupCollectionBox(
        groups: matchResult.groups,
        namedGroups: matchResult.namedGroups
    )
    return registerRuntimeObject(collection)
}

private func matchGroupCollectionBoxFromRaw(_ raw: Int) -> RuntimeMatchGroupCollectionBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeMatchGroupCollectionBox.self)
}

private func matchGroupBoxFromRaw(_ raw: Int) -> RuntimeMatchGroupBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeMatchGroupBox.self)
}

/// MatchGroupCollection.get(name: String) -> MatchGroup?
@_cdecl("kk_match_group_collection_get")
public func kk_match_group_collection_get(_ collectionRaw: Int, _ nameRaw: Int) -> Int {
    guard let collection = matchGroupCollectionBoxFromRaw(collectionRaw) else {
        return runtimeNullSentinelInt
    }
    guard let name = regexStringFromRaw(nameRaw) else {
        return runtimeNullSentinelInt
    }
    guard let groupIndex = collection.namedGroups[name],
          groupIndex < collection.groups.count,
          let group = collection.groups[groupIndex] else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(group)
}

/// MatchGroup.value: String
@_cdecl("kk_match_group_value")
public func kk_match_group_value(_ groupRaw: Int) -> Int {
    guard let group = matchGroupBoxFromRaw(groupRaw) else { return regexMakeStringRaw("") }
    return regexMakeStringRaw(group.value)
}

/// MatchGroup.range: IntRange
@_cdecl("kk_match_group_range")
public func kk_match_group_range(_ groupRaw: Int) -> Int {
    guard let group = matchGroupBoxFromRaw(groupRaw) else {
        return registerRuntimeObject(RuntimeRangeBox(first: 0, last: -1, step: 1))
    }
    return registerRuntimeObject(RuntimeRangeBox(first: group.rangeStart, last: group.rangeEnd, step: 1))
}

// MARK: - STDLIB-REGEX-095: MatchResult complete implementation

/// MatchResult.range: IntRange — the range of the entire match.
@_cdecl("kk_match_result_range")
public func kk_match_result_range(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          let group0 = matchResult.groups.first,
          let g = group0 else {
        return registerRuntimeObject(RuntimeRangeBox(first: 0, last: -1, step: 1))
    }
    return registerRuntimeObject(RuntimeRangeBox(first: g.rangeStart, last: g.rangeEnd, step: 1))
}

/// MatchResult.component1() — the entire match value (destructuring).
@_cdecl("kk_match_result_component1")
public func kk_match_result_component1(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else { return regexMakeStringRaw("") }
    return regexMakeStringRaw(matchResult.value)
}

/// MatchResult.component2() — the first capture group value (destructuring).
@_cdecl("kk_match_result_component2")
public func kk_match_result_component2(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else { return regexMakeStringRaw("") }
    let firstGroup = matchResult.groupValues.count > 1 ? matchResult.groupValues[1] : ""
    return regexMakeStringRaw(firstGroup)
}

/// MatchResult.next() — returns the next MatchResult in the input, or null.
@_cdecl("kk_match_result_next")
public func kk_match_result_next(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          let inputString = matchResult.inputString,
          let regexBox = matchResult.regexBox else {
        return runtimeNullSentinelInt
    }
    let startOffset = matchResult.matchEndOffset
    let isZeroLengthMatch = matchResult.value.isEmpty
    let effectiveOffset = isZeroLengthMatch ? startOffset + 1 : startOffset
    // Convert UTF-16 offset to String.Index
    guard let utf16StartIdx = inputString.utf16.index(
        inputString.utf16.startIndex,
        offsetBy: effectiveOffset,
        limitedBy: inputString.utf16.endIndex
    ) else {
        return runtimeNullSentinelInt
    }
    guard let startIdx = utf16StartIdx.samePosition(in: inputString),
          startIdx < inputString.endIndex else {
        return runtimeNullSentinelInt
    }
    let searchStr = String(inputString[startIdx...])
    let nsRange = NSRange(searchStr.startIndex..., in: searchStr)
    guard let result = regexBox.regex.firstMatch(in: searchStr, options: [], range: nsRange) else {
        return runtimeNullSentinelInt
    }
    let nextMatchResult = makeMatchResultWithOffset(
        from: result,
        in: searchStr,
        inputOffset: effectiveOffset,
        regexBox: regexBox,
        fullInput: inputString
    )
    return registerRuntimeObject(nextMatchResult)
}

/// MatchGroupCollection[index]: MatchGroup? — integer index access.
@_cdecl("kk_match_group_collection_get_at")
public func kk_match_group_collection_get_at(_ collectionRaw: Int, _ index: Int) -> Int {
    guard let collection = matchGroupCollectionBoxFromRaw(collectionRaw) else {
        return runtimeNullSentinelInt
    }
    guard index >= 0, index < collection.groups.count else {
        return runtimeNullSentinelInt
    }
    guard let group = collection.groups[index] else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(group)
}

// MARK: - Private helper for next() with offset-adjusted ranges

private func makeMatchResultWithOffset(
    from result: NSTextCheckingResult,
    in str: String,
    inputOffset: Int,
    regexBox: RuntimeRegexBox?,
    fullInput: String
) -> RuntimeMatchResultBox {
    let matchRange = Range(result.range, in: str)!
    let value = String(str[matchRange])

    var groupValues: [String] = []
    var groups: [RuntimeMatchGroupBox?] = []
    for i in 0 ..< result.numberOfRanges {
        let groupRange = result.range(at: i)
        if groupRange.location != NSNotFound, let range = Range(groupRange, in: str) {
            let groupValue = String(str[range])
            groupValues.append(groupValue)
            let utf16Start = range.lowerBound.samePosition(in: str.utf16) ?? str.utf16.startIndex
            let localStart = str.utf16.distance(from: str.utf16.startIndex, to: utf16Start)
            let startIndex = inputOffset + localStart
            let endIndex = startIndex + str[range].utf16.count - 1
            groups.append(RuntimeMatchGroupBox(value: groupValue, rangeStart: startIndex, rangeEnd: endIndex))
        } else {
            groupValues.append("")
            groups.append(nil)
        }
    }

    var namedGroups: [String: Int] = [:]
    if let regexBox = regexBox {
        let names = extractNamedGroupNames(from: regexBox.pattern)
        for name in names {
            let namedRange = result.range(withName: name)
            guard namedRange.location != NSNotFound else { continue }
            for groupIndex in 1 ..< result.numberOfRanges where result.range(at: groupIndex) == namedRange {
                namedGroups[name] = groupIndex
                break
            }
        }
    }

    // Compute match end offset in full input's UTF-16
    let utf16End = matchRange.upperBound.samePosition(in: str.utf16) ?? str.utf16.endIndex
    let localEnd = str.utf16.distance(from: str.utf16.startIndex, to: utf16End)
    let matchEnd = inputOffset + localEnd

    return RuntimeMatchResultBox(
        value: value,
        groupValues: groupValues,
        groups: groups,
        namedGroups: namedGroups,
        inputString: fullInput,
        matchEndOffset: matchEnd,
        regexBox: regexBox
    )
}

// MARK: - STDLIB-REGEX-097: Regex.groupNames

/// Regex.groupNames: Set<String>
/// Returns the set of named capture group names defined in the regex pattern.
@_cdecl("kk_regex_group_names")
public func kk_regex_group_names(_ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    let names = extractNamedGroupNames(from: regexBox.pattern)
    let nameRaws = names.map(regexMakeStringRaw)
    let setBox = RuntimeSetBox(elements: nameRaws)
    return registerRuntimeObject(setBox)
}

// MARK: - STDLIB-REGEX-098: Regex.matches(input)

/// Regex.matches(input): Boolean
/// Returns true if the entire input string is matched by this regex.
@_cdecl("kk_regex_matches")
public func kk_regex_matches(_ regexRaw: Int, _ inputRaw: Int) -> Int {
    let rawInput = regexStringFromRaw(inputRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let input = regexBox.normalizeIfNeeded(rawInput)
    let range = NSRange(input.startIndex..., in: input)
    guard let result = regexBox.regex.firstMatch(in: input, options: [], range: range) else {
        return kk_box_bool(0)
    }
    let matchRange = Range(result.range, in: input)!
    let isFullMatch = matchRange.lowerBound == input.startIndex && matchRange.upperBound == input.endIndex
    return kk_box_bool(isFullMatch ? 1 : 0)
}
