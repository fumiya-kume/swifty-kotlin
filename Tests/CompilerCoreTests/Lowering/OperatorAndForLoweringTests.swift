@testable import CompilerCore
import Foundation
import XCTest

// swiftformat:disable trailingCommas

// swiftlint:disable:next type_body_length
final class OperatorAndForLoweringTests: XCTestCase {
    // MARK: - Helper

    private func makeKIRContext(interner: StringInterner, sema: SemaModule? = nil) -> KIRContext {
        let options = CompilerOptions(
            moduleName: "OpForTest",
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

    private func makeModule(
        body: [KIRInstruction],
        interner: StringInterner,
        arena: KIRArena,
        fnName: String = "main"
    ) -> (KIRModule, KIRDeclID) {
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern(fnName),
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

    private func calleesInDecl(_ declID: KIRDeclID, module: KIRModule, interner: StringInterner) -> [String] {
        guard case let .function(fn) = module.arena.decl(declID) else { return [] }
        return extractCallees(from: fn.body, interner: interner)
    }

    private func bodyInDecl(_ declID: KIRDeclID, module: KIRModule) -> [KIRInstruction] {
        guard case let .function(fn) = module.arena.decl(declID) else { return [] }
        return fn.body
    }

    // MARK: - OperatorLoweringPass: println

    func testOperatorLoweringKeepsPrintlnWhenNoTypeInfo() throws {
        // Without sema type info, println is not rewritten (no typed variant can be selected).
        let interner = StringInterner()
        let arena = KIRArena()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("println"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),

                .returnUnit
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner) // no sema

        try OperatorLoweringPass().run(module: module, ctx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        // Without type info println stays as-is (no specific typed variant selected)
        XCTAssertTrue(callees.contains("println"), "println should remain when no type info is available")
    }

    func testOperatorLoweringRewritesCharPrintlnAndPreservesUnitResult() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let sema = SemaModule(
            symbols: SymbolTable(),
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        let arg = arena.appendExpr(.temporary(0), type: types.charType)
        let result = arena.appendExpr(.temporary(1), type: types.unitType)
        let (module, declID) = makeModule(
            body: [
                // swiftlint:disable:next line_length
                .call(symbol: nil, callee: interner.intern("println"), arguments: [arg], result: result, canThrow: false, thrownResult: nil),

                .returnUnit
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try OperatorLoweringPass().run(module: module, ctx: ctx)

        let body = bodyInDecl(declID, module: module)
        XCTAssertGreaterThanOrEqual(body.count, 2)

        guard case let .call(_, loweredCallee, _, loweredResult, _, _, _) = body[0] else {
            return XCTFail("Expected first lowered instruction to be a call")
        }
        XCTAssertEqual(interner.resolve(loweredCallee), "kk_println_char")
        XCTAssertNil(loweredResult, "Lowered primitive println call should be side-effect only")

        guard case let .constValue(unitResult, value) = body[1] else {
            return XCTFail("Expected second lowered instruction to synthesize Unit")
        }
        XCTAssertEqual(unitResult, result)
        XCTAssertEqual(value, .unit)
    }

    // MARK: - OperatorLoweringPass: binary ops

    func testOperatorLoweringRewritesIntBinaryAddToRuntimeCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let v2 = arena.appendExpr(.temporary(2))
        let (module, declID) = makeModule(
            body: [
                .binary(op: .add, lhs: v0, rhs: v1, result: v2),

                .returnUnit
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner)

        try OperatorLoweringPass().run(module: module, ctx: ctx)

        let body = bodyInDecl(declID, module: module)
        let hasBinaryAdd = body.contains { instruction in
            if case .binary(.add, _, _, _) = instruction { return true }
            return false
        }
        XCTAssertFalse(hasBinaryAdd, "Binary .add should be rewritten to runtime call")

        let callees = calleesInDecl(declID, module: module, interner: interner)
        let hasAddCall = callees.contains { $0 == "kk_op_add" }
        XCTAssertTrue(hasAddCall, "Binary add should produce kk_op_add, got callees: \(callees)")
    }

    func testOperatorLoweringRewritesNullAssertToRuntimeCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let (module, declID) = makeModule(
            body: [
                .nullAssert(operand: v0, result: v1),

                .returnUnit
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner)

        try OperatorLoweringPass().run(module: module, ctx: ctx)

        let body = bodyInDecl(declID, module: module)
        let hasNullAssert = body.contains { instruction in
            if case .nullAssert = instruction { return true }
            return false
        }
        XCTAssertFalse(hasNullAssert, "nullAssert should be rewritten to runtime call")
        let callees = calleesInDecl(declID, module: module, interner: interner)
        let hasNullCheckCall = callees.contains { $0 == "kk_op_notnull" }
        XCTAssertTrue(hasNullCheckCall, "nullAssert should produce kk_op_notnull, got callees: \(callees)")
    }

    // MARK: - OperatorLoweringPass: shouldRun

    func testOperatorLoweringShouldRunReturnsFalseForEmptyModule() {
        let interner = StringInterner()
        let arena = KIRArena()
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        _ = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        XCTAssertFalse(OperatorLoweringPass().shouldRun(module: module, ctx: ctx))
    }

    func testOperatorLoweringShouldRunReturnsTrueForBinaryInstruction() {
        let interner = StringInterner()
        let arena = KIRArena()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let v2 = arena.appendExpr(.temporary(2))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.binary(op: .add, lhs: v0, rhs: v1, result: v2)],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        XCTAssertTrue(OperatorLoweringPass().shouldRun(module: module, ctx: ctx))
    }

    func testOperatorLoweringShouldRunReturnsTrueForPrintlnCall() {
        let interner = StringInterner()
        let arena = KIRArena()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.call(symbol: nil, callee: interner.intern("println"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil)],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        XCTAssertTrue(OperatorLoweringPass().shouldRun(module: module, ctx: ctx))
    }

    // MARK: - ForLoweringPass

    func testForLoweringRewritesKkForLoweredToHasNextNextLoop() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let v2 = arena.appendExpr(.temporary(2))
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_range_iterator"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_for_lowered"), arguments: [v1], result: v2, canThrow: false, thrownResult: nil),

                .returnUnit
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner)

        try ForLoweringPass().run(module: module, ctx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("kk_for_lowered"), "kk_for_lowered should be rewritten")
        XCTAssertTrue(
            callees.contains("kk_range_hasNext") || callees.contains("kk_list_iterator_hasNext"),
            "For loop should use hasNext pattern, got callees: \(callees)"
        )
    }

