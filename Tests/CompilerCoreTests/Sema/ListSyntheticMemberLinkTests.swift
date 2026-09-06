#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct ListSyntheticMemberLinkTests {
    static nonisolated(unsafe) var _sharedListSema: CompilationContext?

    func sharedListSemaContext() throws -> CompilationContext {
        if let cached = Self._sharedListSema {
            return cached
        }
        var result: CompilationContext?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedListSema = ctx
        return ctx
    }

    @Test
    func testListLastIndexExtensionFunctionResolvesToBundledSource() throws {
        let source = """
        import kotlin.collections.lastIndex

        fun last(values: List<String>): Int {
            return values.lastIndex
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.lastIndex to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let propertyExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "lastIndex" && args.isEmpty
            })
            #expect(sema.bindings.exprType(for: propertyExpr) == sema.types.intType)

            let getter = try #require(sema.bindings.callBinding(for: propertyExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: getter) == nil)
            #expect(sema.symbols.isSourceBackedSymbol(getter))

            #expect(sema.symbols.functionSignature(for: getter)?.returnType == sema.types.intType)
        }
    }

    @Test
    func testListTransformMembersUseRuntimeExternalLinksForParameterReceivers() throws {
        let source = """
        import kotlin.random.Random

        fun render(values: List<Int>) {
            values.take(3)
            values.drop(2)
            values.reversed()
            values.sorted()
            values.distinct()
            values.shuffled()
            values.shuffled(Random)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let expectedExternalLinks = [
                // KSP-427: take / drop / takeLast / dropLast / slice / subList are now bundled Kotlin source.
                ("take", 1, nil as String?),
                ("drop", 1, nil as String?),
                // KSP-428: reversed and distinct are bundled Kotlin source.
                ("reversed", 0, nil as String?),
                ("sorted", 0, nil as String?),
                ("distinct", 0, nil as String?),
                ("shuffled", 0, "kk_list_shuffled" as String?),
                ("shuffled", 1, "kk_list_shuffled_random" as String?),
            ]

            for (memberName, argumentCount, externalLinkName) in expectedExternalLinks {
                let callExpr = try #require(firstExprID(in: ast) { id, expr in
                    guard case let .memberCall(_, callee, _, args, range) = expr else { return false }
                    guard ctx.interner.resolve(callee) == memberName && args.count == argumentCount else { return false }
                    guard !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_") else { return false }
                    return true
                })
                let binding = sema.bindings.callBinding(for: callExpr)
                let chosenCallee = try #require(binding?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName ?? "nil")")
            }
        }
    }

    @Test
    func testListAndCollectionConversionMembersUseRuntimeExternalLinks() throws {
        let cases: [SyntheticMemberCallCase] = [
            .init(
                source: """
                fun copy(values: List<Pair<String, Int>>) {
                    values.toMap()
                }
                """,
                memberName: "toMap",
                expectedExternalLink: nil,
                expectedTypeShape: .classNamed("Map")
            ),
            .init(
                source: """
                fun copy(values: List<String>): MutableSet<String> {
                    return values.toHashSet()
                }
                """,
                memberName: "toHashSet",
                expectedExternalLink: nil,
                expectedTypeShape: nil
            ),
        ]

        for testCase in cases {
            try assertSyntheticMemberCall(testCase)
        }
    }

    @Test
    func testListIndicesExtensionFunctionResolvesToBundledSource() throws {
        let source = """
        import kotlin.collections.indices
        import kotlin.ranges.IntRange

        fun range(values: List<String>): IntRange {
            return values.indices
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.indices to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let propertyExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "indices" && args.isEmpty
            })
            let propertyType = try #require(sema.bindings.exprType(for: propertyExpr))
            guard case let .classType(rangeType) = sema.types.kind(of: propertyType) else {
                Issue.record("Expected List.indices to have IntRange type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(rangeType.classSymbol)?.name)) == "IntRange")

            let getter = try #require(sema.bindings.callBinding(for: propertyExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: getter) == nil)
            #expect(sema.symbols.isSourceBackedSymbol(getter))

            #expect(sema.symbols.functionSignature(for: getter)?.returnType == propertyType)
        }
    }

    @Test
    func testArrayListOfFactoryInfersMutableListType() throws {
        let source = """
        fun probe() {
            val values = arrayListOf(1, 2)
            values.add(3)
            val typed: ArrayList<Int> = arrayListOf<Int>()
            typed.add(4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected arrayListOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let arrayListCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "arrayListOf"
            })
            let callType = try #require(sema.bindings.exprTypes[arrayListCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected arrayListOf to produce a MutableList class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "MutableList")
            #expect(classType.args == [.invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(arrayListCall), "Expected arrayListOf to be tracked as a collection expression")
        }
    }

    @Test
    func testLinkedSetOfFactoryInfersLinkedHashSetType() throws {
        let source = """
        fun probe() {
            val values = linkedSetOf(1, 2)
            values.add(3)
            val typed: LinkedHashSet<Int> = linkedSetOf<Int>()
            typed.add(4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected linkedSetOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let linkedSetCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "linkedSetOf"
            })
            let callType = try #require(sema.bindings.exprTypes[linkedSetCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected linkedSetOf to produce a LinkedHashSet class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "LinkedHashSet")
            #expect(classType.args == [.invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(linkedSetCall), "Expected linkedSetOf to be tracked as a collection expression")

            let linkedSetCallee = try #require(sema.bindings.callBinding(for: linkedSetCall)?.chosenCallee)
            let linkedSetSymbol = try #require(sema.symbols.symbol(linkedSetCallee))
            #expect(sema.symbols.isSourceBackedSymbol(linkedSetCallee), "linkedSetOf must resolve to bundled Kotlin source")
            #expect(!linkedSetSymbol.flags.contains(.synthetic), "linkedSetOf must not use the synthetic bootstrap stub")
            #expect(linkedSetSymbol.declSite != nil, "linkedSetOf source declaration should carry a declaration site")
            #expect(sema.symbols.externalLinkName(for: linkedSetCallee) == nil)
        }
    }

    @Test
    func testLinkedHashSetConcreteClassAndConstructorSurfaceIsRegistered() throws {
        let source = """
        fun probe() {
            val constructed: LinkedHashSet<Int> = LinkedHashSet<Int>()
            val asMutable: MutableSet<Int> = constructed
            val fromExpectedMutable: MutableSet<Int> = LinkedHashSet()
            constructed.add(1)
            asMutable.add(2)
            fromExpectedMutable.add(3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected LinkedHashSet concrete class calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let kotlinCollections = [interner.intern("kotlin"), interner.intern("collections")]
            let linkedHashSetFQ = kotlinCollections + [interner.intern("LinkedHashSet")]
            let mutableSetFQ = kotlinCollections + [interner.intern("MutableSet")]
            let linkedHashSetSymbol = try #require(sema.symbols.lookup(fqName: linkedHashSetFQ))
            let mutableSetSymbol = try #require(sema.symbols.lookup(fqName: mutableSetFQ))

            let linkedHashSetInfo = try #require(sema.symbols.symbol(linkedHashSetSymbol))
            #expect(linkedHashSetInfo.kind == .class)
            // KSP-627: `kotlin.collections.LinkedHashSet` is source-backed by
            // `Sources/CompilerCore/Stdlib/kotlin/collections/CollectionAliases.kt`.
            #expect(!linkedHashSetInfo.flags.contains(.synthetic))
            #expect(linkedHashSetInfo.flags.contains(.openType))
            #expect(sema.symbols.directSupertypes(for: linkedHashSetSymbol).contains(mutableSetSymbol))
            #expect(sema.types.nominalTypeParameterVariances(for: linkedHashSetSymbol) == [.invariant])

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: linkedHashSetFQ + [interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .public)
            // The source constructors carry no runtime link: CollectionLiteralLoweringPass
            // rewrites `LinkedHashSet(...)` calls to `__kk_emptySet` /
            // `__kk_iterable_toMutableSet` by callee name.
            #expect(sema.symbols.externalLinkName(for: constructorSymbol) == nil)
            let signature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
            #expect(signature.parameterTypes.isEmpty)
            #expect(signature.typeParameterSymbols.count == 1)
            #expect(signature.classTypeParameterCount == 1)

            let constructorCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      let range = ast.arena.exprRange(callee)
                else { return false }
                return interner.resolve(name) == "LinkedHashSet"
                    && ctx.sourceManager.path(of: range.start.file) == path
            })
            let callType = try #require(sema.bindings.exprTypes[constructorCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected LinkedHashSet constructor to produce a class type"); return
            }
            #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "LinkedHashSet")
            #expect(classType.args == [.invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(constructorCall), "Expected LinkedHashSet constructor to be tracked as a collection expression")
        }
    }

    @Test
    func testHashSetConcreteClassAndConstructorSurfaceIsRegistered() throws {
        let source = """
        fun probe() {
            val constructed: HashSet<Int> = HashSet<Int>()
            val sized: HashSet<Int> = HashSet<Int>(8)
            val asMutable: MutableSet<Int> = constructed
            val copied = HashSet(constructed)
            val copiedFromCollection: HashSet<Int> = HashSet<Int>(listOf(4))
            val converted: HashSet<Int> = listOf(6).toHashSet()
            val copiedAsMutable: MutableSet<Int> = copied
            val fromExpectedMutable: MutableSet<Int> = HashSet()
            constructed.add(1)
            asMutable.add(2)
            sized.add(8)
            copiedFromCollection.add(5)
            converted.add(7)
            fromExpectedMutable.add(3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected HashSet concrete class calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let kotlinCollections = [interner.intern("kotlin"), interner.intern("collections")]
            let hashSetFQ = kotlinCollections + [interner.intern("HashSet")]
            let abstractMutableSetFQ = kotlinCollections + [interner.intern("AbstractMutableSet")]
            let mutableSetFQ = kotlinCollections + [interner.intern("MutableSet")]
            let hashSetSymbol = try #require(sema.symbols.lookup(fqName: hashSetFQ))
            let abstractMutableSetSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableSetFQ))
            let mutableSetSymbol = try #require(sema.symbols.lookup(fqName: mutableSetFQ))

            let hashSetInfo = try #require(sema.symbols.symbol(hashSetSymbol))
            #expect(hashSetInfo.kind == .class)
            #expect(!hashSetInfo.flags.contains(.synthetic))
            #expect(!hashSetInfo.flags.contains(.openType))
            #expect(hashSetInfo.declSite != nil)
            #expect(sema.symbols.directSupertypes(for: hashSetSymbol).contains(abstractMutableSetSymbol))
            #expect(sema.symbols.directSupertypes(for: hashSetSymbol).contains(mutableSetSymbol))
            #expect(sema.types.nominalTypeParameterVariances(for: hashSetSymbol) == [.invariant])

            let collectionSymbol = try #require(sema.symbols.lookup(fqName: kotlinCollections + [interner.intern("Collection")]))
            let constructorSymbols = sema.symbols.lookupAll(fqName: hashSetFQ + [interner.intern("<init>")])
            let constructorSignatures: [[TypeID]] = constructorSymbols.compactMap { constructorSymbol in
                guard let constructorInfo = sema.symbols.symbol(constructorSymbol),
                      constructorInfo.kind == .constructor,
                      constructorInfo.visibility == .public,
                      sema.symbols.externalLinkName(for: constructorSymbol) == nil,
                      let signature = sema.symbols.functionSignature(for: constructorSymbol)
                else {
                    return nil
                }
                #expect(signature.typeParameterSymbols.count == 1)
                #expect(signature.classTypeParameterCount == 1)
                return signature.parameterTypes
            }
            #expect(constructorSignatures.contains([]))
            #expect(constructorSignatures.contains([sema.types.intType]))
            #expect(constructorSignatures.contains { parameterTypes in
                guard let parameterType = parameterTypes.first,
                      case let .classType(collectionType) = sema.types.kind(of: parameterType)
                else {
                    return false
                }
                return collectionType.classSymbol == collectionSymbol
            })

            let constructorCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      let range = ast.arena.exprRange(callee)
                else { return false }
                return interner.resolve(name) == "HashSet"
                    && ctx.sourceManager.path(of: range.start.file) == path
            })
            let callType = try #require(sema.bindings.exprTypes[constructorCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected HashSet constructor to produce a class type"); return
            }
            #expect(interner.resolve(try #require(sema.symbols.symbol(classType.classSymbol)?.name)) == "HashSet")
            #expect(classType.args == [.invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(constructorCall), "Expected HashSet constructor to be tracked as a collection expression")
        }
    }

    @Test
    func testCollectionTypeAliasesAreSourceBacked() throws {
        let source = """
        fun probe() {
            val list: ArrayList<Int> = ArrayList<Int>()
            val set: HashSet<Int> = HashSet<Int>()
            val map: HashMap<String, Int> = HashMap<String, Int>()
            val linkedMap: LinkedHashMap<String, Int> = LinkedHashMap<String, Int>()
            list.add(1)
            set.add(2)
            map.put("a", 3)
            linkedMap.put("b", 4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected collection alias declarations to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let kotlinCollections = [interner.intern("kotlin"), interner.intern("collections")]

            // KSP-627: the remaining aliases are declared by
            // `Sources/CompilerCore/Stdlib/kotlin/collections/CollectionAliases.kt`,
            // not by synthetic self-registration.
            for (aliasName, targetName) in [
                ("ArrayList", "MutableList"),
                ("LinkedHashMap", "MutableMap"),
            ] {
                let aliasSymbol = try #require(
                    sema.symbols.lookupAll(fqName: kotlinCollections + [interner.intern(aliasName)])
                        .first { sema.symbols.symbol($0)?.kind == .typeAlias },
                    "Expected \(aliasName) to be registered as a type alias"
                )
                let aliasInfo = try #require(sema.symbols.symbol(aliasSymbol))
                #expect(!aliasInfo.flags.contains(.synthetic), "Expected \(aliasName) to be source-backed")
                #expect(aliasInfo.declSite != nil, "Expected \(aliasName) to carry a declaration site")

                let underlying = try #require(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol))
                guard case let .classType(underlyingClass) = sema.types.kind(of: underlying) else {
                    Issue.record("Expected \(aliasName) to expand to a class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(underlyingClass.classSymbol)?.name)) == targetName)
            }

            let hashMapSymbol = try #require(
                sema.symbols.lookupAll(fqName: kotlinCollections + [interner.intern("HashMap")])
                    .first { sema.symbols.symbol($0)?.kind == .class },
                "Expected HashMap to be registered as a class"
            )
            let hashMapInfo = try #require(sema.symbols.symbol(hashMapSymbol))
            #expect(!hashMapInfo.flags.contains(.synthetic), "Expected HashMap to be source-backed")
            #expect(hashMapInfo.declSite != nil, "Expected HashMap to carry a declaration site")
            let mutableMapSymbol = try #require(
                sema.symbols.lookup(fqName: kotlinCollections + [interner.intern("MutableMap")])
            )
            #expect(sema.symbols.directSupertypes(for: hashMapSymbol).contains(mutableMapSymbol))
        }
    }

    @Test
    func testLinkedMapOfFactoryInfersMutableMapType() throws {
        let source = """
        fun probe() {
            val values = linkedMapOf("a" to 1)
            values.put("b", 2)
            val typed: LinkedHashMap<String, Int> = linkedMapOf<String, Int>()
            typed.put("c", 3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected linkedMapOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let linkedMapCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "linkedMapOf"
            })
            let callType = try #require(sema.bindings.exprTypes[linkedMapCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected linkedMapOf to produce a MutableMap class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "MutableMap")
            #expect(classType.args == [.invariant(sema.types.stringType), .invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(linkedMapCall), "Expected linkedMapOf to be tracked as a collection expression")

            let linkedMapCallee = try #require(sema.bindings.callBinding(for: linkedMapCall)?.chosenCallee)
            let linkedMapSymbol = try #require(sema.symbols.symbol(linkedMapCallee))
            #expect(sema.symbols.isSourceBackedSymbol(linkedMapCallee), "linkedMapOf must resolve to bundled Kotlin source")
            #expect(!linkedMapSymbol.flags.contains(.synthetic), "linkedMapOf must not use the synthetic bootstrap stub")
            #expect(linkedMapSymbol.declSite != nil, "linkedMapOf source declaration should carry a declaration site")
            #expect(sema.symbols.externalLinkName(for: linkedMapCallee) == nil)
        }
    }

    @Test
    func testHashMapOfFactoryInfersMutableMapType() throws {
        let source = """
        fun probe() {
            val values = hashMapOf("a" to 1)
            values.put("b", 2)
            val typed: HashMap<String, Int> = hashMapOf<String, Int>()
            typed.put("c", 3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected hashMapOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let hashMapCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "hashMapOf"
            })
            let callType = try #require(sema.bindings.exprTypes[hashMapCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected hashMapOf to produce a MutableMap class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "MutableMap")
            #expect(classType.args == [.invariant(sema.types.stringType), .invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(hashMapCall), "Expected hashMapOf to be tracked as a collection expression")
        }
    }

    @Test
    func testHashSetOfFactoryInfersHashSetType() throws {
        let source = """
        fun probe() {
            val values = hashSetOf(1, 2)
            values.add(3)
            val typed: HashSet<Int> = hashSetOf<Int>()
            typed.add(4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected hashSetOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let hashSetCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "hashSetOf"
            })
            let callType = try #require(sema.bindings.exprTypes[hashSetCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                Issue.record("Expected hashSetOf to produce a HashSet class type"); return
            }
            #expect(try ctx.interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "HashSet")
            #expect(classType.args == [.invariant(sema.types.intType)])
            #expect(sema.bindings.isCollectionExpr(hashSetCall), "Expected hashSetOf to be tracked as a collection expression")
        }
    }

    @Test
    func testListAggregateMembersUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let expectedExternalLinks: [String: String?] = [
                "sum": nil,
                // KSP-426: sort/max/min family is source-backed in ListSortingHOF.kt
                // and ListExtremaHOF.kt, so synthetic stubs have no external link.
                "max": nil,
                "maxBy": nil,
                "maxByOrNull": nil,
                "maxOf": nil,
                "maxOfOrNull": nil,
                "maxOfWith": nil,
                "maxOfWithOrNull": nil,
                "maxOrNull": nil,
                "maxWith": nil,
                "maxWithOrNull": nil,
                "min": nil,
                "minBy": nil,
                "minByOrNull": nil,
                "minOf": nil,
                "minOfOrNull": nil,
                "minOfWith": nil,
                "minOfWithOrNull": nil,
                "minOrNull": nil,
                "minWith": nil,
                "minWithOrNull": nil,
                "sorted": nil,
                "sortedBy": nil,
                "sortedByDescending": nil,
                "sortedDescending": nil,
                "sortedWith": nil,
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let symbolID = try #require(listBackedFunctionSymbol(
                    memberName: memberName,
                    sema: sema,
                    interner: ctx.interner,
                    sourceManager: ctx.sourceManager
                ), "Expected List.\(memberName) to resolve")
                #expect(sema.symbols.externalLinkName(for: symbolID) == externalLinkName, "Expected \(memberName) externalLinkName to be \(String(describing: externalLinkName))")
            }

            // find / findLast are source-backed in ListSearchHOF.kt (KSP-423)
            // and therefore have no external link name.
            let collectionsPkg = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]
            for memberName in ["find", "findLast"] {
                let sourceSymbols = sema.symbols.lookupAll(fqName: collectionsPkg + [ctx.interner.intern(memberName)]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let fileID = sema.symbols.sourceFileID(for: symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.receiverType != nil
                    else {
                        return false
                    }
                    return ctx.sourceManager.path(of: fileID).hasPrefix("__bundled_")
                }
                #expect(!sourceSymbols.isEmpty, "Expected bundled Kotlin source for List.\(memberName)")
                #expect(sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil }, "List.\(memberName) should be source-backed")
            }
        }
    }

    @Test
    func testBundledListAggregateHOFsSuppressSyntheticStubs() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let packageFQName = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let listOwnerFQName = packageFQName + [ctx.interner.intern("List")]
            let iterableOwnerFQName = packageFQName + [ctx.interner.intern("Iterable")]

            func bundledListExtensionSymbols(named name: String, arity: Int) -> [SymbolID] {
                let fqName = packageFQName + [ctx.interner.intern(name)]
                return sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let fileID = sema.symbols.sourceFileID(for: symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.parameterTypes.count == arity,
                          signature.receiverType != nil
                    else {
                        return false
                    }
                    return ctx.sourceManager.path(of: fileID).hasPrefix("__bundled_")
                }
            }

            func syntheticMemberSymbols(
                ownerFQName: [InternedString],
                name: String,
                arity: Int,
                externalLinkPrefix: String? = nil
            ) -> [SymbolID] {
                let memberFQName = ownerFQName + [ctx.interner.intern(name)]
                return sema.symbols.lookupAll(fqName: memberFQName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          symbol.flags.contains(.synthetic),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.parameterTypes.count == arity
                    else {
                        return false
                    }
                    if let externalLinkPrefix,
                       let link = sema.symbols.externalLinkName(for: symbolID)
                    {
                        return link.hasPrefix(externalLinkPrefix)
                    }
                    return externalLinkPrefix == nil
                }
            }

            for name in ["count", "any", "all"] {
                let bundled = bundledListExtensionSymbols(named: name, arity: 1)
                #expect(!bundled.isEmpty, "Expected bundled Kotlin source for List.\(name)(predicate)")
                for symbolID in bundled {
                    #expect(
                        sema.symbols.externalLinkName(for: symbolID) == nil,
                        "Bundled List.\(name) should not have an external link name"
                    )
                }
            }

            for name in ["sumOf", "maxByOrNull", "minByOrNull"] {
                let synthetic = syntheticMemberSymbols(
                    ownerFQName: listOwnerFQName,
                    name: name,
                    arity: 1,
                    externalLinkPrefix: "kk_list_"
                )
                #expect(
                    synthetic.isEmpty,
                    "Expected no synthetic List.\(name) stub when bundled Kotlin source exists, found \(synthetic.count)"
                )
            }

            let sourceBackedFilters: [(name: String, arity: Int)] = [
                ("filter", 1),
                ("filterNot", 1),
                ("filterNotNull", 0),
                ("filterIndexed", 1),
                ("filterIsInstance", 0),
            ]
            for (name, arity) in sourceBackedFilters {
                let bundled = bundledListExtensionSymbols(named: name, arity: arity)
                #expect(!bundled.isEmpty, "Expected bundled Kotlin source for List.\(name)")
                #expect(
                    bundled.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                    "Bundled List.\(name) should not have an external link name"
                )
                let synthetic = syntheticMemberSymbols(
                    ownerFQName: listOwnerFQName,
                    name: name,
                    arity: arity,
                    externalLinkPrefix: "kk_list_"
                )
                #expect(
                    synthetic.isEmpty,
                    "Expected no synthetic List.\(name) stub when bundled Kotlin source exists, found \(synthetic.count)"
                )
            }

            // KSP-423: search and predicate HOFs are source-backed.
            let sourceBackedSearchHOFs: [(name: String, arity: Int)] = [
                ("contains", 1),
                ("containsAll", 1),
                ("lastIndexOf", 1),
                ("count", 0),
                ("count", 1),
                ("any", 0),
                ("any", 1),
                ("all", 1),
                ("none", 0),
                ("none", 1),
                ("binarySearch", 3),
                ("binarySearch", 4),
                ("binarySearchBy", 4),
            ]
            for (name, arity) in sourceBackedSearchHOFs {
                let bundled = bundledListExtensionSymbols(named: name, arity: arity)
                #expect(!bundled.isEmpty, "Expected bundled Kotlin source for List.\(name)(arity: \(arity))")
                #expect(
                    bundled.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                    "Bundled List.\(name) should not have an external link name"
                )
                let synthetic = syntheticMemberSymbols(
                    ownerFQName: listOwnerFQName,
                    name: name,
                    arity: arity,
                    externalLinkPrefix: "kk_list_"
                )
                #expect(
                    synthetic.isEmpty,
                    "Expected no synthetic List.\(name)(arity: \(arity)) stub when bundled Kotlin source exists, found \(synthetic.count)"
                )
            }

            for (name, link) in [("any", "__kk_iterable_any"), ("all", "__kk_iterable_all")] {
                let synthetic = syntheticMemberSymbols(
                    ownerFQName: iterableOwnerFQName,
                    name: name,
                    arity: 1,
                    externalLinkPrefix: link
                )
                #expect(
                    synthetic.isEmpty,
                    "Expected no synthetic Iterable.\(name)(predicate) stub when bundled List.\(name) exists"
                )
            }

            #expect(
                syntheticMemberSymbols(ownerFQName: listOwnerFQName, name: "count", arity: 1).isEmpty
            )
            #expect(
                syntheticMemberSymbols(ownerFQName: iterableOwnerFQName, name: "count", arity: 1).isEmpty
            )
        }
    }

    @Test
    func testListSearchHOFsHaveBundledSourceDefinitions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let packageFQName = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let expectedArities: [String: Set<Int>] = [
                "first": [0, 1],
                "firstOrNull": [0, 1],
                "last": [0, 1],
                "lastOrNull": [0, 1],
                "single": [0, 1],
                "singleOrNull": [0, 1],
                "find": [1],
                "findLast": [1],
                "indexOf": [1],
                "indexOfFirst": [1],
                "indexOfLast": [1],
                "lastIndexOf": [1],
                "contains": [1],
                "containsAll": [1],
                "count": [0, 1],
                "any": [0, 1],
                "all": [1],
                "none": [0, 1],
                "binarySearch": [3, 4],
                "binarySearchBy": [4],
            ]

            for (name, arities) in expectedArities {
                let fqName = packageFQName + [ctx.interner.intern(name)]
                let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let fileID = sema.symbols.sourceFileID(for: symbolID)
                    else {
                        return false
                    }
                    let path = ctx.sourceManager.path(of: fileID)
                    return path.hasPrefix("__bundled_")
                }
                let registeredArities = Set(sourceSymbols.compactMap { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count
                })
                #expect(arities.isSubset(of: registeredArities), "Expected \(name) bundled source overloads \(arities), got \(registeredArities)")
                #expect(sourceSymbols.allSatisfy { symbolID in
                        sema.symbols.functionSignature(for: symbolID)?.receiverType != nil
                    }, "Expected \(name) bundled source definitions to be List extension functions")

            }
        }
    }

    @Test
    func testListBinarySearchBindsToBundledSource() throws {
        let source = """
        fun search(values: List<Int>): Int {
            return values.binarySearch(3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected List.binarySearch to type-check cleanly, got: \(diagnosticSummary)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "binarySearch" && args.count == 1
            })
            let binding = sema.bindings.callBinding(for: callExpr)
            let chosenCallee = try #require(binding?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.symbols.symbol(chosenCallee)?.declSite != nil)
        }
    }

    @Test
    func testListBinarySearchByAndComparatorBindsToBundledSource() throws {
        let source = """
        fun search(values: List<Int>): Int {
            val natural = naturalOrder<Int>()
            val byKey = values.binarySearchBy(3) { it }
            val byComparator = values.binarySearch(3, natural)
            return byKey + byComparator
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected List.binarySearchBy/comparator to type-check cleanly, got: \(diagnosticSummary)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let byKeyCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "binarySearchBy" && args.count == 2
            })
            let byKeyBinding = sema.bindings.callBinding(for: byKeyCall)
            let byKeyCallee = try #require(byKeyBinding?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: byKeyCallee) == nil)
            #expect(sema.symbols.symbol(byKeyCallee)?.declSite != nil)

            let byComparatorCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "binarySearch" && args.count == 2
            })
            let byComparatorBinding = sema.bindings.callBinding(for: byComparatorCall)
            let byComparatorCallee = try #require(byComparatorBinding?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: byComparatorCallee) == nil)
            #expect(sema.symbols.symbol(byComparatorCallee)?.declSite != nil)
        }
    }

    @Test
    func testListFilterIsInstanceToBindsBundledSource() throws {
        let source = """
        fun collect(values: List<Any>, dest: MutableList<String>) {
            values.filterIsInstanceTo(dest)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected List.filterIsInstanceTo to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterIsInstanceTo"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.symbols.symbol(chosenCallee)?.declSite != nil)
            #expect(sema.bindings.isCollectionExpr(callExpr), "Expected filterIsInstanceTo result to be tracked as a collection expression")
        }
    }

    @Test
    func testIterableDistinctByBindsBundledSource() throws {
        let source = """
        fun deduplicate(values: List<Int>): List<Int> {
            return values.distinctBy { value -> value % 2 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, "Expected List.distinctBy to type-check cleanly, got: \(diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "distinctBy"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let fileID = try #require(sema.symbols.sourceFileID(for: chosenCallee))
            #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ListCollectionOps.kt")
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        }
    }

    @Test
    func testIterableSumByResolvesToSourceBacked() throws {
        let source = """
        fun checksum(values: Iterable<Int>): Int {
            return values.sumBy { value ->
                value * value
            }
        }

        fun checksumFromList(values: List<Int>): Int {
            return values.sumBy(selector = { value ->
                value * 2
            })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.sumBy surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberSymbol = try #require(sourceBackedIterableExtensionSymbol(
                named: "sumBy",
                sema: sema,
                interner: ctx.interner
            ))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == nil)
            #expect(sema.symbols.annotations(for: memberSymbol).contains { KnownCompilerAnnotation.deprecated.matches($0.annotationFQName) }, "Iterable.sumBy should carry Deprecated metadata")

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.parameterTypes.count == 1)
            guard case let .functionType(selectorType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("Expected Iterable.sumBy selector parameter to be a function"); return
            }
            #expect(selectorType.params.count == 1)
            #expect(signature.returnType == sema.types.intType)

            let callLinks = sema.bindings.callBindings.values
                .filter { $0.chosenCallee == memberSymbol }
                .compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            // KSP-632: Iterable.sumBy is bundled Kotlin source, so no public
            // kk_list_sumBy runtime bridge remains.
            #expect(callLinks.filter { $0 == "kk_list_sumBy" }.count == 0)
        }
    }

    @Test
    func testIterableSumByDoubleResolvesToSourceBacked() throws {
        let source = """
        fun checksum(values: Iterable<Int>): Double {
            return values.sumByDouble { value ->
                if (value == 2) 1.5 else 0.25
            }
        }

        fun checksumFromList(values: List<Int>): Double {
            return values.sumByDouble(selector = { value ->
                value.toDouble()
            })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.sumByDouble surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberSymbol = try #require(sourceBackedIterableExtensionSymbol(
                named: "sumByDouble",
                sema: sema,
                interner: ctx.interner
            ))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == nil)
            #expect(sema.symbols.annotations(for: memberSymbol).contains { KnownCompilerAnnotation.deprecated.matches($0.annotationFQName) }, "Iterable.sumByDouble should carry Deprecated metadata")

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.parameterTypes.count == 1)
            guard case let .functionType(selectorType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("Expected Iterable.sumByDouble selector parameter to be a function"); return
            }
            #expect(selectorType.params.count == 1)
            #expect(signature.returnType == sema.types.doubleType)

            let callLinks = sema.bindings.callBindings.values
                .filter { $0.chosenCallee == memberSymbol }
                .compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            // KSP-632: Iterable.sumByDouble is bundled Kotlin source, so no public
            // kk_list_sumByDouble runtime bridge remains.
            #expect(callLinks.filter { $0 == "kk_list_sumByDouble" }.count == 0)
        }
    }

    @Test
    func testIterableFirstNotNullOfResolvesInCallExpressions() throws {
        let source = """
        fun pickLabel(values: Iterable<Int>): String {
            return values.firstNotNullOf<String> { value ->
                if (value == 2) "two" else null
            }
        }

        fun pickListLabel(values: List<Int>): String {
            return values.firstNotNullOf<String> { value ->
                if (value == 3) "three" else null
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.firstNotNullOf surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "firstNotNullOf"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            // KSP-435: firstNotNullOf is bundled Kotlin source, so no public
            // kk_iterable_* link may remain on the Iterable surface.
            #expect(!links.contains("kk_iterable_firstNotNullOf"))
        }
    }

    @Test
    func testIterableFirstNotNullOfOrNullResolvesInCallExpressions() throws {
        let source = """
        fun pickLabel(values: Iterable<Int>): String? {
            return values.firstNotNullOfOrNull<String> { value ->
                if (value == 2) "two" else null
            }
        }

        fun pickListLabel(values: List<Int>): String? {
            return values.firstNotNullOfOrNull<String> { value ->
                if (value == 3) "three" else null
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.firstNotNullOfOrNull surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "firstNotNullOfOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            // KSP-435: firstNotNullOfOrNull is bundled Kotlin source, so no
            // public kk_iterable_* link may remain on the Iterable surface.
            #expect(!links.contains("kk_iterable_firstNotNullOfOrNull"))
        }
    }

    @Test
    func testIterableMinusElementResolvesToSourceBacked() throws {
        let source = """
        fun removeValue(values: Iterable<Int>): List<Int> {
            return values.minusElement(2)
        }

        fun removeFromList(values: List<Int>): List<Int> {
            return values.minusElement(element = 3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.minusElement surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberSymbol = try #require(sourceBackedIterableExtensionSymbol(
                named: "minusElement",
                sema: sema,
                interner: ctx.interner
            ))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == nil)

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.parameterTypes.count == 1)
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                  let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
            else {
                Issue.record("Expected Iterable.minusElement to return List<E>"); return
            }
            #expect(ctx.interner.resolve(returnSymbol.name) == "List")

            let callLinks = sema.bindings.callBindings.values
                .filter { $0.chosenCallee == memberSymbol }
                .compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            // KSP-701: Iterable.minusElement is bundled Kotlin source, so no public
            // kk_list_minus_element runtime bridge remains.
            #expect(callLinks.filter { $0 == "kk_list_minus_element" }.count == 0)
        }
    }

    @Test
    func testIterableFilterAndReduceMembersResolveToSourceBacked() throws {
        let source = """
        fun filterValues(values: Iterable<Int>): List<Int> {
            return values.filter { it % 2 == 0 }
        }

        fun reduceValues(values: Iterable<Int>): Int {
            return values.reduce { acc: Int, value: Int -> acc + value }
        }

        fun reduceIndexedValues(values: Iterable<Int>): Int {
            return values.reduceIndexed { index: Int, acc: Int, value: Int -> acc + index + value }
        }

        fun reduceOrNullValues(values: Iterable<Int>): Int? {
            return values.reduceOrNull { acc: Int, value: Int -> acc + value }
        }

        fun reduceIndexedOrNullValues(values: Iterable<Int>): Int? {
            return values.reduceIndexedOrNull { index: Int, acc: Int, value: Int -> acc + index + value }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable collection members to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            for memberName in ["filter", "reduce", "reduceIndexed", "reduceOrNull", "reduceIndexedOrNull"] {
                let memberSymbol = try #require(sourceBackedIterableExtensionSymbol(
                    named: memberName,
                    sema: sema,
                    interner: ctx.interner
                ))
                #expect(sema.symbols.externalLinkName(for: memberSymbol) == nil)
                #expect(sema.symbols.isSourceBackedSymbol(memberSymbol))

                let callLinks = sema.bindings.callBindings.values
                    .filter { $0.chosenCallee == memberSymbol }
                    .compactMap { sema.symbols.externalLinkName(for: $0.chosenCallee) }
                #expect(callLinks.isEmpty, "Expected Iterable.\(memberName) to avoid a runtime bridge")
            }
        }
    }

    @Test
    func testIterableIndexFamilyResolvesToSourceBackedWithoutHijackingList() throws {
        let source = """
        class OneShot<T> : Iterable<T> {
            override fun iterator(): Iterator<T> = emptyList<T>().iterator()
        }

        fun probe(
            values: Iterable<Int>,
            nullable: Iterable<String?>,
            custom: OneShot<Int>,
            list: List<Int>
        ) {
            values.indexOf(1)
            nullable.indexOf(null)
            custom.indexOfFirst { it > 0 }
            values.indexOfFirst { it > 0 }
            values.indexOfLast { it > 0 }
            list.indexOf(1)
            list.indexOfFirst { it > 0 }
            list.indexOfLast { it > 0 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, "Expected Iterable.index-family to type-check cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            for memberName in ["indexOf", "indexOfFirst", "indexOfLast"] {
                let iterableSymbol = try #require(sourceBackedIterableExtensionSymbol(
                    named: memberName,
                    sema: sema,
                    interner: ctx.interner
                ))
                #expect(sema.symbols.externalLinkName(for: iterableSymbol) == nil)
                #expect(sema.symbols.isSourceBackedSymbol(iterableSymbol))
                let declarationRange = try #require(sema.symbols.symbol(iterableSymbol)?.declSite)
                let declarationSource = ctx.sourceManager.slice(declarationRange)
                // Reaching Int.MAX_VALUE requires 2^31 iterator elements, so
                // lock the overflow guard ordering at the bundled source boundary.
                #expect(
                    declarationSource.contains("if (index < 0)"),
                    "Expected Iterable.\(memberName) to check overflow after counter wrap"
                )
                #expect(
                    !declarationSource.contains("index == Int.MAX_VALUE"),
                    "Iterable.\(memberName) must evaluate the Int.MAX_VALUE candidate before throwing"
                )
                let iterableCallCount = sema.bindings.callBindings.values
                    .filter { $0.chosenCallee == iterableSymbol }
                    .count
                #expect(iterableCallCount > 0, "Expected Iterable.\(memberName) to bind to its source declaration")

                let listSymbol = try #require(listBackedFunctionSymbol(
                    memberName: memberName,
                    sema: sema,
                    interner: ctx.interner,
                    sourceManager: ctx.sourceManager
                ))
                let listCallCount = sema.bindings.callBindings.values
                    .filter { $0.chosenCallee == listSymbol }
                    .count
                #expect(listCallCount > 0, "Expected List.\(memberName) to retain its existing source declaration")
            }
        }
    }

    @Test
    func testIterableFilterFamilyResolvesToSourceBacked() throws {
        let source = """
        fun filterFamily(values: Iterable<Any?>, nullable: Iterable<String?>) {
            values.filter { it != null }
            values.filterIndexed { index, _ -> index % 2 == 0 }

            val indexedDestination = mutableListOf<Any?>()
            values.filterIndexedTo(indexedDestination) { index, _ -> index % 2 == 0 }

            values.filterIsInstance<String>()
            val instanceDestination = mutableListOf<String>()
            values.filterIsInstanceTo(instanceDestination)

            values.filterNot { it == null }
            nullable.filterNotNull()

            val notNullDestination = mutableListOf<String>()
            nullable.filterNotNullTo(notNullDestination)

            val notDestination = mutableListOf<Any?>()
            values.filterNotTo(notDestination) { it == null }

            val destination = mutableListOf<Any?>()
            values.filterTo(destination) { it != null }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, "Expected Iterable.filter-family to type-check cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            for memberName in [
                "filter", "filterIndexed", "filterIndexedTo", "filterIsInstance", "filterIsInstanceTo",
                "filterNot", "filterNotNull", "filterNotNullTo", "filterNotTo", "filterTo",
            ] {
                let memberSymbol = try #require(sourceBackedIterableExtensionSymbol(
                    named: memberName,
                    sema: sema,
                    interner: ctx.interner
                ))
                #expect(sema.symbols.externalLinkName(for: memberSymbol) == nil)
                #expect(sema.symbols.isSourceBackedSymbol(memberSymbol))
                let callCount = sema.bindings.callBindings.values
                    .filter { $0.chosenCallee == memberSymbol }
                    .count
                #expect(callCount > 0, "Expected Iterable.\(memberName) call to bind to its source declaration")
            }
        }
    }

    @Test
    func testRangeInitializerOnlyWidensToPlainIterableAnnotation() throws {
        let validSource = """
        fun valid() {
            val values: Iterable<Int> = 1..3
        }
        """
        try withTemporaryFile(contents: validSource) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected Iterable<Int> range annotation to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")
        }

        let invalidSources: [(String, String)] = [
            ("List", "val values: List<Int> = 1..3"),
            ("Set", "val values: Set<Int> = 1..3"),
            ("Collection", "val values: Collection<Int> = 1..3"),
            ("Array", "val values: Array<Int> = 1..3"),
            ("String", "val values: String = 'a'..'c'"),
        ]
        for (annotationName, declaration) in invalidSources {
            let source = """
            fun invalid() {
                \(declaration)
            }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)
                #expect(ctx.diagnostics.hasError, "Expected range-to-\(annotationName) assignment to produce a type error")
            }
        }
    }

    @Test
    func testIterableReduceRightIndexedResolvesToSourceBacked() throws {
        let source = """
        fun checksum(values: Iterable<Int>): Int {
            return values.reduceRightIndexed { index, value, acc ->
                index * 100 + value * 10 + acc
            }
        }

        fun checksumFromList(values: List<Int>): Int {
            return values.reduceRightIndexed(operation = { index, value, acc ->
                index + value + acc
            })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.reduceRightIndexed surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberSymbol = try #require(sourceBackedIterableExtensionSymbol(
                named: "reduceRightIndexed",
                sema: sema,
                interner: ctx.interner
            ))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == nil)

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.parameterTypes.count == 1)
            guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("Expected Iterable.reduceRightIndexed operation parameter to be a function"); return
            }
            #expect(operationType.params.count == 3)
            guard case let .primitive(indexPrimitive, indexNullability) = sema.types.kind(of: operationType.params[0]) else {
                Issue.record("Expected first reduceRightIndexed lambda parameter to be Int"); return
            }
            #expect(indexPrimitive == .int)
            #expect(indexNullability == .nonNull)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            // KSP-632: both Iterable and List reduceRightIndexed are bundled Kotlin
            // source, so no public kk_list_reduceRightIndexed runtime bridge remains.
            #expect(callLinks.filter { $0 == "kk_list_reduceRightIndexed" }.count == 0)
        }
    }

    @Test
    func testIterableReduceRightIndexedOrNullResolvesToSourceBacked() throws {
        let source = """
        fun checksum(values: Iterable<Int>): Int? {
            return values.reduceRightIndexedOrNull { index, value, acc ->
                index * 100 + value * 10 + acc
            }
        }

        fun checksumFromList(values: List<Int>): Int? {
            return values.reduceRightIndexedOrNull(operation = { index, value, acc ->
                index + value + acc
            })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.reduceRightIndexedOrNull surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberSymbol = try #require(sourceBackedIterableExtensionSymbol(
                named: "reduceRightIndexedOrNull",
                sema: sema,
                interner: ctx.interner
            ))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == nil)

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.parameterTypes.count == 1)
            guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("Expected Iterable.reduceRightIndexedOrNull operation parameter to be a function"); return
            }
            #expect(operationType.params.count == 3)
            guard case let .primitive(indexPrimitive, indexNullability) = sema.types.kind(of: operationType.params[0]) else {
                Issue.record("Expected first reduceRightIndexedOrNull lambda parameter to be Int"); return
            }
            #expect(indexPrimitive == .int)
            #expect(indexNullability == .nonNull)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            // KSP-632: both Iterable and List reduceRightIndexedOrNull are bundled
            // Kotlin source, so no public kk_list_reduceRightIndexedOrNull runtime
            // bridge remains.
            #expect(callLinks.filter { $0 == "kk_list_reduceRightIndexedOrNull" }.count == 0)
        }
    }

    @Test
    func testIterableReduceRightOrNullResolvesToSourceBacked() throws {
        let source = """
        fun checksum(values: Iterable<Int>): Int? {
            return values.reduceRightOrNull { value, acc ->
                value * 10 + acc
            }
        }

        fun checksumFromList(values: List<Int>): Int? {
            return values.reduceRightOrNull(operation = { value, acc ->
                value + acc
            })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable.reduceRightOrNull surface to resolve cleanly, got: \(diagnosticSummary)")

            let sema = try #require(ctx.sema)
            let memberSymbol = try #require(sourceBackedIterableExtensionSymbol(
                named: "reduceRightOrNull",
                sema: sema,
                interner: ctx.interner
            ))
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == nil)

            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.parameterTypes.count == 1)
            guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("Expected Iterable.reduceRightOrNull operation parameter to be a function"); return
            }
            #expect(operationType.params.count == 2)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            // KSP-632: both Iterable and List reduceRightOrNull are bundled Kotlin
            // source, so no public kk_list_reduceRightOrNull runtime bridge remains.
            #expect(callLinks.filter { $0 == "kk_list_reduceRightOrNull" }.count == 0)
        }
    }

    @Test
    func testListFirstAndOrNullTerminalsReturnElementsWithoutCollectionMarking() throws {
        let source = """
        fun probe(values: List<Int>) {
            values.first()
            values.firstOrNull()
            values.firstOrNull { it > 1 }
            values.lastOrNull()
            values.lastOrNull { it < 3 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let nullableIntType = sema.types.makeNullable(sema.types.intType)
            let expectedTerminalCalls: [(memberName: String, expectedType: TypeID)] = [
                ("first", sema.types.intType),
                ("firstOrNull", nullableIntType),
                ("lastOrNull", nullableIntType),
            ]

            for (memberName, expectedType) in expectedTerminalCalls {
                // Use lastExprID rather than firstExprID: bundled stdlib sources
                // (injected before the fixture's own source) may already contain
                // calls to the same member name, which would otherwise shadow the
                // fixture's own call site.
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName && args.isEmpty
                })

                #expect(sema.bindings.exprTypes[callExpr] == expectedType, "Expected \(memberName) to return the expected element type")
                #expect(!(sema.bindings.isCollectionExpr(callExpr)), "Expected \(memberName) result to avoid collection-expression marking")
            }

            for memberName in ["firstOrNull", "lastOrNull"] {
                let predicateCall = try #require(lastExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName && args.count == 1
                })
                guard case let .memberCall(_, _, _, args, _) = ast.arena.expr(predicateCall),
                      let predicateArg = args.first?.expr
                else {
                    Issue.record("Expected \(memberName)(predicate) call to keep its lambda argument")
                    continue
                }
                #expect(!sema.bindings.isCollectionHOFLambdaExpr(predicateArg), "Expected \(memberName)(predicate) lambda to be unmarked for source-backed lowering")
                #expect(sema.bindings.exprTypes[predicateCall] == nullableIntType, "Expected \(memberName)(predicate) to return nullable element type")
                #expect(!(sema.bindings.isCollectionExpr(predicateCall)), "Expected \(memberName)(predicate) result to avoid collection-expression marking")
            }
        }
    }

    @Test
    func testListMaxOrNullAndMinOrNullRequireComparableElements() throws {
        let source = """
        class Box

        fun render(values: List<Box>) {
            values.maxOrNull()
            values.minOrNull()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            let boundDiagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-BOUND" }
            #expect(boundDiagnostics.count == 2, "Expected bound diagnostics for maxOrNull/minOrNull")
        }
    }

    @Test
    func testComparableSyntheticStubUsesContravariantTypeParameter() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let comparableSymbol = try #require(sema.types.comparableInterfaceSymbol)
            #expect(sema.types.nominalTypeParameterVariances(for: comparableSymbol) == [.in], "Expected Comparable to be declared as Comparable<in T>")

            let comparableAny = sema.types.make(.classType(ClassType(
                classSymbol: comparableSymbol,
                args: [.invariant(sema.types.anyType)],
                nullability: .nonNull
            )))
            let comparableString = sema.types.make(.classType(ClassType(
                classSymbol: comparableSymbol,
                args: [.invariant(sema.types.stringType)],
                nullability: .nonNull
            )))

            #expect(sema.types.isSubtype(comparableAny, comparableString), "Expected Comparable<Any> to be a subtype of Comparable<String>")
            #expect(!(sema.types.isSubtype(comparableString, comparableAny)), "Expected Comparable<String> not to be a subtype of Comparable<Any>")
        }
    }

    @Test
    func testCollectionFallbackRejectsListOnlyIndexedLookupsOnAbstractCollection() throws {
        let source = """
        fun firstValue(values: Collection<Int>): Int? = values.firstOrNull()
        fun lastValue(values: Collection<Int>): Int? = values.lastOrNull()
        fun fallbackValue(values: Collection<Int>): Int = values.getOrElse(0) { -1 }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let nullableIntType = sema.types.makeNullable(sema.types.intType)

            for memberName in ["firstOrNull", "lastOrNull", "getOrElse"] {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                if memberName == "firstOrNull" {
                    // KSP-973: Collection inherits Iterable, so firstOrNull now resolves to bundled source.
                    let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    let chosenSymbol = try #require(sema.symbols.symbol(chosenCallee))
                    #expect(
                        chosenSymbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "firstOrNull"],
                        "Expected Collection.firstOrNull to resolve to kotlin.collections.firstOrNull"
                    )
                    #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)

                    let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                    #expect(signature.parameterTypes.isEmpty, "Expected Iterable.firstOrNull() to have no value parameters")
                    let receiverType = try #require(signature.receiverType)
                    guard case let .classType(receiver) = sema.types.kind(of: receiverType),
                          let receiverSymbol = sema.symbols.symbol(receiver.classSymbol)
                    else {
                        Issue.record("Expected Collection.firstOrNull to have a class receiver")
                        continue
                    }
                    #expect(
                        receiverSymbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "Iterable"],
                        "Expected Collection.firstOrNull receiver to be kotlin.collections.Iterable"
                    )
                    #expect(
                        sema.bindings.exprTypes[callExpr] == nullableIntType,
                        "Expected Collection.firstOrNull to return Int?"
                    )
                } else if memberName == "lastOrNull" {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected Collection.lastOrNull to bind to the Iterable source extension"
                    )
                    #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                    let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                    let receiverType = try #require(signature.receiverType)
                    guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
                        Issue.record("Expected Collection.lastOrNull to bind to an Iterable receiver")
                        continue
                    }
                    let iterableSymbol = try #require(sema.symbols.lookup(fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("collections"),
                        ctx.interner.intern("Iterable"),
                    ]))
                    #expect(receiverClassType.classSymbol == iterableSymbol)
                } else {
                    #expect(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee == nil,
                        "Expected Collection.\(memberName) to remain unresolved"
                    )
                }
            }

            #expect(!(ctx.diagnostics.diagnostics.isEmpty), "Expected diagnostics for Collection indexed lookup fallbacks")
        }
    }

    @Test
    func testCollectionLastInfersElementType() throws {
        let source = """
        fun lastValue(values: Collection<Int>): Int = values.last()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                guard ctx.interner.resolve(callee) == "last" else { return false }
                // KSP-483: bundled Stdlib/kotlin/io/Files.kt also calls
                // List<String>.last() internally; exclude bundled call sites
                // so this finds the user's Collection<Int>.last() call.
                return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            })
            let type = try #require(sema.bindings.exprType(for: callExpr))
            #expect(sema.types.kind(of: type) == .primitive(.int, .nonNull))
        }
    }

    @Test
    func testPrimitiveIteratorSurfacesAreRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let iteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Iterator")]))
            let specs: [(className: String, nextName: String, elementType: TypeID)] = [
                ("BooleanIterator", "nextBoolean", sema.types.booleanType),
                ("ByteIterator", "nextByte", sema.types.byteType),
                ("ShortIterator", "nextShort", sema.types.shortType),
                ("IntIterator", "nextInt", sema.types.intType),
                ("LongIterator", "nextLong", sema.types.longType),
                ("FloatIterator", "nextFloat", sema.types.floatType),
                ("DoubleIterator", "nextDouble", sema.types.doubleType),
                ("CharIterator", "nextChar", sema.types.charType),
            ]

            for spec in specs {
                let classFQName = collectionsPkg + [ctx.interner.intern(spec.className)]
                let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
                let classInfo = try #require(sema.symbols.symbol(classSymbol))
                // KSP-664: the primitive iterator shells are source-backed Kotlin
                // declarations (PrimitiveIterators.kt), not synthetic stubs.
                #expect(classInfo.kind == .class)
                #expect(!classInfo.flags.contains(.synthetic))
                #expect(classInfo.flags.contains(.abstractType))
                #expect(sema.symbols.directSupertypes(for: classSymbol).contains(iteratorSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: classSymbol, supertype: iteratorSymbol) == [.invariant(spec.elementType)])

                let primitiveNextSymbol = try #require(sema.symbols.lookup(fqName: classFQName + [ctx.interner.intern(spec.nextName)]))
                let primitiveNextInfo = try #require(sema.symbols.symbol(primitiveNextSymbol))
                #expect(!primitiveNextInfo.flags.contains(.synthetic))
                #expect(primitiveNextInfo.flags.contains(.abstractType))
                let primitiveNextSignature = try #require(sema.symbols.functionSignature(for: primitiveNextSymbol))
                #expect(primitiveNextSignature.parameterTypes.isEmpty)
                #expect(primitiveNextSignature.returnType == spec.elementType)

                let nextSymbol = try #require(sema.symbols.lookup(fqName: classFQName + [ctx.interner.intern("next")]))
                let nextInfo = try #require(sema.symbols.symbol(nextSymbol))
                #expect(!nextInfo.flags.contains(.synthetic))
                #expect(nextInfo.flags.contains(.overrideMember))
                #expect(try #require(sema.symbols.functionSignature(for: nextSymbol)).returnType == spec.elementType)
            }
        }
    }

    @Test
    func testPrimitiveIteratorSubclassResolvesAsIterator() throws {
        let source = """
        import kotlin.collections.IntIterator
        import kotlin.collections.Iterator

        class ProbeIntIterator : IntIterator() {
            override fun hasNext(): Boolean = false
            override fun nextInt(): Int = 42
        }

        fun accept(iterator: Iterator<Int>) {}

        fun probe(iterator: ProbeIntIterator): Int {
            accept(iterator)
            return iterator.nextInt() + iterator.next()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected primitive iterator subclass surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractIteratorSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let abstractIteratorFQName = ["kotlin", "collections", "AbstractIterator"]
                .map { ctx.interner.intern($0) }
            let abstractIteratorSymbol = try #require(sema.symbols.lookup(fqName: abstractIteratorFQName))
            let abstractIteratorInfo = try #require(sema.symbols.symbol(abstractIteratorSymbol))
            // KSP-664: AbstractIterator is a source-backed Kotlin declaration
            // (AbstractIterator.kt), not a synthetic stub.
            #expect(abstractIteratorInfo.kind == .class)
            #expect(!abstractIteratorInfo.flags.contains(.synthetic))
            #expect(abstractIteratorInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractIteratorSymbol) == [.invariant])

            let iteratorSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "Iterator"].map { ctx.interner.intern($0) }))
            #expect(sema.symbols.directSupertypes(for: abstractIteratorSymbol).contains(iteratorSymbol))
            #expect(sema.types.directNominalSupertypes(for: abstractIteratorSymbol).contains(iteratorSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractIteratorSymbol, supertype: iteratorSymbol).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractIteratorSymbol, supertype: iteratorSymbol).count == 1)

            // Source-backed members carry no `.synthetic` flag; abstract/override
            // shape comes from the Kotlin modifiers in AbstractIterator.kt.
            let expectedMembers: [(name: String, visibility: Visibility, requiredFlags: SymbolFlags, parameterCount: Int)] = [
                ("computeNext", .protected, [.abstractType], 0),
                ("done", .protected, [], 0),
                ("setNext", .protected, [], 1),
                ("hasNext", .public, [.overrideMember], 0),
                ("next", .public, [.overrideMember], 0),
            ]
            for expected in expectedMembers {
                let memberSymbol = try #require(sema.symbols.lookup(fqName: abstractIteratorFQName + [ctx.interner.intern(expected.name)]))
                let memberInfo = try #require(sema.symbols.symbol(memberSymbol))
                #expect(memberInfo.visibility == expected.visibility)
                #expect(!memberInfo.flags.contains(.synthetic))
                #expect(memberInfo.flags.isSuperset(of: expected.requiredFlags))
                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                #expect(signature.parameterTypes.count == expected.parameterCount)
            }
        }
    }

    @Test
    func testAbstractIteratorSubclassProtectedMembersResolve() throws {
        let source = """
        import kotlin.collections.AbstractIterator
        import kotlin.collections.Iterator

        class OneShotIterator(private val value: Int) : AbstractIterator<Int>() {
            override fun computeNext() {
                setNext(value)
                done()
            }
        }

        fun accept(iterator: Iterator<Int>) {}

        fun probe(iterator: OneShotIterator) {
            accept(iterator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractIterator subclass surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractCollectionSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let abstractCollectionFQName = ["kotlin", "collections", "AbstractCollection"]
                .map { ctx.interner.intern($0) }
            let abstractCollectionSymbol = try #require(sema.symbols.lookup(fqName: abstractCollectionFQName))
            let abstractCollectionInfo = try #require(sema.symbols.symbol(abstractCollectionSymbol))
            #expect(abstractCollectionInfo.kind == .class)
            // KSP-633: `kotlin.collections.AbstractCollection` is source-backed by
            // `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractCollection.kt`. The
            // source declaration reuses the synthetic shell symbol on bundle load and
            // clears the `.synthetic` flag.
            #expect(!abstractCollectionInfo.flags.contains(.synthetic))
            #expect(abstractCollectionInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractCollectionSymbol) == [.out])

            let collectionSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "Collection"].map { ctx.interner.intern($0) }))
            #expect(sema.symbols.directSupertypes(for: abstractCollectionSymbol).contains(collectionSymbol))
            #expect(sema.types.directNominalSupertypes(for: abstractCollectionSymbol).contains(collectionSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractCollectionSymbol, supertype: collectionSymbol).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractCollectionSymbol, supertype: collectionSymbol).count == 1)

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractCollectionFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .protected)
            let signature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
            #expect(signature.parameterTypes.isEmpty)
        }
    }

    @Test
    func testCollectionInterfaceIsSourceBackedWithNativeSurface() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()
            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let collectionFQName = collectionsPkg + [ctx.interner.intern("Collection")]
            let collectionSymbol = try #require(sema.symbols.lookup(fqName: collectionFQName))
            let collectionInfo = try #require(sema.symbols.symbol(collectionSymbol))

            #expect(collectionInfo.kind == .interface)
            #expect(!collectionInfo.flags.contains(.synthetic))
            #expect(sema.types.nominalTypeParameterVariances(for: collectionSymbol) == [.out])
            let collectionFileID = try #require(sema.symbols.sourceFileID(for: collectionSymbol))
            #expect(ctx.sourceManager.path(of: collectionFileID) == "__bundled_kotlin/collections/AbstractCollection.kt")

            let iterableSymbol = try #require(sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("Iterable")]
            ))
            #expect(sema.symbols.directSupertypes(for: collectionSymbol).contains(iterableSymbol))
            #expect(sema.types.directNominalSupertypes(for: collectionSymbol).contains(iterableSymbol))

            let expectedExternalLinks: [String: String?] = [
                "size": "__kk_collection_size",
                "isEmpty": "__kk_collection_isEmpty",
                "contains": "kk_op_contains",
                "iterator": "kk_list_iterator",
                "containsAll": "__kk_collection_containsAll",
            ]
            for (memberName, expectedExternalLink) in expectedExternalLinks {
                let memberFQName = collectionFQName + [ctx.interner.intern(memberName)]
                let members = sema.symbols.lookupAll(fqName: memberFQName).filter {
                    sema.symbols.parentSymbol(for: $0) == collectionSymbol
                }
                #expect(members.count == 1, "Expected one source-backed Collection.(memberName) member")
                let member = try #require(members.first)
                let memberInfo = try #require(sema.symbols.symbol(member))
                #expect(!memberInfo.flags.contains(.synthetic))
                #expect(memberInfo.declSite != nil)
                let memberFileID = try #require(sema.symbols.sourceFileID(for: member))
                #expect(ctx.sourceManager.path(of: memberFileID) == "__bundled_kotlin/collections/AbstractCollection.kt")
                #expect(sema.symbols.externalLinkName(for: member) == expectedExternalLink)
            }

            let iteratorSymbol = try #require(sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("Iterator")]
            ))
            for (memberName, expectedExternalLink) in [("hasNext", "kk_iterator_hasNext"), ("next", "kk_iterator_next")] {
                let memberFQName = collectionsPkg + [ctx.interner.intern("Iterator"), ctx.interner.intern(memberName)]
                let member = try #require(sema.symbols.lookupAll(fqName: memberFQName).first {
                    sema.symbols.parentSymbol(for: $0) == iteratorSymbol
                })
                #expect(sema.symbols.externalLinkName(for: member) == expectedExternalLink)
            }
        }
    }

    @Test
    func testSourceBackedCollectionMembersTypeCheckThroughCollectionReceiver() throws {
        let source = """
        import kotlin.collections.Collection

        fun inspect(values: Collection<Int>, other: Collection<Int>): Boolean {
            val size = values.size
            val empty = values.isEmpty()
            val member = values.contains(2)
            val all = values.containsAll(other)
            val iterator = values.iterator()
            return size >= 0 && (empty || member || all || iterator.hasNext())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected Collection members to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func testAbstractCollectionCanBeUsedAsCollectionSupertype() throws {
        let source = """
        import kotlin.collections.AbstractCollection
        import kotlin.collections.Collection

        abstract class ProbeCollection : AbstractCollection<Int>()

        fun accept(values: Collection<Int>) {}

        fun probe(values: ProbeCollection) {
            accept(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractCollection subclass surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    /// KSP-633: the source-backed skeletal classes declare `size` / `iterator` / `add` as
    /// abstract members, so a concrete subclass overriding them has to type-check.
    @Test
    func testSourceBackedAbstractCollectionsAllowConcreteSubclasses() throws {
        let source = """
        import kotlin.collections.AbstractCollection
        import kotlin.collections.AbstractMutableCollection
        import kotlin.collections.Collection
        import kotlin.collections.Iterator
        import kotlin.collections.MutableCollection
        import kotlin.collections.MutableIterable
        import kotlin.collections.MutableIterator

        class EvenNumbers(private val limit: Int) : AbstractCollection<Int>() {
            override val size: Int
                get() = (limit + 1) / 2

            override fun iterator(): Iterator<Int> = ArrayList<Int>().iterator()
        }

        class EmptyIntIterator : MutableIterator<Int> {
            override fun hasNext(): Boolean = false

            override fun next(): Int = 0

            override fun remove() {}
        }

        class IntBag : AbstractMutableCollection<Int>() {
            private val items = ArrayList<Int>()

            override val size: Int
                get() = items.size

            override fun add(element: Int): Boolean = items.add(element)

            override fun iterator(): MutableIterator<Int> = EmptyIntIterator()
        }

        class Countdown : MutableIterable<Int> {
            override fun iterator(): MutableIterator<Int> = EmptyIntIterator()
        }

        fun acceptReadonly(values: Collection<Int>) {}
        fun acceptMutable(values: MutableCollection<Int>) {}
        fun acceptIterable(values: MutableIterable<Int>) {}

        fun probe(numbers: EvenNumbers, bag: IntBag, countdown: Countdown) {
            acceptReadonly(numbers)
            acceptMutable(bag)
            acceptIterable(countdown)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected concrete subclasses of the source-backed skeletal collections to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractCollectionProvidesConcreteCollectionDefaults() throws {
        let source = """
        import kotlin.collections.AbstractCollection
        import kotlin.collections.Collection
        import kotlin.collections.Iterator

        class IntBag : AbstractCollection<Int>() {
            override val size: Int
                get() = 0

            override fun iterator(): Iterator<Int> = ArrayList<Int>().iterator()
        }

        fun probe(values: IntBag): Boolean {
            val collection: Collection<Int> = values
            return collection.isEmpty() || collection.contains(1) || collection.containsAll(collection)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractCollection defaults to satisfy Collection members: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractListSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let abstractCollectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("AbstractCollection")]))
            let listSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("List")]))

            let abstractListFQName = collectionsPkg + [ctx.interner.intern("AbstractList")]
            let abstractListSymbol = try #require(sema.symbols.lookup(fqName: abstractListFQName))
            let abstractListInfo = try #require(sema.symbols.symbol(abstractListSymbol))
            #expect(abstractListInfo.kind == .class)
            // KSP-697: AbstractList is now a bundled Kotlin declaration. Its
            // indexed members remain compiler residuals, but the nominal class
            // itself must retain the source declaration and location.
            #expect(!abstractListInfo.flags.contains(.synthetic))
            #expect(abstractListInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractListSymbol) == [.out])

            let abstractListFileID = try #require(sema.symbols.sourceFileID(for: abstractListSymbol))
            #expect(ctx.sourceManager.path(of: abstractListFileID) == "__bundled_kotlin/collections/AbstractList.kt")

            let directSupertypes = sema.symbols.directSupertypes(for: abstractListSymbol)
            #expect(directSupertypes.contains(abstractCollectionSymbol))
            #expect(directSupertypes.contains(listSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractListSymbol, supertype: abstractCollectionSymbol).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: abstractListSymbol, supertype: listSymbol).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractListSymbol, supertype: abstractCollectionSymbol).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractListSymbol, supertype: listSymbol).count == 1)

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractListFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testKSP697CollectionShellsAreSourceBackedWithoutDuplicateNominals() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let expected: [(packagePath: [String], name: String, variances: [TypeVariance], sourcePath: String)] = [
                (["kotlin"], "Comparable", [.in], "__bundled_kotlin/Comparable.kt"),
                (["kotlin", "collections"], "Iterable", [.out], "__bundled_kotlin/collections/Iterable.kt"),
                (["kotlin", "collections"], "Collection", [.out], "__bundled_kotlin/collections/AbstractCollection.kt"),
                (["kotlin", "collections"], "List", [.out], "__bundled_kotlin/collections/List.kt"),
                (["kotlin", "collections"], "MutableCollection", [.invariant], "__bundled_kotlin/collections/MutableCollection.kt"),
                (["kotlin", "collections"], "AbstractList", [.out], "__bundled_kotlin/collections/AbstractList.kt"),
            ]

            for item in expected {
                let fqName = (item.packagePath + [item.name]).map { ctx.interner.intern($0) }
                let candidates = sema.symbols.lookupAll(fqName: fqName)
                #expect(candidates.count == 1, "Expected one nominal symbol for \(item.packagePath.joined(separator: ".")).\(item.name), got \(candidates.count)")
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                let info = try #require(sema.symbols.symbol(symbol))
                #expect(!info.flags.contains(.synthetic))
                #expect(sema.types.nominalTypeParameterVariances(for: symbol) == item.variances)
                let fileID = try #require(sema.symbols.sourceFileID(for: symbol))
                #expect(ctx.sourceManager.path(of: fileID) == item.sourcePath)
            }

            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            func symbol(_ name: String) throws -> SymbolID {
                try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern(name)]))
            }

            let iterable = try symbol("Iterable")
            let collection = try symbol("Collection")
            let list = try symbol("List")
            let mutableIterable = try symbol("MutableIterable")
            let mutableCollection = try symbol("MutableCollection")
            #expect(sema.symbols.directSupertypes(for: collection).contains(iterable))
            #expect(sema.symbols.directSupertypes(for: list).contains(collection))
            #expect(sema.symbols.directSupertypes(for: mutableCollection).contains(collection))
            #expect(sema.symbols.directSupertypes(for: mutableCollection).contains(mutableIterable))
            #expect(sema.symbols.supertypeTypeArgs(for: collection, supertype: iterable).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: list, supertype: collection).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: mutableCollection, supertype: collection).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: mutableCollection, supertype: mutableIterable).count == 1)
        }
    }

    @Test
    func testKSP697CollectionShellsSupportCustomImplementationsAndResidualDispatch() throws {
        let source = """
        class CustomIterable(private val value: Int) : Iterable<Int> {
            override fun iterator(): Iterator<Int> = listOf(value).iterator()
        }

        class CustomList(private val value: Int) : AbstractList<Int>() {
            override val size: Int get() = 1
            override fun get(index: Int): Int = value
            override fun iterator(): Iterator<Int> = listOf(value).iterator()
        }

        fun probe(values: List<Int>): Int {
            val custom = CustomList(values[0])
            return custom[0] + custom.iterator().next() + CustomIterable(1).iterator().next()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected source-backed collection shells and residual indexing/iterator members to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testSourceBackedAbstractMutableListSurfaceAndSubclassTypes() throws {
        let source = """
        import kotlin.collections.AbstractMutableList
        import kotlin.collections.List
        import kotlin.collections.MutableList
        import kotlin.collections.MutableIterator

        class ProbeIterator : MutableIterator<Int> {
            override fun hasNext(): Boolean = false
            override fun next(): Int = 0
            override fun remove() {}
        }

        class Probe : AbstractMutableList<Int>() {
            override val size: Int
                get() = 0

            override fun get(index: Int): Int = 0
            override fun set(index: Int, element: Int): Int = 0
            override fun add(index: Int, element: Int) {}
            override fun removeAt(index: Int): Int = 0
            override fun iterator(): MutableIterator<Int> = ProbeIterator()
        }

        fun acceptList(values: List<Int>) {}
        fun acceptMutableList(values: MutableList<Int>) {}

        fun probe(values: Probe) {
            val asList: List<Int> = values
            val asMutable: MutableList<Int> = values
            acceptList(asList)
            acceptMutableList(asMutable)
            values.add(0, 1)
            values.set(0, 2)
            values.removeAt(0)
            values.iterator()
            asList.subList(0, 0)
            asMutable.listIterator()
            asMutable.subList(0, 0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let diagnosticMessages = ctx.diagnostics.diagnostics.map { $0.message }
            #expect(!(ctx.diagnostics.hasError), "Expected AbstractMutableList subclass surface to resolve: \(diagnosticMessages)")

            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let abstractMutableListFQName = collectionsPkg + [ctx.interner.intern("AbstractMutableList")]
            let abstractMutableListSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableListFQName))
            let info = try #require(sema.symbols.symbol(abstractMutableListSymbol))
            #expect(info.kind == .class)
            #expect(!info.flags.contains(.synthetic))
            #expect(info.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractMutableListSymbol) == [.invariant])

            let abstractMutableCollectionSymbol = try #require(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("AbstractMutableCollection")])
            )
            let mutableListSymbol = try #require(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableList")])
            )
            #expect(sema.symbols.directSupertypes(for: abstractMutableListSymbol).contains(abstractMutableCollectionSymbol))
            #expect(sema.symbols.directSupertypes(for: abstractMutableListSymbol).contains(mutableListSymbol))
            #expect(sema.types.directNominalSupertypes(for: abstractMutableListSymbol).contains(abstractMutableCollectionSymbol))
            #expect(sema.types.directNominalSupertypes(for: abstractMutableListSymbol).contains(mutableListSymbol))

            let constructorSymbol = try #require(
                sema.symbols.lookup(fqName: abstractMutableListFQName + [ctx.interner.intern("<init>")])
            )
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testAbstractSetSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let collectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Collection")]))
            let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Set")]))

            let abstractSetFQName = collectionsPkg + [ctx.interner.intern("AbstractSet")]
            let abstractSetSymbol = try #require(sema.symbols.lookup(fqName: abstractSetFQName))
            let abstractSetInfo = try #require(sema.symbols.symbol(abstractSetSymbol))
            #expect(abstractSetInfo.kind == .class)
            // KSP-932: the nominal declaration now comes from the bundled
            // `Stdlib/kotlin/collections/AbstractSet.kt` source. The
            // compiler-side shell remains only as the no-stdlib fallback.
            #expect(!abstractSetInfo.flags.contains(.synthetic))
            #expect(abstractSetInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractSetSymbol) == [.out])

            let abstractCollectionSymbol = sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("AbstractCollection")]
            )
            let collectionSupertype = abstractCollectionSymbol ?? collectionSymbol
            let directSupertypes = sema.symbols.directSupertypes(for: abstractSetSymbol)
            #expect(directSupertypes.contains(collectionSupertype))
            #expect(directSupertypes.contains(setSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractSetSymbol, supertype: collectionSupertype).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: abstractSetSymbol, supertype: setSymbol).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractSetSymbol, supertype: collectionSupertype).count == 1)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractSetSymbol, supertype: setSymbol).count == 1)

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractSetFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testSourceBackedAbstractSetUsesInheritedAbstractContract() throws {
        let source = """
        import kotlin.collections.AbstractSet

        abstract class ProbeSet : AbstractSet<Int>()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let abstractSetName = ctx.interner.intern("AbstractSet")
            let abstractSetFQName = collectionsPkg + [abstractSetName]
            let abstractSetSymbol = try #require(sema.symbols.lookup(fqName: abstractSetFQName))
            let abstractSetInfo = try #require(sema.symbols.symbol(abstractSetSymbol))
            let abstractCollectionName = ctx.interner.intern("AbstractCollection")
            let abstractCollectionFQName = collectionsPkg + [abstractCollectionName]
            let abstractCollectionSymbol = try #require(sema.symbols.lookup(fqName: abstractCollectionFQName))

            // The bundled AbstractSet source has no direct abstract member;
            // its abstract size/iterator contract is inherited from
            // AbstractCollection, matching Kotlin's stdlib hierarchy.
            #expect(!abstractSetInfo.flags.contains(.synthetic))
            #expect(sema.symbols.directSupertypes(for: abstractSetSymbol).contains(abstractCollectionSymbol))
            let inheritedAbstractNames = sema.symbols.children(ofFQName: abstractCollectionFQName)
                .compactMap { sema.symbols.symbol($0) }
                .filter { symbol in
                    (symbol.kind == .function || symbol.kind == .property) && symbol.flags.contains(.abstractType)
                }
                .map { ctx.interner.resolve($0.name) }
            #expect(inheritedAbstractNames.contains("size"))
            #expect(inheritedAbstractNames.contains("iterator"))

            let falsePositiveWarnings = ctx.diagnostics.diagnostics.filter { diagnostic in
                diagnostic.code == "KSWIFTK-SEMA-ABSTRACT" &&
                    (diagnostic.message.contains("kotlin.collections.AbstractSet") ||
                        diagnostic.message.contains("ProbeSet"))
            }
            #expect(
                falsePositiveWarnings.isEmpty,
                "AbstractSet's inherited abstract contract must not produce an empty-abstract-class warning for AbstractSet or its minimal subclass: \(falsePositiveWarnings)"
            )
        }
    }

    @Test
    func testAbstractListCanBeUsedAsListSupertype() throws {
        let source = """
        import kotlin.collections.AbstractList
        import kotlin.collections.Collection
        import kotlin.collections.List

        abstract class ProbeList : AbstractList<Int>()

        fun acceptCollection(values: Collection<Int>) {}
        fun acceptList(values: List<Int>) {}

        fun probe(values: ProbeList) {
            acceptCollection(values)
            acceptList(values)
            values[0]
            values.listIterator()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractList subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractSetCanBeUsedAsCollectionAndSetSupertype() throws {
        let source = """
        import kotlin.collections.AbstractSet
        import kotlin.collections.Collection
        import kotlin.collections.Set

        abstract class ProbeSet : AbstractSet<Int>()

        fun acceptCollection(values: Collection<Int>) {}
        fun acceptSet(values: Set<Int>) {}

        fun probe(values: ProbeSet) {
            acceptCollection(values)
            acceptSet(values)
            values.contains(1)
            values.isEmpty()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractSet subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testRandomAccessMarkerInterfaceSurfaceIsRegistered() throws {
        let source = """
        import kotlin.collections.RandomAccess

        class IndexedBag : RandomAccess

        fun keepRandomAccess(marker: RandomAccess): RandomAccess {
            return marker
        }

        fun probe(value: IndexedBag): RandomAccess {
            return keepRandomAccess(value)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected RandomAccess marker interface surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let sema = try #require(ctx.sema)
            let randomAccessFQName = ["kotlin", "collections", "RandomAccess"]
                .map { ctx.interner.intern($0) }
            let randomAccessSymbol = try #require(sema.symbols.lookup(fqName: randomAccessFQName))
            let randomAccessInfo = try #require(sema.symbols.symbol(randomAccessSymbol))
            #expect(randomAccessInfo.kind == .interface)
            // KSP-669: `kotlin.collections.RandomAccess` is source-backed by
            // `Sources/CompilerCore/Stdlib/kotlin/collections/RandomAccess.kt`. When the
            // bundled stdlib is loaded the source declaration reuses the synthetic shell
            // symbol and clears the `.synthetic` flag, so the registered marker interface
            // is no longer synthetic.
            #expect(!randomAccessInfo.flags.contains(.synthetic))
            #expect(sema.types.nominalTypeParameterSymbols(for: randomAccessSymbol).isEmpty)
        }
    }

    @Test
    func testAbstractMutableCollectionSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let collectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Collection")]))
            let mutableCollectionFQName = collectionsPkg + [ctx.interner.intern("MutableCollection")]
            let mutableCollectionSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName))
            #expect(sema.types.nominalTypeParameterVariances(for: mutableCollectionSymbol) == [.invariant])
            #expect(sema.symbols.directSupertypes(for: mutableCollectionSymbol).contains(collectionSymbol))
            #expect(sema.types.directNominalSupertypes(for: mutableCollectionSymbol).contains(collectionSymbol))

            let expectedMutableMembers: [(name: String, parameterCount: Int)] = [
                ("add", 1),
                ("addAll", 1),
                ("clear", 0),
                ("remove", 1),
                ("removeAll", 1),
                ("retainAll", 1),
            ]
            for expected in expectedMutableMembers {
                let memberSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName + [ctx.interner.intern(expected.name)]))
                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                #expect(signature.parameterTypes.count == expected.parameterCount)
            }

            let addSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName + [ctx.interner.intern("add")]))
            #expect(sema.symbols.externalLinkName(for: addSymbol) == "__kk_mutable_collection_add")
            let addAllSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName + [ctx.interner.intern("addAll")]))
            #expect(sema.symbols.externalLinkName(for: addAllSymbol) == "__kk_mutable_collection_addAll")

            let abstractMutableCollectionFQName = collectionsPkg + [ctx.interner.intern("AbstractMutableCollection")]
            let abstractMutableCollectionSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableCollectionFQName))
            let abstractMutableCollectionInfo = try #require(sema.symbols.symbol(abstractMutableCollectionSymbol))
            #expect(abstractMutableCollectionInfo.kind == .class)
            // KSP-633: `kotlin.collections.AbstractMutableCollection` is source-backed by
            // `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMutableCollection.kt`.
            #expect(!abstractMutableCollectionInfo.flags.contains(.synthetic))
            #expect(abstractMutableCollectionInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractMutableCollectionSymbol) == [.invariant])

            let abstractCollectionSymbol = sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("AbstractCollection")]
            )
            let readonlySupertype = abstractCollectionSymbol ?? collectionSymbol
            let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableCollectionSymbol)
            #expect(directSupertypes.contains(readonlySupertype))
            #expect(directSupertypes.contains(mutableCollectionSymbol))
            #expect(sema.symbols.supertypeTypeArgs(
                    for: abstractMutableCollectionSymbol,
                    supertype: readonlySupertype
                ).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(
                    for: abstractMutableCollectionSymbol,
                    supertype: mutableCollectionSymbol
                ).count == 1)

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableCollectionFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testAbstractMutableCollectionCanBeUsedAsMutableCollectionSupertype() throws {
        let source = """
        import kotlin.collections.AbstractMutableCollection
        import kotlin.collections.Collection
        import kotlin.collections.MutableCollection

        abstract class ProbeMutableCollection : AbstractMutableCollection<Int>()

        fun acceptReadonly(values: Collection<Int>) {}
        fun acceptMutable(values: MutableCollection<Int>) {}

        fun probe(values: ProbeMutableCollection) {
            acceptReadonly(values)
            acceptMutable(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractMutableCollection subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractMapSurfaceIsSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()
            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let mapSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Map")]))
            let abstractMapFQName = collectionsPkg + [ctx.interner.intern("AbstractMap")]
            let abstractMapSymbol = try #require(sema.symbols.lookup(fqName: abstractMapFQName))
            let abstractMapInfo = try #require(sema.symbols.symbol(abstractMapSymbol))

            #expect(abstractMapInfo.kind == .class)
            #expect(!abstractMapInfo.flags.contains(.synthetic))
            #expect(abstractMapInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractMapSymbol) == [.invariant, .out])
            #expect(sema.symbols.directSupertypes(for: abstractMapSymbol).contains(mapSymbol))
            #expect(sema.types.directNominalSupertypes(for: abstractMapSymbol).contains(mapSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractMapSymbol, supertype: mapSymbol).count == 2)
            #expect(sema.types.nominalSupertypeTypeArgs(for: abstractMapSymbol, supertype: mapSymbol).count == 2)

            let constructorSymbol = try #require(
                sema.symbols.lookup(fqName: abstractMapFQName + [ctx.interner.intern("<init>")])
            )
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testAbstractMapConcreteSubclassCanBeUsedAsMap() throws {
        let source = """
        import kotlin.collections.AbstractMap
        import kotlin.collections.Map
        import kotlin.collections.Set

        class ProbeMap : AbstractMap<String, Int>() {
            override val entries: Set<Map.Entry<String, Int>>
                get() = emptyMap<String, Int>().entries
        }

        fun accept(values: Map<String, Int>) {}

        fun probe(values: ProbeMap) {
            accept(values)
            values["missing"]
            values.containsKey("missing")
            values.containsValue(1)
            values.entries
            values.keys
            values.values
            values.isEmpty()
            values.hashCode()
            values.toString()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !(ctx.diagnostics.hasError),
                "Expected source-backed AbstractMap subclass surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    /// `MutableSet<E> : Set<E>, MutableCollection<E>`; without the
    /// MutableCollection supertype a `MutableSet` argument was rejected for a
    /// `MutableCollection` parameter (KSWIFTK-SEMA-0002).
    @Test
    func testMutableSetIsAssignableToMutableCollectionParameter() throws {
        let source = """
        fun mutate(values: MutableCollection<Int>): Boolean = values.add(1)

        fun run(): Boolean = mutate(mutableSetOf(1, 2))
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let mutableSetSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableSet")]))
            let mutableCollectionSymbol = try #require(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableCollection")])
            )

            #expect(sema.symbols.directSupertypes(for: mutableSetSymbol).contains(mutableCollectionSymbol))
            #expect(
                sema.symbols.supertypeTypeArgs(for: mutableSetSymbol, supertype: mutableCollectionSymbol).count == 1
            )
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected MutableSet to satisfy a MutableCollection parameter: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    @Test
    func testAbstractMutableSetSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let mutableSetSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableSet")]))
            let abstractMutableSetFQName = collectionsPkg + [ctx.interner.intern("AbstractMutableSet")]
            let abstractMutableSetSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableSetFQName))
            let abstractMutableSetInfo = try #require(sema.symbols.symbol(abstractMutableSetSymbol))
            #expect(abstractMutableSetInfo.kind == .class)
            #expect(!abstractMutableSetInfo.flags.contains(.synthetic))
            #expect(abstractMutableSetInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractMutableSetSymbol) == [.invariant])
            #expect(sema.symbols.lookupAll(fqName: abstractMutableSetFQName).count == 1)
            let sourceFileID = try #require(sema.symbols.sourceFileID(for: abstractMutableSetSymbol))
            #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/collections/AbstractMutableSet.kt")

            let abstractMutableCollectionSymbol = try #require(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("AbstractMutableCollection")])
            )
            let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableSetSymbol)
            #expect(directSupertypes.contains(abstractMutableCollectionSymbol))
            #expect(directSupertypes.contains(mutableSetSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableSetSymbol, supertype: abstractMutableCollectionSymbol).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableSetSymbol, supertype: mutableSetSymbol).count == 1)

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableSetFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testAbstractMutableMapSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let mapSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Map")]))
            let mutableMapSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableMap")]))
            let abstractMutableMapFQName = collectionsPkg + [ctx.interner.intern("AbstractMutableMap")]
            let abstractMutableMapSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableMapFQName))
            let abstractMutableMapInfo = try #require(sema.symbols.symbol(abstractMutableMapSymbol))
            #expect(abstractMutableMapInfo.kind == .class)
            #expect(!abstractMutableMapInfo.flags.contains(.synthetic))
            #expect(abstractMutableMapInfo.flags.contains(.abstractType))
            #expect(sema.types.nominalTypeParameterVariances(for: abstractMutableMapSymbol) == [.invariant, .invariant])

            let abstractMapSymbol = sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("AbstractMap")]
            )
            let readonlySupertype = abstractMapSymbol ?? mapSymbol
            let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableMapSymbol)
            #expect(directSupertypes.contains(readonlySupertype))
            #expect(directSupertypes.contains(mutableMapSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableMapSymbol, supertype: readonlySupertype).count == 2)
            #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableMapSymbol, supertype: mutableMapSymbol).count == 2)

            let mutableEntryFQName = collectionsPkg + [
                ctx.interner.intern("MutableMap"),
                ctx.interner.intern("MutableEntry"),
            ]
            let mutableEntrySymbol = try #require(sema.symbols.lookup(fqName: mutableEntryFQName))
            let mapEntrySymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [
                ctx.interner.intern("Map"),
                ctx.interner.intern("Entry"),
            ]))
            #expect(sema.symbols.directSupertypes(for: mutableEntrySymbol).contains(mapEntrySymbol))

            let putSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableMapFQName + [ctx.interner.intern("put")]))
            let putInfo = try #require(sema.symbols.symbol(putSymbol))
            #expect(putInfo.kind == .function)
            #expect(putInfo.flags.contains(.abstractType))
            #expect(try #require(sema.symbols.functionSignature(for: putSymbol)).parameterTypes.count == 2)
            let entriesSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableMapFQName + [ctx.interner.intern("entries")]))
            let entriesInfo = try #require(sema.symbols.symbol(entriesSymbol))
            #expect(entriesInfo.kind == .property)
            #expect(entriesInfo.flags.contains(.abstractType))

            let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableMapFQName + [ctx.interner.intern("<init>")]))
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            #expect(constructorInfo.kind == .constructor)
            #expect(constructorInfo.visibility == .protected)
            #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    @Test
    func testAbstractMutableSetCanBeUsedAsSetAndMutableSetSupertype() throws {
        let source = """
        import kotlin.collections.AbstractMutableSet
        import kotlin.collections.Set
        import kotlin.collections.MutableSet

        // KSP-931: `AbstractMutableSet` is source-backed and exposes the
        // `size` / `iterator` / `add` contract for concrete subclasses.
        abstract class ProbeMutableSet : AbstractMutableSet<Int>()

        fun acceptReadonly(values: Set<Int>) {}
        fun acceptMutable(values: MutableSet<Int>) {}

        fun probe(values: ProbeMutableSet) {
            acceptReadonly(values)
            acceptMutable(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractMutableSet subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAbstractMutableMapCanBeUsedAsMapAndMutableMapSupertype() throws {
        let source = """
        import kotlin.collections.AbstractMutableMap
        import kotlin.collections.Map
        import kotlin.collections.MutableMap

        // KSP-928: AbstractMap.entries is source-backed and abstract, so the
        // probe remains abstract while exercising both map supertypes.
        abstract class ProbeMutableMap : AbstractMutableMap<String, Int>()

        fun acceptReadonly(values: Map<String, Int>) {}
        fun acceptMutable(values: MutableMap<String, Int>) {}

        fun probe(values: ProbeMutableMap) {
            acceptReadonly(values)
            acceptMutable(values)
        }

        fun inheritedMapSurface(values: ProbeMutableMap, missing: String): Int? {
            val readonly: Map<String, Int> = values
            val mutable: MutableMap<String, Int> = values
            val missingValue = readonly[missing]
            mutable.putAll(emptyMap<String, Int>())
            mutable.put(missing, 1)
            mutable.remove(missing)
            val keyView = mutable.keys
            val valueView = mutable.values
            val readonlyEntryView = readonly.entries
            val mutableEntryView = mutable.entries
            values.equals(readonly)
            values.hashCode()
            values.toString()
            keyView.size
            valueView.size
            readonlyEntryView.size
            mutableEntryView.size
            return missingValue
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected AbstractMutableMap subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testMutableListIteratorSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let listIteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("ListIterator")]))
            let mutableIteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableIterator")]))

            let mutableListIteratorFQName = collectionsPkg + [ctx.interner.intern("MutableListIterator")]
            let mutableListIteratorSymbol = try #require(sema.symbols.lookup(fqName: mutableListIteratorFQName))
            let mutableListIteratorInfo = try #require(sema.symbols.symbol(mutableListIteratorSymbol))
            #expect(mutableListIteratorInfo.kind == .interface)
            // KSP-945: the nominal interface is source-backed; mutation members
            // remain compiler residuals until their separate migration lands.
            #expect(!mutableListIteratorInfo.flags.contains(.synthetic))
            #expect(sema.types.nominalTypeParameterVariances(for: mutableListIteratorSymbol) == [.invariant])

            let directSupertypes = sema.symbols.directSupertypes(for: mutableListIteratorSymbol)
            #expect(directSupertypes.contains(listIteratorSymbol))
            #expect(directSupertypes.contains(mutableIteratorSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: mutableListIteratorSymbol, supertype: listIteratorSymbol).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: mutableListIteratorSymbol, supertype: mutableIteratorSymbol).count == 1)

            for memberName in ["add", "set"] {
                let memberSymbol = try #require(sema.symbols.lookup(fqName: mutableListIteratorFQName + [ctx.interner.intern(memberName)]))
                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                #expect(signature.parameterTypes.count == 1)
                #expect(signature.returnType == sema.types.unitType)
            }
            let removeSymbol = try #require(sema.symbols.lookup(fqName: mutableListIteratorFQName + [ctx.interner.intern("remove")]))
            let removeSignature = try #require(sema.symbols.functionSignature(for: removeSymbol))
            #expect(removeSignature.parameterTypes.isEmpty)
            #expect(removeSignature.returnType == sema.types.unitType)

            let mutableListSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableList")]))
            let listIteratorMember = try #require(sema.symbols.lookup(
                    fqName: collectionsPkg + [ctx.interner.intern("MutableList"), ctx.interner.intern("listIterator")]
                ))
            #expect(sema.symbols.parentSymbol(for: listIteratorMember) == mutableListSymbol)
            let listIteratorSignature = try #require(sema.symbols.functionSignature(for: listIteratorMember))
            guard case let .classType(returnType) = sema.types.kind(of: listIteratorSignature.returnType) else {
                Issue.record("MutableList.listIterator should return MutableListIterator<E>")
                return
            }
            #expect(returnType.classSymbol == mutableListIteratorSymbol)
        }
    }

    @Test
    func testMutableIterableSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let iterableSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Iterable")]))
            let iteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Iterator")]))
            let mutableIteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableIterator")]))
            let mutableIteratorInfo = try #require(sema.symbols.symbol(mutableIteratorSymbol))
            // KSP-943: MutableIterator is backed by bundled Kotlin source while
            // the synthetic shell remains available for non-bundled contexts.
            #expect(!mutableIteratorInfo.flags.contains(.synthetic))
            #expect(sema.symbols.sourceFileID(for: mutableIteratorSymbol) == ctx.sourceManager.fileID(forPath: "__bundled_kotlin/collections/MutableIterator.kt"))
            #expect(sema.types.nominalTypeParameterVariances(for: mutableIteratorSymbol) == [.out])
            #expect(sema.symbols.directSupertypes(for: mutableIteratorSymbol).contains(iteratorSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: mutableIteratorSymbol, supertype: iteratorSymbol).count == 1)
            let removeSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableIterator"), ctx.interner.intern("remove")]))
            let removeInfo = try #require(sema.symbols.symbol(removeSymbol))
            #expect(!removeInfo.flags.contains(.synthetic))
            let removeSignature = try #require(sema.symbols.functionSignature(for: removeSymbol))
            #expect(removeSignature.parameterTypes.isEmpty)
            #expect(removeSignature.returnType == sema.types.unitType)

            let mutableIterableFQName = collectionsPkg + [ctx.interner.intern("MutableIterable")]
            let mutableIterableSymbol = try #require(sema.symbols.lookup(fqName: mutableIterableFQName))
            let mutableIterableInfo = try #require(sema.symbols.symbol(mutableIterableSymbol))
            #expect(mutableIterableInfo.kind == .interface)
            // KSP-633: `kotlin.collections.MutableIterable` is source-backed by
            // `Sources/CompilerCore/Stdlib/kotlin/collections/MutableIterable.kt`.
            #expect(!mutableIterableInfo.flags.contains(.synthetic))
            #expect(sema.types.nominalTypeParameterVariances(for: mutableIterableSymbol) == [.out])
            #expect(sema.symbols.directSupertypes(for: mutableIterableSymbol).contains(iterableSymbol))
            #expect(sema.types.directNominalSupertypes(for: mutableIterableSymbol).contains(iterableSymbol))
            #expect(sema.symbols.supertypeTypeArgs(for: mutableIterableSymbol, supertype: iterableSymbol).count == 1)

            let iteratorMember = try #require(sema.symbols.lookup(fqName: mutableIterableFQName + [ctx.interner.intern("iterator")]))
            #expect(try #require(sema.symbols.symbol(iteratorMember)).flags.contains(.operatorFunction))
            let iteratorSignature = try #require(sema.symbols.functionSignature(for: iteratorMember))
            #expect(iteratorSignature.parameterTypes.isEmpty)
            guard case let .classType(iteratorReturnType) = sema.types.kind(of: iteratorSignature.returnType) else {
                Issue.record("MutableIterable.iterator should return MutableIterator<T>")
                return
            }
            #expect(iteratorReturnType.classSymbol == mutableIteratorSymbol)

            for collectionName in ["MutableList", "MutableSet"] {
                let collectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern(collectionName)]))
                #expect(sema.symbols.directSupertypes(for: collectionSymbol).contains(mutableIterableSymbol))
                #expect(sema.types.directNominalSupertypes(for: collectionSymbol).contains(mutableIterableSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: collectionSymbol, supertype: mutableIterableSymbol).count == 1)
            }
        }
    }

    @Test
    func testMutableListIteratorMembersResolveFromMutableList() throws {
        let source = """
        fun probe(values: MutableList<Int>) {
            val iterator = values.listIterator()
            iterator.add(1)
            iterator.set(2)
            iterator.remove()
            iterator.hasPrevious()
            iterator.previous()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected MutableListIterator surface to resolve from MutableList: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testMutableListIteratorTypeParameterIsInvariantForMutation() throws {
        let source = """
        fun acceptAny(iterator: MutableListIterator<Any>) {
            iterator.add(1)
            iterator.set(2)
        }

        fun probe(iterator: MutableListIterator<String>) {
            acceptAny(iterator)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.hasError, "Expected MutableListIterator<String> to remain invariant when mutation consumes T")
        }
    }

    @Test
    func testCustomMutableListIteratorImplementationResolves() throws {
        let source = """
        class ProbeMutableListIterator : MutableListIterator<Int> {
            override fun hasNext(): Boolean = false
            override fun next(): Int = 0
            override fun hasPrevious(): Boolean = false
            override fun previous(): Int = 0
            override fun nextIndex(): Int = 0
            override fun previousIndex(): Int = 0
            override fun add(element: Int) {}
            override fun set(element: Int) {}
            override fun remove() {}
        }

        fun probe(iterator: MutableListIterator<Int>) {
            iterator.add(1)
            iterator.set(2)
            iterator.remove()
            iterator.hasNext()
            iterator.next()
            iterator.hasPrevious()
            iterator.previous()
            iterator.nextIndex()
            iterator.previousIndex()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected custom MutableListIterator implementation to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testMutableIterableSubtypeResolution() throws {
        let source = """
        import kotlin.collections.Iterable
        import kotlin.collections.MutableIterable
        import kotlin.collections.MutableList
        import kotlin.collections.MutableSet

        abstract class ProbeMutableIterable : MutableIterable<Int>

        fun acceptIterable(values: Iterable<Int>) {}
        fun acceptMutableIterable(values: MutableIterable<Int>) {}

        fun probeIterable(values: ProbeMutableIterable) {
            acceptIterable(values)
            acceptMutableIterable(values)
            values.iterator().remove()
        }

        fun probeList(values: MutableList<Int>) {
            acceptMutableIterable(values)
        }

        fun probeSet(values: MutableSet<Int>) {
            acceptMutableIterable(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected MutableIterable subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testSetFallbackRejectsListOnlyIndexedLookups() throws {
        let source = """
        fun firstValue(values: Set<Int>): Int? = values.firstOrNull()
        fun lastValue(values: Set<Int>): Int? = values.lastOrNull()
        fun fallbackValue(values: Set<Int>): Int = values.getOrElse(0) { -1 }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for memberName in ["getOrElse"] {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == nil, "Expected Set.\(memberName) to remain unresolved")
            }

            #expect(!(ctx.diagnostics.diagnostics.isEmpty), "Expected diagnostics for Set indexed lookup fallbacks")
        }
    }

    @Test
    func testCollectionFallbackResolvesTrailingLambdaIndexedLookups() throws {
        let source = """
        fun probe(): Int {
            val list = listOf(1, 2, 3)
            val listValue = list.getOrElse(5) { -1 }
            val map = mapOf("a" to 1, "b" to 2)
            val mapValue = map.getOrElse("z") { 99 }
            val mutableMap = mutableMapOf("a" to 1, "b" to 2)
            val mutableValue = mutableMap.getOrPut("c") { 3 }
            return listValue + mapValue + mutableValue
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0003", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let listCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "getOrElse",
                      let receiverExpr = ast.arena.expr(receiver),
                      case let .nameRef(receiverName, _) = receiverExpr
                else { return false }
                return ctx.interner.resolve(receiverName) == "list"
            })
            let listCallee = try #require(sema.bindings.callBinding(for: listCall)?.chosenCallee)
            let listSymbol = try #require(sema.symbols.symbol(listCallee))
            #expect(sema.symbols.externalLinkName(for: listCallee) == nil)
            #expect(!listSymbol.flags.contains(.synthetic))
            #expect(ctx.interner.resolve(listSymbol.name) == "getOrElse")

            let mapCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "getOrElse",
                      let receiverExpr = ast.arena.expr(receiver),
                      case let .nameRef(receiverName, _) = receiverExpr
                else { return false }
                return ctx.interner.resolve(receiverName) == "map"
            })
            let mapCallee = try #require(sema.bindings.callBinding(for: mapCall)?.chosenCallee)
            let mapSymbol = try #require(sema.symbols.symbol(mapCallee))
            #expect(sema.symbols.externalLinkName(for: mapCallee) == nil)
            #expect(!mapSymbol.flags.contains(.synthetic))
            #expect(ctx.interner.resolve(mapSymbol.name) == "getOrElse")

            let mutableCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "getOrPut",
                      let receiverExpr = ast.arena.expr(receiver),
                      case let .nameRef(receiverName, _) = receiverExpr
                else { return false }
                return ctx.interner.resolve(receiverName) == "mutableMap"
            })
            let mutableCallee = try #require(sema.bindings.callBinding(for: mutableCall)?.chosenCallee)
            let mutableSymbol = try #require(sema.symbols.symbol(mutableCallee))
            #expect(sema.symbols.externalLinkName(for: mutableCallee) == nil)
            #expect(!mutableSymbol.flags.contains(.synthetic))
            #expect(ctx.interner.resolve(mutableSymbol.name) == "getOrPut")
        }
    }

    @Test
    func testMapGetOrElseAssignsLambdaExpectedTypeToLambdaArgument() throws {
        let source = """
        fun useMapDefault(values: Map<String, Int>): Int {
            return values.getOrElse("z") { 99 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "getOrElse"
                })
            #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType, "Expected getOrElse result to be Int")
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected map getOrElse fallback to resolve without diagnostics, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func testListBinarySearchHasComparableElementUpperBound() throws {
        let source = """
        fun render(values: List<Int>) {
            values.binarySearch(5)
            values.binarySearch(5, 1, 4)
            values.binarySearch { it - 5 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let symbolID = try #require(sema.symbols.lookupAll(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("collections"),
                        ctx.interner.intern("binarySearch"),
                    ]
                ).first(where: { sema.symbols.isSourceBackedSymbol($0) }))
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.typeParameterUpperBoundsList == [[]])
            #expect(signature.valueParameterHasDefaultValues == [false, true, true])

            let callExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "binarySearch"
                else {
                    return nil
                }
                return exprID
            }
            #expect(callExprIDs.count == 3)
            for callExprID in callExprIDs {
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExprID)?.chosenCallee)
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
                let chosenSignature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let receiverType = try #require(chosenSignature.receiverType)
                guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
                    Issue.record("Expected binarySearch source receiver to be a class type"); continue
                }
                let listSymbol = try #require(sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("collections"),
                    ctx.interner.intern("List"),
                ]))
                #expect(receiverClassType.classSymbol == listSymbol)
            }
        }
    }

    @Test
    func testListBinarySearchComparatorOverloadHasDefaultedRange() throws {
        try withTemporaryFile(contents: "fun noop() {}") { _ in
            let ctx = try sharedListSemaContext()

            let sema = try #require(ctx.sema)
            let symbolID = try #require(sema.symbols.lookupAll(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("collections"),
                    ctx.interner.intern("binarySearch"),
                ]).first(where: { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate) else {
                        return false
                    }
                    return signature.parameterTypes.count == 4
                        && sema.symbols.isSourceBackedSymbol(candidate)
                }))
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.parameterTypes.count == 4)
            #expect(signature.valueParameterSymbols.count == 4)
            #expect(signature.valueParameterHasDefaultValues == [false, false, true, true])
            #expect(signature.typeParameterSymbols.count == 1)
            #expect(signature.classTypeParameterCount == 0)
            #expect(signature.typeParameterUpperBoundsList == [[]])

            let parameterNames = signature.valueParameterSymbols.compactMap { paramSymbol in
                sema.symbols.symbol(paramSymbol)?.name
            }.map { ctx.interner.resolve($0) }
            #expect(parameterNames == ["element", "comparator", "fromIndex", "toIndex"])

            #expect(signature.parameterTypes[0] == sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0],
                nullability: .nonNull
            ))))
            #expect(signature.parameterTypes[2] == sema.types.intType)
            #expect(signature.parameterTypes[3] == sema.types.intType)

            if let comparatorSymbol = sema.symbols.lookupByShortName(ctx.interner.intern("Comparator")).first,
               case let .classType(comparatorClassType) = sema.types.kind(of: signature.parameterTypes[1])
            {
                #expect(comparatorClassType.classSymbol == comparatorSymbol)
                #expect(comparatorClassType.args.count == 1)
            } else {
                guard case let .functionType(comparatorFunctionType) = sema.types.kind(of: signature.parameterTypes[1]) else {
                    Issue.record("Expected binarySearch comparator parameter to be Comparator<T> or a comparator function type"); return
                }
                #expect(comparatorFunctionType.params.count == 2)
                #expect(comparatorFunctionType.returnType == sema.types.intType)
            }
        }
    }

    @Test
    func testListBinarySearchByUsesComparableKeyAndRuntimeOverloads() throws {
        let source = """
        data class Person(val name: String, val age: Int)

        fun render(values: List<Person>) {
            values.binarySearchBy(35) { it.age }
            values.binarySearchBy(35, 1) { it.age }
            values.binarySearchBy(35, 1, 4) { it.age }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "binarySearchBy"
                else {
                    return nil
                }
                return exprID
            }
            #expect(callExprIDs.count == 3, "Expected three binarySearchBy calls")

            for callExprID in callExprIDs {
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExprID)?.chosenCallee)
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                #expect(sema.bindings.exprType(for: callExprID) == sema.types.intType, "Expected binarySearchBy to return Int")
            }

            let binarySearchByFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("binarySearchBy"),
            ]

            let symbolID = try #require(sema.symbols.lookupAll(fqName: binarySearchByFQName).first(where: {
                sema.symbols.isSourceBackedSymbol($0)
            }))
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.returnType == sema.types.intType)
            #expect(signature.parameterTypes.count == 4)
            #expect(signature.valueParameterHasDefaultValues == [false, true, true, false])
            #expect(signature.typeParameterSymbols.count == 2)
            #expect(signature.typeParameterUpperBoundsList == [[], []])

            let selectorType = try #require(signature.parameterTypes.last)
            guard case let .functionType(functionType) = sema.types.kind(of: selectorType) else {
                Issue.record("Expected selector parameter to be a function type"); return
            }
            #expect(functionType.params.count == 1)

            let expectedListElementType = sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0],
                nullability: .nonNull
            )))
            #expect(functionType.params[0] == expectedListElementType)
            #expect(functionType.returnType == signature.parameterTypes[0])

            let expectedKeyType = sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[1],
                nullability: .nonNull
            )))
            #expect(signature.parameterTypes[0] == expectedKeyType)
            #expect(signature.parameterTypes[1] == sema.types.intType)
            #expect(signature.parameterTypes[2] == sema.types.intType)
        }
    }

    @Test
    func testListToTypeArrayResolvesToSourceBackedDeclaration() throws {
        let source = """
        fun convert(values: List<String>) {
            val converted: Array<String> = values.toTypedArray()
            converted.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toTypedArray"
            })
            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            // KSP-628: source-backed (Stdlib/kotlin/collections/ArrayConversions.kt),
            // so no direct kk_list_toTypedArray runtime link.
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
            guard case let .classType(classType) = sema.types.kind(of: signature.returnType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                Issue.record("Expected toTypedArray to return Array"); return
            }
            #expect(ctx.interner.resolve(symbol.name) == "Array")
        }
    }

    @Test
    func testIterableLocalVariableFromNonFactoryFunctionResolvesFilterAndCount() throws {
        // Regression test: assigning the result of an ordinary (non collection-factory)
        // function call to an explicitly `Iterable<T>`-typed local used to leave that
        // local's receiver classification without isCollectionExpr/isCollectionType/
        // isSequenceReceiver, so tryCollectionMemberFallback's guard rejected members
        // like filter/count even though the static receiver type is nominally Iterable.
        let source = """
        fun getStrings(): List<String> = listOf("a", "bb", "ccc")

        fun checksum(): Int {
            val parts = getStrings()
            val iter: Iterable<String> = parts
            val filtered = iter.filter { it.length > 1 }
            return iter.count() + filtered.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable<T> local from a non-factory function call to resolve filter/count cleanly, got: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let filterExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filter"
            })
            #expect(sema.bindings.callBinding(for: filterExpr)?.chosenCallee != nil, "Expected filter call on the Iterable-typed local to bind to a callee")

            let countExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "count" && args.isEmpty
            })
            #expect(sema.bindings.exprType(for: countExpr) == sema.types.intType)
        }
    }

    @Test
    func testIterableParameterFromNonListLiteralArgumentResolvesFilterAndCount() throws {
        // Companion regression coverage: the same static-type gap also affected
        // Iterable<T>-typed function parameters (not just locals), since parameters
        // never carry the isCollectionExpr propagation mark either.
        let source = """
        fun checksum(values: Iterable<Int>): Int {
            return values.filter { it > 1 }.count()
        }

        fun caller(): Int = checksum(listOf(1, 2, 3))
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Expected Iterable<T> parameter to resolve filter/count cleanly, got: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })")
        }
    }

}

