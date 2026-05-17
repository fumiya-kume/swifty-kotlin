@testable import CompilerCore
import RuntimeABI
import XCTest

final class StdlibSurfaceSpecTests: XCTestCase {
    func testCollectionHOFSpecKeysAreUnique() {
        var seen: Set<SpecKey> = []

        for spec in StdlibSurfaceSpec.collectionHOFMembers {
            let key = SpecKey(
                ownerKind: spec.ownerKind,
                memberName: spec.memberName,
                arityMinimum: spec.arity.minimum,
                arityMaximum: spec.arity.maximum
            )
            XCTAssertTrue(
                seen.insert(key).inserted,
                "Duplicate stdlib surface spec for \(key)"
            )
        }
    }

    func testCollectionHOFSpecRuntimeLinksAreNonEmpty() {
        for spec in StdlibSurfaceSpec.collectionHOFMembers {
            XCTAssertFalse(
                spec.runtimeLinkName.isEmpty,
                "Expected runtime link for \(spec.ownerKind.rawValue).\(spec.memberName)/\(spec.arity.minimum)"
            )
        }
    }

    func testCollectionHOFSpecRuntimeLinksAreRegisteredInRuntimeABI() {
        let abiNames = Set(RuntimeABISpec.allFunctions.map(\.name))

        for spec in StdlibSurfaceSpec.collectionHOFMembers {
            XCTAssertTrue(
                abiNames.contains(spec.runtimeLinkName),
                "Expected RuntimeABISpec to register \(spec.runtimeLinkName) for \(spec.ownerKind.rawValue).\(spec.memberName)"
            )
        }
    }

    func testCollectionHOFSpecContainsV1Surface() {
        let expected: Set<SpecKey> = [
            list("map", 1),
            list("filter", 1),
            list("filterNot", 1),
            list("mapNotNull", 1),
            list("flatMap", 1),
            list("forEach", 1),
            list("groupBy", 1),
            list("groupingBy", 1),
            list("associateBy", 1),
            list("associateWith", 1),
            list("associate", 1),
            list("sumOf", 1),
            list("sumBy", 1),
            list("sumByDouble", 1),
            list("firstNotNullOf", 1),
            list("firstNotNullOfOrNull", 1),
            list("forEachIndexed", 1),
            list("onEach", 1),
            list("onEachIndexed", 1),
            list("mapIndexed", 1),
            list("filterIndexed", 1),
            list("takeWhile", 1),
            list("dropWhile", 1),
            list("takeLastWhile", 1),
            list("dropLastWhile", 1),
            list("filterTo", 2),
            list("filterNotTo", 2),
            list("mapTo", 2),
            list("flatMapTo", 2),
            list("mapNotNullTo", 2),
            list("mapIndexedTo", 2),
            list("mapIndexedNotNullTo", 2),
            list("flatMapIndexedTo", 2),
            list("filterIndexedTo", 2),
            list("associateTo", 2),
            list("associateByTo", 2),
            list("associateWithTo", 2),
            list("groupByTo", 2),

            set("map", 1),
            set("filter", 1),
            set("forEach", 1),
            set("filterNot", 1),
            set("mapNotNull", 1),
            set("flatMap", 1),
            set("any", 1),
            set("none", 1),
            set("all", 1),
            set("count", 1),

            map("forEach", 1),
            map("map", 1),
            map("mapNotNull", 1),
            map("filter", 1),
            map("filterNot", 1),
            map("count", 1),
            map("any", 1),
            map("all", 1),
            map("none", 1),
            map("mapValues", 1),
            map("mapKeys", 1),
            map("mapValuesTo", 2),
            map("mapKeysTo", 2),
            map("filterKeys", 1),
            map("filterValues", 1),

            sequence("map", 1),
            sequence("filter", 1),
            sequence("filterNot", 1),
            sequence("mapNotNull", 1),
            sequence("flatMap", 1),
            sequence("flatMapIndexed", 1),
            sequence("forEach", 1),
            sequence("groupBy", 1),
            sequence("associate", 1),
            sequence("associateBy", 1),
            sequence("associateWith", 1),
            sequence("partition", 1),
            sequence("plus", 1),
            sequence("randomOrNull", 0),
            sequence("plusElement", 1),
            sequence("chunked", 1),
            sequence("contains", 1),
            sequence("drop", 1),
            sequence("dropWhile", 1),
            sequence("distinctBy", 1),
            sequence("constrainOnce", 0),
            sequence("count", 0),
            sequence("shuffled", 0),
            sequence("shuffled", 1),
            sequence("averageOf", 1),
            sequence("elementAtOrNull", 1),
            sequence("elementAt", 1),
            sequence("elementAtOrElse", 2),
            sequence("sumOf", 1),
            sequence("sumBy", 1),
            sequence("sumByDouble", 1),
            sequence("minOf", 1),
            sequence("maxWith", 1),
            sequence("minWithOrNull", 1),
            sequence("minOfOrNull", 1),
            sequence("none", 0),
            sequence("none", 1),
            sequence("first", 0),
            sequence("firstOrNull", 0),
            sequence("maxWithOrNull", 1),
            sequence("minOrNull", 0),
            sequence("minWith", 1),
            sequence("firstNotNullOf", 1),
            sequence("firstNotNullOfOrNull", 1),
            sequence("indexOfLast", 1),
            sequence("intersect", 1),
            sequence("maxOrNull", 0),
            sequence("fold", 2),
            sequence("foldIndexed", 2),
            sequence("indexOfFirst", 1),
            sequence("minByOrNull", 1),
            sequence("minBy", 1),
            sequence("min", 0),
            sequence("forEachIndexed", 1),
            sequence("onEach", 1),
            sequence("onEachIndexed", 1),
            sequence("takeWhile", 1),
            sequence("mapIndexed", 1),
            sequence("reversed", 0),
            sequence("filterIndexed", 1),
            sequence("runningReduceIndexed", 1),
            sequence("scanIndexed", 2),
            sequence("runningFoldIndexed", 2),
            sequence("runningFold", 2),
            sequence("scan", 2),
            sequence("filterNotNull", 0),
            sequence("filterTo", 2),
            sequence("filterNotTo", 2),
            sequence("mapTo", 2),
            sequence("flatMapTo", 2),
            sequence("mapIndexedNotNullTo", 2),
            sequence("filterIndexedTo", 2),
            sequence("flatMapIndexedTo", 2),
            sequence("filterNotNullTo", 1),
            sequence("filterIsInstance", 0),
            sequence("filterIsInstanceTo", 1),
            sequence("reduceRightIndexed", 1),
            sequence("reduceRightOrNull", 1),
            sequence("requireNoNulls", 0),
            sequence("minus", 1),
            sequence("reduceRightIndexedOrNull", 1),
            sequence("associateTo", 2),
            sequence("associateByTo", 2),
            sequence("associateWithTo", 2),
            sequence("groupByTo", 2),
            sequence("reduceOrNull", 1),
            sequence("reduceRight", 1),
            sequence("reduceIndexed", 1),
            sequence("reduce", 1),
        ]

        let actual = Set(StdlibSurfaceSpec.collectionHOFMembers.map(SpecKey.init(spec:)))
        XCTAssertTrue(
            expected.isSubset(of: actual),
            "Missing expected stdlib surface specs: \(expected.subtracting(actual))"
        )
    }

