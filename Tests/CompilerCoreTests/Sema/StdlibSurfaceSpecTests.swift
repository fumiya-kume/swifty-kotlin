@testable import CompilerCore
import RuntimeABI
import Testing

@Suite
struct StdlibSurfaceSpecTests {
    @Test func testCollectionHOFSpecKeysAreUnique() {
        var seen: Set<SpecKey> = []

        for spec in StdlibSurfaceSpec.collectionHOFMembers {
            let key = SpecKey(
                ownerKind: spec.ownerKind,
                memberName: spec.memberName,
                arityMinimum: spec.arity.minimum,
                arityMaximum: spec.arity.maximum
            )
            #expect(
                seen.insert(key).inserted,
                "Duplicate stdlib surface spec for \(key)"
            )
        }
    }

    @Test func testCollectionHOFSpecRuntimeLinksAreNonEmpty() {
        for spec in StdlibSurfaceSpec.collectionHOFMembers {
            #expect(
                !spec.runtimeLinkName.isEmpty,
                "Expected runtime link for \(spec.ownerKind.rawValue).\(spec.memberName)/\(spec.arity.minimum)"
            )
        }
    }

    @Test func testCollectionHOFSpecRuntimeLinksAreRegisteredInRuntimeABI() {
        let abiNames = Set(RuntimeABISpec.allFunctions.map(\.name))

        for spec in StdlibSurfaceSpec.collectionHOFMembers {
            #expect(
                abiNames.contains(spec.runtimeLinkName),
                "Expected RuntimeABISpec to register \(spec.runtimeLinkName) for \(spec.ownerKind.rawValue).\(spec.memberName)"
            )
        }
    }

    @Test func testCollectionHOFSpecContainsV1Surface() {
        let expected: Set<SpecKey> = [
            list("forEach", 1),
            list("firstNotNullOf", 1),
            list("firstNotNullOfOrNull", 1),
            list("maxOfOrNull", 1),

            // Map and Set HOFs are source-backed and intentionally have no
            // runtime surface-spec entries.
            sequence("map", 1),
            sequence("filter", 1),
            sequence("filterNot", 1),
            sequence("mapNotNull", 1),
            sequence("flatMap", 1),
            sequence("flatMapIndexed", 1),
            sequence("plus", 1),
            sequence("randomOrNull", 0),
            sequence("plusElement", 1),
            sequence("contains", 1),
            sequence("indexOf", 1),
            sequence("constrainOnce", 0),
            sequence("count", 0),
            sequence("shuffled", 0),
            sequence("shuffled", 1),
            sequence("elementAtOrNull", 1),
            sequence("elementAt", 1),
            sequence("elementAtOrElse", 2),
            sequence("none", 0),
            sequence("none", 1),
            sequence("first", 0),
            sequence("firstOrNull", 0),
            sequence("minOrNull", 0),
            sequence("firstNotNullOf", 1),
            sequence("firstNotNullOfOrNull", 1),
            sequence("indexOfLast", 1),
            sequence("intersect", 1),
            sequence("maxOrNull", 0),
            sequence("indexOfFirst", 1),
            sequence("min", 0),
            sequence("onEach", 1),
            sequence("onEachIndexed", 1),
            sequence("mapIndexed", 1),
            sequence("reversed", 0),
            sequence("filterIndexed", 1),
            sequence("filterNotNull", 0),
            sequence("requireNoNulls", 0),
            sequence("minus", 1),
        ]

        let actual = Set(StdlibSurfaceSpec.collectionHOFMembers.map(SpecKey.init(spec:)))
        #expect(
            expected.isSubset(of: actual),
            "Missing expected stdlib surface specs: \(expected.subtracting(actual))"
        )
    }

    @Test func testCollectionHOFSpecRuntimeLinksMatchRegisteredSyntheticMembers() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)

            let cases: [(ownerKind: StdlibSurfaceOwnerKind, ownerFQName: [String], memberName: String, arity: Int)] = [
                // Source-backed members (ListHOF.kt / Sequence*.kt) have no
                // synthetic runtime-bridge stub; remaining entries are still
                // synthetically registered with their runtime links.
                // KSP-435 migrated Iterable.firstNotNullOf to bundled Kotlin
                // source, so it no longer registers a synthetic bridge member.
                // KSP-632 migrated Iterable.sumBy to bundled Kotlin source too.
                (.sequence, ["kotlin", "sequences", "Sequence"], "firstNotNullOf", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "random", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "reversed", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "plus", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "randomOrNull", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "plusElement", 1),
                (.sequence, ["kotlin", "sequences", "Sequence"], "shuffled", 0),
                (.sequence, ["kotlin", "sequences", "Sequence"], "shuffled", 1),
            ]

            for testCase in cases {
                let spec = try #require(
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
                #expect(
                    links.contains(spec.runtimeLinkName),
                    "Expected \(testCase.memberName) to register \(spec.runtimeLinkName), got \(links)"
                )
            }
        }
    }

    @Test func testSpecDrivenCollectionFallbackMembersKeepLambdaAndReturnTypes() throws {
        let source = """
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
            #expect(
                !ctx.diagnostics.hasError,
                "Expected spec-backed collection fallback cases to type-check cleanly, got: \(diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedTypes: [(memberName: String, className: String)] = [
                ("mapIndexedTo", "MutableList"),
                ("mapValuesTo", "MutableMap"),
                ("filterKeys", "Map"),
                ("filterValues", "Map"),
                ("mapIndexed", "Sequence"),
            ]

            for (memberName, expectedClassName) in expectedTypes {
                let callExpr = try memberCall(named: memberName, in: ast, interner: ctx.interner)
                let type = try #require(sema.bindings.exprType(for: callExpr))
                #expect(
                    stdlibSurfaceClassName(of: type, sema: sema, interner: ctx.interner) == expectedClassName,
                    "Expected \(memberName) to return \(expectedClassName)"
                )
            }

            let firstNotNullOfCall = try memberCall(named: "firstNotNullOf", in: ast, interner: ctx.interner)
            #expect(sema.bindings.exprType(for: firstNotNullOfCall) == sema.types.stringType)
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
    try #require(firstExprID(in: ast) { _, expr in
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
