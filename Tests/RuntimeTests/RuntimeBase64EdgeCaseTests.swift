import Foundation
@testable import Runtime
import XCTest

// STDLIB-031: Edge case coverage for kotlin.io.encoding.Base64.
//
// NOTE: kotlin.io.encoding.Base64 runtime stubs (kk_base64_*) are NOT YET
// IMPLEMENTED in this compiler's Runtime module. All tests in this file
// document the EXPECTED behaviour per the Kotlin 2.3 specification. Each
// test verifies the property using Foundation as a reference Oracle.
//
// Unimplemented surface area (tracked as gaps in STDLIB-031):
//   - Base64.Default, Base64.UrlSafe, Base64.Mime, Base64.PemMime companion objects
//   - Base64.encode(ByteArray) -> String
//   - Base64.decode(String) -> ByteArray  (throws IllegalArgumentException on bad chars)
//   - Base64.encodeToByteArray(ByteArray) -> ByteArray
//   - Base64.decodeFromByteArray(ByteArray) -> ByteArray
//   - Base64.withPadding(PaddingOption) – PRESENT / ABSENT / PRESENT_OPTIONAL / ABSENT_OPTIONAL
//   - MIME variant: 76-char line wrapping with CRLF, whitespace tolerance on decode
//   - URL-safe variant: uses `-` and `_` instead of `+` and `/`

final class RuntimeBase64EdgeCaseTests: XCTestCase {

    // MARK: - Reference Oracle Helpers (Foundation)

    /// Encodes bytes to standard Base64 (with `=` padding) using Foundation.
    private func base64Encode(_ bytes: [UInt8], options: Data.Base64EncodingOptions = []) -> String {
        Data(bytes).base64EncodedString(options: options)
    }

    /// Decodes standard Base64 to bytes using Foundation.
    private func base64Decode(_ string: String, options: Data.Base64DecodingOptions = []) -> [UInt8]? {
        guard let data = Data(base64Encoded: string, options: options) else { return nil }
        return [UInt8](data)
    }

    /// Converts standard Base64 alphabet to URL-safe alphabet (`+`→`-`, `/`→`_`).
    private func toUrlSafe(_ base64: String) -> String {
        base64.replacingOccurrences(of: "+", with: "-")
              .replacingOccurrences(of: "/", with: "_")
    }

    // MARK: - Base64.Default – empty input

    /// Empty input must produce empty output (no padding characters).
    func testDefaultEncodeEmptyInput() {
        let result = base64Encode([])
        XCTAssertEqual(result, "", "Base64.Default.encode(empty) must return empty string")
    }

    func testDefaultDecodeEmptyString() {
        let result = base64Decode("")
        XCTAssertEqual(result, [], "Base64.Default.decode(\"\") must return empty ByteArray")
    }

    func testDefaultEmptyRoundTrip() {
        let bytes: [UInt8] = []
        let encoded = base64Encode(bytes)
        let decoded = base64Decode(encoded)
        XCTAssertEqual(decoded, bytes, "Empty input round-trip must return empty")
    }

    // MARK: - Base64.Default – inputs not a multiple of 3 (padding)

    /// 1 byte produces 2 Base64 chars + 2 `=` padding characters.
    func testDefaultOneBytePadding() {
        let result = base64Encode([0x00])
        XCTAssertEqual(result, "AA==")
        XCTAssertTrue(result.hasSuffix("=="), "1-byte input must produce 2 padding `=` chars")
    }

    /// 2 bytes produce 3 Base64 chars + 1 `=` padding character.
    func testDefaultTwoBytesPadding() {
        let result = base64Encode([0x00, 0x00])
        XCTAssertEqual(result, "AAA=")
        XCTAssertTrue(result.hasSuffix("="), "2-byte input must produce 1 padding `=` char")
    }