    func testCollectionHOFSpecRuntimeLinksMatchRegisteredSyntheticMembers() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            let cases: [(ownerKind: StdlibSurfaceOwnerKind, ownerFQName: [String], memberName: String, arity: Int)] = [
                (.list, ["kotlin", "collections", "List"], "filterIndexedTo", 2),
                (.list, ["kotlin", "collections", "List"], "mapIndexedTo", 2),
                (.list, ["kotlin", "collections", "List"], "associateTo", 2),
                (.list, ["kotlin", "collections", "List"], "groupByTo", 2),
                (.list, ["kotlin", "collections", "Iterable"], "firstNotNullOf", 1),
                (.list, ["kotlin", "collections", "Iterable"], "sumBy", 1),
                (.map, ["kotlin", "collections", "Map"], "mapValuesTo", 2),
                (.map, ["kotlin", "collections", "Map"], "mapKeysTo", 2),
                (.map, ["kotlin", "collections", "Map"], "filterKeys", 1),
                (.map, ["kotlin", "collections", "Map"], "filterValues", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "groupBy", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "flatMapIndexedTo", 2),
                (.sequence, ["kotlin", "sequences", "Sequence"], "flatMap", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "flatMapIndexed", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "foldIndexed", 2),
                (.sequence, ["kotlin", "sequences", "Sequence"], "first", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "minBy", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "firstOrNull", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "flatMapTo", 2),
                (.sequence, ["kotlin", "sequences", "Sequence"], "fold", 2),
                (.sequence, ["kotlin", "sequences", "Sequence"], "firstNotNullOf", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "runningReduceIndexed", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "partition", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "random", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "reversed", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "scanIndexed", 2),
                (.sequence, ["kotlin", "sequences", "Sequence"], "reduceRightIndexed", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "reduceRightOrNull", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "plus", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "runningFoldIndexed", 2),
                (.sequence, ["kotlin", "sequences", "Sequence"], "runningFold", 2),
                (.sequence, ["kotlin", "sequences", "Sequence"], "reduceIndexed", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "randomOrNull", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "plusElement", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "requireNoNulls", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "reduceOrNull", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "shuffled", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "shuffled", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "reduceRight", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "scan", 2),
                (.sequence, ["kotlin", "sequences", "Sequence"], "maxOrNull", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "reduce", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "reduceRightIndexedOrNull", 1),
            ]

