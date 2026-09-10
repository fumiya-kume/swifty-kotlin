#if canImport(Testing)
@testable import CompilerCore
@testable import GoldenHarnessSupport
import Foundation
import Testing

/// RF-GOLDEN-001 — contract inventory for the Sema golden format.
///
/// These tests pin, as executable cases, which information classes the
/// *ordinary* Sema golden carries today and which classes are explicitly
/// assigned to dedicated tests (stdlib contract goldens, ABI/bridge/runtime
/// suites). They deliberately do not change the renderer or any golden;
/// they make the boundary reproducible so later items (002 / 003 / 005 / 011)
/// can move metadata without silent loss.
///
/// ## Information-class mapping (ordinary golden → verification owner)
///
/// | class | ordinary golden today | dedicated owner |
/// |---|---|---|
/// | fixture 宣言 binding（`decl` / `sym=`） | kept | stays |
/// | expr 推論型 `type=` | kept | stays |
/// | 参照・呼び出し解決 `ref=` / `call=` / `targs=` | kept | stays (key: RF-GOLDEN-010; public-ref mapping: RF-GOLDEN-006) |
/// | fixture 所有 symbol の `kind=` / `vis=` / `flags=` / `sig=` / `type=` | kept | stays |
/// | 外部 symbol の推移的 `sig=` / `type=` / `flags=` メタデータ | emitted today | dedicated stdlib golden (RF-GOLDEN-011), migrated by RF-GOLDEN-003 |
/// | 由来（source / synthetic / imported / alias） | only `flags=synthetic` | origin classification RF-GOLDEN-002 + dedicated tests |
/// | `canThrow` / `throws` / `throwingFunction` | **not emitted** | ABI / bridge / runtime tests (RF-GOLDEN-005) |
/// | nominal 宣言側 variance / supertype / 型引数 | **not emitted** | dedicated stdlib golden section (RF-GOLDEN-011) |
/// | typealias underlyingType / 型パラメータ | **not emitted** | dedicated stdlib golden section (RF-GOLDEN-011) |
/// | symbol-level annotations | only `file` line `annotations=` | dedicated stdlib golden section (RF-GOLDEN-011) |
/// | ABI / externalLinkName / runtime export | **not emitted** | `RuntimeABIExternalLinkValidationTests` + `Scripts/validate_runtime_abi_links.sh` |
/// | 実行 profile（source / artifact / no-stdlib） | not modeled | RF-GOLDEN-012 case identity |
/// | error diagnostics / `<error>` types | 15 + 3 pinned cases | no new case may join the inventory without review |
///
@Suite("GoldenHarness.MetadataContract")
struct GoldenHarnessMetadataContractTests {
    /// Checked-in Sema goldens keyed by the case's `.kt` basename
    /// (e.g. `stdlib_kotlin_collections_Map_map.kt`).
    private static func semaGoldenContents() throws -> [String: String] {
        let cases = try GoldenHarnessCaseDiscovery.loadCases(suite: .sema)
        var result: [String: String] = [:]
        for caseFile in cases {
            result[caseFile.basename] = try String(contentsOf: caseFile.goldenURL, encoding: .utf8)
        }
        return result
    }

    // MARK: - Representative cases keep every ordinary info class

    /// Representative fixtures across the constructs named by RF-GOLDEN-001:
    /// a stdlib typealias user (`linkedhashmap_alias`), collection HOFs
    /// (`stdlib_kotlin_collections_Map_map`), a generic nominal (`stdlib_kotlin_Pair_n_n`), user data
    /// class (`data_class_copy_edge`), enum (`enum_class`), object literal
    /// (`object_literal_property_no_init`) and a custom accessor
    /// (`computed_property`). Each must still carry the full ordinary
    /// information classes.
    @Test
    func representativeCasesCarryEveryOrdinaryInfoClass() throws {
        let goldens = try Self.semaGoldenContents()

        let expectations: [String: [String]] = [
            "linkedhashmap_alias.kt": ["symbol fq=", "kind=", "vis=", "flags=", "type=", "ref=", "call="],
            "stdlib_kotlin_collections_Map_map.kt": ["call=", "targs=[", "fn{p="],
            // `kotlin.Pair` is library-owned (no case-file `declSite`), so RF-GOLDEN-001's
            // original "fq=kotlin.Pair[kind=class;gen=2]" standalone symbol line no longer
            // prints — `isExcludedLibrarySymbol` (PR: golden-stdlib-artifact) omits every
            // symbol without a case-file declSite from `symbol` lines. The generic-arity
            // metadata (`gen=2`) is still observable through the constructor call site.
            "stdlib_kotlin_Pair_n_n.kt": ["call=kotlin.Pair.<init>[kind=ctor;recv=kotlin.Pair<T0,T1>;params=T0,T1;gen=2]", "call=kotlin.Pair.<init>"],
            "data_class_copy_edge.kt": ["flags=dataType", ".copy[kind=fun", "defaults=["],
            "enum_class.kt": ["kind=enum"],
            "object_literal_property_no_init.kt": ["__ObjectLiteral_", "flags=synthetic"],
            "computed_property.kt": ["kind=bfield", "flags=mutable"],
        ]
        for (basename, tokens) in expectations {
            let text = try #require(goldens[basename], "missing golden \(basename)")
            for token in tokens {
                #expect(text.contains(token), Comment(rawValue: "\(basename) lost info class \(token)"))
            }
        }
    }