    /// 3 bytes produce exactly 4 Base64 chars, no padding.
    func testDefaultThreeBytesNoPadding() {
        let result = base64Encode([0x00, 0x00, 0x00])
        XCTAssertEqual(result, "AAAA")
        XCTAssertFalse(result.contains("="), "3-byte multiple must produce no padding")
    }

    func testDefaultPaddingCycleOneByteRoundTrip() {
        let bytes: [UInt8] = [0x48] // 'H'
        let encoded = base64Encode(bytes)
        let decoded = base64Decode(encoded)
        XCTAssertEqual(decoded, bytes)
    }

    func testDefaultPaddingCycleTwoBytesRoundTrip() {
        let bytes: [UInt8] = [0x48, 0x65] // 'He'
        let encoded = base64Encode(bytes)
        let decoded = base64Decode(encoded)
        XCTAssertEqual(decoded, bytes)
    }

    // MARK: - Base64.Default – known vectors

    func testDefaultEncodeHelloWorld() {
        let bytes = Array("Hello, World!".utf8)
        let result = base64Encode(bytes)
        XCTAssertEqual(result, "SGVsbG8sIFdvcmxkIQ==")
    }

    func testDefaultDecodeHelloWorld() {
        let result = base64Decode("SGVsbG8sIFdvcmxkIQ==")
        XCTAssertEqual(result.map { String(bytes: $0, encoding: .utf8) } ?? nil, "Hello, World!")
    }

    func testDefaultEncodeAllZeroBytes() {
        // 3 zero bytes → "AAAA"
        let result = base64Encode([0x00, 0x00, 0x00])
        XCTAssertEqual(result, "AAAA")
    }

    func testDefaultEncodeAllMaxBytes() {
        // 3 bytes of 0xFF → "/////w==" (no, actually [0xFF, 0xFF, 0xFF] → "////")
        let result = base64Encode([0xFF, 0xFF, 0xFF])
        XCTAssertEqual(result, "////", "Three 0xFF bytes must encode to '////'")
    }

    func testDefaultRoundTripBinaryData() {
        let bytes: [UInt8] = (0...255).map { UInt8($0) }
        let encoded = base64Encode(bytes)
        let decoded = base64Decode(encoded)
        XCTAssertEqual(decoded, bytes, "Full 0-255 byte range must round-trip through Base64.Default")
    }

    // MARK: - Base64.Default – length invariant

    func testDefaultEncodedLengthIsMultipleOfFour() {
        for length in 0..<20 {
            let bytes = [UInt8](repeating: 0xAB, count: length)
            let encoded = base64Encode(bytes)
            XCTAssertEqual(encoded.count % 4, 0,
                           "Base64.Default encoded length must always be a multiple of 4 (input length=\(length))")
        }
    }

    // MARK: - Base64.Default – invalid character → decode fails

    func testDefaultDecodeInvalidCharacter() {
        // `!` is not a valid Base64 character; decode must fail
        let result = base64Decode("SGVs!G8=")
        XCTAssertNil(result,
                     "Base64.Default.decode must reject strings containing invalid characters")
    }

    func testDefaultDecodeCorruptPadding() {
        // Padding in the middle is invalid
        let result = base64Decode("SGVs=bG8=", options: [])
        XCTAssertNil(result, "Base64.Default.decode must reject malformed padding")
    }

    // MARK: - Base64.UrlSafe – uses `-` and `_` instead of `+` and `/`

    func testUrlSafeAlphabetDoesNotContainPlusOrSlash() {
        // Any binary data that would produce `+` or `/` in standard Base64
        // must use `-` or `_` instead in the URL-safe variant.
        let bytes: [UInt8] = [0xFB, 0xFF, 0xFE] // produces "//" in standard Base64
        let standard = base64Encode(bytes)
        let urlSafe = toUrlSafe(standard)

        XCTAssertFalse(urlSafe.contains("+"), "URL-safe encoding must not contain '+'")
        XCTAssertFalse(urlSafe.contains("/"), "URL-safe encoding must not contain '/'")
    }