struct SyntheticMemberCallCase {
    let source: String
    let memberName: String
    /// `nil` means the member must be source-backed (no direct `kk_*` link).
    let expectedExternalLink: String?
    let expectedTypeShape: SyntheticMemberTypeShape?
}

enum SyntheticMemberTypeShape {
    case classNamed(String)
}

func assertSyntheticMemberCall(
    _ testCase: SyntheticMemberCallCase,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    try withTemporaryFile(contents: testCase.source) { path in
        let ctx = makeCompilationContext(inputs: [path])
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected \(testCase.memberName) to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        // Use lastExprID rather than firstExprID: bundled stdlib sources (injected
        // before the fixture's own source) may contain unrelated calls to the same
        // member name (e.g. Sequence aggregate HOFs calling `this.toList()`
        // internally), which would otherwise shadow the fixture's own call site.
        let callExpr = try #require(lastExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == testCase.memberName
        })
        let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
        #expect(
            sema.symbols.externalLinkName(for: chosenCallee) == testCase.expectedExternalLink,
            "Expected \(testCase.memberName) to resolve to \(testCase.expectedExternalLink ?? "a source-backed declaration")"
        )

        if let expectedTypeShape = testCase.expectedTypeShape {
            let resultType = try #require(sema.bindings.exprType(for: callExpr))
            try assertSyntheticMemberType(
                resultType,
                matches: expectedTypeShape,
                sema: sema,
                interner: ctx.interner,
                memberName: testCase.memberName,
                file: file,
                line: line
            )
        }
    }
}

