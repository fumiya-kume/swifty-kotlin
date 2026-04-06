import Foundation

// MARK: - DecimalFormat Runtime Box

/// Runtime representation of java.text.DecimalFormat.
/// Wraps Foundation's NumberFormatter and stores the original Kotlin-style pattern.
final class RuntimeDecimalFormatBox {
    let formatter: NumberFormatter
    let pattern: String

    init(pattern: String, locale: Locale?) {
        self.pattern = pattern
        let formatter = NumberFormatter()
        formatter.locale = locale ?? Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        RuntimeDecimalFormatBox.applyPattern(pattern, to: formatter)
        self.formatter = formatter
    }

    /// Applies a Kotlin/Java-style decimal pattern (e.g. "#,##0.00") to a NumberFormatter.
    private static func applyPattern(_ pattern: String, to formatter: NumberFormatter) {
        // Split positive/negative sub-patterns
        let subPatterns = pattern.components(separatedBy: ";")
        let positivePattern = subPatterns[0]

        // Detect grouping separator in the integer part
        let integerPart: String
        let fractionPart: String
        if let dotIndex = positivePattern.firstIndex(of: ".") {
            integerPart = String(positivePattern[positivePattern.startIndex..<dotIndex])
            fractionPart = String(positivePattern[positivePattern.index(after: dotIndex)...])
        } else {
            integerPart = positivePattern
            fractionPart = ""
        }

        // Grouping
        let integerStripped = integerPart.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "+", with: "")
        let groupingEnabled = integerStripped.contains(",")
        formatter.usesGroupingSeparator = groupingEnabled
        if groupingEnabled {
            let groups = integerStripped.components(separatedBy: ",")
            formatter.groupingSize = groups.last.map { $0.filter { $0 == "#" || $0 == "0" }.count } ?? 3
        }

        // Minimum integer digits (count of '0' in integer part)
        let minIntDigits = integerStripped.filter { $0 == "0" }.count
        formatter.minimumIntegerDigits = max(1, minIntDigits)

        // Fraction digits
        let minFrac = fractionPart.filter { $0 == "0" }.count
        let maxFrac = fractionPart.filter { $0 == "0" || $0 == "#" }.count
        formatter.minimumFractionDigits = minFrac
        formatter.maximumFractionDigits = maxFrac

        // Percent / per-mille
        if positivePattern.contains("%") {
            formatter.numberStyle = .percent
            formatter.multiplier = 100
        } else if positivePattern.contains("‰") {
            formatter.multiplier = 1000
        }

        // Prefix / suffix (characters that are not pattern chars)
        let patternChars = CharacterSet(charactersIn: "0#,.E-+;@%‰")
        func extractAffix(_ s: String) -> (prefix: String, suffix: String) {
            var prefix = ""
            var suffix = ""
            var hitPattern = false
            var hitSuffix = false
            for ch in s {
                let scalar = ch.unicodeScalars.first!
                if patternChars.contains(scalar) {
                    hitPattern = true
                } else if hitPattern {
                    hitSuffix = true
                    suffix.append(ch)
                } else if !hitSuffix {
                    prefix.append(ch)
                }
            }
            return (prefix, suffix)
        }

        let (positivePrefix, positiveSuffix) = extractAffix(positivePattern)
        formatter.positivePrefix = positivePrefix
        formatter.positiveSuffix = positiveSuffix

        if subPatterns.count > 1 {
            let (negativePrefix, negativeSuffix) = extractAffix(subPatterns[1])
            formatter.negativePrefix = negativePrefix
            formatter.negativeSuffix = negativeSuffix
        } else {
            formatter.negativePrefix = formatter.positivePrefix + "-"
            formatter.negativeSuffix = formatter.positiveSuffix
        }
    }
}

// MARK: - Private Helpers

private func numberFormatString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let value = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return value
}

private func numberFormatMakeStringRaw(_ value: String) -> Int {
    var result: Int = 0
    value.utf8.withContiguousStorageIfAvailable { bytes in
        result = Int(bitPattern: kk_string_from_utf8(bytes.baseAddress!, Int32(bytes.count)))
    } ?? {
        let bytes = Array(value.utf8)
        result = Int(bitPattern: bytes.withUnsafeBufferPointer { buf in
            kk_string_from_utf8(buf.baseAddress!, Int32(buf.count))
        })
    }()
    return result
}

private func decimalFormatBox(from raw: Int) -> RuntimeDecimalFormatBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeDecimalFormatBox.self)
}

private func numberFormatLocale(from raw: Int) -> Locale? {
    runtimeLocaleBox(from: raw)?.locale
}

// MARK: - DecimalFormat factory

@_cdecl("kk_decimalformat_new")
public func kk_decimalformat_new(_ patternRaw: Int) -> Int {
    let pattern = numberFormatString(from: patternRaw, caller: #function)
    return registerRuntimeObject(RuntimeDecimalFormatBox(pattern: pattern, locale: Locale(identifier: "en_US_POSIX")))
}

@_cdecl("kk_decimalformat_newWithLocale")
public func kk_decimalformat_newWithLocale(_ patternRaw: Int, _ localeRaw: Int) -> Int {
    let pattern = numberFormatString(from: patternRaw, caller: #function)
    let locale = numberFormatLocale(from: localeRaw)
    return registerRuntimeObject(RuntimeDecimalFormatBox(pattern: pattern, locale: locale))
}

// MARK: - DecimalFormat.format()

private func decimalFormatString(_ formatterRaw: Int, value: NSNumber, caller: StaticString) -> Int {
    guard let box = decimalFormatBox(from: formatterRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid DecimalFormat handle")
    }
    guard let formatted = box.formatter.string(from: value) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) failed to format number")
    }
    return numberFormatMakeStringRaw(formatted)
}