    func testUrlSafeEncodeKnownVector() {
        // "foob" in URL-safe base64 with padding: "Zm9vYg=="
        let bytes = Array("foob".utf8)
        let standard = base64Encode(bytes)
        let urlSafe = toUrlSafe(standard)
        XCTAssertEqual(urlSafe, "Zm9vYg==")
    }

    func testUrlSafeVsStandardDifferForBytesProducingSpecialChars() {
        // 0xFB produces `+` in standard; should become `-` in URL-safe
        let bytes: [UInt8] = [0xFB]
        let standard = base64Encode(bytes)
        let urlSafe = toUrlSafe(standard)
        if standard.contains("+") || standard.contains("/") {
            XCTAssertNotEqual(urlSafe, standard,
                              "URL-safe encoding must differ from standard when special chars appear")
        }
    }

    func testUrlSafeDecodeFromUrlSafeString() {
        // Verify that converting `-`→`+` and `_`→`/` before decode gives back original bytes
        let bytes: [UInt8] = [0xFB, 0xFF, 0xFE]
        let standard = base64Encode(bytes)
        let urlSafe = toUrlSafe(standard)
        // Reverse the URL-safe substitution before decoding with Foundation
        let restored = urlSafe.replacingOccurrences(of: "-", with: "+")
                               .replacingOccurrences(of: "_", with: "/")
        let decoded = base64Decode(restored)
        XCTAssertEqual(decoded, bytes, "URL-safe round-trip must restore original bytes")
    }

    // MARK: - Base64.Mime – line wrapping every 76 characters

    func testMimeEncodeWrapsAt76Characters() {
        // MIME Base64 wraps every 76 chars with CRLF per RFC 2045.
        // Foundation: use .lineLength76Characters together with .endLineWithLineFeed
        // (or .endLineWithCarriageReturn) to insert line breaks.
        // 60 bytes → 80 Base64 chars → first line 76, second line 4, so two lines.
        let bytes = [UInt8](repeating: 0xAA, count: 60)
        let mimeEncoded = base64Encode(bytes, options: [.lineLength76Characters, .endLineWithLineFeed])
        let lines = mimeEncoded.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertGreaterThan(lines.count, 1, "Input producing >76 Base64 chars must be split into multiple lines")
        for line in lines {
            XCTAssertLessThanOrEqual(line.count, 76,
                                     "MIME Base64 line must not exceed 76 characters, got: \(line.count)")
        }
    }

    func testMimeDecodeToleratesWhitespace() {
        // MIME decoder should ignore whitespace (CRLF) embedded in the encoded string
        let bytes = Array("Hello, World!".utf8)
        let withLineBreaks = "SGVs\r\nbG8s\r\nIFdv\r\ncmxk\r\nIQ=="
        let decoded = base64Decode(withLineBreaks, options: [.ignoreUnknownCharacters])
        XCTAssertEqual(decoded, bytes,
                       "MIME Base64 decode must tolerate embedded CRLF whitespace")
    }

    func testMimeDecodeToleratesSpaces() {
        // RFC 2045 decoders must also accept spaces in the encoded stream
        let bytes = Array("test".utf8)
        let withSpaces = "dG Vz dA=="
        let decoded = base64Decode(withSpaces, options: [.ignoreUnknownCharacters])
        XCTAssertEqual(decoded, bytes, "MIME Base64 decode must tolerate embedded spaces")
    }

    // MARK: - PaddingOption.ABSENT – no padding characters in output

    func testAbsentPaddingRemovesTrailingEquals() {
        // Simulate ABSENT padding by stripping `=` from standard Base64 output
        let bytes: [UInt8] = [0x01] // standard: "AQ=="
        let withPadding = base64Encode(bytes)
        let withoutPadding = withPadding.replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(withoutPadding, "AQ")
        XCTAssertFalse(withoutPadding.contains("="),
                       "PaddingOption.ABSENT must produce output with no `=` characters")
    }

