import Foundation

// MARK: - BigInteger Runtime Support (STDLIB-NUM-129)

/// Internal box holding a BigInteger value as a Swift Decimal for arbitrary precision arithmetic.
///
/// KSwiftK represents BigInteger as a boxed arbitrary-precision integer using Swift's
/// Decimal type for moderate sizes. The value is stored as a String for lossless
/// representation and operations are performed via string-based arbitrary precision arithmetic.
final class RuntimeBigIntegerBox {
    let value: BigIntValue

    init(value: BigIntValue) {
        self.value = value
    }
}

/// Arbitrary-precision integer backed by an array of 32-bit digits in base 2^32.
/// Supports positive and negative values.
struct BigIntValue: Equatable {
    /// Decimal digits representation for easy I/O
    var stringValue: String

    init(string: String) {
        self.stringValue = string
    }

    init(long: Int64) {
        self.stringValue = String(long)
    }

    static let zero = BigIntValue(string: "0")
    static let one = BigIntValue(string: "1")

    var isNegative: Bool {
        stringValue.hasPrefix("-")
    }

    var absString: String {
        isNegative ? String(stringValue.dropFirst()) : stringValue
    }

    func abs() -> BigIntValue {
        BigIntValue(string: absString)
    }

    func negate() -> BigIntValue {
        if stringValue == "0" {
            return self
        }
        return isNegative
            ? BigIntValue(string: String(stringValue.dropFirst()))
            : BigIntValue(string: "-" + stringValue)
    }

    func toInt() -> Int {
        Int(stringValue) ?? 0
    }

    func toLong() -> Int64 {
        Int64(stringValue) ?? 0
    }

    // MARK: - Comparison helpers