@_cdecl("kk_decimalformat_formatInt")
public func kk_decimalformat_formatInt(_ formatRaw: Int, _ value: Int) -> Int {
    decimalFormatString(formatRaw, value: NSNumber(value: value), caller: #function)
}

@_cdecl("kk_decimalformat_formatLong")
public func kk_decimalformat_formatLong(_ formatRaw: Int, _ value: Int) -> Int {
    decimalFormatString(formatRaw, value: NSNumber(value: Int64(value)), caller: #function)
}

@_cdecl("kk_decimalformat_formatDouble")
public func kk_decimalformat_formatDouble(_ formatRaw: Int, _ value: Double) -> Int {
    decimalFormatString(formatRaw, value: NSNumber(value: value), caller: #function)
}

@_cdecl("kk_decimalformat_formatFloat")
public func kk_decimalformat_formatFloat(_ formatRaw: Int, _ value: Float) -> Int {
    decimalFormatString(formatRaw, value: NSNumber(value: value), caller: #function)
}

// MARK: - DecimalFormat.parse()

/// Returns a boxed Double, or null sentinel if parsing fails.
@_cdecl("kk_decimalformat_parse")
public func kk_decimalformat_parse(_ formatRaw: Int, _ stringRaw: Int) -> Int {
    guard let box = decimalFormatBox(from: formatRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_decimalformat_parse received invalid DecimalFormat handle")
    }
    let str = numberFormatString(from: stringRaw, caller: #function)
    guard let number = box.formatter.number(from: str) else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimeDoubleBox(number.doubleValue))
}

// MARK: - NumberFormat.parse()

/// Parses a string using an existing NumberFormat box (from RuntimeI18N).
@_cdecl("kk_numberformat_parse")
public func kk_numberformat_parse(_ formatRaw: Int, _ stringRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: formatRaw),
          let box = tryCast(ptr, to: RuntimeNumberFormatBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_numberformat_parse received invalid NumberFormat handle")
    }
    let str = numberFormatString(from: stringRaw, caller: #function)
    guard let number = box.formatter.number(from: str) else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimeDoubleBox(number.doubleValue))
}

// MARK: - NumberFormat grouping separator / decimal separator accessors

@_cdecl("kk_numberformat_getGroupingSeparator")
public func kk_numberformat_getGroupingSeparator(_ formatRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: formatRaw),
          let box = tryCast(ptr, to: RuntimeNumberFormatBox.self)
    else {
        return numberFormatMakeStringRaw(",")
    }
    let sep = box.formatter.groupingSeparator ?? ","
    return numberFormatMakeStringRaw(sep)
}

@_cdecl("kk_numberformat_getDecimalSeparator")
public func kk_numberformat_getDecimalSeparator(_ formatRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: formatRaw),
          let box = tryCast(ptr, to: RuntimeNumberFormatBox.self)
    else {
        return numberFormatMakeStringRaw(".")
    }
    let sep = box.formatter.decimalSeparator ?? "."
    return numberFormatMakeStringRaw(sep)
}

@_cdecl("kk_decimalformat_getGroupingSeparator")
public func kk_decimalformat_getGroupingSeparator(_ formatRaw: Int) -> Int {
    guard let box = decimalFormatBox(from: formatRaw) else {
        return numberFormatMakeStringRaw(",")
    }
    let sep = box.formatter.groupingSeparator ?? ","
    return numberFormatMakeStringRaw(sep)
}

@_cdecl("kk_decimalformat_getDecimalSeparator")
public func kk_decimalformat_getDecimalSeparator(_ formatRaw: Int) -> Int {
    guard let box = decimalFormatBox(from: formatRaw) else {
        return numberFormatMakeStringRaw(".")
    }
    let sep = box.formatter.decimalSeparator ?? "."
    return numberFormatMakeStringRaw(sep)
}

// MARK: - NumberFormat.setGroupingUsed / setMaximumFractionDigits

@_cdecl("kk_numberformat_setGroupingUsed")
public func kk_numberformat_setGroupingUsed(_ formatRaw: Int, _ used: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: formatRaw),
          let box = tryCast(ptr, to: RuntimeNumberFormatBox.self)
    else { return 0 }
    box.formatter.usesGroupingSeparator = used != 0
    return 0
}

@_cdecl("kk_numberformat_setMaximumFractionDigits")
public func kk_numberformat_setMaximumFractionDigits(_ formatRaw: Int, _ digits: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: formatRaw),
          let box = tryCast(ptr, to: RuntimeNumberFormatBox.self)
    else { return 0 }
    box.formatter.maximumFractionDigits = digits
    return 0
}

@_cdecl("kk_numberformat_setMinimumFractionDigits")
public func kk_numberformat_setMinimumFractionDigits(_ formatRaw: Int, _ digits: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: formatRaw),
          let box = tryCast(ptr, to: RuntimeNumberFormatBox.self)
    else { return 0 }
    box.formatter.minimumFractionDigits = digits
    return 0
}
