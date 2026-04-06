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

    func toByteArray() -> [UInt8] {
        return twosComplementBytes()
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
            while remainder.count > 1 && remainder.last == 0 {
                remainder.removeLast()
            }
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

    private static func divideDigitsByUInt32(_ digits: [UInt64], _ divisor: UInt32) -> ([UInt64], UInt32) {
        guard divisor != 0 else {
            return ([0], 0)
        }
        var quotient = [UInt64](repeating: 0, count: max(digits.count, 1))
        var remainder: UInt64 = 0
        for index in stride(from: digits.count - 1, through: 0, by: -1) {
            let partial = remainder * base + digits[index]
            quotient[index] = partial / UInt64(divisor)
            remainder = partial % UInt64(divisor)
        }
        while quotient.count > 1 && quotient.last == 0 {
            quotient.removeLast()
        }
        return (quotient, UInt32(remainder))
    }

    private static func multiplyDigitsByUInt32(_ digits: [UInt64], _ factor: UInt32) -> [UInt64] {
        guard factor != 0 else { return [0] }
        var result = [UInt64](repeating: 0, count: max(digits.count, 1))
        var carry: UInt64 = 0
        for index in 0..<digits.count {
            let partial = digits[index] * UInt64(factor) + carry
            result[index] = partial % base
            carry = partial / base
        }
        while carry > 0 {
            result.append(carry % base)
            carry /= base
        }
        while result.count > 1 && result.last == 0 {
            result.removeLast()
        }
        return result
    }

    private static func addUInt32ToDigits(_ digits: [UInt64], _ value: UInt32) -> [UInt64] {
        var result = digits.isEmpty ? [0] : digits
        var carry = UInt64(value)
        var index = 0
        while carry > 0 {
            if index == result.count {
                result.append(0)
            }
            let partial = result[index] + carry
            result[index] = partial % base
            carry = partial / base
            index += 1
        }
        while result.count > 1 && result.last == 0 {
            result.removeLast()
        }
        return result
    }

    private static func magnitudeBytes(from decimalString: String) -> [UInt8] {
        var digits = stringToDigits(decimalString)
        if digits.count == 1, digits[0] == 0 {
            return [0]
        }
        var bytes: [UInt8] = []
        while !(digits.count == 1 && digits[0] == 0) {
            let (quotient, remainder) = divideDigitsByUInt32(digits, 256)
            bytes.append(UInt8(truncatingIfNeeded: remainder))
            digits = quotient
        }
        return bytes.reversed()
    }

    private static func digits(fromMagnitudeBytes bytes: [UInt8]) -> [UInt64] {
        var digits: [UInt64] = [0]
        for byte in bytes {
            digits = multiplyDigitsByUInt32(digits, 256)
            digits = addUInt32ToDigits(digits, UInt32(byte))
        }
        return digits
    }

    private static func normalizeTwosComplementBytes(_ bytes: [UInt8]) -> [UInt8] {
        guard !bytes.isEmpty else { return [0] }
        let negative = bytes[0] & 0x80 != 0
        var start = 0
        if negative {
            while start < bytes.count - 1 && bytes[start] == 0xFF && bytes[start + 1] & 0x80 != 0 {
                start += 1
            }
        } else {
            while start < bytes.count - 1 && bytes[start] == 0x00 && bytes[start + 1] & 0x80 == 0 {
                start += 1
            }
        }
        return Array(bytes[start...])
    }

    private static func signExtended(_ bytes: [UInt8], to width: Int) -> [UInt8] {
        guard bytes.count < width else { return bytes }
        let fill = bytes.first.map { $0 & 0x80 != 0 ? UInt8(0xFF) : UInt8(0x00) } ?? 0x00
        return Array(repeating: fill, count: width - bytes.count) + bytes
    }

    private static func addOneToBytes(_ bytes: [UInt8]) -> [UInt8] {
        guard !bytes.isEmpty else { return [1] }
        var result = bytes
        var index = result.count - 1
        while true {
            if result[index] == 0xFF {
                result[index] = 0x00
                if index == 0 {
                    result.insert(0x01, at: 0)
                    break
                }
                index -= 1
            } else {
                result[index] &+= 1
                break
            }
        }
        return result
    }

    private func twosComplementBytes() -> [UInt8] {
        if stringValue == "0" {
            return [0]
        }
        let magnitude = BigIntValue.magnitudeBytes(from: absString)
        if !isNegative {
            if let first = magnitude.first, first & 0x80 != 0 {
                return [0x00] + magnitude
            }
            return magnitude
        }

        var width = magnitude.count
        if let first = magnitude.first,
           first > 0x80 || (first == 0x80 && magnitude.dropFirst().contains(where: { $0 != 0 }))
        {
            width += 1
        }
        var bytes = BigIntValue.signExtended(magnitude, to: width)
        bytes = bytes.map { ~$0 }
        bytes = BigIntValue.addOneToBytes(bytes)
        return BigIntValue.normalizeTwosComplementBytes(bytes)
    }

    private static func fromTwosComplementBytes(_ bytes: [UInt8]) -> BigIntValue {
        let normalized = normalizeTwosComplementBytes(bytes)
        guard !normalized.isEmpty else {
            return .zero
        }
        let negative = normalized[0] & 0x80 != 0
        if !negative {
            let magnitude = digits(fromMagnitudeBytes: normalized)
            return BigIntValue(string: digitsToString(magnitude))
        }

        var magnitudeBytes = normalized.map { ~$0 }
        magnitudeBytes = addOneToBytes(magnitudeBytes)
        while magnitudeBytes.count > 1 && magnitudeBytes[0] == 0 {
            magnitudeBytes.removeFirst()
        }
        let magnitudeDigits = digits(fromMagnitudeBytes: magnitudeBytes)
        let magnitudeString = digitsToString(magnitudeDigits)
        return magnitudeString == "0" ? .zero : BigIntValue(string: "-" + magnitudeString)
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

    func modInverse(_ modulus: BigIntValue) throws -> BigIntValue {
        guard modulus.stringValue != "0" else {
            throw NSError(domain: "ArithmeticException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Modulus must be non-zero"])
        }
        
        let a = self.abs()
        let m = modulus.abs()
        
        // Extended Euclidean Algorithm
        var oldR = a
        var r = m
        var oldS = BigIntValue(string: "1")
        var s = BigIntValue(string: "0")
        var oldT = BigIntValue(string: "0")
        var t = BigIntValue(string: "1")
        
        while r.stringValue != "0" {
            let quotient = oldR.divide(r)
            let tempR = r
            r = oldR.subtract(quotient.multiply(r))
            oldR = tempR
            
            let tempS = s
            s = oldS.subtract(quotient.multiply(s))
            oldS = tempS
            
            let tempT = t
            t = oldT.subtract(quotient.multiply(t))
            oldT = tempT
        }
        
        // Check if inverse exists
        if oldR.stringValue != "1" {
            throw NSError(domain: "ArithmeticException", code: 0, userInfo: [NSLocalizedDescriptionKey: "BigInteger has no modular inverse"])
        }
        
        var result = oldS
        if result.isNegative {
            result = result.add(m)
        }
        
        // Handle sign of original number
        if isNegative {
            result = result.negate()
            result = result.add(m)
        }
        
        return result
    }

    func modPow(_ exponent: BigIntValue, _ modulus: BigIntValue) throws -> BigIntValue {
        guard modulus.stringValue != "0" else {
            throw NSError(
                domain: "ArithmeticException",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Modulus must be non-zero"]
            )
        }
        
        if exponent.stringValue == "0" {
            // a^0 mod m = 1 mod m
            // If modulus is 1, then 1 mod 1 = 0
            if modulus.stringValue == "1" {
                return BigIntValue(string: "0")
            } else {
                return BigIntValue(string: "1")
            }
        }
        
        if exponent.isNegative {
            let inv = try modInverse(modulus)
            return try inv.modPow(exponent.negate(), modulus)
        }
        
        var result = BigIntValue(string: "1")
        var base = self.mod(modulus)
        var exp = exponent
        
        while exp.stringValue != "0" {
            if exp.and(BigIntValue(string: "1")).stringValue != "0" {
                result = result.multiply(base).mod(modulus)
            }
            base = base.multiply(base).mod(modulus)
            exp = exp.shiftRight(1)
        }
        
        return result
    }

    private func mod(_ modulus: BigIntValue) -> BigIntValue {
        let aDigits = BigIntValue.stringToDigits(absString)
        let bDigits = BigIntValue.stringToDigits(modulus.absString)
        let (_, remainderDigits) = BigIntValue.divideDigits(aDigits, bDigits)
        let remainderStr = BigIntValue.digitsToString(remainderDigits)
        let resultNeg = isNegative && remainderStr != "0"
        return BigIntValue(string: resultNeg ? "-" + remainderStr : remainderStr)
    }

    func and(_ other: BigIntValue) -> BigIntValue {
        let lhsBytes = twosComplementBytes()
        let rhsBytes = other.twosComplementBytes()
        let width = max(lhsBytes.count, rhsBytes.count)
        let lhsExtended = BigIntValue.signExtended(lhsBytes, to: width)
        let rhsExtended = BigIntValue.signExtended(rhsBytes, to: width)
        let resultBytes = zip(lhsExtended, rhsExtended).map { $0 & $1 }
        return BigIntValue.fromTwosComplementBytes(resultBytes)
    }

    func or(_ other: BigIntValue) -> BigIntValue {
        let lhsBytes = twosComplementBytes()
        let rhsBytes = other.twosComplementBytes()
        let width = max(lhsBytes.count, rhsBytes.count)
        let lhsExtended = BigIntValue.signExtended(lhsBytes, to: width)
        let rhsExtended = BigIntValue.signExtended(rhsBytes, to: width)
        let resultBytes = zip(lhsExtended, rhsExtended).map { $0 | $1 }
        return BigIntValue.fromTwosComplementBytes(resultBytes)
    }

    func xor(_ other: BigIntValue) -> BigIntValue {
        let lhsBytes = twosComplementBytes()
        let rhsBytes = other.twosComplementBytes()
        let width = max(lhsBytes.count, rhsBytes.count)
        let lhsExtended = BigIntValue.signExtended(lhsBytes, to: width)
        let rhsExtended = BigIntValue.signExtended(rhsBytes, to: width)
        let resultBytes = zip(lhsExtended, rhsExtended).map { $0 ^ $1 }
        return BigIntValue.fromTwosComplementBytes(resultBytes)
    }

    func not() -> BigIntValue {
        let bytes = twosComplementBytes()
        let invertedBytes = bytes.map { ~$0 }
        return BigIntValue.fromTwosComplementBytes(invertedBytes)
    }

    func shiftLeft(_ n: Int) -> BigIntValue {
        if n == 0 { return self }
        if n < 0 { return shiftRight(-n) }
        
        let bytes = twosComplementBytes()
        let totalShiftBits = n
        let byteShift = totalShiftBits / 8
        let bitShift = totalShiftBits % 8
        
        var result = [UInt8](repeating: 0, count: bytes.count + byteShift + 1)
        
        for i in 0..<bytes.count {
            let sourceIdx = i
            let targetIdx = i + byteShift
            
            var value = UInt16(bytes[sourceIdx]) << UInt16(bitShift)
            result[targetIdx] |= UInt8(value & 0xFF)
            
            if bitShift > 0 && targetIdx + 1 < result.count {
                result[targetIdx + 1] |= UInt8((value >> 8) & 0xFF)
            }
        }

        // Drop redundant LSB zero bytes (big-endian twos-complement); avoids e.g. [8,0] → 2048.
        while result.count > 1,
              result[result.count - 1] == 0,
              (result[result.count - 2] & 0x80) == 0 {
            result.removeLast()
        }

        return BigIntValue.fromTwosComplementBytes(result)
    }

    func shiftRight(_ n: Int) -> BigIntValue {
        if n == 0 { return self }
        if n < 0 { return shiftLeft(-n) }
        
        let bytes = twosComplementBytes()
        let totalShiftBits = n
        let byteShift = totalShiftBits / 8
        let bitShift = totalShiftBits % 8
        
        if byteShift >= bytes.count {
            if bytes.first.map({ $0 & 0x80 != 0 }) ?? false {
                return BigIntValue(string: "-1")
            } else {
                return .zero
            }
        }
        
        var result = [UInt8](repeating: 0, count: bytes.count - byteShift)
        let isNegative = bytes.first.map({ $0 & 0x80 != 0 }) ?? false
        
        for i in 0..<result.count {
            let sourceIdx = i + byteShift
            let targetIdx = i
            
            var value = UInt16(bytes[sourceIdx]) >> UInt16(bitShift)
            
            if bitShift > 0 && sourceIdx + 1 < bytes.count {
                value |= UInt16(bytes[sourceIdx + 1]) << UInt16(8 - bitShift)
            }
            
            result[targetIdx] = UInt8(value & 0xFF)
        }

        // Arithmetic right shift: set the top `bitShift` bits of the MSB to 1 for negative values.
        if isNegative, !result.isEmpty, bitShift > 0 {
            let mask = UInt8(truncatingIfNeeded: (0xFF << (8 - bitShift)) & 0xFF)
            result[0] |= mask
        }

        return BigIntValue.fromTwosComplementBytes(result)
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

// MARK: - and()

@_cdecl("kk_biginteger_and")
public func kk_biginteger_and(_ selfRaw: Int, _ otherRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw),
          let otherBox = runtimeBigIntegerBox(from: otherRaw)
    else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.and(otherBox.value)
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - or()

@_cdecl("kk_biginteger_or")
public func kk_biginteger_or(_ selfRaw: Int, _ otherRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw),
          let otherBox = runtimeBigIntegerBox(from: otherRaw)
    else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.or(otherBox.value)
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - xor()

@_cdecl("kk_biginteger_xor")
public func kk_biginteger_xor(_ selfRaw: Int, _ otherRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw),
          let otherBox = runtimeBigIntegerBox(from: otherRaw)
    else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.xor(otherBox.value)
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - not()

@_cdecl("kk_biginteger_not")
public func kk_biginteger_not(_ selfRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw) else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.not()
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - shiftLeft()

@_cdecl("kk_biginteger_shiftLeft")
public func kk_biginteger_shiftLeft(_ selfRaw: Int, _ n: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw) else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.shiftLeft(n)
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - shiftRight()

@_cdecl("kk_biginteger_shiftRight")
public func kk_biginteger_shiftRight(_ selfRaw: Int, _ n: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw) else {
        return kk_biginteger_valueOf(0)
    }
    let result = selfBox.value.shiftRight(n)
    return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
}

// MARK: - modInverse()

@_cdecl("kk_biginteger_modInverse")
public func kk_biginteger_modInverse(_ selfRaw: Int, _ modulusRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw),
          let modulusBox = runtimeBigIntegerBox(from: modulusRaw)
    else {
        return kk_biginteger_valueOf(0)
    }
    if modulusBox.value.stringValue == "0" {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArithmeticException: Modulus must be non-zero")
        return 0
    }
    
    do {
        let result = try selfBox.value.modInverse(modulusBox.value)
        return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
    } catch let error as NSError {
        let errorMessage = error.userInfo[NSLocalizedDescriptionKey] as? String ?? "ArithmeticException: BigInteger has no modular inverse"
        outThrown?.pointee = runtimeAllocateThrowable(message: errorMessage)
        return 0
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArithmeticException: BigInteger has no modular inverse")
        return 0
    }
}

