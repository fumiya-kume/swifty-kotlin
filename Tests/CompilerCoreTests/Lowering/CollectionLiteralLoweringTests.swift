@testable import CompilerCore
import Foundation
import XCTest

final class CollectionLiteralLoweringTests: XCTestCase {
    // MARK: - Helper

    private func makeKIRContext(interner: StringInterner) -> KIRContext {
        let options = CompilerOptions(
            moduleName: "CollLiteralTest",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        return KIRContext(
            diagnostics: DiagnosticEngine(),
            options: options,
            interner: interner
        )
    }

    private func makeModuleWithCall(callee: InternedString, interner: StringInterner, arena: KIRArena) -> (KIRModule, KIRDeclID) {
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: callee, arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        return (module, declID)
    }

    private func runPass(module: KIRModule, kirCtx: KIRContext) throws {
        try CollectionLiteralLoweringPass().run(module: module, ctx: kirCtx)
    }

    private func calleesInDecl(_ declID: KIRDeclID, module: KIRModule, interner: StringInterner) -> [String] {
        guard case let .function(fn) = module.arena.decl(declID) else { return [] }
        return extractCallees(from: fn.body, interner: interner)
    }

    // MARK: - listOf rewriting

    func testListOfRewrittenToKkListOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("listOf")
        let (module, declID) = makeModuleWithCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("listOf"), "listOf should be rewritten")
        XCTAssertTrue(callees.contains("kk_list_of"), "listOf should become kk_list_of")
    }

    func testMutableListOfRewrittenToKkListOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("mutableListOf")
        let (module, declID) = makeModuleWithCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("mutableListOf"), "mutableListOf should be rewritten")
        XCTAssertTrue(callees.contains("kk_list_of"), "mutableListOf should become kk_list_of")
    }

    func testEmptyListRewrittenToKkListOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("emptyList")
        let (module, declID) = makeModuleWithCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("emptyList"), "emptyList should be rewritten")
        XCTAssertTrue(callees.contains("kk_list_of"), "emptyList should become kk_list_of")
    }

    func testListOfNotNullRewrittenToKkListOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("listOfNotNull")
        let (module, declID) = makeModuleWithCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("listOfNotNull"), "listOfNotNull should be rewritten")
        XCTAssertTrue(callees.contains("kk_list_of"), "listOfNotNull should become kk_list_of")
    }

    // MARK: - mapOf rewriting

    func testMapOfRewrittenToKkMapOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        // mapOf rewrites each argument as a Pair; argument count becomes the entry count
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let v2 = arena.appendExpr(.temporary(2))
        let v3 = arena.appendExpr(.temporary(3))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("mapOf"), arguments: [v0, v1, v2, v3], result: v3, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("mapOf"), "mapOf should be rewritten")
        XCTAssertTrue(callees.contains("kk_map_of"), "mapOf should become kk_map_of")
    }

    func testEmptyMapRewrittenToKkMapOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("emptyMap")
        let (module, declID) = makeModuleWithCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("emptyMap"), "emptyMap should be rewritten")
        XCTAssertTrue(callees.contains("kk_map_of"), "emptyMap should become kk_map_of")
    }

    func testMapCountRewriteToKkMapCount() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let entry0 = arena.appendExpr(.temporary(0))
        let entry1 = arena.appendExpr(.temporary(1))
        let entry2 = arena.appendExpr(.temporary(2))
        let entry3 = arena.appendExpr(.temporary(3))
        let lambda = arena.appendExpr(.temporary(4))
        let mapExpr = arena.appendExpr(.temporary(5))
        let countResult = arena.appendExpr(.temporary(6))
        let closureRaw = arena.appendExpr(.intLiteral(0), type: nil)
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("mapOf"),
                    arguments: [entry0, entry1, entry2, entry3],
                    result: mapExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("count"),
                    arguments: [mapExpr, lambda, closureRaw],
                    result: countResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("mapOf"), "mapOf should be rewritten")
        XCTAssertFalse(callees.contains("count"), "map.count should be rewritten")
        XCTAssertTrue(callees.contains("kk_map_of"), "mapOf should become kk_map_of")
        XCTAssertTrue(callees.contains("kk_map_count"), "count on map should become kk_map_count")
    }

    func testMapAnyRewriteToKkMapAny() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let entry0 = arena.appendExpr(.temporary(0))
        let entry1 = arena.appendExpr(.temporary(1))
        let entry2 = arena.appendExpr(.temporary(2))
        let entry3 = arena.appendExpr(.temporary(3))
        let lambda = arena.appendExpr(.temporary(4))
        let mapExpr = arena.appendExpr(.temporary(5))
        let anyResult = arena.appendExpr(.temporary(6))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("mapOf"),
                    arguments: [entry0, entry1, entry2, entry3],
                    result: mapExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("any"),
                    arguments: [mapExpr, lambda],
                    result: anyResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("mapOf"), "mapOf should be rewritten")
        XCTAssertFalse(callees.contains("any"), "map.any should be rewritten")
        XCTAssertTrue(callees.contains("kk_map_of"), "mapOf should become kk_map_of")
        XCTAssertTrue(callees.contains("kk_map_any"), "any on map should become kk_map_any")
    }

    func testMapAllRewriteToKkMapAll() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let entry0 = arena.appendExpr(.temporary(0))
        let entry1 = arena.appendExpr(.temporary(1))
        let entry2 = arena.appendExpr(.temporary(2))
        let entry3 = arena.appendExpr(.temporary(3))
        let lambda = arena.appendExpr(.temporary(4))
        let mapExpr = arena.appendExpr(.temporary(5))
        let allResult = arena.appendExpr(.temporary(6))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("mapOf"),
                    arguments: [entry0, entry1, entry2, entry3],
                    result: mapExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("all"),
                    arguments: [mapExpr, lambda],
                    result: allResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("mapOf"), "mapOf should be rewritten")
        XCTAssertFalse(callees.contains("all"), "map.all should be rewritten")
        XCTAssertTrue(callees.contains("kk_map_of"), "mapOf should become kk_map_of")
        XCTAssertTrue(callees.contains("kk_map_all"), "all on map should become kk_map_all")
    }

    func testMapNoneRewriteToKkMapNone() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let entry0 = arena.appendExpr(.temporary(0))
        let entry1 = arena.appendExpr(.temporary(1))
        let entry2 = arena.appendExpr(.temporary(2))
        let entry3 = arena.appendExpr(.temporary(3))
        let lambda = arena.appendExpr(.temporary(4))
        let mapExpr = arena.appendExpr(.temporary(5))
        let noneResult = arena.appendExpr(.temporary(6))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("mapOf"),
                    arguments: [entry0, entry1, entry2, entry3],
                    result: mapExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("none"),
                    arguments: [mapExpr, lambda],
                    result: noneResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("mapOf"), "mapOf should be rewritten")
        XCTAssertFalse(callees.contains("none"), "map.none should be rewritten")
        XCTAssertTrue(callees.contains("kk_map_of"), "mapOf should become kk_map_of")
        XCTAssertTrue(callees.contains("kk_map_none"), "none on map should become kk_map_none")
    }

    // MARK: - setOf rewriting

    func testSetOfRewrittenToKkSetOf() throws {
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
            body: [
                .call(symbol: nil, callee: interner.intern("setOf"), arguments: [v0, v1], result: v2, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("setOf"), "setOf should be rewritten")
        XCTAssertTrue(callees.contains("kk_set_of"),
                      "setOf should be rewritten to kk_set_of, got: \(callees)")
    }

    // MARK: - buildList rewriting (STDLIB-070)

    func testBuildListRewrittenToKkBuildList() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("buildList")
        let (module, declID) = makeModuleWithCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("buildList"), "buildList should be rewritten")
        XCTAssertTrue(callees.contains("kk_build_list"), "buildList should become kk_build_list")
    }

    func testBuildListCapacityRewrittenToKkBuildListWithCapacity() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let arg0 = arena.appendExpr(.temporary(0))
        let arg1 = arena.appendExpr(.temporary(1))
        let result = arena.appendExpr(.temporary(2))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("buildList"),
                    arguments: [arg0, arg1],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("buildList"), "buildList(capacity) should be rewritten")
        XCTAssertTrue(
            callees.contains("kk_build_list_with_capacity"),
            "buildList(capacity) should become kk_build_list_with_capacity"
        )
    }

    // MARK: - buildMap rewriting (STDLIB-071)

    func testBuildMapRewrittenToKkBuildMap() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("buildMap")
        let (module, declID) = makeModuleWithCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("buildMap"), "buildMap should be rewritten")
        XCTAssertTrue(callees.contains("kk_build_map"), "buildMap should become kk_build_map")
    }

    func testStringSplitResultIsTreatedAsListForPrintlnRewrite() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sourceExpr = arena.appendExpr(.temporary(0))
        let delimitersExpr = arena.appendExpr(.temporary(1))
        let ignoreCaseExpr = arena.appendExpr(.temporary(2))
        let limitExpr = arena.appendExpr(.temporary(3))
        let splitResult = arena.appendExpr(.temporary(4))
        let printlnResult = arena.appendExpr(.temporary(5))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_string_split"),
                    arguments: [sourceExpr, delimitersExpr, ignoreCaseExpr, limitExpr],
                    result: splitResult,
                    canThrow: true,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_println_any"),
                    arguments: [splitResult],
                    result: printlnResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertTrue(callees.contains("kk_string_split"))
        XCTAssertTrue(callees.contains("kk_list_to_string"),
                      "split result should be recognized as list and routed through kk_list_to_string")
    }

    func testRangeReversedRewrittenToKkRangeReversed() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let start = arena.appendExpr(.temporary(0))
        let end = arena.appendExpr(.temporary(1))
        let range = arena.appendExpr(.temporary(2))
        let result = arena.appendExpr(.temporary(3))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_op_rangeTo"),
                    arguments: [start, end],
                    result: range,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("reversed"),
                    arguments: [range],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("reversed"), "range.reversed should be rewritten")
        XCTAssertTrue(callees.contains("kk_range_reversed"), "range.reversed should become kk_range_reversed")
    }

    func testRangeAsReversedIsNotRewrittenToKkRangeReversed() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let start = arena.appendExpr(.temporary(0))
        let end = arena.appendExpr(.temporary(1))
        let range = arena.appendExpr(.temporary(2))
        let result = arena.appendExpr(.temporary(3))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_op_rangeTo"),
                    arguments: [start, end],
                    result: range,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("asReversed"),
                    arguments: [range],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertTrue(callees.contains("asReversed"), "range.asReversed should remain unresolved for non-list receivers")
        XCTAssertFalse(callees.contains("kk_range_reversed"), "range.asReversed must not become kk_range_reversed")
    }

    func testShouldRunAlwaysReturnsTrue() {
        let interner = StringInterner()
        let arena = KIRArena()
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [])], arena: arena)
        let ctx = makeKIRContext(interner: interner)

        let shouldRun = CollectionLiteralLoweringPass().shouldRun(module: module, ctx: ctx)
        XCTAssertTrue(shouldRun)
    }
}
