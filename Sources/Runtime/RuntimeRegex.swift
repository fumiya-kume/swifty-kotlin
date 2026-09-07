import Foundation

// MARK: - Regex Runtime Types

final class RuntimeRegexBox {
    let regex: NSRegularExpression
    let pattern: String
    /// When true, input strings are NFC-normalized before matching to emulate
    /// Kotlin's `RegexOption.CANON_EQ` (Unicode canonical equivalence).
    /// The pattern itself is also NFC-normalized at creation time.
    let canonEq: Bool
    /// The Kotlin `RegexOption` ordinals this regex was created with.
    /// Used by the `Regex.options` property to reconstruct the original
    /// `Set<RegexOption>`.
    let optionOrdinals: Set<Int>

    init(regex: NSRegularExpression, pattern: String, canonEq: Bool = false, optionOrdinals: Set<Int> = []) {
        self.regex = regex
        self.pattern = pattern
        self.canonEq = canonEq
        self.optionOrdinals = optionOrdinals
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
    /// Names declared by the pattern, including groups that did not participate.
    let namedGroupNames: Set<String>
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
        namedGroupNames: Set<String> = [],
        inputString: String? = nil,
        matchEndOffset: Int = 0,
        regexBox: RuntimeRegexBox? = nil
    ) {
        self.value = value
        self.groupValues = groupValues
        self.groups = groups
        self.namedGroups = namedGroups
        self.namedGroupNames = namedGroupNames
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

// MARK: - Private Helpers

/// Fixed ICU/NSRegularExpression pattern that never matches any input.
///
/// Used when a user-supplied pattern fails to compile: Kotlin's `Regex` constructor
/// throws `PatternSyntaxException` on invalid syntax; this runtime substitutes a
/// never-match regex so subsequent `find`/`matches` calls return empty results
/// instead of crashing.
///
/// `(?!)` is a negative lookahead with an empty sub-expression — always
/// unsatisfiable. It is independent of user input and is valid POSIX/ICU regex
/// syntax, so `NSRegularExpression` compilation cannot fail for this literal.
private enum RegexNeverMatch {
    static let expression: NSRegularExpression = {
        // "(?!)" is a static literal independent of user input — provably valid
        // ICU/POSIX syntax. If this fails, Foundation itself is broken.
        guard let expression = try? NSRegularExpression(pattern: "(?!)", options: []) else {
            preconditionFailure("KSwiftK: static never-match regex (?!) failed to compile — Foundation/ICU broken")
        }
        return expression
    }()
}

private func regexStringFromRaw(_ raw: Int) -> String? {
    if raw == runtimeNullSentinelInt { return nil }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return extractString(from: pointer)
}

private func regexStringFromFlat(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int
) -> String {
    runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
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

/// Defense-in-depth bounds for regex evaluation.
///
/// The runtime applies these caps on top of ICU / `NSRegularExpression` to keep
/// catastrophic-backtracking inputs from hanging the calling thread
/// indefinitely. Kotlin/JVM does not impose these bounds; they are a KSwiftK
/// runtime safety measure.
///
/// - `KSWIFTK_REGEX_TIMEOUT_MS`: per-operation wall-clock timeout in
///   milliseconds. The default is 30000ms (30s) — generous enough that
///   legitimate matches over large inputs complete well within it, while still
///   bounding catastrophic backtracking that would otherwise never return. A
///   value `<= 0` disables the timeout entirely and restores unbounded behavior.
/// - `KSWIFTK_REGEX_MAX_INPUT_LENGTH`: optional maximum input length in UTF-16
///   units. The default is `0`, which disables the cap. Any positive value
///   enables a fail-closed precheck that treats oversized inputs as no match.
///
/// When a timeout or size cap trips, bulk operations such as replace and split
/// fail closed and return the original input unchanged rather than hanging or
/// producing partial output. Tune or disable the limits with the environment
/// variables above.
private enum RegexEvaluationLimits {
    static let matchTimeout: TimeInterval = {
        let environment = ProcessInfo.processInfo.environment
        guard let rawValue = environment["KSWIFTK_REGEX_TIMEOUT_MS"] else {
            return 30.0
        }
        guard let timeoutMs = Double(rawValue), timeoutMs > 0 else { return 0.0 }
        return timeoutMs / 1000.0
    }()

    static let maxInputLength: Int = {
        let environment = ProcessInfo.processInfo.environment
        guard let rawValue = environment["KSWIFTK_REGEX_MAX_INPUT_LENGTH"],
              let inputLength = Int(rawValue),
              inputLength > 0 else {
            return 0
        }
        return inputLength
    }()

    static var isTimeoutEnabled: Bool {
        matchTimeout > 0
    }
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
    // NSRegularExpression only returns matches whose ranges are within the matched string,
    // so this conversion should never fail in practice.
    guard let matchRange = Range(result.range, in: str) else {
        return RuntimeMatchResultBox(value: "", groupValues: [])
    }
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
    var namedGroupNames: Set<String> = []
    if let regexBox = regexBox {
        let names = extractNamedGroupNames(from: regexBox.pattern)
        namedGroupNames = Set(names)
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
        namedGroupNames: namedGroupNames,
        inputString: str,
        matchEndOffset: matchEnd,
        regexBox: regexBox
    )
}

private func boundedFirstMatch(
    _ regex: NSRegularExpression,
    in str: String,
    options: NSRegularExpression.MatchingOptions,
    range: NSRange
) -> NSTextCheckingResult? {
    if RegexEvaluationLimits.maxInputLength > 0, range.length > RegexEvaluationLimits.maxInputLength {
        return nil
    }
    guard RegexEvaluationLimits.isTimeoutEnabled else {
        return regex.firstMatch(in: str, options: options, range: range)
    }

    let deadline = Date().addingTimeInterval(RegexEvaluationLimits.matchTimeout)
    let matchingOptions = options.union(.reportProgress)
    var firstMatch: NSTextCheckingResult?
    regex.enumerateMatches(in: str, options: matchingOptions, range: range) { result, flags, stop in
        if flags.contains(.progress) {
            if Date() >= deadline {
                stop.pointee = true
            }
            return
        }

        if let result {
            firstMatch = result
            stop.pointee = true
        }
    }
    return firstMatch
}

private func boundedMatches(
    _ regex: NSRegularExpression,
    in str: String,
    options: NSRegularExpression.MatchingOptions,
    range: NSRange
) -> [NSTextCheckingResult]? {
    if RegexEvaluationLimits.maxInputLength > 0, range.length > RegexEvaluationLimits.maxInputLength {
        return nil
    }
    guard RegexEvaluationLimits.isTimeoutEnabled else {
        return regex.matches(in: str, options: options, range: range)
    }

    let deadline = Date().addingTimeInterval(RegexEvaluationLimits.matchTimeout)
    let matchingOptions = options.union(.reportProgress)
    var matches: [NSTextCheckingResult] = []
    var timedOut = false
    regex.enumerateMatches(in: str, options: matchingOptions, range: range) { result, flags, stop in
        if flags.contains(.progress) {
            if Date() >= deadline {
                timedOut = true
                stop.pointee = true
            }
            return
        }

        if let result {
            matches.append(result)
        }
    }
    return timedOut ? nil : matches
}

// MARK: - STDLIB-100: Regex constructor, matches, contains

@_cdecl("__kk_regex_create_flat")
public func kk_regex_create_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRegexCreate(
        pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        outThrown: outThrown
    )
}


private func runtimeRegexCreate(pattern: String, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Illegal pattern: \(pattern)"
        )
        return 0
    }
    return registerRuntimeObject(RuntimeRegexBox(regex: regex, pattern: pattern))
}