    /// Returns -1, 0, or 1 for absolute value comparison (no sign consideration)
    private static func compareAbsolute(_ a: [UInt32], _ b: [UInt32]) -> Int {
        if a.count != b.count {
            return a.count < b.count ? -1 : 1
        }
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            if a[i] != b[i] {
                return a[i] < b[i] ? -1 : 1
            }
        }
        return 0
    }

    // MARK: - Digit array arithmetic (base 10^9 for simplicity)

    private static let base: UInt64 = 1_000_000_000

    private static func stringToDigits(_ s: String) -> [UInt64] {
        // Returns digits in chunks of 9 decimal digits, least significant first
        var result: [UInt64] = []
        var i = s.endIndex
        while i > s.startIndex {
            let start = s.index(i, offsetBy: -min(9, s.distance(from: s.startIndex, to: i)))
            let chunk = s[start..<i]
            result.append(UInt64(chunk) ?? 0)
            i = start
        }
        return result
    }

    private static func digitsToString(_ digits: [UInt64]) -> String {
        guard !digits.isEmpty else { return "0" }
        var result = ""
        var first = true
        for digit in digits.reversed() {
            if first {
                result += String(digit)
                first = false
            } else {
                result += String(format: "%09llu", digit)
            }
        }
        return result.isEmpty ? "0" : result
    }

    private static func addDigits(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        let maxLen = max(a.count, b.count)
        var result = [UInt64](repeating: 0, count: maxLen + 1)
        var carry: UInt64 = 0
        for i in 0..<maxLen {
            let av: UInt64 = i < a.count ? a[i] : 0
            let bv: UInt64 = i < b.count ? b[i] : 0
            let sum = av + bv + carry
            result[i] = sum % base
            carry = sum / base
        }
        result[maxLen] = carry
        while result.count > 1 && result.last == 0 {
            result.removeLast()
        }
        return result
    }

    // Returns a - b assuming a >= b (absolute values)
    private static func subtractDigits(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        var result = [UInt64](repeating: 0, count: a.count)
        var borrow: Int64 = 0
        for i in 0..<a.count {
            let av = Int64(a[i])
            let bv: Int64 = i < b.count ? Int64(b[i]) : 0
            var diff = av - bv - borrow
            if diff < 0 {
                diff += Int64(base)
                borrow = 1
            } else {
                borrow = 0
            }
            result[i] = UInt64(diff)
        }
        while result.count > 1 && result.last == 0 {
            result.removeLast()
        }
        return result
    }

    private static func compareDigits(_ a: [UInt64], _ b: [UInt64]) -> Int {
        if a.count != b.count {
            return a.count < b.count ? -1 : 1
        }
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            if a[i] < b[i] { return -1 }
            if a[i] > b[i] { return 1 }
        }
        return 0
    }

    private static func multiplyDigits(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        if a.isEmpty || b.isEmpty { return [0] }
        var result = [UInt64](repeating: 0, count: a.count + b.count)
        for i in 0..<a.count {
            var carry: UInt64 = 0
            for j in 0..<b.count {
                let prod = a[i] * b[j] + result[i + j] + carry
                result[i + j] = prod % base
                carry = prod / base
            }
            result[i + b.count] += carry
        }
        while result.count > 1 && result.last == 0 {
            result.removeLast()
        }
        return result
    }

    // Returns (quotient, remainder) for a / b, assuming b != 0 and both are positive digit arrays
    private static func divideDigits(_ a: [UInt64], _ b: [UInt64]) -> ([UInt64], [UInt64]) {
        if compareDigits(a, b) < 0 {
            return ([0], a)
        }
        // Simple long division
        var remainder: [UInt64] = []
        var quotient: [UInt64] = [UInt64](repeating: 0, count: a.count)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            remainder.insert(a[i], at: 0)
            // Find q such that q * b <= remainder < (q+1) * b
            var lo: UInt64 = 0
            var hi: UInt64 = base - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                let prod = multiplyDigits(b, [mid])
                if compareDigits(prod, remainder) <= 0 {
                    lo = mid
                } else {
                    hi = mid - 1
                }
            }
            quotient[i] = lo
            if lo > 0 {
                let prod = multiplyDigits(b, [lo])
                remainder = subtractDigits(remainder, prod)
            }
            while remainder.count > 1 && remainder.last == 0 {
                remainder.removeLast()
            }
        }
        while quotient.count > 1 && quotient.last == 0 {
            quotient.removeLast()
        }
        return (quotient, remainder)
    }

    // MARK: - Operations

    func add(_ other: BigIntValue) -> BigIntValue {
        if isNegative == other.isNegative {
            // Same sign: add absolutes and keep sign
            let aDigits = BigIntValue.stringToDigits(absString)
            let bDigits = BigIntValue.stringToDigits(other.absString)
            let resultDigits = BigIntValue.addDigits(aDigits, bDigits)
            let resultStr = BigIntValue.digitsToString(resultDigits)
            return BigIntValue(string: isNegative && resultStr != "0" ? "-" + resultStr : resultStr)
        } else {
            // Different signs: subtract smaller absolute from larger
            let aDigits = BigIntValue.stringToDigits(absString)
            let bDigits = BigIntValue.stringToDigits(other.absString)
            let cmp = BigIntValue.compareDigits(aDigits, bDigits)
            if cmp == 0 {
                return .zero
            }
            let (larger, smaller, resultNeg): ([UInt64], [UInt64], Bool)
            if cmp > 0 {
                (larger, smaller, resultNeg) = (aDigits, bDigits, isNegative)
            } else {
                (larger, smaller, resultNeg) = (bDigits, aDigits, other.isNegative)
            }
            let resultDigits = BigIntValue.subtractDigits(larger, smaller)
            let resultStr = BigIntValue.digitsToString(resultDigits)
            return BigIntValue(string: resultNeg && resultStr != "0" ? "-" + resultStr : resultStr)
        }
    }

    func subtract(_ other: BigIntValue) -> BigIntValue {
        add(other.negate())
    }

    func multiply(_ other: BigIntValue) -> BigIntValue {
        let aDigits = BigIntValue.stringToDigits(absString)
        let bDigits = BigIntValue.stringToDigits(other.absString)
        let resultDigits = BigIntValue.multiplyDigits(aDigits, bDigits)
        let resultStr = BigIntValue.digitsToString(resultDigits)
        let resultNeg = isNegative != other.isNegative
        return BigIntValue(string: resultNeg && resultStr != "0" ? "-" + resultStr : resultStr)
    }

    func divide(_ other: BigIntValue) -> BigIntValue {
        let aDigits = BigIntValue.stringToDigits(absString)
        let bDigits = BigIntValue.stringToDigits(other.absString)
        let (quotientDigits, _) = BigIntValue.divideDigits(aDigits, bDigits)
        let resultStr = BigIntValue.digitsToString(quotientDigits)
        let resultNeg = isNegative != other.isNegative
        return BigIntValue(string: resultNeg && resultStr != "0" ? "-" + resultStr : resultStr)
    }

    func gcd(_ other: BigIntValue) -> BigIntValue {
        // Euclidean algorithm on absolute values
        var aDigits = BigIntValue.stringToDigits(absString)
        var bDigits = BigIntValue.stringToDigits(other.absString)
        while BigIntValue.compareDigits(bDigits, [0]) != 0 {
            let (_, rem) = BigIntValue.divideDigits(aDigits, bDigits)
            aDigits = bDigits
            bDigits = rem
            while bDigits.count > 1 && bDigits.last == 0 {
                bDigits.removeLast()
            }
        }
        return BigIntValue(string: BigIntValue.digitsToString(aDigits))
    }

    func pow(_ exponent: Int) -> BigIntValue {
        if exponent == 0 { return .one }
        if exponent == 1 { return self }
        var result = BigIntValue.one
        var base = self
        var exp = exponent
        while exp > 0 {
            if exp & 1 == 1 {
                result = result.multiply(base)
            }
            base = base.multiply(base)
            exp >>= 1
        }
        return result
    }

}

