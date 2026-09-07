#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// STDLIB-004: Codegen coverage for primitive array factory calls and
// lambda constructors.  These tests verify the KIR lowering output so
// that any regression in the array-creation code path is caught early.
extension BuildKIRRegressionTests {

    private static nonisolated(unsafe) var _sharedPrimitiveArrayCtx: (ctx: CompilationContext, paths: [String])?

    private func sharedPrimitiveArrayCtx() throws -> CompilationContext {
        if let cached = Self._sharedPrimitiveArrayCtx { return cached.ctx }
        let sources: [String] = [
            """
            package sample0
            fun make0() = intArrayOf(1, 2, 3)
            fun main0(): Int {
                val arr = make0()
                return arr.size
            }
            """,
            """
            package sample1
            fun make1() = byteArrayOf(1.toByte(), 127.toByte())
            fun main1(): Int {
                val arr = make1()
                return arr.size
            }
            """,
            """
            package sample2
            fun make2() = charArrayOf('a', 'b', 'c')
            fun main2(): Int {
                val arr = make2()
                return arr.size
            }
            """,
            """
            package sample3
            fun make3() = IntArray(3) { it * 2 }
            fun main3(): Int {
                val arr = make3()
                return arr.size
            }
            """,
            """
            package sample4
            fun make4() = ByteArray(4) { (it + 1).toByte() }
            fun main4(): Int {
                val arr = make4()
                return arr.size
            }
            """,
            """
            package sample5
            fun make5() = ByteArray(8)
            fun main5(): Int {
                val arr = make5()
                return arr.size
            }
            """,
            """
            package sample6
            fun make6() = IntArray(3)
            fun main6(): Int {
                val arr = make6()
                return arr.size
            }
            """,
            """
            package sample7
            fun make7(list: List<Int>) = list.toIntArray()
            fun main7(): Int {
                val arr = make7(listOf(10, 20, 30))
                return arr.size
            }
            """,
            """
            package sample8
            fun make8(list: List<UInt>) = list.toUIntArray()
            fun main8(): Int {
                val arr = make8(listOf(1u, 4000000000u))
                return arr.size
            }
            """,
            """
            package sample9
            fun make9(arr: IntArray) = arr.toList()
            fun main9(): Int {
                val list = make9(intArrayOf(1, 2))
                return list.size
            }
            """,
            """
            package sample10
            fun make10() = UIntArray(3)
            fun main10(): Int {
                val arr = make10()
                return arr.size
            }
            """,
            """
            package sample11
            fun make11() = ULongArray(3)
            fun main11(): Int {
                val arr = make11()
                return arr.size
            }
            """,
            """
            package sample12
            fun make12() = BooleanArray(4) { it % 2 == 0 }
            fun main12(): Int {
                val arr = make12()
                return arr.size
            }
            """
        ]
        var result: CompilationContext?
        var capturedPaths: [String]?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            result = ctx
            capturedPaths = paths
        }
        let ctx = try #require(result)
        let paths = try #require(capturedPaths)
        Self._sharedPrimitiveArrayCtx = (ctx, paths)
        return ctx
    }

    @Test
    func testIntArrayOfFactoryLowersToKkArrayOf() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let makeBody = try findKIRFunctionBody(named: "make0", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: makeBody, interner: ctx.interner)

        #expect(
            callNames.contains("kk_array_of"),
            "intArrayOf must lower to kk_array_of; got: \(callNames)"
        )
        #expect(
            !(callNames.contains("intArrayOf")),
            "intArrayOf call should have been rewritten; got: \(callNames)"
        )
    }

    @Test
    func testByteArrayOfFactoryLowersToKkArrayOf() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let makeBody = try findKIRFunctionBody(named: "make1", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: makeBody, interner: ctx.interner)

        #expect(
            callNames.contains("kk_array_of"),
            "byteArrayOf must lower to kk_array_of; got: \(callNames)"
        )
    }

    @Test
    func testCharArrayOfFactoryUsesSourceBackedInlinePath() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let makeBody = try findKIRFunctionBody(named: "make2", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: makeBody, interner: ctx.interner)

        #expect(
            callNames.contains("kk_array_new"),
            "source-backed charArrayOf must allocate a primitive array; got: \(callNames)"
        )
        #expect(
            callNames.filter { $0 == "kk_array_set" }.count == 3,
            "source-backed charArrayOf must store each Char element; got: \(callNames)"
        )
        #expect(
            !callNames.contains("kk_array_of"),
            "source-backed charArrayOf must not lower to kk_array_of; got: \(callNames)"
        )
        #expect(
            !callNames.contains("charArrayOf"),
            "inline charArrayOf should not remain as a call in KIR; got: \(callNames)"
        )
        #expect(
            !callNames.contains("kk_box_char"),
            "primitive Char elements should not be boxed; got: \(callNames)"
        )
        #expect(
            !callNames.contains("kk_array_toList") && !callNames.contains("__kk_array_toList"),
            "inline charArrayOf should not route through List varargs; got: \(callNames)"
        )
    }

    @Test
    func testIntArrayLambdaConstructorLowersToArrayNewAndArraySet() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let makeBody = try findKIRFunctionBody(named: "make3", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: makeBody, interner: ctx.interner)

        #expect(
            callNames.contains("kk_array_new_checked"),
            "IntArray(n) { init } must emit kk_array_new_checked; got: \(callNames)"
        )
        #expect(
            callNames.contains("kk_array_set"),
            "IntArray(n) { init } must emit kk_array_set in the fill loop; got: \(callNames)"
        )

        let throwFlags = extractThrowFlags(from: makeBody, interner: ctx.interner)
        #expect(
            throwFlags["kk_array_new_checked"]?.allSatisfy { $0 == true } == true,
            "kk_array_new_checked inside constructor must be throwing (NegativeArraySizeException)"
        )
    }

    @Test
    func testByteArrayLambdaConstructorLowersToArrayNewAndArraySet() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let makeBody = try findKIRFunctionBody(named: "make4", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: makeBody, interner: ctx.interner)

        #expect(
            callNames.contains("kk_array_new_checked"),
            "ByteArray(n) { init } must emit kk_array_new_checked; got: \(callNames)"
        )
        #expect(
            callNames.contains("kk_array_set"),
            "ByteArray(n) { init } must emit kk_array_set; got: \(callNames)"
        )
    }

    @Test
    func testByteArraySizeOnlyConstructorLowersToArrayNewWithoutLoop() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let makeBody = try findKIRFunctionBody(named: "make5", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: makeBody, interner: ctx.interner)

        #expect(
            callNames.contains("kk_array_new_checked"),
            "ByteArray(n) (size-only) must emit kk_array_new_checked; got: \(callNames)"
        )
        #expect(
            !callNames.contains("kk_array_set"),
            "ByteArray(n) (size-only) must not emit a fill loop; got: \(callNames)"
        )
        #expect(
            !callNames.contains("ByteArray"),
            "ByteArray(n) (size-only) must not fall through to an unresolved 'ByteArray' call; got: \(callNames)"
        )
    }

    @Test
    func testIntArraySizeOnlyConstructorLowersToArrayNewWithoutLoop() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let makeBody = try findKIRFunctionBody(named: "make6", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: makeBody, interner: ctx.interner)

        #expect(
            callNames.contains("kk_array_new_checked"),
            "IntArray(n) (size-only) must emit kk_array_new_checked; got: \(callNames)"
        )
        #expect(
            !callNames.contains("kk_array_set"),
            "IntArray(n) (size-only) must not emit a fill loop; got: \(callNames)"
        )
        #expect(
            !callNames.contains("IntArray"),
            "IntArray(n) (size-only) must not fall through to an unresolved 'IntArray' call; got: \(callNames)"
        )
    }

    @Test
    func testUIntArraySizeOnlyConstructorLowersToArrayNewWithoutLoop() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let makeBody = try findKIRFunctionBody(named: "make10", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: makeBody, interner: ctx.interner)

        #expect(
            callNames.contains("kk_array_new_checked"),
            "UIntArray(n) (size-only) must emit kk_array_new_checked; got: \(callNames)"
        )
        #expect(
            !callNames.contains("kk_array_set"),
            "UIntArray(n) (size-only) must not emit a fill loop; got: \(callNames)"
        )
        #expect(
            !callNames.contains("UIntArray"),
            "UIntArray(n) (size-only) must not fall through to an unresolved 'UIntArray' call; got: \(callNames)"
        )
    }

    @Test
    func testULongArraySizeOnlyConstructorLowersToArrayNewWithoutLoop() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let makeBody = try findKIRFunctionBody(named: "make11", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: makeBody, interner: ctx.interner)

        #expect(
            callNames.contains("kk_array_new_checked"),
            "ULongArray(n) (size-only) must emit kk_array_new_checked; got: \(callNames)"
        )
        #expect(
            !callNames.contains("kk_array_set"),
            "ULongArray(n) (size-only) must not emit a fill loop; got: \(callNames)"
        )
        #expect(
            !callNames.contains("ULongArray"),
            "ULongArray(n) (size-only) must not fall through to an unresolved 'ULongArray' call; got: \(callNames)"
        )
    }

    @Test
    func testBooleanArrayLambdaConstructorLowersToArrayNewAndArraySet() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let makeBody = try findKIRFunctionBody(named: "make12", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: makeBody, interner: ctx.interner)

        #expect(
            callNames.contains("kk_array_new_checked"),
            "BooleanArray(n) { init } must emit kk_array_new_checked; got: \(callNames)"
        )
        #expect(
            callNames.contains("kk_array_set"),
            "BooleanArray(n) { init } must emit kk_array_set in the fill loop; got: \(callNames)"
        )
        #expect(
            !callNames.contains("BooleanArray"),
            "BooleanArray(n) { init } must not remain as an unresolved call; got: \(callNames)"
        )

        let throwFlags = extractThrowFlags(from: makeBody, interner: ctx.interner)
        #expect(
            throwFlags["kk_array_new_checked"]?.allSatisfy { $0 == true } == true,
            "kk_array_new_checked inside BooleanArray constructor must be throwing (NegativeArraySizeException)"
        )
    }

    @Test
    func testListToIntArrayLowersToSourceBackedCall() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let convertBody = try findKIRFunctionBody(named: "make7", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: convertBody, interner: ctx.interner)

        #expect(
            !callNames.contains("kk_list_toIntArray"),
            "List<Int>.toIntArray() must no longer use the removed kk_list_toIntArray bridge; got: \(callNames)"
        )
        #expect(
            callNames == ["toIntArray"],
            "List<Int>.toIntArray() must lower to a single call of the bundled declaration; got: \(callNames)"
        )

        // The call must carry a resolved declaration symbol (bundled stdlib),
        // not an unresolved name that would only be matched at link time.
        let calleeSymbol = try #require(convertBody.compactMap { instruction -> SymbolID? in
            guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "toIntArray"
            else { return nil }
            return symbol
        }.first)
        #expect(ctx.sema?.symbols.externalLinkName(for: calleeSymbol) == nil)
    }

    @Test
    func testListToUIntArrayLowersToSourceBackedCall() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let convertBody = try findKIRFunctionBody(named: "make8", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: convertBody, interner: ctx.interner)

        #expect(
            !callNames.contains("kk_list_toUIntArray"),
            "List<UInt>.toUIntArray() must no longer use the removed kk_list_toUIntArray bridge; got: \(callNames)"
        )
        #expect(
            callNames == ["toUIntArray"],
            "List<UInt>.toUIntArray() must lower to a single call of the bundled declaration; got: \(callNames)"
        )

        let calleeSymbol = try #require(convertBody.compactMap { instruction -> SymbolID? in
            guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "toUIntArray"
            else { return nil }
            return symbol
        }.first)
        #expect(ctx.sema?.symbols.externalLinkName(for: calleeSymbol) == nil)
    }

    @Test
    func testIntArrayToListLowersToSourceBackedCall() throws {
        let ctx = try sharedPrimitiveArrayCtx()
        let module = try #require(ctx.kir)
        let convertBody = try findKIRFunctionBody(named: "make9", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: convertBody, interner: ctx.interner)

        #expect(
            callNames == ["toList"],
            "IntArray.toList() must remain a call to the bundled source declaration; got: \(callNames)"
        )
        #expect(
            convertBody.compactMap { instruction -> SymbolID? in
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == "toList"
                else { return nil }
                return symbol
            }.contains(where: { symbol in
                ctx.sema?.symbols.isSourceBackedSymbol(symbol) == true
                    && ctx.sema?.symbols.externalLinkName(for: symbol) == nil
            }),
            "IntArray.toList() must resolve to source-backed Kotlin code; got: \(callNames)"
        )
    }
}
#endif