func assertSyntheticMemberType(
    _ type: TypeID,
    matches expectedTypeShape: SyntheticMemberTypeShape,
    sema: SemaModule,
    interner: StringInterner,
    memberName: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    switch expectedTypeShape {
    case let .classNamed(expectedName):
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            Issue.record("Expected \(memberName) to return \(expectedName)"); return
        }
        #expect(interner.resolve(symbol.name) == expectedName)
    }
}

func projectedType(
    _ arg: TypeArg,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> TypeID {
    switch arg {
    case let .invariant(type), let .out(type), let .in(type):
        return type
    case .star:
        return try #require(nil as TypeID?)
    }
}

func assertListType(
    _ type: TypeID,
    elementType expectedElementType: TypeID,
    sema: SemaModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard case let .classType(listType) = sema.types.kind(of: type) else {
        Issue.record("Expected List type"); return
    }
    #expect(try interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
    #expect(listType.args.count == 1)
    let elementType = try projectedType(try #require(listType.args.first), file: file, line: line)
    #expect(elementType == expectedElementType)
}

/// Resolves a List member from either a source-backed extension or a synthetic stub.
func listBackedFunctionSymbol(
    memberName: String,
    sema: SemaModule,
    interner: StringInterner,
    sourceManager: SourceManager
) -> SymbolID? {
    let listFQName: [InternedString] = [
        interner.intern("kotlin"),
        interner.intern("collections"),
        interner.intern("List"),
        interner.intern(memberName),
    ]
    if let synthetic = sema.symbols.lookup(fqName: listFQName) {
        return synthetic
    }

    let packageFQName = listFQName.dropLast(2) + [interner.intern(memberName)]
    return sema.symbols.lookupAll(fqName: Array(packageFQName)).first { symbolID in
        guard let symbol = sema.symbols.symbol(symbolID),
              symbol.kind == .function,
              !symbol.flags.contains(.synthetic),
              let fileID = sema.symbols.sourceFileID(for: symbolID),
              let signature = sema.symbols.functionSignature(for: symbolID),
              let receiverType = signature.receiverType,
              let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
        else { return false }
        return interner.resolve(receiverSymbol.name) == "List"
            && sourceManager.path(of: fileID).hasPrefix("__bundled_")
    }
}

private func sourceBackedIterableExtensionSymbol(
    named name: String,
    sema: SemaModule,
    interner: StringInterner
) -> SymbolID? {
    let iterableFQName: [InternedString] = [
        interner.intern("kotlin"),
        interner.intern("collections"),
        interner.intern("Iterable")
    ]
    guard let iterableSymbol = sema.symbols.lookup(fqName: iterableFQName) else { return nil }
    let shortName = interner.intern(name)
    return sema.symbols.lookupByShortName(shortName).first { candidate in
        guard sema.symbols.isSourceBackedSymbol(candidate),
              let signature = sema.symbols.functionSignature(for: candidate),
              let receiverType = signature.receiverType,
              case let .classType(classType) = sema.types.kind(of: receiverType)
        else { return false }
        return classType.classSymbol == iterableSymbol
    }
}
#endif
