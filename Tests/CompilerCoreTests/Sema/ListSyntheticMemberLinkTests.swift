@testable import CompilerCore
import Foundation
import XCTest

final class ListSyntheticMemberLinkTests: XCTestCase {
    func testListLastIndexExtensionPropertyResolvesToRuntimeGetter() throws {
        let source = """
        import kotlin.collections.lastIndex

        fun last(values: List<String>): Int {
            return values.lastIndex
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected List.lastIndex to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let propertyExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "lastIndex" && args.isEmpty
            }, "Expected values.lastIndex property access in AST")
            XCTAssertEqual(sema.bindings.exprType(for: propertyExpr), sema.types.intType)

            let getter = try XCTUnwrap(sema.bindings.callBinding(for: propertyExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: getter), "kk_list_lastIndex")

            let property = try XCTUnwrap(sema.bindings.identifierSymbol(for: propertyExpr))
            XCTAssertEqual(sema.symbols.externalLinkName(for: property), "kk_list_lastIndex")
            XCTAssertEqual(sema.symbols.propertyType(for: property), sema.types.intType)
        }
    }

    func testListTransformMembersUseRuntimeExternalLinksForParameterReceivers() throws {
        let source = """
        fun render(values: List<Int>) {
            values.take(3)
            values.drop(2)
            values.reversed()
            values.sorted()
            values.distinct()
            values.shuffled()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks = [
                "take": "kk_list_take",
                "drop": "kk_list_drop",
                "reversed": "kk_list_reversed",
                "sorted": "kk_list_sorted",
                "distinct": "kk_list_distinct",
                "shuffled": "kk_list_shuffled",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testListToMapUsesRuntimeExternalLink() throws {
        let source = """
        fun copy(values: List<Pair<String, Int>>) {
            values.toMap()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected List.toMap to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toMap"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_list_toMap")

            let resultType = try XCTUnwrap(sema.bindings.exprTypes[callExpr])
            guard case let .classType(classType) = sema.types.kind(of: resultType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return XCTFail("Expected toMap to return Map")
            }
            XCTAssertEqual(ctx.interner.resolve(symbol.name), "Map")
        }
    }

    func testCollectionToListUsesRuntimeExternalLink() throws {
        let source = """
        fun copy(values: Collection<String>): List<String> {
            return values.toList()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected Collection.toList to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toList"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_collection_toList")

            let resultType = try XCTUnwrap(sema.bindings.exprTypes[callExpr])
            guard case let .classType(classType) = sema.types.kind(of: resultType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return XCTFail("Expected toList to return List")
            }
            XCTAssertEqual(ctx.interner.resolve(symbol.name), "List")
        }
    }

    func testListIndicesExtensionPropertyResolvesToRuntimeGetter() throws {
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

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected List.indices to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let propertyExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "indices" && args.isEmpty
            }, "Expected values.indices property access in AST")
            let propertyType = try XCTUnwrap(sema.bindings.exprType(for: propertyExpr))
            guard case let .classType(rangeType) = sema.types.kind(of: propertyType) else {
                return XCTFail("Expected List.indices to have IntRange type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(rangeType.classSymbol)?.name)), "IntRange")

            let getter = try XCTUnwrap(sema.bindings.callBinding(for: propertyExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: getter), "kk_list_indices")

            let property = try XCTUnwrap(sema.bindings.identifierSymbol(for: propertyExpr))
            XCTAssertEqual(sema.symbols.externalLinkName(for: property), "kk_list_indices")
            XCTAssertEqual(sema.symbols.propertyType(for: property), propertyType)
        }
    }

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

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected arrayListOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let arrayListCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "arrayListOf"
            })
            let callType = try XCTUnwrap(sema.bindings.exprTypes[arrayListCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                return XCTFail("Expected arrayListOf to produce a MutableList class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)), "MutableList")
            XCTAssertEqual(classType.args, [.invariant(sema.types.intType)])
            XCTAssertTrue(
                sema.bindings.isCollectionExpr(arrayListCall),
                "Expected arrayListOf to be tracked as a collection expression"
            )
        }
    }

    func testLinkedListConcreteClassAndConstructorSurfaceIsRegistered() throws {
        let source = """
        fun probe() {
            val constructed: LinkedList<Int> = LinkedList<Int>()
            val asMutable: MutableList<Int> = constructed
            val asList: List<Int> = constructed
            val inferred = LinkedList<Int>()
            inferred.add(1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected LinkedList constructor calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let constructorCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "LinkedList"
            })
            let callType = try XCTUnwrap(sema.bindings.exprTypes[constructorCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                return XCTFail("Expected LinkedList constructor to produce a LinkedList class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)), "LinkedList")
            XCTAssertEqual(classType.args, [.invariant(sema.types.intType)])
            XCTAssertTrue(
                sema.bindings.isCollectionExpr(constructorCall),
                "Expected LinkedList constructor to be tracked as a collection expression"
            )

            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let linkedListFQName = collectionsPkg + [ctx.interner.intern("LinkedList")]
            let linkedListSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: linkedListFQName),
                "Expected kotlin.collections.LinkedList to be registered"
            )
            let linkedListInfo = try XCTUnwrap(sema.symbols.symbol(linkedListSymbol))
            XCTAssertEqual(linkedListInfo.kind, .class)
            XCTAssertTrue(linkedListInfo.flags.contains(.synthetic))
            XCTAssertTrue(linkedListInfo.flags.contains(.openType))

            let mutableListSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableList")])
            )
            XCTAssertTrue(sema.symbols.directSupertypes(for: linkedListSymbol).contains(mutableListSymbol))
            XCTAssertEqual(
                sema.types.nominalTypeParameterVariances(for: linkedListSymbol),
                [.invariant]
            )

            let constructorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: linkedListFQName + [ctx.interner.intern("<init>")]),
                "Expected LinkedList public constructor to be registered"
            )
            let constructorInfo = try XCTUnwrap(sema.symbols.symbol(constructorSymbol))
            XCTAssertEqual(constructorInfo.kind, .constructor)
            XCTAssertEqual(constructorInfo.visibility, .public)
            XCTAssertEqual(sema.symbols.externalLinkName(for: constructorSymbol), "kk_emptyList")
        }
    }

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

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected linkedSetOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let linkedSetCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "linkedSetOf"
            })
            let callType = try XCTUnwrap(sema.bindings.exprTypes[linkedSetCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                return XCTFail("Expected linkedSetOf to produce a LinkedHashSet class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)), "LinkedHashSet")
            XCTAssertEqual(classType.args, [.invariant(sema.types.intType)])
            XCTAssertTrue(
                sema.bindings.isCollectionExpr(linkedSetCall),
                "Expected linkedSetOf to be tracked as a collection expression"
            )
        }
    }

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

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected LinkedHashSet concrete class calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let kotlinCollections = [interner.intern("kotlin"), interner.intern("collections")]
            let linkedHashSetFQ = kotlinCollections + [interner.intern("LinkedHashSet")]
            let mutableSetFQ = kotlinCollections + [interner.intern("MutableSet")]
            let linkedHashSetSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: linkedHashSetFQ))
            let mutableSetSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: mutableSetFQ))

            let linkedHashSetInfo = try XCTUnwrap(sema.symbols.symbol(linkedHashSetSymbol))
            XCTAssertEqual(linkedHashSetInfo.kind, .class)
            XCTAssertTrue(linkedHashSetInfo.flags.contains(.synthetic))
            XCTAssertTrue(linkedHashSetInfo.flags.contains(.openType))
            XCTAssertTrue(sema.symbols.directSupertypes(for: linkedHashSetSymbol).contains(mutableSetSymbol))
            XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: linkedHashSetSymbol), [.invariant])

            let constructorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: linkedHashSetFQ + [interner.intern("<init>")]),
                "Expected LinkedHashSet public constructor to be registered"
            )
            let constructorInfo = try XCTUnwrap(sema.symbols.symbol(constructorSymbol))
            XCTAssertEqual(constructorInfo.kind, .constructor)
            XCTAssertEqual(constructorInfo.visibility, .public)
            XCTAssertEqual(sema.symbols.externalLinkName(for: constructorSymbol), "kk_emptySet")
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol))
            XCTAssertTrue(signature.parameterTypes.isEmpty)
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)
            XCTAssertEqual(signature.classTypeParameterCount, 1)

            let constructorCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return interner.resolve(name) == "LinkedHashSet"
            })
            let callType = try XCTUnwrap(sema.bindings.exprTypes[constructorCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                return XCTFail("Expected LinkedHashSet constructor to produce a class type")
            }
            XCTAssertEqual(try interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)), "LinkedHashSet")
            XCTAssertEqual(classType.args, [.invariant(sema.types.intType)])
            XCTAssertTrue(
                sema.bindings.isCollectionExpr(constructorCall),
                "Expected LinkedHashSet constructor to be tracked as a collection expression"
            )
        }
    }

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

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected linkedMapOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let linkedMapCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "linkedMapOf"
            })
            let callType = try XCTUnwrap(sema.bindings.exprTypes[linkedMapCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                return XCTFail("Expected linkedMapOf to produce a MutableMap class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)), "MutableMap")
            XCTAssertEqual(classType.args, [.invariant(sema.types.stringType), .invariant(sema.types.intType)])
            XCTAssertTrue(
                sema.bindings.isCollectionExpr(linkedMapCall),
                "Expected linkedMapOf to be tracked as a collection expression"
            )
        }
    }

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

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected hashMapOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let hashMapCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "hashMapOf"
            })
            let callType = try XCTUnwrap(sema.bindings.exprTypes[hashMapCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                return XCTFail("Expected hashMapOf to produce a MutableMap class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)), "MutableMap")
            XCTAssertEqual(classType.args, [.invariant(sema.types.stringType), .invariant(sema.types.intType)])
            XCTAssertTrue(
                sema.bindings.isCollectionExpr(hashMapCall),
                "Expected hashMapOf to be tracked as a collection expression"
            )
        }
    }

    func testHashSetOfFactoryInfersMutableSetType() throws {
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

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected hashSetOf factory calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let hashSetCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "hashSetOf"
            })
            let callType = try XCTUnwrap(sema.bindings.exprTypes[hashSetCall])
            guard case let .classType(classType) = sema.types.kind(of: callType) else {
                return XCTFail("Expected hashSetOf to produce a MutableSet class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)), "MutableSet")
            XCTAssertEqual(classType.args, [.invariant(sema.types.intType)])
            XCTAssertTrue(
                sema.bindings.isCollectionExpr(hashSetCall),
                "Expected hashSetOf to be tracked as a collection expression"
            )
        }
    }

    func testListAggregateMembersUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let expectedExternalLinks = [
                "filterNot": "kk_list_filterNot",
                "sum": "kk_list_sum",
                "sumOf": "kk_list_sumOf",
                "maxOfWith": "kk_list_maxOfWith",
                "minBy": "kk_list_minBy",
                "maxOfWithOrNull": "kk_list_maxOfWithOrNull",
                "maxWithOrNull": "kk_list_maxWithOrNull",
                "min": "kk_list_min",
                "maxOrNull": "kk_list_maxOrNull",
                "minOrNull": "kk_list_minOrNull",
                "minOf": "kk_list_minOf",
                "minByOrNull": "kk_list_minByOrNull",
                "maxBy": "kk_list_maxBy",
                "maxByOrNull": "kk_list_maxByOrNull",
                "minOfWithOrNull": "kk_list_minOfWithOrNull",
                "filterNotTo": "kk_list_filterNotTo",
                "filterNotNullTo": "kk_list_filterNotNullTo",
                "findLast": "kk_list_findLast",
                "filterTo": "kk_list_filterTo",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("collections"),
                            ctx.interner.intern("List"),
                            ctx.interner.intern(memberName),
                        ]
                    ),
                    "Expected synthetic List member \(memberName) to be registered"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: symbolID),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testListFilterIsInstanceToUsesRuntimeExternalLink() throws {
        let source = """
        fun collect(values: List<Any>, dest: MutableList<String>) {
            values.filterIsInstanceTo(dest)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected List.filterIsInstanceTo to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterIsInstanceTo"
            })
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected filterIsInstanceTo to bind to its synthetic runtime callee"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_list_filterIsInstanceTo")
            XCTAssertTrue(
                sema.bindings.isCollectionExpr(callExpr),
                "Expected filterIsInstanceTo result to be tracked as a collection expression"
            )
        }
    }

    func testIterableSumByResolvesToListRuntime() throws {
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
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Iterable.sumBy surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "sumBy"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            XCTAssertEqual(sema.symbols.externalLinkName(for: memberSymbol), "kk_list_sumBy")
            XCTAssertTrue(
                sema.symbols.annotations(for: memberSymbol).contains { $0.annotationFQName == "kotlin.Deprecated" },
                "Iterable.sumBy should carry Deprecated metadata"
            )

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memberSymbol))
            XCTAssertEqual(signature.parameterTypes.count, 1)
            guard case let .functionType(selectorType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                return XCTFail("Expected Iterable.sumBy selector parameter to be a function")
            }
            XCTAssertEqual(selectorType.params.count, 1)
            XCTAssertEqual(signature.returnType, sema.types.intType)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            XCTAssertEqual(callLinks.filter { $0 == "kk_list_sumBy" }.count, 2)
        }
    }

    func testIterableSumByDoubleResolvesToListRuntime() throws {
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
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Iterable.sumByDouble surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "sumByDouble"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            XCTAssertEqual(sema.symbols.externalLinkName(for: memberSymbol), "kk_list_sumByDouble")
            XCTAssertTrue(
                sema.symbols.annotations(for: memberSymbol).contains { $0.annotationFQName == "kotlin.Deprecated" },
                "Iterable.sumByDouble should carry Deprecated metadata"
            )

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memberSymbol))
            XCTAssertEqual(signature.parameterTypes.count, 1)
            guard case let .functionType(selectorType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                return XCTFail("Expected Iterable.sumByDouble selector parameter to be a function")
            }
            XCTAssertEqual(selectorType.params.count, 1)
            XCTAssertEqual(signature.returnType, sema.types.doubleType)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            XCTAssertEqual(callLinks.filter { $0 == "kk_list_sumByDouble" }.count, 2)
        }
    }

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
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Iterable.firstNotNullOf surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "firstNotNullOf"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_iterable_firstNotNullOf"))
        }
    }

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
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Iterable.firstNotNullOfOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "firstNotNullOfOrNull"]
                .map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            XCTAssertTrue(links.contains("kk_iterable_firstNotNullOfOrNull"))
        }
    }

    func testIterableMinusElementResolvesToListRuntime() throws {
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
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Iterable.minusElement surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "minusElement"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            XCTAssertEqual(sema.symbols.externalLinkName(for: memberSymbol), "kk_list_minus_element")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memberSymbol))
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                  let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
            else {
                return XCTFail("Expected Iterable.minusElement to return List<E>")
            }
            XCTAssertEqual(ctx.interner.resolve(returnSymbol.name), "List")

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            XCTAssertEqual(callLinks.filter { $0 == "kk_list_minus_element" }.count, 2)
        }
    }

    func testIterableReduceRightIndexedResolvesToListRuntime() throws {
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
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Iterable.reduceRightIndexed surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "reduceRightIndexed"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            XCTAssertEqual(sema.symbols.externalLinkName(for: memberSymbol), "kk_list_reduceRightIndexed")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memberSymbol))
            XCTAssertEqual(signature.parameterTypes.count, 1)
            guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                return XCTFail("Expected Iterable.reduceRightIndexed operation parameter to be a function")
            }
            XCTAssertEqual(operationType.params.count, 3)
            guard case let .primitive(indexPrimitive, indexNullability) = sema.types.kind(of: operationType.params[0]) else {
                return XCTFail("Expected first reduceRightIndexed lambda parameter to be Int")
            }
            XCTAssertEqual(indexPrimitive, .int)
            XCTAssertEqual(indexNullability, .nonNull)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            XCTAssertEqual(callLinks.filter { $0 == "kk_list_reduceRightIndexed" }.count, 2)
        }
    }

    func testIterableReduceRightIndexedOrNullResolvesToListRuntime() throws {
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
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Iterable.reduceRightIndexedOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "reduceRightIndexedOrNull"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            XCTAssertEqual(sema.symbols.externalLinkName(for: memberSymbol), "kk_list_reduceRightIndexedOrNull")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memberSymbol))
            XCTAssertEqual(signature.parameterTypes.count, 1)
            guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                return XCTFail("Expected Iterable.reduceRightIndexedOrNull operation parameter to be a function")
            }
            XCTAssertEqual(operationType.params.count, 3)
            guard case let .primitive(indexPrimitive, indexNullability) = sema.types.kind(of: operationType.params[0]) else {
                return XCTFail("Expected first reduceRightIndexedOrNull lambda parameter to be Int")
            }
            XCTAssertEqual(indexPrimitive, .int)
            XCTAssertEqual(indexNullability, .nonNull)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            XCTAssertEqual(callLinks.filter { $0 == "kk_list_reduceRightIndexedOrNull" }.count, 2)
        }
    }

    func testIterableReduceRightOrNullResolvesToListRuntime() throws {
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
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Iterable.reduceRightOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Iterable", "reduceRightOrNull"]
                .map { ctx.interner.intern($0) }
            let memberSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            XCTAssertEqual(sema.symbols.externalLinkName(for: memberSymbol), "kk_list_reduceRightOrNull")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memberSymbol))
            XCTAssertEqual(signature.parameterTypes.count, 1)
            guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                return XCTFail("Expected Iterable.reduceRightOrNull operation parameter to be a function")
            }
            XCTAssertEqual(operationType.params.count, 2)

            let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee)
            }
            XCTAssertEqual(callLinks.filter { $0 == "kk_list_reduceRightOrNull" }.count, 2)
        }
    }

    func testListFirstOrNullAndLastOrNullReturnNullableElementsWithoutCollectionMarking() throws {
        let source = """
        fun probe(values: List<Int>) {
            values.firstOrNull()
            values.lastOrNull()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let expectedMembers = [
                "firstOrNull": "kk_list_firstOrNull",
                "lastOrNull": "kk_list_lastOrNull",
            ]
            let nullableIntType = sema.types.makeNullable(sema.types.intType)

            for (memberName, externalLinkName) in expectedMembers {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for \(memberName)"
                )

                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    nullableIntType,
                    "Expected \(memberName) to return a nullable element type"
                )
                XCTAssertFalse(
                    sema.bindings.isCollectionExpr(callExpr),
                    "Expected \(memberName) result to avoid collection-expression marking"
                )
            }
        }
    }

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
            XCTAssertEqual(boundDiagnostics.count, 2, "Expected bound diagnostics for maxOrNull/minOrNull")
        }
    }

    func testComparableSyntheticStubUsesContravariantTypeParameter() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let comparableSymbol = try XCTUnwrap(
                sema.types.comparableInterfaceSymbol,
                "Expected synthetic Comparable interface to be registered"
            )
            XCTAssertEqual(
                sema.types.nominalTypeParameterVariances(for: comparableSymbol),
                [.in],
                "Expected Comparable to be declared as Comparable<in T>"
            )

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

            XCTAssertTrue(
                sema.types.isSubtype(comparableAny, comparableString),
                "Expected Comparable<Any> to be a subtype of Comparable<String>"
            )
            XCTAssertFalse(
                sema.types.isSubtype(comparableString, comparableAny),
                "Expected Comparable<String> not to be a subtype of Comparable<Any>"
            )
        }
    }

    func testCollectionFallbackRejectsListOnlyIndexedLookupsOnAbstractCollection() throws {
        let source = """
        fun firstValue(values: Collection<Int>): Int? = values.firstOrNull()
        fun lastValue(values: Collection<Int>): Int? = values.lastOrNull()
        fun fallbackValue(values: Collection<Int>): Int = values.getOrElse(0) { -1 }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            for memberName in ["firstOrNull", "lastOrNull", "getOrElse"] {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName)")
                XCTAssertNil(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected Collection.\(memberName) to remain unresolved"
                )
            }

            XCTAssertFalse(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected diagnostics for Collection indexed lookup fallbacks"
            )
        }
    }

    func testCollectionLastInfersElementType() throws {
        let source = """
        fun lastValue(values: Collection<Int>): Int = values.last()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "last"
            })
            let type = try XCTUnwrap(sema.bindings.exprType(for: callExpr))
            XCTAssertEqual(sema.types.kind(of: type), .primitive(.int, .nonNull))
        }
    }

    func testPrimitiveIteratorSurfacesAreRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let iteratorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Iterator")])
            )
            let specs: [(className: String, nextName: String, elementType: TypeID)] = [
                ("BooleanIterator", "nextBoolean", sema.types.booleanType),
                ("ByteIterator", "nextByte", sema.types.intType),
                ("ShortIterator", "nextShort", sema.types.intType),
                ("IntIterator", "nextInt", sema.types.intType),
                ("LongIterator", "nextLong", sema.types.longType),
                ("FloatIterator", "nextFloat", sema.types.floatType),
                ("DoubleIterator", "nextDouble", sema.types.doubleType),
                ("CharIterator", "nextChar", sema.types.charType),
            ]

            for spec in specs {
                let classFQName = collectionsPkg + [ctx.interner.intern(spec.className)]
                let classSymbol = try XCTUnwrap(
                    sema.symbols.lookup(fqName: classFQName),
                    "Expected \(spec.className) to be registered"
                )
                let classInfo = try XCTUnwrap(sema.symbols.symbol(classSymbol))
                XCTAssertEqual(classInfo.kind, .class)
                XCTAssertTrue(classInfo.flags.contains(.synthetic))
                XCTAssertTrue(classInfo.flags.contains(.abstractType))
                XCTAssertTrue(sema.symbols.directSupertypes(for: classSymbol).contains(iteratorSymbol))
                XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: classSymbol, supertype: iteratorSymbol), [.out(spec.elementType)])

                let primitiveNextSymbol = try XCTUnwrap(
                    sema.symbols.lookup(fqName: classFQName + [ctx.interner.intern(spec.nextName)]),
                    "Expected \(spec.className).\(spec.nextName) to be registered"
                )
                let primitiveNextInfo = try XCTUnwrap(sema.symbols.symbol(primitiveNextSymbol))
                XCTAssertTrue(primitiveNextInfo.flags.isSuperset(of: [.synthetic, .abstractType]))
                let primitiveNextSignature = try XCTUnwrap(sema.symbols.functionSignature(for: primitiveNextSymbol))
                XCTAssertTrue(primitiveNextSignature.parameterTypes.isEmpty)
                XCTAssertEqual(primitiveNextSignature.returnType, spec.elementType)

                let nextSymbol = try XCTUnwrap(
                    sema.symbols.lookup(fqName: classFQName + [ctx.interner.intern("next")]),
                    "Expected \(spec.className).next to be registered"
                )
                let nextInfo = try XCTUnwrap(sema.symbols.symbol(nextSymbol))
                XCTAssertTrue(nextInfo.flags.isSuperset(of: [.synthetic, .openType, .overrideMember, .operatorFunction]))
                XCTAssertEqual(try XCTUnwrap(sema.symbols.functionSignature(for: nextSymbol)).returnType, spec.elementType)
            }
        }
    }

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

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected primitive iterator subclass surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testAbstractIteratorSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let abstractIteratorFQName = ["kotlin", "collections", "AbstractIterator"]
                .map { ctx.interner.intern($0) }
            let abstractIteratorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractIteratorFQName),
                "Expected kotlin.collections.AbstractIterator to be registered"
            )
            let abstractIteratorInfo = try XCTUnwrap(sema.symbols.symbol(abstractIteratorSymbol))
            XCTAssertEqual(abstractIteratorInfo.kind, .class)
            XCTAssertTrue(abstractIteratorInfo.flags.contains(.synthetic))
            XCTAssertTrue(abstractIteratorInfo.flags.contains(.abstractType))
            XCTAssertEqual(
                sema.types.nominalTypeParameterVariances(for: abstractIteratorSymbol),
                [.invariant]
            )

            let iteratorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: ["kotlin", "collections", "Iterator"].map { ctx.interner.intern($0) })
            )
            XCTAssertTrue(sema.symbols.directSupertypes(for: abstractIteratorSymbol).contains(iteratorSymbol))
            XCTAssertTrue(sema.types.directNominalSupertypes(for: abstractIteratorSymbol).contains(iteratorSymbol))
            XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: abstractIteratorSymbol, supertype: iteratorSymbol).count, 1)
            XCTAssertEqual(sema.types.nominalSupertypeTypeArgs(for: abstractIteratorSymbol, supertype: iteratorSymbol).count, 1)

            let expectedMembers: [(name: String, visibility: Visibility, requiredFlags: SymbolFlags, parameterCount: Int)] = [
                ("computeNext", .protected, [.synthetic, .abstractType], 0),
                ("done", .protected, [.synthetic], 0),
                ("setNext", .protected, [.synthetic], 1),
                ("hasNext", .public, [.synthetic, .openType, .overrideMember, .operatorFunction], 0),
                ("next", .public, [.synthetic, .openType, .overrideMember, .operatorFunction], 0),
            ]
            for expected in expectedMembers {
                let memberSymbol = try XCTUnwrap(
                    sema.symbols.lookup(fqName: abstractIteratorFQName + [ctx.interner.intern(expected.name)]),
                    "Expected AbstractIterator.\(expected.name) to be registered"
                )
                let memberInfo = try XCTUnwrap(sema.symbols.symbol(memberSymbol))
                XCTAssertEqual(memberInfo.visibility, expected.visibility)
                XCTAssertTrue(memberInfo.flags.isSuperset(of: expected.requiredFlags))
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memberSymbol))
                XCTAssertEqual(signature.parameterTypes.count, expected.parameterCount)
            }
        }
    }

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

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected AbstractIterator subclass surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testAbstractCollectionSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let abstractCollectionFQName = ["kotlin", "collections", "AbstractCollection"]
                .map { ctx.interner.intern($0) }
            let abstractCollectionSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractCollectionFQName),
                "Expected kotlin.collections.AbstractCollection to be registered"
            )
            let abstractCollectionInfo = try XCTUnwrap(sema.symbols.symbol(abstractCollectionSymbol))
            XCTAssertEqual(abstractCollectionInfo.kind, .class)
            XCTAssertTrue(abstractCollectionInfo.flags.contains(.synthetic))
            XCTAssertTrue(abstractCollectionInfo.flags.contains(.abstractType))
            XCTAssertEqual(
                sema.types.nominalTypeParameterVariances(for: abstractCollectionSymbol),
                [.out]
            )

            let collectionSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: ["kotlin", "collections", "Collection"].map { ctx.interner.intern($0) })
            )
            XCTAssertTrue(sema.symbols.directSupertypes(for: abstractCollectionSymbol).contains(collectionSymbol))
            XCTAssertTrue(sema.types.directNominalSupertypes(for: abstractCollectionSymbol).contains(collectionSymbol))
            XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: abstractCollectionSymbol, supertype: collectionSymbol).count, 1)
            XCTAssertEqual(sema.types.nominalSupertypeTypeArgs(for: abstractCollectionSymbol, supertype: collectionSymbol).count, 1)

            let constructorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractCollectionFQName + [ctx.interner.intern("<init>")]),
                "Expected AbstractCollection protected constructor to be registered"
            )
            let constructorInfo = try XCTUnwrap(sema.symbols.symbol(constructorSymbol))
            XCTAssertEqual(constructorInfo.kind, .constructor)
            XCTAssertEqual(constructorInfo.visibility, .protected)
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol))
            XCTAssertTrue(signature.parameterTypes.isEmpty)
        }
    }

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

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected AbstractCollection subclass surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testAbstractListSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let abstractCollectionSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("AbstractCollection")])
            )
            let listSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("List")])
            )

            let abstractListFQName = collectionsPkg + [ctx.interner.intern("AbstractList")]
            let abstractListSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractListFQName),
                "Expected kotlin.collections.AbstractList to be registered"
            )
            let abstractListInfo = try XCTUnwrap(sema.symbols.symbol(abstractListSymbol))
            XCTAssertEqual(abstractListInfo.kind, .class)
            XCTAssertTrue(abstractListInfo.flags.contains(.synthetic))
            XCTAssertTrue(abstractListInfo.flags.contains(.abstractType))
            XCTAssertEqual(
                sema.types.nominalTypeParameterVariances(for: abstractListSymbol),
                [.out]
            )

            let directSupertypes = sema.symbols.directSupertypes(for: abstractListSymbol)
            XCTAssertTrue(directSupertypes.contains(abstractCollectionSymbol))
            XCTAssertTrue(directSupertypes.contains(listSymbol))
            XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: abstractListSymbol, supertype: abstractCollectionSymbol).count, 1)
            XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: abstractListSymbol, supertype: listSymbol).count, 1)
            XCTAssertEqual(sema.types.nominalSupertypeTypeArgs(for: abstractListSymbol, supertype: abstractCollectionSymbol).count, 1)
            XCTAssertEqual(sema.types.nominalSupertypeTypeArgs(for: abstractListSymbol, supertype: listSymbol).count, 1)

            let constructorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractListFQName + [ctx.interner.intern("<init>")]),
                "Expected AbstractList protected constructor to be registered"
            )
            let constructorInfo = try XCTUnwrap(sema.symbols.symbol(constructorSymbol))
            XCTAssertEqual(constructorInfo.kind, .constructor)
            XCTAssertEqual(constructorInfo.visibility, .protected)
            XCTAssertTrue(try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    func testAbstractSetSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let collectionSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Collection")])
            )
            let setSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Set")])
            )

            let abstractSetFQName = collectionsPkg + [ctx.interner.intern("AbstractSet")]
            let abstractSetSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractSetFQName),
                "Expected kotlin.collections.AbstractSet to be registered"
            )
            let abstractSetInfo = try XCTUnwrap(sema.symbols.symbol(abstractSetSymbol))
            XCTAssertEqual(abstractSetInfo.kind, .class)
            XCTAssertTrue(abstractSetInfo.flags.contains(.synthetic))
            XCTAssertTrue(abstractSetInfo.flags.contains(.abstractType))
            XCTAssertEqual(
                sema.types.nominalTypeParameterVariances(for: abstractSetSymbol),
                [.out]
            )

            let abstractCollectionSymbol = sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("AbstractCollection")]
            )
            let collectionSupertype = abstractCollectionSymbol ?? collectionSymbol
            let directSupertypes = sema.symbols.directSupertypes(for: abstractSetSymbol)
            XCTAssertTrue(directSupertypes.contains(collectionSupertype))
            XCTAssertTrue(directSupertypes.contains(setSymbol))
            XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: abstractSetSymbol, supertype: collectionSupertype).count, 1)
            XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: abstractSetSymbol, supertype: setSymbol).count, 1)
            XCTAssertEqual(sema.types.nominalSupertypeTypeArgs(for: abstractSetSymbol, supertype: collectionSupertype).count, 1)
            XCTAssertEqual(sema.types.nominalSupertypeTypeArgs(for: abstractSetSymbol, supertype: setSymbol).count, 1)

            let constructorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractSetFQName + [ctx.interner.intern("<init>")]),
                "Expected AbstractSet protected constructor to be registered"
            )
            let constructorInfo = try XCTUnwrap(sema.symbols.symbol(constructorSymbol))
            XCTAssertEqual(constructorInfo.kind, .constructor)
            XCTAssertEqual(constructorInfo.visibility, .protected)
            XCTAssertTrue(try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

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

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected AbstractList subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

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

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected AbstractSet subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

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

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected RandomAccess marker interface surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let randomAccessFQName = ["kotlin", "collections", "RandomAccess"]
                .map { ctx.interner.intern($0) }
            let randomAccessSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: randomAccessFQName),
                "Expected kotlin.collections.RandomAccess to be registered"
            )
            let randomAccessInfo = try XCTUnwrap(sema.symbols.symbol(randomAccessSymbol))
            XCTAssertEqual(randomAccessInfo.kind, .interface)
            XCTAssertTrue(randomAccessInfo.flags.contains(.synthetic))
            XCTAssertTrue(sema.types.nominalTypeParameterSymbols(for: randomAccessSymbol).isEmpty)
        }
    }


    func testAbstractMutableCollectionSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let collectionSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Collection")])
            )
            let mutableCollectionFQName = collectionsPkg + [ctx.interner.intern("MutableCollection")]
            let mutableCollectionSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: mutableCollectionFQName),
                "Expected kotlin.collections.MutableCollection to be registered"
            )
            XCTAssertEqual(
                sema.types.nominalTypeParameterVariances(for: mutableCollectionSymbol),
                [.invariant]
            )
            XCTAssertTrue(sema.symbols.directSupertypes(for: mutableCollectionSymbol).contains(collectionSymbol))
            XCTAssertTrue(sema.types.directNominalSupertypes(for: mutableCollectionSymbol).contains(collectionSymbol))

            let expectedMutableMembers: [(name: String, parameterCount: Int)] = [
                ("add", 1),
                ("addAll", 1),
                ("clear", 0),
                ("remove", 1),
                ("removeAll", 1),
                ("retainAll", 1),
            ]
            for expected in expectedMutableMembers {
                let memberSymbol = try XCTUnwrap(
                    sema.symbols.lookup(fqName: mutableCollectionFQName + [ctx.interner.intern(expected.name)]),
                    "Expected MutableCollection.\(expected.name) to be registered"
                )
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memberSymbol))
                XCTAssertEqual(signature.parameterTypes.count, expected.parameterCount)
            }

            let abstractMutableCollectionFQName = collectionsPkg + [ctx.interner.intern("AbstractMutableCollection")]
            let abstractMutableCollectionSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractMutableCollectionFQName),
                "Expected kotlin.collections.AbstractMutableCollection to be registered"
            )
            let abstractMutableCollectionInfo = try XCTUnwrap(sema.symbols.symbol(abstractMutableCollectionSymbol))
            XCTAssertEqual(abstractMutableCollectionInfo.kind, .class)
            XCTAssertTrue(abstractMutableCollectionInfo.flags.contains(.synthetic))
            XCTAssertTrue(abstractMutableCollectionInfo.flags.contains(.abstractType))
            XCTAssertEqual(
                sema.types.nominalTypeParameterVariances(for: abstractMutableCollectionSymbol),
                [.invariant]
            )

            let abstractCollectionSymbol = sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("AbstractCollection")]
            )
            let readonlySupertype = abstractCollectionSymbol ?? collectionSymbol
            let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableCollectionSymbol)
            XCTAssertTrue(directSupertypes.contains(readonlySupertype))
            XCTAssertTrue(directSupertypes.contains(mutableCollectionSymbol))
            XCTAssertEqual(
                sema.symbols.supertypeTypeArgs(
                    for: abstractMutableCollectionSymbol,
                    supertype: readonlySupertype
                ).count,
                1
            )
            XCTAssertEqual(
                sema.symbols.supertypeTypeArgs(
                    for: abstractMutableCollectionSymbol,
                    supertype: mutableCollectionSymbol
                ).count,
                1
            )

            let constructorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractMutableCollectionFQName + [ctx.interner.intern("<init>")]),
                "Expected AbstractMutableCollection protected constructor to be registered"
            )
            let constructorInfo = try XCTUnwrap(sema.symbols.symbol(constructorSymbol))
            XCTAssertEqual(constructorInfo.visibility, .protected)
            XCTAssertTrue(try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

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

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected AbstractMutableCollection subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testAbstractMutableSetSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let setSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Set")])
            )
            let mutableSetSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableSet")])
            )
            let abstractMutableSetFQName = collectionsPkg + [ctx.interner.intern("AbstractMutableSet")]
            let abstractMutableSetSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractMutableSetFQName),
                "Expected kotlin.collections.AbstractMutableSet to be registered"
            )
            let abstractMutableSetInfo = try XCTUnwrap(sema.symbols.symbol(abstractMutableSetSymbol))
            XCTAssertEqual(abstractMutableSetInfo.kind, .class)
            XCTAssertTrue(abstractMutableSetInfo.flags.contains(.synthetic))
            XCTAssertTrue(abstractMutableSetInfo.flags.contains(.abstractType))
            XCTAssertEqual(
                sema.types.nominalTypeParameterVariances(for: abstractMutableSetSymbol),
                [.invariant]
            )

            let abstractSetSymbol = sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("AbstractSet")]
            )
            let readonlySupertype = abstractSetSymbol ?? setSymbol
            let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableSetSymbol)
            XCTAssertTrue(directSupertypes.contains(readonlySupertype))
            XCTAssertTrue(directSupertypes.contains(mutableSetSymbol))
            XCTAssertEqual(
                sema.symbols.supertypeTypeArgs(for: abstractMutableSetSymbol, supertype: readonlySupertype).count,
                1
            )
            XCTAssertEqual(
                sema.symbols.supertypeTypeArgs(for: abstractMutableSetSymbol, supertype: mutableSetSymbol).count,
                1
            )

            let constructorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractMutableSetFQName + [ctx.interner.intern("<init>")]),
                "Expected AbstractMutableSet protected constructor to be registered"
            )
            let constructorInfo = try XCTUnwrap(sema.symbols.symbol(constructorSymbol))
            XCTAssertEqual(constructorInfo.kind, .constructor)
            XCTAssertEqual(constructorInfo.visibility, .protected)
            XCTAssertTrue(try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    func testAbstractMutableMapSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let mapSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Map")])
            )
            let mutableMapSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableMap")])
            )
            let abstractMutableMapFQName = collectionsPkg + [ctx.interner.intern("AbstractMutableMap")]
            let abstractMutableMapSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractMutableMapFQName),
                "Expected kotlin.collections.AbstractMutableMap to be registered"
            )
            let abstractMutableMapInfo = try XCTUnwrap(sema.symbols.symbol(abstractMutableMapSymbol))
            XCTAssertEqual(abstractMutableMapInfo.kind, .class)
            XCTAssertTrue(abstractMutableMapInfo.flags.contains(.synthetic))
            XCTAssertTrue(abstractMutableMapInfo.flags.contains(.abstractType))
            XCTAssertEqual(
                sema.types.nominalTypeParameterVariances(for: abstractMutableMapSymbol),
                [.invariant, .invariant]
            )

            let abstractMapSymbol = sema.symbols.lookup(
                fqName: collectionsPkg + [ctx.interner.intern("AbstractMap")]
            )
            let readonlySupertype = abstractMapSymbol ?? mapSymbol
            let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableMapSymbol)
            XCTAssertTrue(directSupertypes.contains(readonlySupertype))
            XCTAssertTrue(directSupertypes.contains(mutableMapSymbol))
            XCTAssertEqual(
                sema.symbols.supertypeTypeArgs(for: abstractMutableMapSymbol, supertype: readonlySupertype).count,
                2
            )
            XCTAssertEqual(
                sema.symbols.supertypeTypeArgs(for: abstractMutableMapSymbol, supertype: mutableMapSymbol).count,
                2
            )

            let constructorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: abstractMutableMapFQName + [ctx.interner.intern("<init>")]),
                "Expected AbstractMutableMap protected constructor to be registered"
            )
            let constructorInfo = try XCTUnwrap(sema.symbols.symbol(constructorSymbol))
            XCTAssertEqual(constructorInfo.kind, .constructor)
            XCTAssertEqual(constructorInfo.visibility, .protected)
            XCTAssertTrue(try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)
        }
    }

    func testAbstractMutableSetCanBeUsedAsSetAndMutableSetSupertype() throws {
        let source = """
        import kotlin.collections.AbstractMutableSet
        import kotlin.collections.Set
        import kotlin.collections.MutableSet

        class ProbeMutableSet : AbstractMutableSet<Int>()

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

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected AbstractMutableSet subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testAbstractMutableMapCanBeUsedAsMapAndMutableMapSupertype() throws {
        let source = """
        import kotlin.collections.AbstractMutableMap
        import kotlin.collections.Map
        import kotlin.collections.MutableMap

        class ProbeMutableMap : AbstractMutableMap<String, Int>()

        fun acceptReadonly(values: Map<String, Int>) {}
        fun acceptMutable(values: MutableMap<String, Int>) {}

        fun probe(values: ProbeMutableMap) {
            acceptReadonly(values)
            acceptMutable(values)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected AbstractMutableMap subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testMutableListIteratorSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let listIteratorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("ListIterator")])
            )
            let mutableIteratorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableIterator")])
            )

            let mutableListIteratorFQName = collectionsPkg + [ctx.interner.intern("MutableListIterator")]
            let mutableListIteratorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: mutableListIteratorFQName),
                "Expected kotlin.collections.MutableListIterator to be registered"
            )
            let mutableListIteratorInfo = try XCTUnwrap(sema.symbols.symbol(mutableListIteratorSymbol))
            XCTAssertEqual(mutableListIteratorInfo.kind, .interface)
            XCTAssertTrue(mutableListIteratorInfo.flags.contains(.synthetic))
            XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: mutableListIteratorSymbol), [.invariant])

            let directSupertypes = sema.symbols.directSupertypes(for: mutableListIteratorSymbol)
            XCTAssertTrue(directSupertypes.contains(listIteratorSymbol))
            XCTAssertTrue(directSupertypes.contains(mutableIteratorSymbol))
            XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: mutableListIteratorSymbol, supertype: listIteratorSymbol).count, 1)
            XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: mutableListIteratorSymbol, supertype: mutableIteratorSymbol).count, 1)

            for memberName in ["add", "set"] {
                let memberSymbol = try XCTUnwrap(
                    sema.symbols.lookup(fqName: mutableListIteratorFQName + [ctx.interner.intern(memberName)]),
                    "Expected MutableListIterator.\(memberName) to be registered"
                )
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memberSymbol))
                XCTAssertEqual(signature.parameterTypes.count, 1)
                XCTAssertEqual(signature.returnType, sema.types.unitType)
            }
            let removeSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: mutableListIteratorFQName + [ctx.interner.intern("remove")]),
                "Expected MutableListIterator.remove to be registered"
            )
            let removeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: removeSymbol))
            XCTAssertTrue(removeSignature.parameterTypes.isEmpty)
            XCTAssertEqual(removeSignature.returnType, sema.types.unitType)

            let mutableListSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableList")])
            )
            let listIteratorMember = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: collectionsPkg + [ctx.interner.intern("MutableList"), ctx.interner.intern("listIterator")]
                ),
                "Expected MutableList.listIterator to be registered"
            )
            XCTAssertEqual(sema.symbols.parentSymbol(for: listIteratorMember), mutableListSymbol)
            let listIteratorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: listIteratorMember))
            guard case let .classType(returnType) = sema.types.kind(of: listIteratorSignature.returnType) else {
                XCTFail("MutableList.listIterator should return MutableListIterator<E>")
                return
            }
            XCTAssertEqual(returnType.classSymbol, mutableListIteratorSymbol)
        }
    }

    func testMutableIterableSurfaceIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let collectionsPkg = ["kotlin", "collections"].map { ctx.interner.intern($0) }
            let iterableSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Iterable")])
            )
            let iteratorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("Iterator")])
            )
            let mutableIteratorSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableIterator")])
            )
            XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: mutableIteratorSymbol), [.out])
            XCTAssertTrue(sema.symbols.directSupertypes(for: mutableIteratorSymbol).contains(iteratorSymbol))
            XCTAssertEqual(
                sema.symbols.supertypeTypeArgs(for: mutableIteratorSymbol, supertype: iteratorSymbol).count,
                1
            )
            let removeSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern("MutableIterator"), ctx.interner.intern("remove")])
            )
            let removeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: removeSymbol))
            XCTAssertTrue(removeSignature.parameterTypes.isEmpty)
            XCTAssertEqual(removeSignature.returnType, sema.types.unitType)

            let mutableIterableFQName = collectionsPkg + [ctx.interner.intern("MutableIterable")]
            let mutableIterableSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: mutableIterableFQName),
                "Expected kotlin.collections.MutableIterable to be registered"
            )
            let mutableIterableInfo = try XCTUnwrap(sema.symbols.symbol(mutableIterableSymbol))
            XCTAssertEqual(mutableIterableInfo.kind, .interface)
            XCTAssertTrue(mutableIterableInfo.flags.contains(.synthetic))
            XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: mutableIterableSymbol), [.out])
            XCTAssertTrue(sema.symbols.directSupertypes(for: mutableIterableSymbol).contains(iterableSymbol))
            XCTAssertTrue(sema.types.directNominalSupertypes(for: mutableIterableSymbol).contains(iterableSymbol))
            XCTAssertEqual(sema.symbols.supertypeTypeArgs(for: mutableIterableSymbol, supertype: iterableSymbol).count, 1)

            let iteratorMember = try XCTUnwrap(
                sema.symbols.lookup(fqName: mutableIterableFQName + [ctx.interner.intern("iterator")]),
                "Expected MutableIterable.iterator to be registered"
            )
            XCTAssertTrue(try XCTUnwrap(sema.symbols.symbol(iteratorMember)).flags.contains(.operatorFunction))
            let iteratorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: iteratorMember))
            XCTAssertTrue(iteratorSignature.parameterTypes.isEmpty)
            guard case let .classType(iteratorReturnType) = sema.types.kind(of: iteratorSignature.returnType) else {
                XCTFail("MutableIterable.iterator should return MutableIterator<T>")
                return
            }
            XCTAssertEqual(iteratorReturnType.classSymbol, mutableIteratorSymbol)

            for collectionName in ["MutableList", "MutableSet"] {
                let collectionSymbol = try XCTUnwrap(
                    sema.symbols.lookup(fqName: collectionsPkg + [ctx.interner.intern(collectionName)])
                )
                XCTAssertTrue(sema.symbols.directSupertypes(for: collectionSymbol).contains(mutableIterableSymbol))
                XCTAssertTrue(sema.types.directNominalSupertypes(for: collectionSymbol).contains(mutableIterableSymbol))
                XCTAssertEqual(
                    sema.symbols.supertypeTypeArgs(for: collectionSymbol, supertype: mutableIterableSymbol).count,
                    1
                )
            }
        }
    }

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

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected MutableListIterator surface to resolve from MutableList: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

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

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected MutableIterable subtype surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testSetFallbackRejectsListOnlyIndexedLookups() throws {
        let source = """
        fun firstValue(values: Set<Int>): Int? = values.firstOrNull()
        fun lastValue(values: Set<Int>): Int? = values.lastOrNull()
        fun fallbackValue(values: Set<Int>): Int = values.getOrElse(0) { -1 }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            for memberName in ["firstOrNull", "lastOrNull", "getOrElse"] {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName)")
                XCTAssertNil(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected Set.\(memberName) to remain unresolved"
                )
            }

            XCTAssertFalse(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected diagnostics for Set indexed lookup fallbacks"
            )
        }
    }

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

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let listCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "getOrElse",
                      let receiverExpr = ast.arena.expr(receiver),
                      case let .nameRef(receiverName, _) = receiverExpr
                else { return false }
                return ctx.interner.resolve(receiverName) == "list"
            }, "Expected a getOrElse member call")
            let listCallee = try XCTUnwrap(sema.bindings.callBinding(for: listCall)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: listCallee), "kk_list_getOrElse")

            let mapCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "getOrElse",
                      let receiverExpr = ast.arena.expr(receiver),
                      case let .nameRef(receiverName, _) = receiverExpr
                else { return false }
                return ctx.interner.resolve(receiverName) == "map"
            }, "Expected a getOrElse member call")
            let mapCallee = try XCTUnwrap(sema.bindings.callBinding(for: mapCall)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: mapCallee), "kk_map_getOrElse")

            let mutableCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(receiver, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "getOrPut",
                      let receiverExpr = ast.arena.expr(receiver),
                      case let .nameRef(receiverName, _) = receiverExpr
                else { return false }
                return ctx.interner.resolve(receiverName) == "mutableMap"
            }, "Expected a getOrPut member call")
            let mutableCallee = try XCTUnwrap(sema.bindings.callBinding(for: mutableCall)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: mutableCallee), "kk_mutable_map_getOrPut")
        }
    }

    func testMapGetOrElseAssignsLambdaExpectedTypeToLambdaArgument() throws {
        let source = """
        fun useMapDefault(values: Map<String, Int>): Int {
            return values.getOrElse("z") { 99 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "getOrElse"
                },
                "Expected member call to getOrElse"
            )
            XCTAssertEqual(
                sema.bindings.exprType(for: callExpr),
                sema.types.intType,
                "Expected getOrElse result to be Int"
            )
            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected map getOrElse fallback to resolve without diagnostics, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }



    func testListBinarySearchHasComparableElementUpperBound() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookupAll(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("collections"),
                        ctx.interner.intern("List"),
                        ctx.interner.intern("binarySearch"),
                    ]
                ).first(where: { sema.symbols.externalLinkName(for: $0) == "kk_list_binarySearch" }),
                "Expected synthetic List member binarySearch to be registered"
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertEqual(signature.typeParameterUpperBoundsList.count, 1)
            let upperBounds = signature.typeParameterUpperBoundsList[0]
            XCTAssertEqual(upperBounds.count, 1, "Expected Comparable upper bound for binarySearch element type")

            guard case let .classType(boundType) = sema.types.kind(of: upperBounds[0]) else {
                return XCTFail("Expected binarySearch upper bound to be a class type")
            }

            XCTAssertEqual(boundType.classSymbol, sema.types.comparableInterfaceSymbol)
            XCTAssertEqual(boundType.args.count, 1)

            guard case let .invariant(argumentType) = boundType.args[0] else {
                return XCTFail("Expected Comparable upper bound to reference invariant element type")
            }

            let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0],
                nullability: .nonNull
            )))
            XCTAssertEqual(argumentType, expectedElementType)
        }
    }

    func testListBinarySearchComparatorOverloadHasDefaultedRange() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let listSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("collections"),
                    ctx.interner.intern("List"),
                ])
            )
            let symbolID = try XCTUnwrap(
                sema.symbols.lookupByShortName(ctx.interner.intern("binarySearch")).first(where: { candidate in
                    sema.symbols.parentSymbol(for: candidate) == listSymbol
                        && sema.symbols.externalLinkName(for: candidate) == "kk_list_binarySearch_comparator"
                }),
                "Expected synthetic List member binarySearch comparator overload to be registered"
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertEqual(signature.parameterTypes.count, 4)
            XCTAssertEqual(signature.valueParameterSymbols.count, 4)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, false, true, true])
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)
            XCTAssertEqual(signature.classTypeParameterCount, 1)
            XCTAssertTrue(signature.typeParameterUpperBoundsList.isEmpty)

            let parameterNames = signature.valueParameterSymbols.compactMap { paramSymbol in
                sema.symbols.symbol(paramSymbol)?.name
            }.map { ctx.interner.resolve($0) }
            XCTAssertEqual(parameterNames, ["element", "comparator", "fromIndex", "toIndex"])

            XCTAssertEqual(signature.parameterTypes[0], sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0],
                nullability: .nonNull
            ))))
            XCTAssertEqual(signature.parameterTypes[2], sema.types.intType)
            XCTAssertEqual(signature.parameterTypes[3], sema.types.intType)

            if let comparatorSymbol = sema.symbols.lookupByShortName(ctx.interner.intern("Comparator")).first,
               case let .classType(comparatorClassType) = sema.types.kind(of: signature.parameterTypes[1])
            {
                XCTAssertEqual(comparatorClassType.classSymbol, comparatorSymbol)
                XCTAssertEqual(comparatorClassType.args.count, 1)
            } else {
                guard case let .functionType(comparatorFunctionType) = sema.types.kind(of: signature.parameterTypes[1]) else {
                    return XCTFail("Expected binarySearch comparator parameter to be Comparator<T> or a comparator function type")
                }
                XCTAssertEqual(comparatorFunctionType.params.count, 2)
                XCTAssertEqual(comparatorFunctionType.returnType, sema.types.intType)
            }
        }
    }

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

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let expectedOverloads: [(externalLinkName: String, parameterCount: Int)] = [
                ("kk_list_binarySearchBy", 2),
                ("kk_list_binarySearchBy_fromIndex", 3),
                ("kk_list_binarySearchBy_range", 4),
            ]

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
            XCTAssertEqual(callExprIDs.count, expectedOverloads.count, "Expected three binarySearchBy calls")

            for (index, callExprID) in callExprIDs.enumerated() {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExprID)?.chosenCallee,
                    "Expected a chosen callee for binarySearchBy overload \(index)"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    expectedOverloads[index].externalLinkName,
                    "Expected binarySearchBy overload \(index) to resolve to \(expectedOverloads[index].externalLinkName)"
                )
                XCTAssertEqual(
                    sema.bindings.exprType(for: callExprID),
                    sema.types.intType,
                    "Expected binarySearchBy overload \(index) to return Int"
                )
            }

            let listFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
                ctx.interner.intern("binarySearchBy"),
            ]

            for overload in expectedOverloads {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookupAll(fqName: listFQName).first(where: {
                        sema.symbols.externalLinkName(for: $0) == overload.externalLinkName
                    }),
                    "Expected synthetic List member \(overload.externalLinkName) to be registered"
                )
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                XCTAssertEqual(signature.returnType, sema.types.intType)
                XCTAssertEqual(signature.parameterTypes.count, overload.parameterCount)
                XCTAssertEqual(signature.typeParameterSymbols.count, 2)
                XCTAssertEqual(signature.typeParameterUpperBoundsList.count, 2)

                let selectorType = try XCTUnwrap(signature.parameterTypes.last)
                guard case let .functionType(functionType) = sema.types.kind(of: selectorType) else {
                    return XCTFail("Expected selector parameter for \(overload.externalLinkName) to be a function type")
                }
                XCTAssertEqual(functionType.params.count, 1)

                let expectedListElementType = sema.types.make(.typeParam(TypeParamType(
                    symbol: signature.typeParameterSymbols[0],
                    nullability: .nonNull
                )))
                XCTAssertEqual(functionType.params[0], expectedListElementType)
                XCTAssertEqual(functionType.returnType, signature.parameterTypes[0])

                let keyUpperBounds = signature.typeParameterUpperBoundsList[1]
                XCTAssertEqual(keyUpperBounds.count, 1, "Expected Comparable upper bound for \(overload.externalLinkName) key type")
                guard case let .classType(boundType) = sema.types.kind(of: keyUpperBounds[0]) else {
                    return XCTFail("Expected \(overload.externalLinkName) upper bound to be a class type")
                }
                XCTAssertEqual(boundType.classSymbol, sema.types.comparableInterfaceSymbol)
                XCTAssertEqual(boundType.args.count, 1)

                guard case let .invariant(argumentType) = boundType.args[0] else {
                    return XCTFail("Expected \(overload.externalLinkName) upper bound to reference invariant key type")
                }

                let expectedKeyType = sema.types.make(.typeParam(TypeParamType(
                    symbol: signature.typeParameterSymbols[1],
                    nullability: .nonNull
                )))
                XCTAssertEqual(argumentType, expectedKeyType)
                XCTAssertEqual(signature.parameterTypes[0], sema.types.makeNullable(expectedKeyType))

                if overload.parameterCount >= 3 {
                    XCTAssertEqual(signature.parameterTypes[1], sema.types.intType)
                }
                if overload.parameterCount == 4 {
                    XCTAssertEqual(signature.parameterTypes[2], sema.types.intType)
                }
            }
        }
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
        return try XCTUnwrap(nil as TypeID?, "Expected concrete type projection", file: file, line: line)
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
        return XCTFail("Expected List type", file: file, line: line)
    }
    XCTAssertEqual(
        try interner.resolve(XCTUnwrap(sema.symbols.symbol(listType.classSymbol)?.name, file: file, line: line)),
        "List",
        file: file,
        line: line
    )
    XCTAssertEqual(listType.args.count, 1, file: file, line: line)
    let elementType = try projectedType(try XCTUnwrap(listType.args.first, file: file, line: line), file: file, line: line)
    XCTAssertEqual(elementType, expectedElementType, file: file, line: line)
}
