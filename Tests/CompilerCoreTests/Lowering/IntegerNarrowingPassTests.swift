@testable import CompilerCore
import Foundation
import XCTest

final class IntegerNarrowingPassTests: XCTestCase {
    private func makeKIRContext(interner: StringInterner, sema: SemaModule?) -> KIRContext {
        let options = CompilerOptions(
            moduleName: "IntNarrowTest",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        return KIRContext(
            diagnostics: DiagnosticEngine(),
            options: options,
            interner: interner,
            sema: sema
        )
    }

    private func makeSema() -> SemaModule {
        SemaModule(
            symbols: SymbolTable(),
            types: TypeSystem(),
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )
    }

    private func makeModule(
        body: [KIRInstruction],
        interner: StringInterner,
        arena: KIRArena
    ) -> (KIRModule, KIRDeclID) {
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        return (module, declID)
    }

    private func body(_ declID: KIRDeclID, _ module: KIRModule) -> [KIRInstruction] {
        guard case let .function(fn) = module.arena.decl(declID) else { return [] }
        return fn.body
    }

    // MARK: - Arithmetic narrowing

    func testIntAdditionResultIsNarrowed() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = makeSema()
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let lhs = arena.appendExpr(.temporary(0), type: intType)
        let rhs = arena.appendExpr(.temporary(1), type: intType)
        let result = arena.appendExpr(.temporary(2), type: intType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [lhs, rhs], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        XCTAssertTrue(IntegerNarrowingPass().shouldRun(module: module, ctx: ctx))
        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = body(declID, module)
        // Expect: kk_op_add -> temp, then kk_int_narrow(temp) -> result.
        guard case let .call(_, addCallee, _, addResult, _, _, _, _) = lowered[0] else {
            return XCTFail("Expected arithmetic call to be preserved")
        }
        XCTAssertEqual(interner.resolve(addCallee), "kk_op_add")
        XCTAssertNotEqual(addResult, result, "Arithmetic result should be redirected to a temporary")

        guard case let .call(_, narrowCallee, narrowArgs, narrowResult, _, _, _, _) = lowered[1] else {
            return XCTFail("Expected a narrowing call after the arithmetic call")
        }
        XCTAssertEqual(interner.resolve(narrowCallee), "kk_int_narrow")
        XCTAssertEqual(narrowArgs, [addResult])
        XCTAssertEqual(narrowResult, result, "Narrowing must write back to the original result id")
    }

    func testLongAdditionResultIsNotNarrowed() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = makeSema()
        let longType = sema.types.make(.primitive(.long, .nonNull))

        let lhs = arena.appendExpr(.temporary(0), type: longType)
        let rhs = arena.appendExpr(.temporary(1), type: longType)
        let result = arena.appendExpr(.temporary(2), type: longType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [lhs, rhs], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = body(declID, module)
        let narrowCount = lowered.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return interner.resolve(callee) == "kk_int_narrow"
            }
            return false
        }.count
        XCTAssertEqual(narrowCount, 0, "Long arithmetic must not be narrowed to 32 bits")
        guard case let .call(_, addCallee, _, addResult, _, _, _, _) = lowered[0] else {
            return XCTFail("Expected the long add call to be preserved")
        }
        XCTAssertEqual(interner.resolve(addCallee), "kk_op_add")
        XCTAssertEqual(addResult, result)
    }

    // MARK: - Shift rewriting

    func testIntShiftLeftIsRewrittenToWidthAwareVariant() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = makeSema()
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let value = arena.appendExpr(.temporary(0), type: intType)
        let distance = arena.appendExpr(.temporary(1), type: intType)
        let result = arena.appendExpr(.temporary(2), type: intType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_shl"), arguments: [value, distance], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = body(declID, module)
        guard case let .call(_, callee, args, shiftResult, _, _, _, _) = lowered[0] else {
            return XCTFail("Expected the shift call to be present")
        }
        XCTAssertEqual(interner.resolve(callee), "kk_op_ishl", "Int shl must use the 32-bit-aware variant")
        XCTAssertEqual(args, [value, distance], "Shift operands must be preserved")
        XCTAssertEqual(shiftResult, result, "Shift result id must be preserved (rename only)")
    }

    func testLongShiftLeftUsesSixBitMaskedVariantWithoutNarrowing() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = makeSema()
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let value = arena.appendExpr(.temporary(0), type: longType)
        let distance = arena.appendExpr(.temporary(1), type: intType)
        let result = arena.appendExpr(.temporary(2), type: longType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_shl"), arguments: [value, distance], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = body(declID, module)
        guard case let .call(_, callee, args, shiftResult, _, _, _, _) = lowered[0] else {
            return XCTFail("Expected the shift call to be present")
        }
        // Long shl uses the 64-bit variant (masks the distance to 6 bits) so
        // distances >= 64 are well defined, but the result is NOT narrowed to 32 bits.
        XCTAssertEqual(interner.resolve(callee), "kk_op_lshl", "Long shl must use the 64-bit-aware variant")
        XCTAssertEqual(args, [value, distance])
        XCTAssertEqual(shiftResult, result)
        let narrowCount = lowered.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return interner.resolve(callee) == "kk_int_narrow"
            }
            return false
        }.count
        XCTAssertEqual(narrowCount, 0, "Long shift result must not be narrowed to 32 bits")
    }

    // MARK: - shouldRun

    func testShouldRunReturnsFalseWithoutRelevantCallees() {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = makeSema()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let (module, _) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_println_any"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)
        XCTAssertFalse(IntegerNarrowingPass().shouldRun(module: module, ctx: ctx))
    }

    func testShouldRunReturnsFalseWithoutSema() {
        let interner = StringInterner()
        let arena = KIRArena()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let v2 = arena.appendExpr(.temporary(2))
        let (module, _) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [v0, v1], result: v2, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: nil)
        XCTAssertFalse(IntegerNarrowingPass().shouldRun(module: module, ctx: ctx), "Pass requires sema type info")
    }
}