@_cdecl("__kk_string_matches_regex_flat")
public func kk_string_matches_regex_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ regexRaw: Int
) -> Int {
    runtimeStringMatchesRegex(
        regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        regexRaw
    )
}

private func runtimeStringMatchesRegex(_ rawStr: String, _ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    let match = boundedFirstMatch(regexBox.regex, in: str, options: [.anchored], range: range)
    let fullMatch = match != nil && match!.range.length == range.length
    return kk_box_bool(fullMatch ? 1 : 0)
}

@_cdecl("__kk_string_contains_regex_flat")
public func kk_string_contains_regex_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ regexRaw: Int
) -> Int {
    runtimeStringContainsRegex(
        regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        regexRaw
    )
}

private func runtimeStringContainsRegex(_ rawStr: String, _ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    let match = boundedFirstMatch(regexBox.regex, in: str, options: [], range: range)
    return kk_box_bool(match != nil ? 1 : 0)
}

// MARK: - STDLIB-101: Regex.find / Regex.findAll

@_cdecl("__kk_regex_find_flat")
public func kk_regex_find_flat(
    _ regexRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeRegexFind(
        regexRaw,
        input: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}


private func runtimeRegexFind(_ regexRaw: Int, input rawStr: String) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return runtimeNullSentinelInt }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    guard let result = boundedFirstMatch(regexBox.regex, in: str, options: [], range: range) else {
        return runtimeNullSentinelInt
    }
    let matchResult = makeMatchResult(from: result, in: str, regexBox: regexBox)
    return registerRuntimeObject(matchResult)
}

