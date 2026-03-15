import Foundation

// MARK: - Regex Runtime Types

final class RuntimeRegexBox {
    let regex: NSRegularExpression
    let pattern: String

    init(regex: NSRegularExpression, pattern: String) {
        self.regex = regex
        self.pattern = pattern
    }
}

final class RuntimeMatchResultBox {
    let value: String
    let groupValues: [String]

    init(value: String, groupValues: [String]) {
        self.value = value
        self.groupValues = groupValues
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

private func makeMatchResult(from result: NSTextCheckingResult, in str: String) -> RuntimeMatchResultBox {
    let matchRange = Range(result.range, in: str)!
    let value = String(str[matchRange])

    var groupValues: [String] = []
    for i in 0 ..< result.numberOfRanges {
        let groupRange = result.range(at: i)
        if groupRange.location != NSNotFound, let range = Range(groupRange, in: str) {
            groupValues.append(String(str[range]))
        } else {
            groupValues.append("")
        }
    }

    return RuntimeMatchResultBox(value: value, groupValues: groupValues)
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
    let str = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Regex handle")
    }
    let range = NSRange(str.startIndex..., in: str)
    let match = regexBox.regex.firstMatch(in: str, options: [.anchored], range: range)
    let fullMatch = match != nil && match!.range.length == range.length
    return kk_box_bool(fullMatch ? 1 : 0)
}

@_cdecl("kk_string_contains_regex")
public func kk_string_contains_regex(_ strRaw: Int, _ regexRaw: Int) -> Int {
    let str = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Regex handle")
    }
    let range = NSRange(str.startIndex..., in: str)
    let match = regexBox.regex.firstMatch(in: str, options: [], range: range)
    return kk_box_bool(match != nil ? 1 : 0)
}

// MARK: - STDLIB-101: Regex.find / Regex.findAll

@_cdecl("kk_regex_find")
public func kk_regex_find(_ regexRaw: Int, _ strRaw: Int) -> Int {
    let str = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Regex handle")
    }
    let range = NSRange(str.startIndex..., in: str)
    guard let result = regexBox.regex.firstMatch(in: str, options: [], range: range) else {
        return runtimeNullSentinelInt
    }
    let matchResult = makeMatchResult(from: result, in: str)
    return registerRuntimeObject(matchResult)
}

@_cdecl("kk_regex_findAll")
public func kk_regex_findAll(_ regexRaw: Int, _ strRaw: Int) -> Int {
    let str = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Regex handle")
    }
    let range = NSRange(str.startIndex..., in: str)
    let results = regexBox.regex.matches(in: str, options: [], range: range)
    let matchResults = results.map { result -> Int in
        let matchResult = makeMatchResult(from: result, in: str)
        return registerRuntimeObject(matchResult)
    }
    return regexMakeListRaw(matchResults)
}

// MARK: - STDLIB-102: String.replace(Regex) / String.split(Regex)

@_cdecl("kk_string_replace_regex")
public func kk_string_replace_regex(_ strRaw: Int, _ regexRaw: Int, _ replacementRaw: Int) -> Int {
    let str = regexStringFromRaw(strRaw) ?? ""
    let replacement = regexStringFromRaw(replacementRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Regex handle")
    }
    let range = NSRange(str.startIndex..., in: str)
    let result = regexBox.regex.stringByReplacingMatches(in: str, options: [], range: range, withTemplate: replacement)
    return regexMakeStringRaw(result)
}

@_cdecl("kk_string_split_regex")
public func kk_string_split_regex(_ strRaw: Int, _ regexRaw: Int) -> Int {
    let str = regexStringFromRaw(strRaw) ?? ""
    guard let regexBox = regexBoxFromRaw(regexRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Regex handle")
    }
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

// MARK: - STDLIB-103: String.toRegex() / Regex.pattern

@_cdecl("kk_string_toRegex")
public func kk_string_toRegex(_ strRaw: Int) -> Int {
    kk_regex_create(strRaw)
}

@_cdecl("kk_regex_pattern")
public func kk_regex_pattern(_ regexRaw: Int) -> Int {
    guard let regexBox = regexBoxFromRaw(regexRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid Regex handle")
    }
    return regexMakeStringRaw(regexBox.pattern)
}

// MARK: - STDLIB-101: MatchResult properties

@_cdecl("kk_match_result_value")
public func kk_match_result_value(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid MatchResult handle")
    }
    return regexMakeStringRaw(matchResult.value)
}

@_cdecl("kk_match_result_groupValues")
public func kk_match_result_groupValues(_ matchRaw: Int) -> Int {
    guard let matchResult = matchResultBoxFromRaw(matchRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid MatchResult handle")
    }
    return regexMakeStringListRaw(matchResult.groupValues)
}