    // MARK: - Diagnostics inventory

    /// The exact set of Sema cases allowed to contain error diagnostics.
    /// A positive fixture must never acquire a new error via mechanical
    /// `UPDATE_GOLDEN` — any new member of this set is either an intended
    /// diagnostic fixture (document it) or a regression to fix first.
    private static let errorDiagnosticCaseBasenames: Set<String> = [
        "collection_firstNotNullOfOrNull.kt",
        "deprecated_annotation.kt",
        "expect_actual.kt",
        "generate_sequence_noarg.kt",
        "inner_class.kt",
        "list_distinctBy_nullable_key.kt",
        "local_decl.kt",
        "sealed_when_missing_branch.kt",
        // stdlib surface cases carrying errors — flagged for individual
        // investigation; they must not silently grow either.
        // AtomicIntArray's internal constructor becomes correctly invisible
        // cross-module under `.kklib` artifact loading (PR: golden-stdlib-artifact) —
        // an intentional parity fix versus bundled-source injection, not a regression.
        "stdlib_kotlin_concurrent_AtomicIntArray_n_n.kt",
        "stdlib_kotlin_collections_Map_iterator.kt",
        "stdlib_kotlin_collections_Map_min.kt",
        "stdlib_kotlin_collections_n_build.kt",
        "stdlib_kotlin_ranges_IntRange_cross_contains_n.kt",
        "stdlib_kotlin_native_SymbolName_n_n.kt",
        "use_site_variance.kt",
        "variance_violation.kt",
    ]