@_cdecl("__kk_regex_findAll_flat")
public func kk_regex_findAll_flat(
    _ regexRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeRegexFindAll(
        regexRaw,
        input: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeRegexFindAll(_ regexRaw: Int, input rawStr: String) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return regexMakeListRaw([]) }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    let results = boundedMatches(regexBox.regex, in: str, options: [], range: range)
    guard let results else { return regexMakeListRaw([]) }
    let matchResults = results.map { result -> Int in
        let matchResult = makeMatchResult(from: result, in: str, regexBox: regexBox)
        return registerRuntimeObject(matchResult)
    }
    return regexMakeListRaw(matchResults)
}

// MARK: - STDLIB-102: String.replace(Regex) / String.split(Regex)

@_cdecl("__kk_string_replace_regex")
public func kk_string_replace_regex(_ strRaw: Int, _ regexRaw: Int, _ replacementRaw: Int) -> Int {
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    let replacement = regexStringFromRaw(replacementRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return regexMakeStringRaw(rawStr) }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    let matches = boundedMatches(regexBox.regex, in: str, options: [], range: range)
    guard let matches else {
        return regexMakeStringRaw(rawStr)
    }
    if matches.isEmpty {
        return regexMakeStringRaw(str)
    }
    var result = ""
    var lastEnd = str.startIndex
    for match in matches {
        guard let matchRange = Range(match.range, in: str) else { continue }
        result.append(String(str[lastEnd ..< matchRange.lowerBound]))
        let templateResult = regexBox.regex.replacementString(for: match, in: str, offset: 0, template: replacement)
        result.append(templateResult)
        lastEnd = matchRange.upperBound
    }
    result.append(String(str[lastEnd...]))
    return regexMakeStringRaw(result)
}

@_cdecl("__kk_string_split_regex_flat")
public func kk_string_split_regex_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ regexRaw: Int
) -> Int {
    runtimeStringSplitRegex(
        regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        regexRaw
    )
}


private func runtimeStringSplitRegex(_ rawStr: String, _ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return regexMakeStringListRaw([rawStr]) }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    let matches = boundedMatches(regexBox.regex, in: str, options: [], range: range)
    guard let matches else {
        return regexMakeStringListRaw([rawStr])
    }
    if matches.isEmpty {
        return regexMakeStringListRaw([str])
    }
    var parts: [String] = []
    var lastEnd = str.startIndex
    for match in matches {
        guard let matchRange = Range(match.range, in: str) else { continue }
        parts.append(String(str[lastEnd ..< matchRange.lowerBound]))
        lastEnd = matchRange.upperBound
    }
    parts.append(String(str[lastEnd...]))
    return regexMakeStringListRaw(parts)
}

// MARK: - STDLIB-351: Regex.replace(input) { matchResult -> replacement }

@_cdecl("__kk_regex_replace_lambda")
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
    let matches = boundedMatches(regexBox.regex, in: str, options: [], range: range)
    guard let matches else { return strRaw }
    if matches.isEmpty { return strRaw }
    var result = ""
    var lastEnd = str.startIndex
    for match in matches {
        guard let matchRange = Range(match.range, in: str) else { continue }
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

@_cdecl("__kk_regex_matchEntire_flat")
public func kk_regex_matchEntire_flat(
    _ regexRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeRegexMatchEntire(
        regexRaw,
        input: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}


private func runtimeRegexMatchEntire(_ regexRaw: Int, input rawStr: String) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return runtimeNullSentinelInt }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    guard let result = boundedFirstMatch(regexBox.regex, in: str, options: [], range: range) else {
        return runtimeNullSentinelInt
    }
    guard let matchRange = Range(result.range, in: str) else {
        return runtimeNullSentinelInt
    }
    guard matchRange.lowerBound == str.startIndex && matchRange.upperBound == str.endIndex else {
        return runtimeNullSentinelInt
    }
    let matchResult = makeMatchResult(from: result, in: str, regexBox: regexBox)
    return registerRuntimeObject(matchResult)
}

