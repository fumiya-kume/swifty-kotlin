@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-COMP-001: kotlin.comparisons API Surface Inventory
//
// This file fixes the canonical API list for kotlin.comparisons and kotlin.Comparator
// and verifies that every symbol is (or is not) registered after sema.
//
// Coverage:
//   • Comparator<T> interface: compare, thenBy, thenByDescending, thenComparator,
//     thenDescending, reversed, nullsFirst, nullsLast
//   • Factory top-levels: compareBy (single-selector & multi-selector), compareByDescending,
//     naturalOrder, reverseOrder
//   • Comparison top-levels: compareValues, compareValuesBy (arities 1–3)
//   • minOf / maxOf with Comparator overloads (kotlin.comparisons package)
//   • coerceIn range overloads (kotlin.ranges — inventory-level cross-check only)
//
// Scope: sema / symbol-table level only.
//   Runtime correctness is in RuntimeComparatorTests (COMP-003 / #1202).
//   Overload resolution is in ComparatorOverloadResolutionTests (COMP-002 / #1257).
//
// Gap convention:
//   APIs not yet registered by the sema layer are marked with `_Gap` suffix and
//   assert the *current absence* with a short follow-up note. Flip `XCTAssertNil` /
//   `XCTAssertTrue(links.isEmpty)` to the positive assertion once implemented.

final class ComparisonsAPISurfaceInventoryTests: XCTestCase {
    private static let officialCommonTargets: Set<String> = [
        "fun compareBy(vararg selectors): Comparator<T>",
        "fun compareBy(selector): Comparator<T>",
        "fun compareBy(comparator, selector): Comparator<T>",
        "fun compareByDescending(selector): Comparator<T>",
        "fun compareByDescending(comparator, selector): Comparator<T>",
        "fun compareValues(a, b): Int",
        "fun compareValuesBy(a, b, vararg selectors): Int",
        "fun compareValuesBy(a, b, selector): Int",
        "fun compareValuesBy(a, b, comparator, selector): Int",
        "fun naturalOrder(): Comparator<T>",
        "fun nullsFirst(): Comparator<T?>",
        "fun nullsFirst(comparator): Comparator<T?>",
        "fun nullsLast(): Comparator<T?>",
        "fun nullsLast(comparator): Comparator<T?>",
        "fun Comparator<T>.reversed(): Comparator<T>",
        "fun reverseOrder(): Comparator<T>",
        "fun Comparator<T>.then(comparator): Comparator<T>",
        "fun Comparator<T>.thenBy(selector): Comparator<T>",
        "fun Comparator<T>.thenBy(comparator, selector): Comparator<T>",
        "fun Comparator<T>.thenByDescending(selector): Comparator<T>",
        "fun Comparator<T>.thenByDescending(comparator, selector): Comparator<T>",
        "fun Comparator<T>.thenDescending(selector): Comparator<T>",
        "fun maxOf(a, b, comparator): T",
        "fun minOf(a, b, comparator): T",
    ]