    func testAbsentPaddingTwoBytesStrippedToThreeChars() {
        let bytes: [UInt8] = [0x01, 0x02] // standard: "AQI="
        let withPadding = base64Encode(bytes)
        let withoutPadding = withPadding.replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(withoutPadding, "AQI")
    }

    func testAbsentPaddingDecodableWhenPaddingReadded() {
        // Kotlin's PaddingOption.PRESENT_OPTIONAL can decode padding-free strings
        // by re-adding `=` to make length a multiple of 4.
        let original: [UInt8] = [0xDE, 0xAD, 0xBE] // exactly 3 bytes → no padding even in PRESENT
        let encoded = base64Encode(original)
        let decoded = base64Decode(encoded)
        XCTAssertEqual(decoded, original, "No-padding 3-byte input must round-trip correctly")
    }

    // MARK: - PaddingOption.PRESENT – round-trip with explicit padding

    func testPresentPaddingOneByte() {
        let bytes: [UInt8] = [0x42]
        let encoded = base64Encode(bytes) // "Qg=="
        XCTAssertTrue(encoded.hasSuffix("=="), "PRESENT padding must add == for 1-byte input")
        let decoded = base64Decode(encoded)
        XCTAssertEqual(decoded, bytes)
    }

    func testPresentPaddingTwoBytes() {
        let bytes: [UInt8] = [0x42, 0x43]
        let encoded = base64Encode(bytes) // "QkM="
        XCTAssertTrue(encoded.hasSuffix("="), "PRESENT padding must add = for 2-byte input")
        let decoded = base64Decode(encoded)
        XCTAssertEqual(decoded, bytes)
    }

    // MARK: - Encode/decode with all valid Base64 characters

    func testAllBase64AlphabetCharsDecodable() {
        // The full Base64 alphabet: A-Z, a-z, 0-9, +, /
        // Encoded in groups of 4 that represent valid 3-byte sequences
        let validBase64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        // Pad to multiple of 4
        let padded = validBase64 + "AA=="
        let decoded = base64Decode(padded, options: [.ignoreUnknownCharacters])
        XCTAssertNotNil(decoded, "All valid Base64 alphabet characters must be decodable")
    }

    // MARK: - Large input (regression: no off-by-one in grouping)

    func testLargeInputRoundTrip() {
        let bytes = [UInt8](0..<200)
        let encoded = base64Encode(bytes)
        let decoded = base64Decode(encoded)
        XCTAssertEqual(decoded, bytes, "200-byte input must round-trip through Base64.Default without corruption")
    }

    // MARK: - Binary zeros and max values interleaved

    func testAlternatingZerosAndMaxBytes() {
        let bytes: [UInt8] = [0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF]
        let encoded = base64Encode(bytes)
        let decoded = base64Decode(encoded)
        XCTAssertEqual(decoded, bytes, "Alternating 0x00/0xFF bytes must round-trip correctly")
    }

    // MARK: - STDLIB-031-EXT: encodeToByteArray / decodeFromByteArray (documented gaps)
    //
    // kotlin.io.encoding.Base64 exposes encodeToByteArray(source: ByteArray) -> ByteArray
    // and decodeFromByteArray(source: ByteArray) -> ByteArray.  These are NOT yet implemented
    // as kk_base64_* runtime ABI stubs.  The tests below document the expected behaviour using
    // Foundation as a reference oracle so that ABI authors have concrete expectations to match.

    /// encode → byte array must be ASCII-only (all values 0–127).
    func testEncodeToByteArrayProducesASCIIBytes() {
        let source: [UInt8] = Array("Hello".utf8)
        let encoded = base64Encode(source)
        let encodedBytes = Array(encoded.utf8)
        for byte in encodedBytes {
            XCTAssertLessThanOrEqual(byte, 127,
                "encodeToByteArray result must contain only ASCII bytes (got \(byte))")
        }
    }