// MARK: - STDLIB-480: Regex(pattern, option) / Regex.containsMatchIn

// Named constants for Kotlin `RegexOption` enum ordinals.
// These must stay in sync with the enum entry declaration order in
// `Sources/CompilerCore/Stdlib/kotlin/text/Regex.kt`.
private let kRegexOptionOrdinalLiteral  = 2
private let kRegexOptionOrdinalCanonEq  = 6

/// Maps a Kotlin `RegexOption` enum ordinal to `NSRegularExpression.Options`.
///
/// **Coupling note**: The ordinal values here must stay in sync with the
/// enum entry declaration order in
/// `Sources/CompilerCore/Stdlib/kotlin/text/Regex.kt`.
/// The canonical order is defined by Kotlin's `kotlin.text.RegexOption`:
///   0 = IGNORE_CASE, 1 = MULTILINE, 2 = LITERAL, 3 = UNIX_LINES,
///   4 = COMMENTS, 5 = DOT_MATCHES_ALL, 6 = CANON_EQ
/// If the compiler-side entry order changes, these ordinals must be updated
/// to match.
private func nsRegexOption(fromOrdinal ordinal: Int) -> NSRegularExpression.Options {
    switch ordinal {
    case 0: return .caseInsensitive          // IGNORE_CASE
    case 1: return .anchorsMatchLines        // MULTILINE
    case kRegexOptionOrdinalLiteral: return []  // LITERAL (handled via escapedPattern)
    case 3: return .useUnixLineSeparators        // UNIX_LINES
    case 4: return .allowCommentsAndWhitespace   // COMMENTS
    case 5: return .dotMatchesLineSeparators     // DOT_MATCHES_ALL
    case kRegexOptionOrdinalCanonEq: return []   // CANON_EQ (handled via NFC normalization)
    default:
        assertionFailure("KSwiftK: unknown RegexOption ordinal \(ordinal) – compiler/runtime enum mismatch?")
        return []
    }
}

/// Applies LITERAL escaping and CANON_EQ normalization and compiles the pattern.
/// Returns `nil` and sets `outThrown` to an `IllegalArgumentException` on compile failure.
private func createRegexBox(
    pattern: String,
    isLiteral: Bool,
    options: NSRegularExpression.Options,
    optionOrdinals: Set<Int>,
    outThrown: UnsafeMutablePointer<Int>?
) -> RuntimeRegexBox? {
    let canonEq = optionOrdinals.contains(kRegexOptionOrdinalCanonEq)
    let normalizedPattern = canonEq ? pattern.precomposedStringWithCanonicalMapping : pattern
    let effectivePattern = isLiteral ? NSRegularExpression.escapedPattern(for: normalizedPattern) : normalizedPattern
    guard let regex = try? NSRegularExpression(pattern: effectivePattern, options: options) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Illegal pattern: \(pattern)"
        )
        return nil
    }
    return RuntimeRegexBox(regex: regex, pattern: pattern, canonEq: canonEq, optionOrdinals: optionOrdinals)
}



@_cdecl("__kk_regex_create_with_option_flat")
public func kk_regex_create_with_option_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ optionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRegexCreateWithOption(
        pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        optionRaw: optionRaw,
        outThrown: outThrown
    )
}

@_cdecl("__kk_string_toRegex_with_option_flat")
public func kk_string_toRegex_with_option_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ optionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRegexCreateWithOption(
        pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        optionRaw: optionRaw,
        outThrown: outThrown
    )
}

private func runtimeRegexCreateWithOption(pattern: String, optionRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let ordinal = Int(kk_unbox_int(optionRaw))
    guard let box = createRegexBox(
        pattern: pattern,
        isLiteral: ordinal == kRegexOptionOrdinalLiteral,
        options: nsRegexOption(fromOrdinal: ordinal),
        optionOrdinals: [ordinal],
        outThrown: outThrown
    ) else {
        return 0
    }
    return registerRuntimeObject(box)
}