    private static let implementedOfficialLinks: [String: (path: [String], link: String)] = [
        "fun compareBy(vararg selectors): Comparator<T>": (
            ["kotlin", "comparisons", "compareBy"],
            "kk_comparator_from_multi_selectors_vararg"
        ),
        "fun compareBy(selector): Comparator<T>": (
            ["kotlin", "comparisons", "compareBy"],
            "kk_comparator_from_selector"
        ),
        "fun compareBy(comparator, selector): Comparator<T>": (
            ["kotlin", "comparisons", "compareBy"],
            "kk_comparator_from_comparator_selector"
        ),
        "fun compareByDescending(selector): Comparator<T>": (
            ["kotlin", "comparisons", "compareByDescending"],
            "kk_comparator_from_selector_descending"
        ),
        "fun compareByDescending(comparator, selector): Comparator<T>": (
            ["kotlin", "comparisons", "compareByDescending"],
            "kk_comparator_from_comparator_selector_descending"
        ),
        "fun compareValues(a, b): Int": (
            ["kotlin", "comparisons", "compareValues"],
            "kk_compareValues"
        ),
        "fun compareValuesBy(a, b, vararg selectors): Int": (
            ["kotlin", "comparisons", "compareValuesBy"],
            "kk_compareValuesByVararg"
        ),
        "fun compareValuesBy(a, b, selector): Int": (
            ["kotlin", "comparisons", "compareValuesBy"],
            "kk_compareValuesBy1"
        ),
        "fun compareValuesBy(a, b, comparator, selector): Int": (
            ["kotlin", "comparisons", "compareValuesBy"],
            "kk_compareValuesByComparator"
        ),
        "fun naturalOrder(): Comparator<T>": (
            ["kotlin", "comparisons", "naturalOrder"],
            "kk_comparator_natural_order"
        ),
        "fun Comparator<T>.reversed(): Comparator<T>": (
            ["kotlin", "Comparator", "reversed"],
            "kk_comparator_reversed"
        ),
        "fun reverseOrder(): Comparator<T>": (
            ["kotlin", "comparisons", "reverseOrder"],
            "kk_comparator_reverse_order"
        ),
        "fun Comparator<T>.thenBy(selector): Comparator<T>": (
            ["kotlin", "Comparator", "thenBy"],
            "kk_comparator_then_by"
        ),
        "fun Comparator<T>.thenBy(comparator, selector): Comparator<T>": (
            ["kotlin", "Comparator", "thenBy"],
            "kk_comparator_then_by_comparator_selector"
        ),
        "fun Comparator<T>.thenByDescending(selector): Comparator<T>": (
            ["kotlin", "Comparator", "thenByDescending"],
            "kk_comparator_then_by_descending"
        ),
        "fun Comparator<T>.thenByDescending(comparator, selector): Comparator<T>": (
            ["kotlin", "Comparator", "thenByDescending"],
            "kk_comparator_then_by_descending_comparator_selector"
        ),
        "fun Comparator<T>.thenDescending(selector): Comparator<T>": (
            ["kotlin", "Comparator", "thenDescending"],
            "kk_comparator_then_descending"
        ),
    ]

    private static let registeredOnlyOfficialTargets: Set<String> = [
        "fun maxOf(a, b, comparator): T",
        "fun minOf(a, b, comparator): T",
    ]

    private static let knownOfficialGaps: [String: String] = [
        "fun nullsFirst(): Comparator<T?>": "STDLIB-COMP-003",
        "fun nullsFirst(comparator): Comparator<T?>": "STDLIB-COMP-003",
        "fun nullsLast(): Comparator<T?>": "STDLIB-COMP-003",
        "fun nullsLast(comparator): Comparator<T?>": "STDLIB-COMP-003",
        "fun Comparator<T>.then(comparator): Comparator<T>": "STDLIB-COMP-002",
    ]

    // MARK: - Shared sema fixture

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    // MARK: - Lookup helpers

    private func externalLink(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let interned = fqPath.map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: interned) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func allExternalLinks(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        let interned = fqPath.map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: interned)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    private func symbolExists(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let interned = fqPath.map { interner.intern($0) }
        return sema.symbols.lookup(fqName: interned) != nil
    }

    // MARK: - 0. Official common target inventory

    func testOfficialCommonTargetInventoryHasExpectedShape() {
        XCTAssertEqual(Self.officialCommonTargets.count, 24)
        XCTAssertEqual(Self.implementedOfficialLinks.count, 17)
        XCTAssertEqual(Self.registeredOnlyOfficialTargets.count, 2)
        XCTAssertEqual(Self.knownOfficialGaps.count, 5)
    }

    func testEveryOfficialCommonTargetIsClassified() {
        let classified = Set(Self.implementedOfficialLinks.keys)
            .union(Self.registeredOnlyOfficialTargets)
            .union(Self.knownOfficialGaps.keys)
        XCTAssertEqual(classified, Self.officialCommonTargets)
    }

    func testImplementedOfficialCommonTargetsResolveToSyntheticLinks() throws {
        let (sema, interner) = try makeSema()
        for (signature, target) in Self.implementedOfficialLinks {
            let links = allExternalLinks(fqPath: target.path, sema: sema, interner: interner)
            XCTAssertTrue(
                links.contains(target.link),
                "\(signature) should resolve to \(target.link); found: \(links)"
            )
        }
    }