    @Test
    func errorDiagnosticInventoryIsPinned() throws {
        let goldens = try Self.semaGoldenContents()
        let actual = Set(goldens.filter { $0.value.contains("diagnostic severity=error") }.keys)
        #expect(
            actual == Self.errorDiagnosticCaseBasenames,
            Comment(rawValue: "error-diagnostic inventory changed: new=\(actual.subtracting(Self.errorDiagnosticCaseBasenames).sorted()), removed=\(Self.errorDiagnosticCaseBasenames.subtracting(actual).sorted())")
        )
    }

    /// Cases where an expression type rendered as `<error>` — the same
    /// mechanical-acceptance guard as the diagnostic inventory.
    private static let errorTypeCaseBasenames: Set<String> = [
        "inner_class.kt",
        "stdlib_kotlin_ranges_IntRange_cross_contains_n.kt",
        "use_site_variance.kt",
    ]

    @Test
    func errorTypeInventoryIsPinned() throws {
        let goldens = try Self.semaGoldenContents()
        let actual = Set(goldens.filter { $0.value.contains("<error>") }.keys)
        #expect(
            actual == Self.errorTypeCaseBasenames,
            Comment(rawValue: "`<error>`-type inventory changed: \(actual.sorted())")
        )
    }

    // MARK: - Flag vocabulary

    /// Every flag name the ordinary renderer can emit. The set is closed so a
    /// formatter change adding a flag (e.g. `throwingFunction`) or dropping one
    /// is a deliberate contract change, not an accident of an update pass.
    // `static` dropped out of the emitted vocabulary under `isExcludedLibrarySymbol`
    // (PR: golden-stdlib-artifact): it was only ever observed on library-owned
    // companion-object symbol lines (e.g. `kotlin.UByte.Companion`), which no
    // longer print — no case-file-local declaration in the corpus carries it.
    private static let ordinaryFlagVocabulary: Set<String> = [
        "_",
        "abstractType",
        "actualDeclaration",
        "constValue",
        "dataType",
        "expectDeclaration",
        "funInterface",
        "inlineFunction",
        "innerClass",
        "mutable",
        "openType",
        "operatorFunction",
        "overrideMember",
        "reifiedTypeParameter",
        "sealedType",
        "suspendFunction",
        "synthetic",
        "valueType",
    ]

    @Test
    func ordinaryFlagVocabularyIsPinned() throws {
        let goldens = try Self.semaGoldenContents()
        var emitted = Set<String>()
        for text in goldens.values {
            for line in text.split(separator: "\n") where line.hasPrefix("symbol fq=") {
                guard let flagsRange = line.range(of: " flags=") else { continue }
                let flags = line[flagsRange.upperBound...].prefix { $0 != " " }
                emitted.formUnion(flags.split(separator: "|").map(String.init))
            }
        }
        // The emitted vocabulary is exactly the pinned set — nothing may be
        // added (e.g. `throwingFunction`) or silently dropped.
        #expect(
            emitted == Self.ordinaryFlagVocabulary,
            Comment(rawValue: "golden flag vocabulary changed: new=\(emitted.subtracting(Self.ordinaryFlagVocabulary).sorted()), lost=\(Self.ordinaryFlagVocabulary.subtracting(emitted).sorted())")
        )
    }

    /// The formatter deliberately cannot render ABI-affecting flags — they are
    /// verified by dedicated tests, not this format.
    @Test
    func abiAffectingFlagsStayOutsideOrdinaryRendering() {
        #expect(GoldenHarnessSemaFormat.renderSymbolFlags(.throwingFunction) == "_")
    }

    // MARK: - Explicitly not in the ordinary contract

    /// `throws` / `canThrow` metadata exists in the semantic model
    /// (`SymbolFlags.throwingFunction`, `FunctionSignature.canThrow`) but the
    /// ordinary golden has never carried it — `@Throws` cases render
    /// `flags=_`. Its verification belongs to ABI / bridge / runtime tests
    /// (RF-GOLDEN-005), not to this format.
    @Test
    func throwingMetadataIsNotInOrdinaryContract() throws {
        let goldens = try Self.semaGoldenContents()
        let throwsCase = try #require(goldens["stdlib_kotlin_n_Throws.kt"])
        #expect(throwsCase.contains("flags=_"), Comment(rawValue: "@Throws surface unexpectedly gained flag output"))
        for (name, text) in goldens {
            #expect(
                !text.contains("throwingFunction") && !text.contains("canThrow"),
                Comment(rawValue: "\(name) now carries throws metadata in the ordinary golden")
            )
        }
    }

    /// Metadata classes the ordinary renderer does not emit today. Pinning
    /// their absence documents what the dedicated stdlib golden (RF-GOLDEN-011)
    /// must own instead of a quiet extension of this format.
    @Test
    func notEmittedMetadataClassesStayAbsent() throws {
        let goldens = try Self.semaGoldenContents()
        let forbidden = ["supertype=", "underlyingType=", "declaredVariance=", "externalLinkName=", "origin="]
        for (name, text) in goldens {
            for token in forbidden {
                #expect(
                    !text.contains(token),
                    Comment(rawValue: "\(name) gained \(token) in the ordinary golden")
                )
            }
        }
    }

    // MARK: - Per-kind field coverage

    /// The per-kind field table of `symbol` lines: functions keep `sig=`,
    /// properties keep `type=`, generic nominals keep `gen=`, and every line
    /// keeps `vis=` — these are the identifying fields the dedicated contract
    /// must preserve or deliberately re-home.
    @Test
    func symbolLinesKeepPerKindFields() throws {
        let goldens = try Self.semaGoldenContents()
        for (name, text) in goldens {
            for line in text.split(separator: "\n") where line.hasPrefix("symbol fq=") {
                #expect(line.contains(" vis="), Comment(rawValue: "\(name): symbol line lost visibility"))
                #expect(line.contains(" flags="), Comment(rawValue: "\(name): symbol line lost flags"))
                if line.contains("kind=function") || line.contains("kind=constructor") {
                    #expect(line.contains(" sig="), Comment(rawValue: "\(name): callable symbol line lost signature"))
                }
                if line.contains("kind=property") || line.contains("kind=local") || line.contains("kind=backingField") {
                    #expect(line.contains(" type="), Comment(rawValue: "\(name): value symbol line lost its type"))
                }
            }
        }
    }
}
#endif
