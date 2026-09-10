#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    /// KSP-417 keeps normalization and codePointCount as runtime bridges,
    /// but demotes their symbols to the private `__kk_` tier.
    @Test func testUnicodeNormalizationAndCodePointCountLowerToPrivateRuntimeBridges() throws {
        let source = """
        fun main() {
            val s = "e\\u0301abc"
            val nfc = s.normalize(NormalizationForms.NFC)
            val nfd = s.normalize(NormalizationForms.NFD)
            val nfkc = s.normalize(NormalizationForms.NFKC)
            val nfkd = s.normalize(NormalizationForms.NFKD)
            val stable = nfc.isNormalized(NormalizationForms.NFC)
            val total = s.codePointCount()
            val from = s.codePointCount(1)
            val range = s.codePointCount(0, 2)
            println("$nfd $nfkc $nfkd $stable $total $from $range")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))

            let expected = [
                "__kk_normalization_form_nfc",
                "__kk_normalization_form_nfd",
                "__kk_normalization_form_nfkc",
                "__kk_normalization_form_nfkd",
                "__kk_string_normalize_flat",
                "__kk_string_isNormalized_flat",
                "__kk_string_codePointCount",
                "__kk_string_codePointCount_from",
                "__kk_string_codePointCount_range",
            ]
            for callee in expected {
                #expect(callees.contains(callee), "\(callee) should be the emitted runtime callee")
            }

            let demotedRuntimeCallees = Set(expected.map { String($0.dropFirst(2)) })
            #expect(
                callees.isDisjoint(with: demotedRuntimeCallees),
                "Public kk_ names should be gone: \(callees.intersection(demotedRuntimeCallees))"
            )
        }
    }
}
#endif