    func testKnownOfficialComparisonGapsStayVisible() throws {
        let (sema, interner) = try makeSema()
        for signature in Self.knownOfficialGaps.keys {
            let links: Set<String> = if signature.contains("nullsFirst") {
                allExternalLinks(fqPath: ["kotlin", "comparisons", "nullsFirst"], sema: sema, interner: interner)
            } else if signature.contains("nullsLast") {
                allExternalLinks(fqPath: ["kotlin", "comparisons", "nullsLast"], sema: sema, interner: interner)
            } else {
                allExternalLinks(fqPath: ["kotlin", "Comparator", "then"], sema: sema, interner: interner)
            }
            XCTAssertTrue(links.isEmpty, "\(signature) should remain in knownOfficialGaps until implemented; found: \(links)")
        }
    }

    // MARK: - 1. kotlin.Comparator interface

    func testComparatorInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        XCTAssertTrue(
            symbolExists(fqPath: ["kotlin", "Comparator"], sema: sema, interner: interner),
            "kotlin.Comparator interface must be registered in symbol table"
        )
    }

    func testComparatorCompareMemberIsRegistered() throws {
        let (sema, interner) = try makeSema()
        XCTAssertTrue(
            symbolExists(fqPath: ["kotlin", "Comparator", "compare"], sema: sema, interner: interner),
            "kotlin.Comparator.compare must be registered"
        )
    }

    // MARK: - 2. Comparator member: thenBy

    func testComparatorThenByIsRegisteredWithCorrectLink() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "Comparator", "thenBy"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_comparator_then_by"),
            "Comparator.thenBy must link to kk_comparator_then_by; found: \(links)"
        )
        XCTAssertTrue(
            links.contains("kk_comparator_then_by_comparator_selector"),
            "Comparator.thenBy(comparator, selector) must link to kk_comparator_then_by_comparator_selector; found: \(links)"
        )
    }

    // MARK: - 3. Comparator member: thenByDescending

    func testComparatorThenByDescendingIsRegisteredWithCorrectLink() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "Comparator", "thenByDescending"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_comparator_then_by_descending"),
            "Comparator.thenByDescending must link to kk_comparator_then_by_descending; found: \(links)"
        )
        XCTAssertTrue(
            links.contains("kk_comparator_then_by_descending_comparator_selector"),
            "Comparator.thenByDescending(comparator, selector) must link to kk_comparator_then_by_descending_comparator_selector; found: \(links)"
        )
    }

    // MARK: - 4. Comparator member: thenComparator

    func testComparatorThenComparatorIsRegisteredWithCorrectLink() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "Comparator", "thenComparator"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_comparator_then_comparator",
            "Comparator.thenComparator must link to kk_comparator_then_comparator"
        )
    }

    // MARK: - 5. Comparator member: thenDescending

    func testComparatorThenDescendingIsRegisteredWithCorrectLink() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "Comparator", "thenDescending"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_comparator_then_descending",
            "Comparator.thenDescending must link to kk_comparator_then_descending"
        )
    }

    // MARK: - 6. Comparator member: reversed

    func testComparatorReversedIsRegisteredWithCorrectLink() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "Comparator", "reversed"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_comparator_reversed",
            "Comparator.reversed must link to kk_comparator_reversed"
        )
    }

    // MARK: - 7. Comparator member: nullsFirst

    func testComparatorNullsFirstIsRegisteredWithCorrectLink() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "Comparator", "nullsFirst"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_comparator_nulls_first",
            "Comparator.nullsFirst must link to kk_comparator_nulls_first"
        )
    }

    // MARK: - 8. Comparator member: nullsLast

    func testComparatorNullsLastIsRegisteredWithCorrectLink() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "Comparator", "nullsLast"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_comparator_nulls_last",
            "Comparator.nullsLast must link to kk_comparator_nulls_last"
        )
    }

    // MARK: - 9. Factory: compareBy (single-selector)

    func testCompareByTopLevelIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "comparisons", "compareBy"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_comparator_from_selector") ||
            links.contains("kk_comparator_from_selector_primitive"),
            "kotlin.comparisons.compareBy (single-selector) must link to a selector comparator runtime; found: \(links)"
        )
    }

    // MARK: - 10. Factory: compareBy (primitive variant)

    func testCompareByPrimitiveVariantIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "comparisons", "compareByPrimitive"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_comparator_from_selector_primitive"),
            "kotlin.comparisons.compareByPrimitive must link to kk_comparator_from_selector_primitive; found: \(links)"
        )
    }

    // MARK: - 11. Factory: compareByDescending (single-selector)

    func testCompareByDescendingTopLevelIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "comparisons", "compareByDescending"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_comparator_from_selector_descending") ||
            links.contains("kk_comparator_from_selector_primitive_descending"),
            "kotlin.comparisons.compareByDescending must link to a descending selector comparator; found: \(links)"
        )
    }

    // MARK: - 12. Factory: compareBy with multi-selector (2 selectors)

    func testCompareByTwoSelectorOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "comparisons", "compareBy"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_comparator_from_multi_selectors"),
            "compareBy with 2 selectors must link to kk_comparator_from_multi_selectors; found: \(links)"
        )
    }

    // MARK: - 13. Factory: compareBy with multi-selector (3 selectors)

    func testCompareByThreeSelectorOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "comparisons", "compareBy"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_comparator_from_multi_selectors3"),
            "compareBy with 3 selectors must link to kk_comparator_from_multi_selectors3; found: \(links)"
        )
    }

    // MARK: - 14. Factory: naturalOrder

    func testNaturalOrderIsRegisteredWithCorrectLink() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "comparisons", "naturalOrder"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_comparator_natural_order"),
            "kotlin.comparisons.naturalOrder must link to kk_comparator_natural_order; found: \(links)"
        )
    }

    // MARK: - 15. Factory: reverseOrder

    func testReverseOrderIsRegisteredWithCorrectLink() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "comparisons", "reverseOrder"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_comparator_reverse_order"),
            "kotlin.comparisons.reverseOrder must link to kk_comparator_reverse_order; found: \(links)"
        )
    }

    // MARK: - 16. compareValues (2 nullable args -> Int)

    func testCompareValuesIsRegisteredWithCorrectLink() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "comparisons", "compareValues"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_compareValues"),
            "kotlin.comparisons.compareValues must link to kk_compareValues; found: \(links)"
        )
    }

    // MARK: - 17. compareValuesBy (1 selector)

    func testCompareValuesByArity1IsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "comparisons", "compareValuesBy"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_compareValuesBy1"),
            "compareValuesBy (1-selector) must link to kk_compareValuesBy1; found: \(links)"
        )
    }

    // MARK: - 18. compareValuesBy (2 selectors)

    func testCompareValuesByArity2IsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "comparisons", "compareValuesBy"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_compareValuesBy"),
            "compareValuesBy (2-selector) must link to kk_compareValuesBy; found: \(links)"
        )
    }

    // MARK: - 19. compareValuesBy (3 selectors)

    func testCompareValuesByArity3IsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "comparisons", "compareValuesBy"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_compareValuesBy3"),
            "compareValuesBy (3-selector) must link to kk_compareValuesBy3; found: \(links)"
        )
    }

    // MARK: - 20. minOf / maxOf with Comparator (2-arg comparator overload)

    /// True when a 3-parameter overload exists whose last parameter is `kotlin.Comparator`
    /// (excludes primitive-only 3-arg overloads such as `minOf(a, b, c)`).
    private func hasThreeParamComparatorOverload(
        comparisonsName: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let fq = ["kotlin", "comparisons", comparisonsName].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        let comparatorFQName = ["kotlin", "Comparator"].map { interner.intern($0) }
        guard let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) else {
            return false
        }
        return syms.contains { sym in
            guard let sig = sema.symbols.functionSignature(for: sym),
                  sig.parameterTypes.count == 3,
                  let lastParamType = sig.parameterTypes.last
            else { return false }
            if case let .classType(ct) = sema.types.kind(of: lastParamType) {
                return ct.classSymbol == comparatorSymbol
            }
            return false
        }
    }

    func testMaxOfWithComparatorOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        XCTAssertTrue(
            hasThreeParamComparatorOverload(comparisonsName: "maxOf", sema: sema, interner: interner),
            "kotlin.comparisons.maxOf must have a 3-param (a, b, Comparator<T>) overload"
        )
    }

    func testMinOfWithComparatorOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        XCTAssertTrue(
            hasThreeParamComparatorOverload(comparisonsName: "minOf", sema: sema, interner: interner),
            "kotlin.comparisons.minOf must have a 3-param (a, b, Comparator<T>) overload"
        )
    }

    // MARK: - 21. coerceIn range overloads (kotlin.ranges cross-inventory)

    func testCoerceInIntOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "ranges", "coerceIn"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_int_coerceIn"),
            "kotlin.ranges.coerceIn (Int) must link to kk_int_coerceIn; found: \(links)"
        )
    }

    func testCoerceInLongOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "ranges", "coerceIn"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_long_coerceIn"),
            "kotlin.ranges.coerceIn (Long) must link to kk_long_coerceIn; found: \(links)"
        )
    }

    func testCoerceInDoubleOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "ranges", "coerceIn"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_double_coerceIn"),
            "kotlin.ranges.coerceIn (Double) must link to kk_double_coerceIn; found: \(links)"
        )
    }

    func testCoerceInFloatOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "ranges", "coerceIn"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_float_coerceIn"),
            "kotlin.ranges.coerceIn (Float) must link to kk_float_coerceIn; found: \(links)"
        )
    }

    // MARK: - 22. Mandatory API completeness assertion

    func testAllMandatoryComparatorAPISymbolsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        // Comparator members
        let comparatorMembers: [(path: [String], link: String)] = [
            (["kotlin", "Comparator", "thenBy"], "kk_comparator_then_by"),
            (["kotlin", "Comparator", "thenBy"], "kk_comparator_then_by_comparator_selector"),
            (["kotlin", "Comparator", "thenByDescending"], "kk_comparator_then_by_descending"),
            (["kotlin", "Comparator", "thenByDescending"], "kk_comparator_then_by_descending_comparator_selector"),
            (["kotlin", "Comparator", "thenComparator"], "kk_comparator_then_comparator"),
            (["kotlin", "Comparator", "thenDescending"], "kk_comparator_then_descending"),
            (["kotlin", "Comparator", "reversed"], "kk_comparator_reversed"),
            (["kotlin", "Comparator", "nullsFirst"], "kk_comparator_nulls_first"),
            (["kotlin", "Comparator", "nullsLast"], "kk_comparator_nulls_last"),
        ]

        for entry in comparatorMembers {
            let links = allExternalLinks(fqPath: entry.path, sema: sema, interner: interner)
            XCTAssertTrue(
                links.contains(entry.link),
                "Missing or mislinked: \(entry.path.joined(separator: ".")) -> \(entry.link)"
            )
        }

        // Factory functions
        // Note: compareBy (single-selector) links to kk_comparator_from_selector.
        // kk_comparator_from_selector_primitive is the link for compareByPrimitive (internal name).
        let factoryLinks: [(path: [String], expectedLinks: [String])] = [
            (
                ["kotlin", "comparisons", "compareBy"],
                [
                    "kk_comparator_from_selector",
                    "kk_comparator_from_multi_selectors",
                    "kk_comparator_from_multi_selectors3",
                    "kk_comparator_from_multi_selectors_vararg",
                ]
            ),
            (
                ["kotlin", "comparisons", "compareByPrimitive"],
                ["kk_comparator_from_selector_primitive"]
            ),
            (["kotlin", "comparisons", "naturalOrder"], ["kk_comparator_natural_order"]),
            (["kotlin", "comparisons", "reverseOrder"], ["kk_comparator_reverse_order"]),
            (["kotlin", "comparisons", "compareValues"], ["kk_compareValues"]),
            (
                ["kotlin", "comparisons", "compareValuesBy"],
                [
                    "kk_compareValuesBy1",
                    "kk_compareValuesBy",
                    "kk_compareValuesBy3",
                    "kk_compareValuesByVararg",
                    "kk_compareValuesByComparator"
                ]
            ),
        ]

        for entry in factoryLinks {
            let links = allExternalLinks(fqPath: entry.path, sema: sema, interner: interner)
            for expectedLink in entry.expectedLinks {
                XCTAssertTrue(
                    links.contains(expectedLink),
                    "Missing: \(entry.path.joined(separator: ".")) -> \(expectedLink) (found: \(links))"
                )
            }
        }
    }
}