/// Creates a Regex from a pattern and a `Set<RegexOption>`.
/// Iterates the set elements, unboxes each as an ordinal, and combines the
/// corresponding `NSRegularExpression.Options`.
@_cdecl("__kk_regex_create_with_options_flat")
public func kk_regex_create_with_options_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ optionsSetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRegexCreateWithOptions(
        pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        optionsSetRaw: optionsSetRaw,
        outThrown: outThrown
    )
}

@_cdecl("__kk_string_toRegex_with_options_flat")
public func kk_string_toRegex_with_options_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ optionsSetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRegexCreateWithOptions(
        pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        optionsSetRaw: optionsSetRaw,
        outThrown: outThrown
    )
}

private func runtimeRegexCreateWithOptions(pattern: String, optionsSetRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    var combined: NSRegularExpression.Options = []
    var isLiteral = false
    var storedOrdinals: Set<Int> = []
    if let setBox = runtimeSetBox(from: optionsSetRaw) {
        for element in setBox.elements {
            let ordinal = Int(kk_unbox_int(element))
            storedOrdinals.insert(ordinal)
            if ordinal == kRegexOptionOrdinalLiteral { isLiteral = true }
            combined.insert(nsRegexOption(fromOrdinal: ordinal))
        }
    }
    guard let box = createRegexBox(
        pattern: pattern, isLiteral: isLiteral, options: combined, optionOrdinals: storedOrdinals, outThrown: outThrown
    ) else {
        return 0
    }
    return registerRuntimeObject(box)
}

@_cdecl("__kk_regex_containsMatchIn_flat")
public func kk_regex_containsMatchIn_flat(
    _ regexRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeRegexContainsMatchIn(
        regexRaw,
        input: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeRegexContainsMatchIn(_ regexRaw: Int, input rawInput: String) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let input = regexBox.normalizeIfNeeded(rawInput)
    let range = NSRange(input.startIndex..., in: input)
    let match = boundedFirstMatch(regexBox.regex, in: input, options: [], range: range)
    return kk_box_bool(match != nil ? 1 : 0)
}

// MARK: - STDLIB-103: String.toRegex() / Regex.pattern

@_cdecl("__kk_string_toRegex_flat")
public func kk_string_toRegex_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeRegexCreate(
        pattern: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash),
        outThrown: outThrown
    )
}


// MARK: - KSP-486: raw regex / match data bridges
//
// The public `Regex.pattern` / `Regex.options` / `Regex.groupNames` accessors and
// the whole MatchResult / MatchGroup / MatchGroupCollection / Destructured API
// live in `Sources/CompilerCore/Stdlib/kotlin/text/MatchResult.kt`. Only the raw
// data that the Foundation match engine owns is exposed here.

@_cdecl("__kk_regex_pattern")
public func __kk_regex_pattern(_ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return regexMakeStringRaw("") }
    return regexMakeStringRaw(regexBox.pattern)
}

/// Bit mask of the Kotlin `RegexOption` ordinals this regex was created with
/// (bit `n` set means the option with ordinal `n` is present).
@_cdecl("__kk_regex_option_mask")
public func __kk_regex_option_mask(_ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return 0 }
    var mask = 0
    for ordinal in regexBox.optionOrdinals where ordinal >= 0 && ordinal < Int.bitWidth - 1 {
        mask |= 1 << ordinal
    }
    return mask
}

// MARK: - STDLIB-101: MatchResult raw group data

/// Number of groups in the match, including group 0 (the entire match).
@_cdecl("__kk_match_result_group_count")
public func __kk_match_result_group_count(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else { return 0 }
    return matchResult.groupValues.count
}

/// Text of group [index], or the empty string when the group is absent.
@_cdecl("__kk_match_result_group_value")
public func __kk_match_result_group_value(_ matchRaw: Int, _ index: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          index >= 0, index < matchResult.groupValues.count else {
        return regexMakeStringRaw("")
    }
    return regexMakeStringRaw(matchResult.groupValues[index])
}

/// UTF-16 start offset of group [index], or -1 when the group did not participate.
@_cdecl("__kk_match_result_group_start")
public func __kk_match_result_group_start(_ matchRaw: Int, _ index: Int) -> Int {
    guard let group = matchResultGroup(matchRaw, index) else { return -1 }
    return group.rangeStart
}

