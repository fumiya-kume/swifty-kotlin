@testable import CompilerCore
import Foundation
import XCTest

final class ListSyntheticMemberLinkTests: XCTestCase {
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

    func testLinkedSetOfFactoryInfersMutableSetType() throws {
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
                return XCTFail("Expected linkedSetOf to produce a MutableSet class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)), "MutableSet")
            XCTAssertEqual(classType.args, [.invariant(sema.types.intType)])
            XCTAssertTrue(
                sema.bindings.isCollectionExpr(linkedSetCall),
                "Expected linkedSetOf to be tracked as a collection expression"
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
                "sumOf": "kk_list_sumOf",
                "maxOrNull": "kk_list_maxOrNull",
                "minOrNull": "kk_list_minOrNull",
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

    func testListSortedAndSortedDescendingHaveComparableUpperBound() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let baseFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
            ]
            let memberCases: [(String, String)] = [
                ("sorted", "kk_list_sorted"),
                ("sortedDescending", "kk_list_sortedDescending"),
            ]

            for (memberName, externalLinkName) in memberCases {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookupAll(
                        fqName: baseFQName + [ctx.interner.intern(memberName)]
                    ).first(where: { sema.symbols.externalLinkName(for: $0) == externalLinkName }),
                    "Expected synthetic List member \(memberName) to be registered"
                )
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                XCTAssertEqual(signature.typeParameterUpperBoundsList.count, 1)
                let upperBounds = signature.typeParameterUpperBoundsList[0]
                XCTAssertEqual(upperBounds.count, 1, "Expected Comparable upper bound for \(memberName) element type")

                guard case let .classType(boundType) = sema.types.kind(of: upperBounds[0]) else {
                    return XCTFail("Expected \(memberName) upper bound to be a class type")
                }

                XCTAssertEqual(boundType.classSymbol, sema.types.comparableInterfaceSymbol)
                XCTAssertEqual(boundType.args.count, 1)

                guard case let .invariant(argumentType) = boundType.args[0] else {
                    return XCTFail("Expected \(memberName) upper bound to reference invariant element type")
                }

                let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                    symbol: signature.typeParameterSymbols[0],
                    nullability: .nonNull
                )))
                XCTAssertEqual(argumentType, expectedElementType)
            }
        }
    }

    func testListSortedAndSortedDescendingRequireComparableElements() throws {
        let source = """
        class Box

        fun render(values: List<Box>) {
            values.sorted()
            values.sortedDescending()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            let boundDiagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-BOUND" }
            XCTAssertEqual(boundDiagnostics.count, 2, "Expected bound diagnostics for sorted/sortedDescending")
        }
    }

    func testListConversionMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun convert(values: List<Int>) {
            values.toMutableList()
            values.toSet()
            values.joinToString(", ")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks = [
                "toMutableList": "kk_list_to_mutable_list",
                "toSet": "kk_list_to_set",
                "joinToString": "kk_list_joinToString",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                if memberName == "addAll" {
                    let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("collections"),
                        ctx.interner.intern("MutableSet"),
                        ctx.interner.intern(memberName),
                    ]))
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: symbol),
                        externalLinkName,
                        "Expected \(memberName) to resolve to \(externalLinkName)"
                    )
                } else {
                    let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return ctx.interner.resolve(callee) == memberName
                    }, "Expected member call to \(memberName) in AST")
                    let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: chosenCallee),
                        externalLinkName,
                        "Expected \(memberName) to resolve to \(externalLinkName)"
                    )
                }
            }
        }
    }

    func testSetBinaryMembersKeepSetResultTypeInFallbackPath() throws {
        let source = """
        fun combine(values: Set<Int>, other: Set<Int>) {
            val left = values.intersect(other)
            val middle = values.union(other)
            val right = values.subtract(other)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let expectedMembers = Set(["intersect", "union", "subtract"])
            let setResultTypes: [String: TypeID] = Dictionary(uniqueKeysWithValues: ast.arena.exprs.indices.compactMap { index in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr
                else {
                    return nil
                }
                let memberName = ctx.interner.resolve(callee)
                guard expectedMembers.contains(memberName),
                      let type = sema.bindings.exprType(for: exprID)
                else {
                    return nil
                }
                return (memberName, type)
            })

            XCTAssertEqual(setResultTypes.keys.count, expectedMembers.count)

            for memberName in expectedMembers {
                let type = try XCTUnwrap(setResultTypes[memberName], "Expected inferred type for \(memberName)")
                guard case let .classType(classType) = sema.types.kind(of: type) else {
                    return XCTFail("Expected \(memberName) to infer as Set<Int>, got \(sema.types.kind(of: type))")
                }
                XCTAssertEqual(
                    try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)),
                    "Set"
                )
                XCTAssertEqual(classType.args.count, 1, "Expected Set<Int> type argument for \(memberName)")
                let elementType: TypeID
                switch classType.args[0] {
                case let .invariant(type), let .out(type), let .in(type):
                    elementType = type
                case .star:
                    return XCTFail("Expected concrete Set element projection for \(memberName)")
                }
                XCTAssertEqual(sema.types.kind(of: elementType), .primitive(.int, .nonNull))
            }
        }
    }

    func testSequenceJoinToStringUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: Sequence<Int>) {
            println(values.joinToString(", "))
            println(values.joinToString(prefix = "<", postfix = ">"))
        }
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
                return ctx.interner.resolve(callee) == "joinToString"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_sequence_joinToString")
        }
    }

    func testSequenceReduceIndexedOrNullUsesRuntimeExternalLink() throws {
        let source = """
        fun render(values: Sequence<Int>) {
            println(values.reduceIndexedOrNull { index, acc, value -> acc + index * value })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let sequenceReduceIndexedOrNullSymbol = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("sequences"),
                        ctx.interner.intern("Sequence"),
                        ctx.interner.intern("reduceIndexedOrNull"),
                    ]
                ),
                "Expected synthetic Sequence.reduceIndexedOrNull member to be registered"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: sequenceReduceIndexedOrNullSymbol),
                "kk_sequence_reduceIndexedOrNull"
            )
        }
    }

    func testSequenceFlatMapIndexedRegistersIterableAndSequenceOverloads() throws {
        let source = """
        fun render(values: Sequence<Int>) {
            val iterableResult = values.flatMapIndexed { index, value -> listOf(index, value * 10) }
            val sequenceResult = values.flatMapIndexed { index, value -> sequenceOf(index + value, value * 100) }
            println(iterableResult.toList())
            println(sequenceResult.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("flatMapIndexed"),
            ]
            let symbols = sema.symbols.lookupAll(fqName: memberFQName)
            XCTAssertEqual(symbols.count, 2, "Expected Iterable and Sequence flatMapIndexed overloads")
            XCTAssertTrue(symbols.allSatisfy {
                sema.symbols.externalLinkName(for: $0) == "kk_sequence_flatMapIndexed"
            })

            let transformReturnTypeNames = symbols.compactMap { symbolID -> String? in
                guard let parameterType = sema.symbols.functionSignature(for: symbolID)?.parameterTypes.first,
                      case let .functionType(functionType) = sema.types.kind(of: parameterType),
                      case let .classType(returnClassType) = sema.types.kind(of: sema.types.makeNonNullable(functionType.returnType)),
                      let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
                else { return nil }
                return ctx.interner.resolve(returnSymbol.name)
            }
            XCTAssertTrue(transformReturnTypeNames.contains("Iterable"))
            XCTAssertTrue(transformReturnTypeNames.contains("Sequence"))
        }
    }

    func testSequenceShuffledUsesRuntimeExternalLinks() throws {
        let source = """
        import kotlin.random.Random

        fun render(values: Sequence<Int>) {
            values.shuffled()
            values.shuffled(Random)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("shuffled"),
            ]
            let externalLinks = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                sema.symbols.externalLinkName(for: $0)
            })
            XCTAssertTrue(externalLinks.contains("kk_sequence_shuffled"))
            XCTAssertTrue(externalLinks.contains("kk_sequence_shuffled_random"))
        }
    }

    func testSequenceRequireNoNullsSyntheticStubHasRuntimeExternalLink() throws {
        let source = """
        fun render(values: Sequence<Int?>) {
            val result: Sequence<Int> = values.requireNoNulls()
            println(result.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("requireNoNulls"),
            ]
            XCTAssertTrue(sema.symbols.lookupAll(fqName: fqName).contains { candidate in
                sema.symbols.externalLinkName(for: candidate) == "kk_sequence_requireNoNulls"
            })
        }
    }

    func testMutableListMutationMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.add(1)
            values.add(1, 0)
            values.addAll(listOf(2, 3))
            values.removeAll(listOf(4))
            values.retainAll(listOf(5))
            values.removeAt(0)
            values.removeFirstOrNull()
            values.removeLastOrNull()
            values.clear()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks: [(String, Int, String)] = [
                ("add", 1, "kk_mutable_list_add"),
                ("add", 2, "kk_mutable_list_add_at"),
                ("addAll", 1, "kk_mutable_list_addAll"),
                ("removeAll", 1, "kk_mutable_list_removeAll"),
                ("retainAll", 1, "kk_mutable_list_retainAll"),
                ("removeAt", 1, "kk_mutable_list_removeAt"),
                ("removeFirstOrNull", 0, "kk_mutable_list_removeFirstOrNull"),
                ("removeLastOrNull", 0, "kk_mutable_list_removeLastOrNull"),
                ("clear", 0, "kk_mutable_list_clear"),
            ]

            for (memberName, argumentCount, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, valueArgs, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName && valueArgs.count == argumentCount
                }, "Expected member call to \(memberName) with \(argumentCount) arguments in AST")
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName)/\(argumentCount) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testMutableListBulkMutationFallbacksReturnBoolean() throws {
        let source = """
        fun mutate(): Boolean {
            val values = listOf(1, 2, 3).toMutableList()
            return values.addAll(listOf(4))
                || values.removeAll(listOf(5))
                || values.retainAll(listOf(1, 2))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("collections"),
                            ctx.interner.intern("MutableList"),
                            ctx.interner.intern(memberName),
                        ]
                    ),
                    "Expected synthetic MutableList member \(memberName) to be registered"
                )

                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: symbolID),
                    "kk_mutable_list_\(memberName)",
                    "Expected \(memberName) to resolve to runtime extern"
                )
                XCTAssertEqual(
                    sema.bindings.exprTypes[callExpr],
                    sema.types.booleanType,
                    "Expected \(memberName) to return Boolean"
                )
                XCTAssertFalse(
                    sema.bindings.isCollectionExpr(callExpr),
                    "Expected \(memberName) result to remain a scalar Boolean"
                )
            }
        }
    }

    func testMutableListSortMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.sort()
            values.sortBy { it }
            values.sortByDescending { it }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
            let expectedExternalLinks = [
                "sort": "kk_mutable_list_sort",
                "sortBy": "kk_mutable_list_sortBy",
                "sortByDescending": "kk_mutable_list_sortByDescending",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                if let chosenCallee = sema.bindings.callBinding(for: callExpr)?.chosenCallee {
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: chosenCallee),
                        externalLinkName,
                        "Expected \(memberName) to resolve to \(externalLinkName)"
                    )
                }
            }
        }
    }

    func testMutableListBulkMutationMembersUseInvariantReceiverTypes() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let ownerFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: ownerFQName + [interner.intern(memberName)]))
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                guard case let .classType(receiverType) = sema.types.kind(of: try XCTUnwrap(signature.receiverType)) else {
                    return XCTFail("Expected \(memberName) to use MutableList receiver type")
                }
                guard case .invariant = try XCTUnwrap(receiverType.args.first) else {
                    return XCTFail("Expected \(memberName) receiver projection to remain invariant")
                }
            }
        }
    }

    func testMutableListBulkCollectionMembersAcceptCollectionOfSameElementType() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.addAll(listOf(1, 2))
            values.removeAll(listOf(3, 4))
            values.retainAll(listOf(5, 6))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks = [
                "addAll": "kk_mutable_list_addAll",
                "removeAll": "kk_mutable_list_removeAll",
                "retainAll": "kk_mutable_list_retainAll",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    func testMutableListBulkCollectionMembersKeepInvariantReceiverType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let mutableListFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(fqName: mutableListFQName + [ctx.interner.intern(memberName)]),
                    "Expected synthetic MutableList member \(memberName) to be registered"
                )
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                let receiverType = try XCTUnwrap(signature.receiverType)
                guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
                    return XCTFail("Expected \(memberName) receiver to be a class type")
                }
                guard case .invariant = try XCTUnwrap(receiverClassType.args.first) else {
                    return XCTFail(
                        "Expected \(memberName) receiver to keep invariant element type, got \(sema.types.renderType(receiverType))"
                    )
                }

                let parameterType = try XCTUnwrap(signature.parameterTypes.first)
                guard case let .classType(parameterClassType) = sema.types.kind(of: parameterType) else {
                    return XCTFail("Expected \(memberName) parameter to be a class type")
                }
                guard case .out = try XCTUnwrap(parameterClassType.args.first) else {
                    return XCTFail(
                        "Expected \(memberName) parameter to remain covariant Collection<out E>, got \(sema.types.renderType(parameterType))"
                    )
                }
            }
        }
    }

    func testOutProjectedMutableListBlocksBulkMutationMembers() throws {
        let source = """
        fun mutate(values: MutableList<out Number>) {
            values.addAll(listOf(1, 2))
            values.removeAll(listOf(3, 4))
            values.retainAll(listOf(5, 6))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-VAR-OUT" }
            XCTAssertEqual(diagnostics.count, 3, "Projected MutableList bulk writes should be rejected")
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    func testListSortMembersRemainUnavailableOnImmutableList() throws {
        let source = """
        fun mutate(values: List<Int>) {
            values.sort()
            values.sortBy { it }
            values.sortByDescending { it }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            for memberName in ["sort", "sortBy", "sortByDescending"] {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                XCTAssertNil(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected immutable List.\(memberName) to remain unresolved"
                )
            }

            XCTAssertFalse(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected diagnostics for immutable List.sort* calls"
            )
        }
    }

    func testMutableListBulkOperationsAcceptListArguments() throws {
        let source = """
        fun mutate(values: MutableList<Int>) {
            values.addAll(listOf(1, 2))
            values.removeAll(listOf(1))
            values.retainAll(listOf(2))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    func testMutableListMatchesTransitiveCollectionConstraint() throws {
        let source = """
        fun <T> consume(values: Collection<T>): T? = values.firstOrNull()

        fun demo(values: MutableList<Int>): Int? = consume(values)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let consumeCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "consume"
            }, "Expected consume(values) call in AST")

            XCTAssertNotNil(
                sema.bindings.callBinding(for: consumeCall)?.chosenCallee,
                "Expected MutableList<Int> to satisfy Collection<T> through transitive lifting"
            )
        }
    }

    func testListIteratorMemberResolvesWithoutTypeConstraintFailure() throws {
        let source = """
        class IntContainer(private val elements: List<Int>) {
            operator fun iterator(): Iterator<Int> = elements.iterator()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let iteratorCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "iterator"
            }, "Expected List.iterator() call in AST")

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: iteratorCall)?.chosenCallee,
                "Expected List.iterator() to resolve"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_range_iterator"
            )
        }
    }

    /// Regression: listOf(...).contains/isEmpty must not emit KSWIFTK-SEMA-VAR-OUT.
    /// The synthetic List type uses .out projection; variance relaxation must apply.
    func testListOfContainsAndIsEmptyDoNotEmitVarOut() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            list.contains(2)
            list.contains(5)
            list.isEmpty()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            var containsCalls: [ExprID] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "contains"
                else { continue }
                containsCalls.append(exprID)
            }
            XCTAssertEqual(containsCalls.count, 2)
            for callID in containsCalls {
                let binding = sema.bindings.callBinding(for: callID)
                XCTAssertNotNil(binding?.chosenCallee, "contains should resolve")
                if let chosen = binding?.chosenCallee {
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: chosen),
                        "kk_list_contains",
                        "contains should resolve to kk_list_contains"
                    )
                }
            }
        }
    }

    func testSetMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun check(values: Set<Int>) {
            values.contains(42)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "contains"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_set_contains",
                "Expected contains to resolve to kk_set_contains"
            )
        }
    }

    func testSetRegistersCollectionAsNominalSupertype() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let setSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
            ]))
            let collectionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Collection"),
            ]))

            XCTAssertEqual(
                sema.types.directNominalSupertypes(for: setSymbol),
                [collectionSymbol],
                "Expected Set to register Collection as its nominal supertype"
            )
        }
    }

    func testContainsAllMembersUseCollectionRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let listContainsAll = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
                ctx.interner.intern("containsAll"),
            ]))
            let setContainsAll = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
                ctx.interner.intern("containsAll"),
            ]))

            XCTAssertEqual(sema.symbols.externalLinkName(for: listContainsAll), "kk_list_containsAll")
            XCTAssertEqual(sema.symbols.externalLinkName(for: setContainsAll), "kk_set_containsAll")
        }
    }

    func testSetContainsAllUsesCollectionParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let setContainsAll = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
                ctx.interner.intern("containsAll"),
            ]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: setContainsAll))
            let parameterType = try XCTUnwrap(signature.parameterTypes.first)

            guard case let .classType(collectionType) = sema.types.kind(of: parameterType) else {
                return XCTFail("Set.containsAll should accept Collection<E>")
            }

            XCTAssertEqual(
                try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(collectionType.classSymbol)?.name)),
                "Collection"
            )
            guard case let .out(elementType) = try XCTUnwrap(collectionType.args.first) else {
                return XCTFail("Collection parameter should preserve the element projection")
            }
            let typeParamSymbol = try XCTUnwrap(signature.typeParameterSymbols.first)
            let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                symbol: typeParamSymbol,
                nullability: .nonNull
            )))
            XCTAssertEqual(elementType, expectedElementType)
        }
    }

    func testContainsMembersAreMarkedOperatorFunctions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let listContains = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
                ctx.interner.intern("contains"),
            ]))
            let setContains = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Set"),
                ctx.interner.intern("contains"),
            ]))
            let stringContains = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("text"),
                ctx.interner.intern("contains"),
            ]))

            XCTAssertTrue(sema.symbols.symbol(listContains)?.flags.contains(.operatorFunction) == true)
            XCTAssertTrue(sema.symbols.symbol(setContains)?.flags.contains(.operatorFunction) == true)
            XCTAssertTrue(sema.symbols.symbol(stringContains)?.flags.contains(.operatorFunction) == true)
        }
    }

    func testWithIndexUsesIterableOfIndexedValueSignature() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let withIndexSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
                ctx.interner.intern("withIndex"),
            ]))
            let indexedValueSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("IndexedValue"),
            ]))
            let indexedValueRecord = try XCTUnwrap(sema.symbols.symbol(indexedValueSymbol))
            XCTAssertEqual(indexedValueRecord.kind, .class)
            XCTAssertTrue(indexedValueRecord.flags.contains(.dataType))

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: withIndexSymbol))
            guard case let .classType(iterableType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected withIndex() to return Iterable<IndexedValue<T>>")
            }
            XCTAssertEqual(
                try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(iterableType.classSymbol)?.name)),
                "Iterable"
            )
            guard case let .out(elementType) = try XCTUnwrap(iterableType.args.first),
                  case let .classType(indexedValueType) = sema.types.kind(of: elementType)
            else {
                return XCTFail("Expected Iterable element type to be IndexedValue")
            }
            XCTAssertEqual(indexedValueType.classSymbol, indexedValueSymbol)
        }
    }

    func testMutableSetMutationMembersUseRuntimeExternalLinks() throws {
        let source = """
        fun mutate(values: MutableSet<Int>) {
            values.add(1)
            values.remove(1)
            values.addAll(listOf(2, 3))
            values.addAll(setOf(2, 3))
            values.clear()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedExternalLinks = [
                "add": "kk_mutable_set_add",
                "remove": "kk_mutable_set_remove",
                "addAll": "kk_mutable_set_addAll",
                "clear": "kk_mutable_set_clear",
            ]

            for (memberName, externalLinkName) in expectedExternalLinks {
                if memberName == "addAll" {
                    let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("collections"),
                        ctx.interner.intern("MutableSet"),
                        ctx.interner.intern(memberName),
                    ]))
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: symbol),
                        externalLinkName,
                        "Expected \(memberName) to resolve to \(externalLinkName)"
                    )
                } else {
                    let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return ctx.interner.resolve(callee) == memberName
                    }, "Expected member call to \(memberName) in AST")
                    let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: chosenCallee),
                        externalLinkName,
                        "Expected \(memberName) to resolve to \(externalLinkName)"
                    )
                }
            }

            let addAllSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableSet"),
                ctx.interner.intern("addAll"),
            ]))
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: addAllSymbol),
                "kk_mutable_set_addAll",
                "Expected addAll to resolve to kk_mutable_set_addAll"
            )
        }
    }

    func testMutableListBulkMutationMembersUseInvariantReceiverType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let mutableListFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableList"),
            ]

            for memberName in ["addAll", "removeAll", "retainAll"] {
                let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: mutableListFQName + [ctx.interner.intern(memberName)]))
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
                let receiverType = try XCTUnwrap(signature.receiverType)

                guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType),
                      let firstArg = receiverClassType.args.first
                else {
                    return XCTFail("Expected MutableList.\(memberName) receiver to be a class type")
                }

                guard case .invariant = firstArg else {
                    return XCTFail("Expected MutableList.\(memberName) receiver to remain invariant")
                }
            }
        }
    }

    func testMutableSetClearIsNotMarkedOperatorFunction() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let clearSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableSet"),
                ctx.interner.intern("clear"),
            ]))

            XCTAssertFalse(
                sema.symbols.symbol(clearSymbol)?.flags.contains(.operatorFunction) == true,
                "MutableSet.clear should not be registered as an operator function"
            )
        }
    }

    func testMutableSetAddAllUsesCollectionParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableSet"),
                interner.intern("addAll"),
            ]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            let parameterType = try XCTUnwrap(signature.parameterTypes.first)

            guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                return XCTFail("Expected MutableSet.addAll to take a collection type")
            }
            XCTAssertEqual(
                try interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)),
                "Collection"
            )
            guard case let .out(elementType) = try XCTUnwrap(classType.args.first),
                  case .typeParam = sema.types.kind(of: elementType)
            else {
                return XCTFail("Expected MutableSet.addAll parameter to use Collection<out E>")
            }
        }
    }

    /// Map member calls (containsKey, put, remove) go through the collection-fallback
    /// inference path which does not record a callBinding. Instead we verify that the
    /// synthetic symbols in the symbol table carry the correct external link names.
    func testMapSyntheticSymbolsHaveCorrectExternalLinkNames() throws {
        let source = """
        fun noop() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let kotlinCollections = ["kotlin", "collections"].map { interner.intern($0) }
            let mapFQ = kotlinCollections + [interner.intern("Map")]
            let mutableMapFQ = kotlinCollections + [interner.intern("MutableMap")]

            let expectedLinks: [(fqName: [InternedString], memberName: String, externalLink: String)] = [
                (mapFQ, "containsKey", "kk_map_contains_key"),
                (mapFQ, "containsValue", "kk_map_contains_value"),
                (mapFQ, "forEach", "kk_map_forEach"),
                (mapFQ, "map", "kk_map_map"),
                (mapFQ, "filter", "kk_map_filter"),
                (mapFQ, "keys", "kk_map_keys"),
                (mapFQ, "values", "kk_map_values"),
                (mapFQ, "entries", "kk_map_entries"),
                (mapFQ, "mapValues", "kk_map_mapValues"),
                (mapFQ, "mapValuesTo", "kk_map_mapValuesTo"),
                (mapFQ, "mapKeys", "kk_map_mapKeys"),
                (mapFQ, "mapKeysTo", "kk_map_mapKeysTo"),
                (mapFQ, "getValue", "kk_map_getValue"),
                (mapFQ, "withDefault", "kk_map_withDefault"),
                (mapFQ, "toList", "kk_map_toList"),
                (mapFQ, "toMutableMap", "kk_map_to_mutable_map"),
                (mutableMapFQ, "put", "kk_mutable_map_put"),
                (mutableMapFQ, "remove", "kk_mutable_map_remove"),
                (mutableMapFQ, "putAll", "kk_mutable_map_putAll"),
            ]

            for (ownerFQ, memberName, expectedExternal) in expectedLinks {
                let memberFQ = ownerFQ + [interner.intern(memberName)]
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(fqName: memberFQ),
                    "Symbol for \(memberName) not found in symbol table"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: symbolID),
                    expectedExternal,
                    "Expected \(memberName) to have external link \(expectedExternal)"
                )
            }
        }
    }

    func testMapWithDefaultSurfaceResolvesDefaultLambda() throws {
        let source = """
        fun probe(values: Map<Int, Int>): Int {
            val defaults = values.withDefault { it * 10 }
            return defaults.getValue(7)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Map.withDefault surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testIndexedAndAggregateListMembersAreInlineSynthetic() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let listFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
            ]

            for memberName in ["sumOf", "forEachIndexed", "mapIndexed"] {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(fqName: listFQName + [ctx.interner.intern(memberName)]),
                    "Expected synthetic List member \(memberName) to be registered"
                )
                let flags = try XCTUnwrap(sema.symbols.symbol(symbolID)?.flags)
                XCTAssertTrue(flags.contains(.inlineFunction), "Expected \(memberName) to be inline")
                XCTAssertTrue(flags.contains(.synthetic), "Expected \(memberName) to be synthetic")
            }
        }
    }

    func testMapHigherOrderMembersAreInlineAndToListPreservesPairType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let mapFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Map"),
            ]

            for memberName in ["forEach", "map", "filter", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo"] {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(fqName: mapFQName + [ctx.interner.intern(memberName)]),
                    "Expected synthetic Map member \(memberName) to be registered"
                )
                let flags = try XCTUnwrap(sema.symbols.symbol(symbolID)?.flags)
                XCTAssertTrue(flags.contains(.inlineFunction), "Expected \(memberName) to be inline")
            }

            let toListSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: mapFQName + [ctx.interner.intern("toList")])
            )
            let toListSignature = try XCTUnwrap(sema.symbols.functionSignature(for: toListSymbol))
            guard case let .classType(listType) = sema.types.kind(of: toListSignature.returnType) else {
                return XCTFail("Expected Map.toList to return List<Pair<K, V>>")
            }
            let listName = try XCTUnwrap(sema.symbols.symbol(listType.classSymbol)?.name)
            XCTAssertEqual(ctx.interner.resolve(listName), "List")
            let firstListArg = try XCTUnwrap(listType.args.first)
            guard case let .out(pairTypeID) = firstListArg,
                  case let .classType(pairType) = sema.types.kind(of: pairTypeID)
            else {
                return XCTFail("Expected Map.toList element type to be Pair")
            }
            let pairName = try XCTUnwrap(sema.symbols.symbol(pairType.classSymbol)?.name)
            XCTAssertEqual(ctx.interner.resolve(pairName), "Pair")
        }
    }

    func testMapEntryToPairSurfaceIsRegistered() throws {
        let source = """
        fun probe(values: Map<String, Int>): List<Pair<String, Int>> {
            return values.map { it.toPair() }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Map.Entry.toPair surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let entryFQName: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Map"),
                ctx.interner.intern("Entry"),
            ]
            let toPairSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: entryFQName + [ctx.interner.intern("toPair")]),
                "Expected Map.Entry.toPair to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: toPairSymbol), "kk_map_entry_to_pair")
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: toPairSymbol))
            guard case let .classType(pairType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected Map.Entry.toPair to return Pair<K, V>")
            }
            let pairName = try XCTUnwrap(sema.symbols.symbol(pairType.classSymbol)?.name)
            XCTAssertEqual(ctx.interner.resolve(pairName), "Pair")
            XCTAssertEqual(pairType.args.count, 2)
        }
    }

    func testBuildListInfersElementTypeFromBuilderCalls() throws {
        let source = """
        fun render(): List<Int> = buildList {
            this.add(1)
            add(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildListCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildList"
            })
            let buildListType = try XCTUnwrap(sema.bindings.exprType(for: buildListCall))
            guard case let .classType(listType) = sema.types.kind(of: buildListType) else {
                return XCTFail("Expected buildList(...) to produce a class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(listType.classSymbol)?.name)), "List")
            guard case let .out(elementType) = try XCTUnwrap(listType.args.first) else {
                return XCTFail("Expected List element type argument")
            }
            XCTAssertEqual(elementType, sema.types.intType)

            let explicitThis = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                if case .thisRef = expr { return true }
                return false
            })
            let explicitThisType = try XCTUnwrap(sema.bindings.exprType(for: explicitThis))
            guard case let .classType(receiverType) = sema.types.kind(of: explicitThisType) else {
                return XCTFail("Expected builder receiver to be a class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(receiverType.classSymbol)?.name)), "MutableList")
            guard case let .invariant(receiverElementType) = try XCTUnwrap(receiverType.args.first) else {
                return XCTFail("Expected MutableList element type argument")
            }
            XCTAssertEqual(receiverElementType, sema.types.intType)
        }
    }

    func testBuildMapInfersKeyAndValueTypesFromBuilderCalls() throws {
        let source = """
        fun render(): Map<String, Int> = buildMap {
            this.put("a", 1)
            put("b", 2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildMapCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildMap"
            })
            let buildMapType = try XCTUnwrap(sema.bindings.exprType(for: buildMapCall))
            guard case let .classType(mapType) = sema.types.kind(of: buildMapType) else {
                return XCTFail("Expected buildMap(...) to produce a class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(mapType.classSymbol)?.name)), "Map")
            guard mapType.args.count >= 2,
                  case let .out(keyType) = mapType.args[0],
                  case let .out(valueType) = mapType.args[1]
            else {
                return XCTFail("Expected Map key/value type arguments")
            }
            XCTAssertEqual(keyType, sema.types.stringType)
            XCTAssertEqual(valueType, sema.types.intType)

            let explicitThis = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                if case .thisRef = expr { return true }
                return false
            })
            let explicitThisType = try XCTUnwrap(sema.bindings.exprType(for: explicitThis))
            guard case let .classType(receiverType) = sema.types.kind(of: explicitThisType) else {
                return XCTFail("Expected builder receiver to be a class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(receiverType.classSymbol)?.name)), "MutableMap")
            guard receiverType.args.count >= 2,
                  case let .invariant(receiverKeyType) = receiverType.args[0],
                  case let .invariant(receiverValueType) = receiverType.args[1]
            else {
                return XCTFail("Expected MutableMap key/value type arguments")
            }
            XCTAssertEqual(receiverKeyType, sema.types.stringType)
            XCTAssertEqual(receiverValueType, sema.types.intType)
        }
    }

    func testMapKeysToResolvesWithMutableMapDestination() throws {
        let source = """
        fun remap(values: Map<Int, String>, destination: MutableMap<Int, String>): MutableMap<Int, String> {
            return values.mapKeysTo(destination) { entry -> entry.key + 10 }
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
                "Expected Map.mapKeysTo surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Map", "mapKeysTo"]
                .map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_map_mapKeysTo")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.parameterTypes.count, 2)
            XCTAssertEqual(signature.returnType, signature.parameterTypes[0])
        }
    }

    func testMapValuesToResolvesWithMutableMapDestination() throws {
        let source = """
        fun remap(values: Map<Int, String>, destination: MutableMap<Int, Int>): MutableMap<Int, Int> {
            return values.mapValuesTo(destination) { entry -> entry.value.length }
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
                "Expected Map.mapValuesTo surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "collections", "Map", "mapValuesTo"]
                .map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: memberFQName))
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_map_mapValuesTo")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.parameterTypes.count, 2)
            XCTAssertEqual(signature.returnType, signature.parameterTypes[0])
        }
    }

    func testMutableMapPutAllUsesProjectedMapParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableMap"),
                interner.intern("putAll"),
            ]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            let parameterType = try XCTUnwrap(signature.parameterTypes.first)

            guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                return XCTFail("Expected MutableMap.putAll to take a map type")
            }
            XCTAssertEqual(
                try interner.resolve(XCTUnwrap(sema.symbols.symbol(classType.classSymbol)?.name)),
                "Map"
            )
            guard classType.args.count == 2,
                  case let .out(keyType) = classType.args[0],
                  case let .out(valueType) = classType.args[1],
                  case .typeParam = sema.types.kind(of: keyType),
                  case .typeParam = sema.types.kind(of: valueType)
            else {
                return XCTFail("Expected MutableMap.putAll parameter to use projected Map<K, V>")
            }
        }
    }

    func testGroupingEachCountToUsesProjectedMutableMapParameterType() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Grouping"),
                interner.intern("eachCountTo"),
            ]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_grouping_eachCountTo")
            XCTAssertEqual(signature.parameterTypes.count, 1)
            XCTAssertEqual(signature.returnType, signature.parameterTypes[0])

            let receiverType = try XCTUnwrap(signature.receiverType)
            guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
                return XCTFail("Expected Grouping.eachCountTo receiver to be a class type")
            }
            XCTAssertEqual(
                try interner.resolve(XCTUnwrap(sema.symbols.symbol(receiverClassType.classSymbol)?.name)),
                "Grouping"
            )

            let parameterType = try XCTUnwrap(signature.parameterTypes.first)
            guard case let .classType(parameterClassType) = sema.types.kind(of: parameterType) else {
                return XCTFail("Expected eachCountTo to take a MutableMap type")
            }
            XCTAssertEqual(
                try interner.resolve(XCTUnwrap(sema.symbols.symbol(parameterClassType.classSymbol)?.name)),
                "MutableMap"
            )
            XCTAssertEqual(parameterClassType.args.count, 2)
            guard case let .in(keyProjection) = parameterClassType.args[0],
                  case .typeParam = sema.types.kind(of: keyProjection),
                  case let .invariant(valueType) = parameterClassType.args[1]
            else {
                return XCTFail("Expected eachCountTo parameter to use MutableMap<in K, Int>")
            }
            XCTAssertEqual(valueType, sema.types.intType)
        }
    }

    func testBuildListCapacityOverloadResolves() throws {
        let source = """
        fun render(): List<Int> = buildList(4) {
            add(1)
            add(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)

            let buildListCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildList"
            })
            let buildListType = try XCTUnwrap(sema.bindings.exprType(for: buildListCall))
            guard case let .classType(listType) = sema.types.kind(of: buildListType) else {
                return XCTFail("Expected buildList(capacity) to produce a class type")
            }
            XCTAssertEqual(try ctx.interner.resolve(XCTUnwrap(sema.symbols.symbol(listType.classSymbol)?.name)), "List")
            guard case let .out(elementType) = try XCTUnwrap(listType.args.first) else {
                return XCTFail("Expected List element type argument")
            }
            XCTAssertEqual(elementType, sema.types.intType)
        }
    }

    func testStringAsIterableImplicitReceiverDoesNotExposeListOnlyMembers() throws {
        let source = """
        fun probe(): Char = with("hello") {
            asIterable().get(0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }
}