    func testForLoweringShouldRunReturnsFalseWithNoForMarker() {
        let interner = StringInterner()
        let arena = KIRArena()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("someFunction"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),

                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        XCTAssertFalse(ForLoweringPass().shouldRun(module: module, ctx: ctx))
    }

    func testForLoweringShouldRunReturnsTrueForKkForLoweredCall() {
        let interner = StringInterner()
        let arena = KIRArena()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("kk_for_lowered"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil)
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        XCTAssertTrue(ForLoweringPass().shouldRun(module: module, ctx: ctx))
    }

    // MARK: - NormalizeBlocksPass

    func testNormalizeBlocksShouldRunReturnsFalseForNoBlocks() {
        let interner = StringInterner()
        let arena = KIRArena()
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        XCTAssertFalse(NormalizeBlocksPass().shouldRun(module: module, ctx: ctx))
    }

    func testNormalizeBlocksShouldRunReturnsTrueForBeginBlock() {
        let interner = StringInterner()
        let arena = KIRArena()
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.beginBlock, .returnUnit, .endBlock],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        XCTAssertTrue(NormalizeBlocksPass().shouldRun(module: module, ctx: ctx))
    }

    func testNormalizeBlocksRemovesBeginAndEndBlock() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let (module, declID) = makeModule(
            body: [
                .beginBlock,
                .call(symbol: nil, callee: interner.intern("foo"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .endBlock,

                .returnUnit
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner)

        try NormalizeBlocksPass().run(module: module, ctx: ctx)

        let body = bodyInDecl(declID, module: module)
        let hasBeginBlock = body.contains { if case .beginBlock = $0 { return true }; return false }
        let hasEndBlock = body.contains { if case .endBlock = $0 { return true }; return false }
        XCTAssertFalse(hasBeginBlock, "beginBlock should be removed by NormalizeBlocksPass")
        XCTAssertFalse(hasEndBlock, "endBlock should be removed by NormalizeBlocksPass")
    }

    // swiftformat:enable trailingCommas
}