/// UTF-16 end offset (inclusive) of group [index], or -1 when the group did not participate.
@_cdecl("__kk_match_result_group_end")
public func __kk_match_result_group_end(_ matchRaw: Int, _ index: Int) -> Int {
    guard let group = matchResultGroup(matchRaw, index) else { return -1 }
    return group.rangeEnd
}

/// Index of the capture group named [nameRaw], or -1 when there is no such group.
@_cdecl("__kk_match_result_group_index_of_name")
public func __kk_match_result_group_index_of_name(_ matchRaw: Int, _ nameRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          let name = regexStringFromRaw(nameRaw),
          let index = matchResult.namedGroups[name] else {
        return -1
    }
    return index
}

/// Whether the regex pattern declares a capture group named [nameRaw].
@_cdecl("__kk_match_result_has_named_group")
public func __kk_match_result_has_named_group(_ matchRaw: Int, _ nameRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          let name = regexStringFromRaw(nameRaw) else {
        return 0
    }
    return matchResult.namedGroupNames.contains(name) ? 1 : 0
}

@_cdecl("__kk_match_result_group_index_of_name_flat")
public func __kk_match_result_group_index_of_name_flat(
    _ matchRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else { return -1 }
    let name = regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    return matchResult.namedGroups[name] ?? -1
}

private func matchResultGroup(_ matchRaw: Int, _ index: Int) -> RuntimeMatchGroupBox? {
    guard let matchResult = matchResultBoxFromRaw(matchRaw),
          index >= 0, index < matchResult.groups.count else {
        return nil
    }
    return matchResult.groups[index]
}