            for testCase in cases {
                let spec = try XCTUnwrap(
                    StdlibSurfaceSpec.collectionHOFMember(
                        ownerKind: testCase.ownerKind,
                        memberName: testCase.memberName,
                        arity: testCase.arity
                    ),
                    "Expected spec for \(testCase.ownerKind.rawValue).\(testCase.memberName)/\(testCase.arity)"
                )
                let fqName = (testCase.ownerFQName + [testCase.memberName]).map { ctx.interner.intern($0) }
                let links = Set(
                    sema.symbols.lookupAll(fqName: fqName)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )
                XCTAssertTrue(
                    links.contains(spec.runtimeLinkName),
                    "Expected \(testCase.memberName) to register \(spec.runtimeLinkName), got \(links)"
                )
            }
        }
    }

    func testSpecDrivenCollectionFallbackMembersKeepLambdaAndReturnTypes() throws {
        let source = """
        fun filterIndexedToSpec(values: List<Int>, destination: MutableList<Int>): MutableList<Int> {
            return values.filterIndexedTo(destination) { index, value -> index == value }
        }

        fun mapIndexedToSpec(values: List<Int>, destination: MutableList<Int>): MutableList<Int> {
            return values.mapIndexedTo(destination) { index, value -> index + value }
        }

        fun mapValuesToSpec(values: Map<Int, String>, destination: MutableMap<Int, Int>): MutableMap<Int, Int> {
            return values.mapValuesTo(destination) { entry -> entry.value.length }
        }

        fun filterKeysSpec(values: Map<Int, String>): Map<Int, String> {
            return values.filterKeys { key -> key + 1 > 1 }
        }

        fun filterValuesSpec(values: Map<Int, String>): Map<Int, String> {
            return values.filterValues { value -> value.length > 1 }
        }

        fun sequenceMapIndexedSpec(values: Sequence<Int>): Sequence<Int> {
            return values.mapIndexed { index, value -> index + value }
        }

        fun sequenceFirstNotNullOfSpec(values: Sequence<Int>): String {
            return values.firstNotNullOf<String> { value -> if (value == 2) "two" else null }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = diagnosticSummary(in: ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected spec-backed collection fallback cases to type-check cleanly, got: \(diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let expectedTypes: [(memberName: String, className: String)] = [
                ("filterIndexedTo", "MutableList"),
                ("mapIndexedTo", "MutableList"),
                ("mapValuesTo", "MutableMap"),
                ("filterKeys", "Map"),
                ("filterValues", "Map"),
                ("mapIndexed", "Sequence"),
            ]

            for (memberName, expectedClassName) in expectedTypes {
                let callExpr = try memberCall(named: memberName, in: ast, interner: ctx.interner)
                let type = try XCTUnwrap(sema.bindings.exprType(for: callExpr))
                XCTAssertEqual(
                    stdlibSurfaceClassName(of: type, sema: sema, interner: ctx.interner),
                    expectedClassName,
                    "Expected \(memberName) to return \(expectedClassName)"
                )
            }

            let firstNotNullOfCall = try memberCall(named: "firstNotNullOf", in: ast, interner: ctx.interner)
            XCTAssertEqual(sema.bindings.exprType(for: firstNotNullOfCall), sema.types.stringType)
        }
    }
}

private struct SpecKey: Hashable, CustomStringConvertible {
    let ownerKind: StdlibSurfaceOwnerKind
    let memberName: String
    let arityMinimum: Int
    let arityMaximum: Int

    init(ownerKind: StdlibSurfaceOwnerKind, memberName: String, arityMinimum: Int, arityMaximum: Int) {
        self.ownerKind = ownerKind
        self.memberName = memberName
        self.arityMinimum = arityMinimum
        self.arityMaximum = arityMaximum
    }

    init(spec: StdlibSurfaceSpec) {
        self.init(
            ownerKind: spec.ownerKind,
            memberName: spec.memberName,
            arityMinimum: spec.arity.minimum,
            arityMaximum: spec.arity.maximum
        )
    }

    var description: String {
        "\(ownerKind.rawValue).\(memberName)/\(arityMinimum)...\(arityMaximum)"
    }
}

private func list(_ memberName: String, _ arity: Int) -> SpecKey {
    SpecKey(ownerKind: .list, memberName: memberName, arityMinimum: arity, arityMaximum: arity)
}

private func set(_ memberName: String, _ arity: Int) -> SpecKey {
    SpecKey(ownerKind: .set, memberName: memberName, arityMinimum: arity, arityMaximum: arity)
}

private func map(_ memberName: String, _ arity: Int) -> SpecKey {
    SpecKey(ownerKind: .map, memberName: memberName, arityMinimum: arity, arityMaximum: arity)
}

private func sequence(_ memberName: String, _ arity: Int) -> SpecKey {
    SpecKey(ownerKind: .sequence, memberName: memberName, arityMinimum: arity, arityMaximum: arity)
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics
        .map { "\($0.code): \($0.message)" }
        .joined(separator: " | ")
}

private func memberCall(
    named memberName: String,
    in ast: ASTModule,
    interner: StringInterner
) throws -> ExprID {
    try XCTUnwrap(firstExprID(in: ast) { _, expr in
        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
        return interner.resolve(callee) == memberName
    }, "Expected member call to \(memberName)")
}

private func stdlibSurfaceClassName(
    of type: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> String? {
    guard case let .classType(classType) = sema.types.kind(of: type),
          let symbol = sema.symbols.symbol(classType.classSymbol)
    else {
        return nil
    }
    return interner.resolve(symbol.name)
}
