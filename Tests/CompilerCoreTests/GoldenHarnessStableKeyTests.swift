#if canImport(Testing)
@testable import GoldenHarnessSupport
import Foundation
import Testing

/// Regression coverage for RF-GOLDEN-010: symbol references in Sema golden
/// dumps must be keyed by the *meaning* of the referenced declaration, never
/// by its position inside a same-FQName candidate set. These tests pin the
/// invariance (unrelated candidate changes cannot shift a reference) and the
/// sensitivity (a genuinely different resolution target must produce a
/// different key).
@Suite("GoldenHarness.StableKey")
struct GoldenHarnessStableKeyTests {
    private func renderSema(
        _ source: String,
        injected: [(path: String, contents: String)] = []
    ) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("case.kt")
        try source.write(to: sourceURL, atomically: false, encoding: .utf8)
        return try GoldenHarnessDump.dumpSema(
            sourcePath: sourceURL.path,
            preInjectedFiles: injected.map { ($0.path, Data($0.contents.utf8)) }
        )
    }

    private func callKeys(in dump: String, calleeName: String) -> [String] {
        dump.split(separator: "\n").compactMap { line in
            guard line.contains("call="),
                  let range = line.range(of: "call=")
            else { return nil }
            let key = String(line[range.upperBound...])
            guard key.contains(".\(calleeName)[") else { return nil }
            return key
        }
    }

    // MARK: - Invariance: unreferenced candidates must not shift keys

    @Test
    func unreferencedBundledOverloadKeepsCallKeyIdentical() throws {
        // The historical failure mode: `call=kotlin.collections.containsAll#2`
        // renumbered when another same-FQName overload was added, even though
        // the call resolution itself never changed. Inject an extra unreferenced
        // `containsAll` candidate through a bundled file — the whole dump must
        // stay byte-identical.
        let source = """
        package sample

        fun main() {
            val s = setOf(1, 2)
            s.containsAll(listOf(1))
        }
        """
        let baseline = try renderSema(source)
        let withExtraOverload = try renderSema(
            source,
            injected: [(
                path: "__bundled_extra_overload.kt",
                contents: """
                package kotlin.collections
                public fun <T> Collection<T>.containsAll(unused: Double): Boolean = true
                """
            )]
        )
        // Comparison happens at the same normalization level the persisted
        // `.golden` uses: injected bundled declarations legitimately shift the
        // raw `__local_N` scope ordinals (a pre-existing mechanism RF-GOLDEN-010
        // does not own), while `call=`/`ref=` keys must stay identical.
        let normalize = { GoldenHarness.normalizedForComparison(suiteName: "Sema", output: $0) }
        #expect(
            normalize(baseline) == normalize(withExtraOverload),
            Comment(rawValue: "Sema dump changed after adding an unreferenced same-FQName overload")
        )
    }

    @Test
    func oneToManyCandidateTransitionsKeepKey() throws {
        // 1→2 and 2→3 candidate transitions used to toggle/reorder `#N`
        // suffixes. The semantic key must be identical for 1, 2, and 3
        // same-FQName candidates.
        let source = """
        package sample

        fun probe(x: Int): Int = x

        fun main() {
            probe(1)
        }
        """
        let one = try renderSema(source)
        let two = try renderSema(
            source,
            injected: [(
                path: "__bundled_probe_a.kt",
                contents: "package sample\nfun probe(x: String): String = x\n"
            )]
        )
        let three = try renderSema(
            source,
            injected: [
                (path: "__bundled_probe_a.kt", contents: "package sample\nfun probe(x: String): String = x\n"),
                (path: "__bundled_probe_b.kt", contents: "package sample\nfun probe(x: Double): Double = x\n"),
            ]
        )
        let oneKey = callKeys(in: one, calleeName: "probe")
        #expect(oneKey == callKeys(in: two, calleeName: "probe"))
        #expect(oneKey == callKeys(in: three, calleeName: "probe"))
        #expect(oneKey.first?.contains("params=Int") == true)
    }

    @Test
    func removingUnreferencedCandidateKeepsKey() throws {
        let source = """
        package sample

        fun probe(x: Int): Int = x

        fun main() {
            probe(1)
        }
        """
        let withCandidate = try renderSema(
            source,
            injected: [(
                path: "__bundled_probe_remove.kt",
                contents: "package sample\nfun probe(x: String): String = x\n"
            )]
        )
        let without = try renderSema(source)
        #expect(callKeys(in: withCandidate, calleeName: "probe") == callKeys(in: without, calleeName: "probe"))
    }

    // MARK: - Sensitivity: a different resolution target must differ

    @Test
    func selectingADifferentOverloadChangesKey() throws {
        let renderCall = { (argument: String) throws -> [String] in
            let dump = try renderSema("""
            package sample

            fun probe(x: Int): Int = x
            fun probe(x: String): String = x

            fun main() {
                probe(\(argument))
            }
            """)
            return callKeys(in: dump, calleeName: "probe")
        }
        let intCall = try renderCall("1")
        let stringCall = try renderCall("\"s\"")
        #expect(intCall.count == 1)
        #expect(stringCall.count == 1)
        #expect(intCall != stringCall, Comment(rawValue: "Distinct overload choices rendered an identical key"))
        #expect(intCall.first?.contains("params=Int") == true)
        #expect(stringCall.first?.contains("params=String") == true)
    }

    @Test
    func nullableFunctionTypeAndNullableReturnTypeStayDistinct() throws {
        // `renderType` collapses `(() -> String)?` and `() -> String?` into the
        // same text; the structural key must not. (Sema currently resolves a
        // nullable function type written literally in a parameter annotation to
        // `Any`, so the nullable function side reaches the signature through a
        // typealias — `Fn?` survives as `functionType(nullable)`.)
        let dump = try renderSema("""
        package sample

        typealias Fn = () -> String
        fun takeNullableFunction(f: Fn?): Int = 1
        fun takeNullableReturn(f: () -> String?): Int = 2
        """)
        #expect(
            dump.contains("sample.takeNullableFunction[kind=fun;params=fn{p=;ret=String}?]"),
            Comment(rawValue: "nullable function type was not encoded as fn{…}?")
        )
        #expect(
            dump.contains("sample.takeNullableReturn[kind=fun;params=fn{p=;ret=String?}]"),
            Comment(rawValue: "nullable return type was not encoded as ret=…?")
        )
    }

    @Test
    func propertyAndFunctionSharingNameAreDistinguishedByKind() throws {
        let dump = try renderSema("""
        package sample

        val probe: Int = 1
        fun probe(): Int = 2

        fun main() {
            probe()
            probe
        }
        """)
        #expect(dump.contains("fq=sample.probe[kind=prop]"))
        #expect(dump.contains("fq=sample.probe[kind=fun;params=]"))
    }

    @Test
    func typeParametersNormalizeToDeclarationOrder() throws {
        // The same public signature spelled with different type-parameter
        // names must render the same positional key (T0), not the name.
        let dump = try renderSema("""
        package sample

        fun <Alpha> firstOf(x: Alpha): Alpha = x
        fun <Beta> secondOf(y: Beta): Beta = y
        """)
        #expect(dump.contains("sample.firstOf[kind=fun;params=T0;gen=1]"))
        #expect(dump.contains("sample.secondOf[kind=fun;params=T0;gen=1]"))
    }

    @Test
    func normalizeDoesNotCollapseDistinctMeaningKeys() throws {
        // The whole-text comparison normalization must leave semantic key
        // content untouched: `T0`, field labels, and differing params stay
        // byte-identical, and two different keys never normalize equal.
        let raw = """
        expr e@1:1 call callee=e@1:1 args=[] type=Int call=p.f[kind=fun;params=T0;gen=1]
        expr e@2:1 call callee=e@2:1 args=[] type=Int call=p.f[kind=fun;params=Int]
        """
        let normalized = GoldenHarness.normalizedForComparison(suiteName: "Sema", output: raw)
        #expect(normalized.contains("call=p.f[kind=fun;params=T0;gen=1]"))
        #expect(normalized.contains("call=p.f[kind=fun;params=Int]"))
        #expect(normalized != GoldenHarness.normalizedForComparison(
            suiteName: "Sema",
            output: raw.replacingOccurrences(of: "params=Int", with: "params=String")
        ))
    }
}
#endif