/// MatchResult.next() — returns the next MatchResult in the input, or null.
@_cdecl("__kk_match_result_next")
public func __kk_match_result_next(_ matchRaw: Int) -> Int {
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
    guard let result = boundedFirstMatch(regexBox.regex, in: searchStr, options: [], range: nsRange) else {
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

// MARK: - Private helper for next() with offset-adjusted ranges

private func makeMatchResultWithOffset(
    from result: NSTextCheckingResult,
    in str: String,
    inputOffset: Int,
    regexBox: RuntimeRegexBox?,
    fullInput: String
) -> RuntimeMatchResultBox {
    guard let matchRange = Range(result.range, in: str) else {
        return RuntimeMatchResultBox(value: "", groupValues: [])
    }
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
    var namedGroupNames: Set<String> = []
    if let regexBox = regexBox {
        let names = extractNamedGroupNames(from: regexBox.pattern)
        namedGroupNames = Set(names)
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
        namedGroupNames: namedGroupNames,
        inputString: fullInput,
        matchEndOffset: matchEnd,
        regexBox: regexBox
    )
}

// MARK: - STDLIB-REGEX-094: Regex.fromLiteral / Regex.matches / String.replaceFirst(Regex)

/// Regex.Companion.fromLiteral(literal: String) -> Regex
/// Creates a Regex that matches the literal string (all special chars are escaped).
/// The first argument is the Companion object receiver (ignored; companion singleton).
@_cdecl("__kk_regex_from_literal_flat")
public func kk_regex_from_literal_flat(
    _ companionRef: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    _ = companionRef
    return runtimeRegexFromLiteral(
        regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeRegexFromLiteral(_ literal: String) -> Int {
    let escapedPattern = NSRegularExpression.escapedPattern(for: literal)
    guard let regex = try? NSRegularExpression(pattern: escapedPattern, options: []) else {
        return registerRuntimeObject(RuntimeRegexBox(regex: RegexNeverMatch.expression, pattern: literal))
    }
    return registerRuntimeObject(RuntimeRegexBox(regex: regex, pattern: escapedPattern))
}

/// String.replaceFirst(regex: Regex, replacement: String) -> String
/// Replaces only the first match of the regex in the string.
@_cdecl("__kk_string_replaceFirst_regex")
public func kk_string_replaceFirst_regex(_ strRaw: Int, _ regexRaw: Int, _ replacementRaw: Int) -> Int {
    let rawStr = regexStringFromRaw(strRaw) ?? ""
    let replacement = regexStringFromRaw(replacementRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return regexMakeStringRaw(rawStr) }
    let str = regexBox.normalizeIfNeeded(rawStr)
    let range = NSRange(str.startIndex..., in: str)
    guard let match = boundedFirstMatch(regexBox.regex, in: str, options: [], range: range),
          let matchRange = Range(match.range, in: str) else {
        return regexMakeStringRaw(str)
    }
    let templateResult = regexBox.regex.replacementString(for: match, in: str, offset: 0, template: replacement)
    var result = str
    result.replaceSubrange(matchRange, with: templateResult)
    return regexMakeStringRaw(result)
}

// MARK: - STDLIB-REGEX-098: Regex.matches(input)

/// Regex.matches(input): Boolean
/// Returns true if the entire input string is matched by this regex.
///
/// Uses the compiled effective pattern from `regexBox.regex.pattern` (which is
/// already escaped for LITERAL regexes) wrapped in `\A(?:...)\z` to force a
/// full-string match. This correctly handles:
///
/// - **Alternation**: `firstMatch` may find only the first alternative (e.g. "a"
///   for pattern `a|ab`), returning a partial match. Wrapping with `\A...\z`
///   forces the engine to match the entire input.
/// - **MULTILINE**: `.anchorsMatchLines` makes `^`/`$` match line boundaries,
///   not string boundaries. Using `\A`/`\z` avoids this. The option is stripped
///   from the anchored regex so `\A`/`\z` bind to the full string.
/// - **LITERAL**: LITERAL regexes in this runtime are compiled by passing the
///   pre-escaped pattern (via `NSRegularExpression.escapedPattern`) to
///   `NSRegularExpression` without `.ignoreMetacharacters`. Therefore
///   `regexBox.regex.pattern` already holds the escaped form and can be embedded
///   directly. `.ignoreMetacharacters` is stripped from the anchored options
///   (it is never set in practice, but removing it defensively ensures the
///   `\A(?:...)\z` wrapper is always parsed as regex syntax, not literal text.
@_cdecl("__kk_regex_matches_flat")
public func kk_regex_matches_flat(
    _ regexRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeRegexMatches(
        regexRaw,
        input: regexStringFromFlat(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeRegexMatches(_ regexRaw: Int, input rawInput: String) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else { return kk_box_bool(0) }
    let input = regexBox.normalizeIfNeeded(rawInput)
    // Use the effective (compiled) pattern stored in the NSRegularExpression. For
    // LITERAL regexes this is already the pre-escaped form, so embedding it directly
    // inside \A(?:...)\z is safe. Strip .anchorsMatchLines so \A/\z bind to the
    // string boundaries rather than line boundaries, and strip .ignoreMetacharacters
    // (defensive) so the wrapper syntax is always interpreted as real regex syntax.
    let effectivePattern = "\\A(?:\(regexBox.regex.pattern))\\z"
    let anchoredOptions = regexBox.regex.options.subtracting([.anchorsMatchLines, .ignoreMetacharacters])
    guard let anchoredRegex = try? NSRegularExpression(
        pattern: effectivePattern,
        options: anchoredOptions
    ) else { return kk_box_bool(0) }
    let range = NSRange(input.startIndex..., in: input)
    let matched = boundedFirstMatch(anchoredRegex, in: input, options: [], range: range) != nil
    return kk_box_bool(matched ? 1 : 0)
}

// MARK: - STDLIB-TEXT-TYPE-010: MatchResult.Destructured

// `MatchResult.Destructured` carries no state beyond the match it destructures,
// so it is represented by the MatchResult object itself. `component1()`..
// `component9()` are derived in Kotlin from the raw group values above.

/// MatchResult.destructured: MatchResult.Destructured
@_cdecl("__kk_match_result_destructured")
public func __kk_match_result_destructured(_ matchRaw: Int) -> Int {
    guard matchResultBoxFromRaw(matchRaw) != nil else { return runtimeNullSentinelInt }
    return matchRaw
}

/// MatchResult.Destructured.match: MatchResult
@_cdecl("__kk_match_result_destructured_match")
public func __kk_match_result_destructured_match(_ destructuredRaw: Int) -> Int {
    guard matchResultBoxFromRaw(destructuredRaw) != nil else { return runtimeNullSentinelInt }
    return destructuredRaw
}