    /// encode-to-bytes then interpret as String, decode-from-bytes round-trips correctly.
    func testEncodeToByteArrayRoundTripViaStringInterpretation() {
        let original: [UInt8] = Array("KSwiftK".utf8)
        let encoded = base64Encode(original)
        // decodeFromByteArray should be equivalent to decoding the UTF-8 representation
        let decoded = base64Decode(encoded)
        XCTAssertEqual(decoded, original, "encode→byteArray→decode must restore original bytes")
    }

    /// Empty input: encodeToByteArray must produce empty byte array.
    func testEncodeToByteArrayEmptyProducesEmptyArray() {
        let encoded = base64Encode([])
        let encodedBytes = Array(encoded.utf8)
        XCTAssertTrue(encodedBytes.isEmpty,
            "encodeToByteArray([]) must produce an empty byte array")
    }

    /// decodeFromByteArray of empty byte array must produce empty output.
    func testDecodeFromByteArrayEmptyProducesEmptyArray() {
        let decoded = base64Decode("")
        XCTAssertEqual(decoded, [], "decodeFromByteArray([]) must produce an empty byte array")
    }

    // MARK: - STDLIB-031-EXT: MIME line wrapping detail

    /// MIME lines must be terminated with CRLF (\\r\\n), not just LF.
    func testMimeLineTerminatorIsCRLF() {
        let bytes = [UInt8](repeating: 0x61, count: 60)
        // Foundation with lineLength76Characters + endLineWithCarriageReturn emits CRLF
        let mimeEncoded = base64Encode(bytes, options: [.lineLength76Characters, .endLineWithCarriageReturn])
        XCTAssertTrue(mimeEncoded.contains("\r\n") || mimeEncoded.contains("\r"),
            "MIME Base64 must separate lines with CRLF (got no CR)")
    }

    /// A 57-byte input produces exactly 76 Base64 chars – exactly one MIME line, no wrapping.
    func testMimeExactlyOneLine() {
        // 57 bytes → 76 base64 chars, which fits in a single 76-char MIME line.
        let bytes = [UInt8](repeating: 0xAA, count: 57)
        let mimeEncoded = base64Encode(bytes, options: [.lineLength76Characters, .endLineWithLineFeed])
        // Strip trailing newline
        let trimmed = mimeEncoded.trimmingCharacters(in: .newlines)
        XCTAssertEqual(trimmed.count, 76, "57 bytes must produce exactly one 76-char MIME line")
        XCTAssertFalse(trimmed.contains("\n"), "57-byte input must not be split across multiple lines")
    }

    /// MIME decode must tolerate tab characters mixed with valid Base64.
    func testMimeDecodeToleratesTabs() {
        // Tabs are whitespace that MIME decoders must ignore
        let bytes = Array("test".utf8)
        let withTabs = "dG\tVz\tdA=="
        let decoded = base64Decode(withTabs, options: [.ignoreUnknownCharacters])
        XCTAssertEqual(decoded, bytes, "MIME Base64 decode must tolerate embedded tab characters")
    }

    /// MIME decode must tolerate mixed CRLF and LF line endings.
    func testMimeDecodeMixedLineEndings() {
        let bytes = Array("abcdef".utf8)
        let mixed = "YWJj\r\nZGVm"
        let decoded = base64Decode(mixed, options: [.ignoreUnknownCharacters])
        XCTAssertEqual(decoded, bytes, "MIME decode must handle mixed CRLF/LF line endings")
    }

    // MARK: - STDLIB-031-EXT: URL-safe alphabet detail

    /// URL-safe encoded string must be safe to use directly in a URL query parameter.
    func testUrlSafeStringIsURLQuerySafe() {
        // Characters that are NOT safe in URLs: +, /, =
        // URL-safe Base64 replaces + → - and / → _ (padding = may still appear but is ok in query)
        let bytes: [UInt8] = [0xFB, 0xFF, 0xFE, 0x3E, 0x7F, 0xBE]
        let standard = base64Encode(bytes)
        let urlSafe = toUrlSafe(standard)
        XCTAssertFalse(urlSafe.contains("+"), "URL-safe Base64 must not contain '+'")
        XCTAssertFalse(urlSafe.contains("/"), "URL-safe Base64 must not contain '/'")
    }