// MARK: - modPow()

@_cdecl("kk_biginteger_modPow")
public func kk_biginteger_modPow(_ selfRaw: Int, _ exponentRaw: Int, _ modulusRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw),
          let exponentBox = runtimeBigIntegerBox(from: exponentRaw),
          let modulusBox = runtimeBigIntegerBox(from: modulusRaw)
    else {
        return kk_biginteger_valueOf(0)
    }
    if modulusBox.value.stringValue == "0" {
        outThrown?.pointee = runtimeAllocateThrowable(message: "ArithmeticException: Modulus must be non-zero")
        return 0
    }
    
    do {
        let result = try selfBox.value.modPow(exponentBox.value, modulusBox.value)
        return registerRuntimeObject(RuntimeBigIntegerBox(value: result))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: error.localizedDescription)
        return 0
    }
}

// MARK: - toByteArray()

@_cdecl("kk_biginteger_toByteArray")
public func kk_biginteger_toByteArray(_ selfRaw: Int) -> Int {
    guard let selfBox = runtimeBigIntegerBox(from: selfRaw) else {
        let box = RuntimeArrayBox(length: 0)
        return registerRuntimeObject(box)
    }
    let byteArray = selfBox.value.toByteArray()
    let box = RuntimeArrayBox(length: byteArray.count)
    for (index, byte) in byteArray.enumerated() {
        box.elements[index] = Int(Int8(bitPattern: byte))
    }
    return registerRuntimeObject(box)
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
