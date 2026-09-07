#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RangeSyntheticMemberLinkTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    private func externalLink(
        for owner: String,
        member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "ranges", owner, member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else {
            return nil
        }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func functionExternalLink(
        for owner: String,
        member: String,
        parameterCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "ranges", owner, member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes.count == parameterCount
        }.flatMap { sema.symbols.externalLinkName(for: $0) }
    }

    @Test func testCharProgressionSyntheticSurface() throws {
        let (sema, interner) = try sharedSema()
        let charProgressionFQName = ["kotlin", "ranges", "CharProgression"].map { interner.intern($0) }
        let charProgressionSymbol = try #require(sema.symbols.lookup(fqName: charProgressionFQName))
        let charProgressionType = sema.types.make(.classType(ClassType(
            classSymbol: charProgressionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: charProgressionSymbol))
        _ = try #require(sema.symbols.symbol(companionSymbol))
        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let fromClosedRangeFQ = ["kotlin", "ranges", "fromClosedRange"].map { interner.intern($0) }
        let fromClosedRangeSymbol = try #require(
            sema.symbols.lookupAll(fqName: fromClosedRangeFQ).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == companionType
                    && signature.parameterTypes == [sema.types.charType, sema.types.charType, sema.types.intType]
            }
        )
        let fromClosedRangeSignature = try #require(sema.symbols.functionSignature(for: fromClosedRangeSymbol))

        #expect(sema.symbols.externalLinkName(for: fromClosedRangeSymbol) == nil)
        #expect(sema.symbols.symbol(fromClosedRangeSymbol)?.flags.contains(.synthetic) == false)
        #expect(fromClosedRangeSignature.parameterTypes == [sema.types.charType, sema.types.charType, sema.types.intType])
        #expect(fromClosedRangeSignature.returnType == charProgressionType)
        let bundledToListName = ["kotlin", "ranges", "toList"].map { interner.intern($0) }
        let bundledToListSymbol = try #require(sema.symbols.lookupAll(fqName: bundledToListName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == charProgressionType
                && signature.parameterTypes.isEmpty
        })
        let bundledToListSignature = try #require(sema.symbols.functionSignature(for: bundledToListSymbol))
        #expect(sema.symbols.externalLinkName(for: bundledToListSymbol) == nil)
        #expect(
            sema.types.displayName(
                of: bundledToListSignature.returnType,
                symbols: sema.symbols,
                interner: interner
            ) == "List<Char>"
        )
        let bundledIsEmptyName = ["kotlin", "ranges", "isEmpty"].map { interner.intern($0) }
        let bundledIsEmptySymbol = try #require(sema.symbols.lookupAll(fqName: bundledIsEmptyName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == charProgressionType
                && signature.parameterTypes.isEmpty
        })
        #expect(sema.symbols.externalLinkName(for: bundledIsEmptySymbol) == nil)
        #expect(sema.symbols.symbol(bundledIsEmptySymbol)?.flags.contains(.synthetic) == false)
        #expect(
            functionExternalLink(
                for: "CharProgression",
                member: "isEmpty",
                parameterCount: 0,
                sema: sema,
                interner: interner
            ) == nil
        )
        let stepFQ = ["kotlin", "ranges", "step"].map { interner.intern($0) }
        let stepSymbol = sema.symbols.lookupAll(fqName: stepFQ).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == charProgressionType
                && signature.parameterTypes.count == 1
        }
        #expect(stepSymbol != nil)
        if let stepSymbol {
            #expect(sema.symbols.externalLinkName(for: stepSymbol) == nil)
            #expect(sema.symbols.symbol(stepSymbol)?.flags.contains(.synthetic) == false)
        }
    }

    @Test func testIntProgressionCompanionIsSourceBacked() throws {
        let (sema, interner) = try sharedSema()
        let intProgressionFQName = ["kotlin", "ranges", "IntProgression"].map { interner.intern($0) }
        let intProgressionSymbol = try #require(sema.symbols.lookup(fqName: intProgressionFQName))
        let intProgressionInfo = try #require(sema.symbols.symbol(intProgressionSymbol))
        #expect(!intProgressionInfo.flags.contains(.synthetic))
        #expect(intProgressionInfo.flags.contains(.openType))
        #expect(intProgressionInfo.declSite != nil)

        let companionFQName = intProgressionFQName + [interner.intern("Companion")]
        let companionSymbols = sema.symbols.lookupAll(fqName: companionFQName)
        #expect(companionSymbols.count == 1)
        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: intProgressionSymbol))
        let companionInfo = try #require(sema.symbols.symbol(companionSymbol))
        #expect(!companionInfo.flags.contains(.synthetic))
        #expect(companionInfo.declSite != nil)
        #expect(sema.symbols.isSourceBackedSymbol(companionSymbol))

        // KSP-1301 keeps the existing runtime-backed member surface unchanged.
        for memberName in ["first", "last", "step"] {
            let memberFQName = intProgressionFQName + [interner.intern(memberName)]
            let memberSymbols = sema.symbols.lookupAll(fqName: memberFQName)
            #expect(
                memberSymbols.contains { sema.symbols.symbol($0)?.flags.contains(.synthetic) == true },
                "IntProgression.\(memberName) remains synthetic until KSP-1301"
            )
        }
    }

    @Test func testCharProgressionFirstFamilyIsSourceBacked() throws {
        let ctx = makeContextFromSource(
            """
            fun firstValue(progression: CharProgression): Char = progression.first()
            fun firstOrNullValue(progress: CharProgression): Char? = progress.firstOrNull()
            fun lastValue(progression: CharProgression): Char = progression.last()
            fun lastOrNullValue(progress: CharProgression): Char? = progress.lastOrNull()
            """
        )
        try runSema(ctx)
        #expect(
            ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0102" }.isEmpty,
            "CharProgression first/last source functions must not overlap synthetic properties: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let charProgressionFQName = ["kotlin", "ranges", "CharProgression"].map { ctx.interner.intern($0) }
        let charProgressionSymbol = try #require(sema.symbols.lookup(fqName: charProgressionFQName))
        let charProgressionType = sema.types.make(.classType(ClassType(
            classSymbol: charProgressionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnTypes: [(name: String, typeName: String)] = [
            ("first", "Char"),
            ("firstOrNull", "Char?"),
            ("last", "Char"),
            ("lastOrNull", "Char?"),
        ]
        for expected in expectedReturnTypes {
            let fqName = ["kotlin", "ranges", expected.name].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == charProgressionType
                    && signature.parameterTypes.isEmpty
            })
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)
            #expect(sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == false)
            #expect(
                sema.types.displayName(of: signature.returnType, symbols: sema.symbols, interner: ctx.interner) == expected.typeName,
                "Unexpected return type for CharProgression.\(expected.name)"
            )
        }
        for expected in expectedReturnTypes {
            let callExpr = try #require(
                ast.arena.exprs.enumerated().first { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == expected.name && args.isEmpty
                }.map { ExprID(rawValue: Int32($0.offset)) }
            )
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.symbol(chosenCallee)?.declSite != nil)
            #expect(
                sema.symbols.symbol(chosenCallee)?.fqName == [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("ranges"),
                    ctx.interner.intern(expected.name),
                ]
            )
        }
    }

    @Test func testUIntRangeMapFilterFamilyIsSourceBacked() throws {
        let ctx = makeContextFromSource(
            """
            fun mapValue(range: UIntRange): List<UInt> = range.map { it }
            fun mapIndexedValue(range: UIntRange): List<UInt> = range.mapIndexed { index, value -> index.toUInt() + value }
            fun mapNotNullValue(range: UIntRange): List<UInt> = range.mapNotNull { if (it % 2u == 0u) null else it }
            fun filterValue(range: UIntRange): List<UInt> = range.filter { it % 2u == 1u }
            fun filterIndexedValue(range: UIntRange): List<UInt> = range.filterIndexed { index, _ -> index % 2 == 0 }
            fun filterNotValue(range: UIntRange): List<UInt> = range.filterNot { it % 2u == 0u }
            """
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected UIntRange map/filter HOFs to type-check, got: \(errors)")
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let expectedMembers = ["map", "mapIndexed", "mapNotNull", "filter", "filterIndexed", "filterNot"]
        let uintRangeFQName = ["kotlin", "ranges", "UIntRange"].map { ctx.interner.intern($0) }
        for member in expectedMembers {
            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == member
                },
                "Expected UIntRange.\(member) member call"
            )
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(signature.parameterTypes.count == 1)
            let receiver = try #require(signature.receiverType)
            let (_, receiverSymbol) = try #require(resolveClassTypeSymbol(receiver, sema: sema))
            #expect(receiverSymbol.fqName == uintRangeFQName)
        }
    }

    @Test func testUIntProgressionMapFilterFamilyIsSourceBacked() throws {
        let ctx = makeContextFromSource(
            """
            fun mapValue(range: UIntProgression): List<UInt> = range.map { it }
            fun mapIndexedValue(range: UIntProgression): List<UInt> = range.mapIndexed { index, value -> index.toUInt() + value }
            fun mapNotNullValue(range: UIntProgression): List<UInt> = range.mapNotNull { if (it % 2u == 0u) null else it }
            fun filterValue(range: UIntProgression): List<UInt> = range.filter { it % 2u == 1u }
            fun filterIndexedValue(range: UIntProgression): List<UInt> = range.filterIndexed { index, _ -> index % 2 == 0 }
            fun filterNotValue(range: UIntProgression): List<UInt> = range.filterNot { it % 2u == 0u }
            """
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected UIntProgression map/filter HOFs to type-check, got: \(errors)")
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let expectedMembers = ["map", "mapIndexed", "mapNotNull", "filter", "filterIndexed", "filterNot"]
        let uintProgressionFQName = ["kotlin", "ranges", "UIntProgression"].map { ctx.interner.intern($0) }
        for member in expectedMembers {
            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == member
                },
                "Expected UIntProgression.\(member) member call"
            )
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(signature.parameterTypes.count == 1)
            let receiver = try #require(signature.receiverType)
            let (_, receiverSymbol) = try #require(resolveClassTypeSymbol(receiver, sema: sema))
            #expect(receiverSymbol.fqName == uintProgressionFQName)
        }
    }

    @Test func testRangeRandomStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try sharedSema()

        let orNullExpected: [(owner: String, link: String)] = [
            // IntRange.firstOrNull is source-backed now; no runtime link.
            ("LongRange", "kk_long_range_firstOrNull"),
            ("ULongRange", "kk_ulong_range_firstOrNull"),
        ]
        for expectation in orNullExpected {
            #expect(
                externalLink(
                    for: expectation.owner,
                    member: "firstOrNull",
                    sema: sema,
                    interner: interner
                ) == expectation.link,
                Comment(rawValue: "\(expectation.owner).firstOrNull should link to \(expectation.link)")
            )
        }
        let lastOrNullExpected: [(owner: String, link: String)] = [
            // IntRange.lastOrNull is source-backed now; no runtime link.
            ("LongRange", "kk_long_range_lastOrNull"),
            ("ULongRange", "kk_ulong_range_lastOrNull"),
        ]
        for expectation in lastOrNullExpected {
            #expect(
                externalLink(
                    for: expectation.owner,
                    member: "lastOrNull",
                    sema: sema,
                    interner: interner
                ) == expectation.link,
                Comment(rawValue: "\(expectation.owner).lastOrNull should link to \(expectation.link)")
            )
        }

        for owner in ["IntRange", "LongRange", "CharRange", "UIntRange", "ULongRange"] {
            for member in ["random", "randomOrNull"] {
                let fq = ["kotlin", "ranges", owner, member].map { interner.intern($0) }
                for symbol in sema.symbols.lookupAll(fqName: fq) {
                    #expect(
                        sema.symbols.externalLinkName(for: symbol) == nil,
                        Comment(rawValue: "\(owner).\(member) must be source-backed")
                    )
                }
            }
        }
    }

    @Test func testRangeRandomMembersResolveInCallExpressions() throws {
        try assertRandomCallLink(
            source: """
            import kotlin.ranges.*

            fun probe(range: IntRange): Int = range.random()
            """,
            expectedLink: nil,
            expectedTypeName: "Int"
        )
        try assertRandomCallLink(
            source: """
            import kotlin.ranges.*

            fun probe(range: LongRange): Long = range.random()
            """,
            expectedLink: nil,
            expectedTypeName: "Long"
        )
        try assertRandomCallLink(
            source: """
            import kotlin.ranges.*

            fun probe(range: CharRange): Char = range.random()
            """,
            expectedLink: nil,
            expectedTypeName: "Char"
        )
        try assertRandomCallLink(
            source: """
            import kotlin.ranges.*

            fun probe(range: UIntRange): UInt = range.random()
            """,
            expectedLink: nil,
            expectedTypeName: "UInt"
        )
        try assertRandomCallLink(
            source: """
            import kotlin.ranges.*

            fun probe(range: ULongRange): ULong = range.random()
            """,
            expectedLink: nil,
            expectedTypeName: "ULong"
        )
    }

    private func assertRandomCallLink(
        source: String,
        expectedLink: String?,
        expectedTypeName: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(callee) == "random"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == expectedLink)
            let expectedType: TypeID
            switch expectedTypeName {
            case "Int":
                expectedType = sema.types.intType
            case "Long":
                expectedType = sema.types.longType
            case "Char":
                expectedType = sema.types.charType
            case "UInt":
                expectedType = sema.types.uintType
            case "ULong":
                expectedType = sema.types.ulongType
            default:
                Issue.record(Comment(rawValue: "Unexpected expected type name: \(expectedTypeName)"))
                return
            }
            #expect(
                sema.bindings.exprTypes[callExpr] == expectedType,
                Comment(rawValue: "Expected random() to return \(expectedTypeName)")
            )
        }
    }
}
#endif