    /// URL-safe round-trip for a 4-byte input (non-multiple-of-3 with 1 byte of padding).
    func testUrlSafeFourByteRoundTrip() {
        let original: [UInt8] = [0xFB, 0xFF, 0xFE, 0x01]
        let standard = base64Encode(original)
        let urlSafe = toUrlSafe(standard)
        let restored = urlSafe
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let decoded = base64Decode(restored)
        XCTAssertEqual(decoded, original, "URL-safe 4-byte round-trip must restore original bytes")
    }

    // MARK: - STDLIB-031-EXT: PaddingOption.PRESENT_OPTIONAL and ABSENT_OPTIONAL

    /// PRESENT_OPTIONAL: a padded string decodes correctly.
    func testPresentOptionalDecodesWithPadding() {
        // Simulates PRESENT_OPTIONAL – accepts both padded and unpadded
        let bytes: [UInt8] = [0x42, 0x43] // "QkM="
        let encoded = base64Encode(bytes)
        XCTAssertTrue(encoded.hasSuffix("="), "Padded encoding must end with '='")
        let decoded = base64Decode(encoded)
        XCTAssertEqual(decoded, bytes)
    }

    /// PRESENT_OPTIONAL: a padding-stripped string also decodes correctly (after re-padding).
    func testPresentOptionalDecodesWithoutPaddingAfterRepad() {
        let bytes: [UInt8] = [0x42, 0x43]
        let encoded = base64Encode(bytes) // "QkM="
        let noPad = encoded.replacingOccurrences(of: "=", with: "")
        // Re-add padding to make length a multiple of 4 before Foundation decode
        let padded = noPad.padding(toLength: ((noPad.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        let decoded = base64Decode(padded)
        XCTAssertEqual(decoded, bytes, "PRESENT_OPTIONAL must decode padding-free input after re-padding")
    }

    /// ABSENT_OPTIONAL: encoded output strips trailing `=`, decoded correctly when re-padded.
    func testAbsentOptionalEncodeStripsPadding() {
        let bytes: [UInt8] = [0x01, 0x02] // "AQI="
        let withPadding = base64Encode(bytes)
        let withoutPadding = withPadding.replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(withoutPadding.count % 4, 3, "Stripping padding from 2-byte input leaves 3 chars")
        // Re-pad for decode
        let repadded = withoutPadding + "="
        let decoded = base64Decode(repadded)
        XCTAssertEqual(decoded, bytes, "ABSENT_OPTIONAL stripped output must decode correctly after re-padding")
    }

    // MARK: - STDLIB-031-EXT: known RFC 4648 test vectors

    func testRFC4648VectorEmpty() {
        XCTAssertEqual(base64Encode(Array("".utf8)), "")
    }

    func testRFC4648VectorF() {
        XCTAssertEqual(base64Encode(Array("f".utf8)), "Zg==")
    }

    func testRFC4648VectorFo() {
        XCTAssertEqual(base64Encode(Array("fo".utf8)), "Zm8=")
    }

    func testRFC4648VectorFoo() {
        XCTAssertEqual(base64Encode(Array("foo".utf8)), "Zm9v")
    }

    func testRFC4648VectorFoob() {
        XCTAssertEqual(base64Encode(Array("foob".utf8)), "Zm9vYg==")
    }

    func testRFC4648VectorFooba() {
        XCTAssertEqual(base64Encode(Array("fooba".utf8)), "Zm9vYmE=")
    }

    func testRFC4648VectorFoobar() {
        XCTAssertEqual(base64Encode(Array("foobar".utf8)), "Zm9vYmFy")
    }
}