// MARK: - Helper

private func runtimeBigIntegerBox(from rawValue: Int) -> RuntimeBigIntegerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeBigIntegerBox.self)
}

private func bigIntMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

// MARK: - BigInteger.valueOf(long)

@_cdecl("kk_biginteger_valueOf")
public func kk_biginteger_valueOf(_ longValue: Int) -> Int {
    let box = RuntimeBigIntegerBox(value: BigIntValue(long: Int64(truncatingIfNeeded: longValue)))
    return registerRuntimeObject(box)
}

// MARK: - BigInteger(String) constructor

@_cdecl("kk_biginteger_fromString")
public func kk_biginteger_fromString(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: strRaw),
          let str = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_biginteger_fromString received invalid string handle")
    }
    // Validate integer format: optional leading sign followed by one or more digits
    var idx = str.startIndex
    guard idx < str.endIndex else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "NumberFormatException: For input string: \"\(str)\""
        )
        return 0
    }
    if str[idx] == "+" || str[idx] == "-" {
        idx = str.index(after: idx)
    }
    let digitStart = idx
    while idx < str.endIndex, str[idx] >= "0", str[idx] <= "9" {
        idx = str.index(after: idx)
    }
    guard idx > digitStart && idx == str.endIndex else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "NumberFormatException: For input string: \"\(str)\""
        )
        return 0
    }
    // Normalize: remove leading zeros but keep sign
    let isNeg = str.hasPrefix("-")
    let absStr = isNeg ? String(str.dropFirst()) : str.hasPrefix("+") ? String(str.dropFirst()) : str
    let normalized = absStr.drop(while: { $0 == "0" })
    let normalizedStr = normalized.isEmpty ? "0" : String(normalized)
    let finalStr = isNeg && normalizedStr != "0" ? "-" + normalizedStr : normalizedStr
    let box = RuntimeBigIntegerBox(value: BigIntValue(string: finalStr))
    return registerRuntimeObject(box)
}

// MARK: - add()

@_cdecl("kk_biginteger_add")
public func kk_biginteger_add(_ selfRaw: Int, _ otherRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw),
          let otherBox = runtimeBigIntegerBox(from: otherRaw)
    else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.add(otherBox.value)
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - subtract()

@_cdecl("kk_biginteger_subtract")
public func kk_biginteger_subtract(_ selfRaw: Int, _ otherRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw),
          let otherBox = runtimeBigIntegerBox(from: otherRaw)
    else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.subtract(otherBox.value)
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - multiply()

@_cdecl("kk_biginteger_multiply")
public func kk_biginteger_multiply(_ selfRaw: Int, _ otherRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw),
          let otherBox = runtimeBigIntegerBox(from: otherRaw)
    else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.multiply(otherBox.value)
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - divide()

@_cdecl("kk_biginteger_divide")
public func kk_biginteger_divide(_ selfRaw: Int, _ otherRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw),
          let otherBox = runtimeBigIntegerBox(from: otherRaw)
    else {
        return kk_biginteger_valueOf(0)
    }
    if otherBox.value.stringValue == "0" {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArithmeticException: / by zero")
        return 0
    }
    let result = selfBox.value.divide(otherBox.value)
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - gcd()

@_cdecl("kk_biginteger_gcd")
public func kk_biginteger_gcd(_ selfRaw: Int, _ otherRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw),
          let otherBox = runtimeBigIntegerBox(from: otherRaw)
    else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.gcd(otherBox.value)
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - abs()

@_cdecl("kk_biginteger_abs")
public func kk_biginteger_abs(_ selfRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw) else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.abs()
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - pow()

@_cdecl("kk_biginteger_pow")
public func kk_biginteger_pow(_ selfRaw: Int, _ exponent: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if exponent < 0 {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArithmeticException: Negative exponent")
        return 0
    }
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw) else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.pow(exponent)
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - toInt()

@_cdecl("kk_biginteger_toInt")
public func kk_biginteger_toInt(_ selfRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw) else {
        return 0
    }
    return selfBox.value.toInt()
}

// MARK: - toLong()

@_cdecl("kk_biginteger_toLong")
public func kk_biginteger_toLong(_ selfRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw) else {
        return 0
    }
    return Int(selfBox.value.toLong())
}

// MARK: - toString()

@_cdecl("kk_biginteger_toString")
public func kk_biginteger_toString(_ selfRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw) else {
        return bigIntMakeStringRaw("0")
    }
    return bigIntMakeStringRaw(selfBox.value.stringValue)
}
