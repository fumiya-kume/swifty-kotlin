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

    private func makeModuleWithZeroArgCall(callee: InternedString, interner: StringInterner, arena: KIRArena) -> (KIRModule, KIRDeclID) {
        let result = arena.appendExpr(.temporary(0))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: callee, arguments: [], result: result, canThrow: false, thrownResult: nil),
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

    func testArrayListOfRewrittenToKkListOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("arrayListOf")
        let (module, declID) = makeModuleWithCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("arrayListOf"), "arrayListOf should be rewritten")
        XCTAssertTrue(callees.contains("kk_list_of"), "arrayListOf should become kk_list_of")
    }

    func testEmptyListRewrittenToKkListOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("emptyList")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("emptyList"), "emptyList should be rewritten")
        XCTAssertTrue(callees.contains("kk_emptyList"), "emptyList should become kk_emptyList")
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
        XCTAssertTrue(callees.contains("kk_list_of_not_null"), "listOfNotNull should become kk_list_of_not_null")
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

    func testLinkedMapOfRewrittenToKkMapOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let pair = arena.appendExpr(.temporary(0))
        let result = arena.appendExpr(.temporary(1))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("linkedMapOf"), arguments: [pair], result: result, canThrow: false, thrownResult: nil),
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
        XCTAssertFalse(callees.contains("linkedMapOf"), "linkedMapOf should be rewritten")
        XCTAssertTrue(callees.contains("kk_map_of"), "linkedMapOf should become kk_map_of")
    }

    func testHashMapOfRewrittenToKkMapOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let pair = arena.appendExpr(.temporary(0))
        let result = arena.appendExpr(.temporary(1))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("hashMapOf"), arguments: [pair], result: result, canThrow: false, thrownResult: nil),
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
        XCTAssertFalse(callees.contains("hashMapOf"), "hashMapOf should be rewritten")
        XCTAssertTrue(callees.contains("kk_map_of"), "hashMapOf should become kk_map_of")
    }

    func testEmptyMapRewrittenToKkMapOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("emptyMap")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("emptyMap"), "emptyMap should be rewritten")
        XCTAssertTrue(callees.contains("kk_emptyMap"), "emptyMap should become kk_emptyMap")
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

    // MARK: - emptySet rewriting

    func testEmptySetRewrittenToKkSetOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("emptySet")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("emptySet"), "emptySet should be rewritten")
        XCTAssertTrue(callees.contains("kk_emptySet"), "emptySet should become kk_emptySet")
    }

    // MARK: - Zero-arg factory rewriting

    func testZeroArgListOfRewrittenToKkEmptyList() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("listOf")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("listOf"), "listOf() with zero args should be rewritten")
        XCTAssertTrue(callees.contains("kk_emptyList"), "listOf() should become kk_emptyList")
    }

    func testZeroArgSetOfRewrittenToKkEmptySet() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("setOf")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("setOf"), "setOf() with zero args should be rewritten")
        XCTAssertTrue(callees.contains("kk_emptySet"), "setOf() should become kk_emptySet")
    }

    func testZeroArgMapOfRewrittenToKkEmptyMap() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("mapOf")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("mapOf"), "mapOf() with zero args should be rewritten")
        XCTAssertTrue(callees.contains("kk_emptyMap"), "mapOf() should become kk_emptyMap")
    }

    // MARK: - Zero-arg mutable factory rewriting

    func testZeroArgMutableListOfRewrittenToKkListOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("mutableListOf")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("mutableListOf"), "mutableListOf() should be rewritten")
        XCTAssertTrue(callees.contains("kk_list_of"), "mutableListOf() should become kk_list_of (fresh mutable)")
    }

    func testZeroArgArrayListOfRewrittenToKkListOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("arrayListOf")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("arrayListOf"), "arrayListOf() should be rewritten")
        XCTAssertTrue(callees.contains("kk_list_of"), "arrayListOf() should become kk_list_of (fresh mutable)")
    }

    func testZeroArgMutableSetOfRewrittenToKkSetOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("mutableSetOf")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("mutableSetOf"), "mutableSetOf() should be rewritten")
        XCTAssertTrue(callees.contains("kk_set_of"), "mutableSetOf() should become kk_set_of (fresh mutable)")
    }

    func testZeroArgLinkedSetOfRewrittenToKkSetOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("linkedSetOf")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("linkedSetOf"), "linkedSetOf() should be rewritten")
        XCTAssertTrue(callees.contains("kk_set_of"), "linkedSetOf() should become kk_set_of (fresh mutable)")
    }

    func testZeroArgHashSetOfRewrittenToKkSetOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("hashSetOf")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("hashSetOf"), "hashSetOf() should be rewritten")
        XCTAssertTrue(callees.contains("kk_set_of"), "hashSetOf() should become kk_set_of (fresh mutable)")
    }

    func testZeroArgMutableMapOfRewrittenToKkMapOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("mutableMapOf")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("mutableMapOf"), "mutableMapOf() should be rewritten")
        XCTAssertTrue(callees.contains("kk_map_of"), "mutableMapOf() should become kk_map_of (fresh mutable)")
    }

    func testZeroArgLinkedMapOfRewrittenToKkMapOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("linkedMapOf")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("linkedMapOf"), "linkedMapOf() should be rewritten")
        XCTAssertTrue(callees.contains("kk_map_of"), "linkedMapOf() should become kk_map_of (fresh mutable)")
    }

    func testZeroArgHashMapOfRewrittenToKkMapOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("hashMapOf")
        let (module, declID) = makeModuleWithZeroArgCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("hashMapOf"), "hashMapOf() should be rewritten")
        XCTAssertTrue(callees.contains("kk_map_of"), "hashMapOf() should become kk_map_of (fresh mutable)")
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

    func testSetOfNotNullRewrittenToKkSetOfNotNull() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("setOfNotNull")
        let (module, declID) = makeModuleWithCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("setOfNotNull"), "setOfNotNull should be rewritten")
        XCTAssertTrue(
            callees.contains("kk_set_of_not_null"),
            "setOfNotNull should be rewritten to kk_set_of_not_null, got: \(callees)"
        )
    }

    func testLinkedSetOfRewrittenToKkSetOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("linkedSetOf")
        let (module, declID) = makeModuleWithCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("linkedSetOf"), "linkedSetOf should be rewritten")
        XCTAssertTrue(callees.contains("kk_set_of"), "linkedSetOf should become kk_set_of")
    }

    func testHashSetOfRewrittenToKkSetOf() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let callee = interner.intern("hashSetOf")
        let (module, declID) = makeModuleWithCall(callee: callee, interner: interner, arena: arena)
        let ctx = makeKIRContext(interner: interner)

        try runPass(module: module, kirCtx: ctx)

        let callees = calleesInDecl(declID, module: module, interner: interner)
        XCTAssertFalse(callees.contains("hashSetOf"), "hashSetOf should be rewritten")
        XCTAssertTrue(callees.contains("kk_set_of"), "hashSetOf should become kk_set_of")
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

    func testListMinusCollectionResultIsTreatedAsListForPrintlnRewrite() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let listInput = arena.appendExpr(.temporary(0))
        let listExpr = arena.appendExpr(.temporary(1))
        let rhsExpr = arena.appendExpr(.temporary(2))
        let minusResult = arena.appendExpr(.temporary(3))
        let printlnResult = arena.appendExpr(.temporary(4))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_list_of"),
                    arguments: [listInput],
                    result: listExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_list_minus_collection"),
                    arguments: [listExpr, rhsExpr],
                    result: minusResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_println_any"),
                    arguments: [minusResult],
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
        XCTAssertTrue(callees.contains("kk_list_minus_collection"))
        XCTAssertTrue(
            callees.contains("kk_list_to_string"),
            "list minus collection result should be recognized as list and routed through kk_list_to_string"
        )
    }

    func testRangeReversedRewrittenToKkRangeReversed() throws {
        let source = """
        fun main() {
            val range = 1..10
            val reversed = range.reversed()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "RangeReversedRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertFalse(callees.contains("reversed"), "range.reversed should be rewritten")
            XCTAssertTrue(callees.contains("kk_range_reversed"), "range.reversed should become kk_range_reversed")
        }
    }

    func testRangeEndExclusiveRewrittenToKkRangeEndExclusive() throws {
        let source = """
        fun main() {
            val range = 1..10
            val exclusive = range.endExclusive
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "RangeEndExclusiveRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertFalse(callees.contains("endExclusive"), "range.endExclusive should be rewritten")
            XCTAssertTrue(callees.contains("kk_range_endExclusive"), "range.endExclusive should become kk_range_endExclusive")
        }
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

    // MARK: - LOWERING-001: Static type based collection classification

    /// Helper to create a KIRContext with SemaModule that has collection type symbols.
    private func makeKIRContextWithSema(
        interner: StringInterner
    ) -> (KIRContext, TypeSystem, SymbolTable) {
        let types = TypeSystem()
        let symbols = SymbolTable()
        let bindings = BindingTable()
        let diag = DiagnosticEngine()
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diag
        )
        let options = CompilerOptions(
            moduleName: "CollLiteralTest",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let ctx = KIRContext(
            diagnostics: diag,
            options: options,
            interner: interner,
            sema: sema
        )
        return (ctx, types, symbols)
    }

    /// Define a nominal type symbol with the given simple name and return its SymbolID.
    private func defineNominalSymbol(
        name: String,
        interner: StringInterner,
        symbols: SymbolTable
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = [interner.intern("kotlin"), interner.intern("collections"), internedName]
        return symbols.define(
            kind: .interface,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: []
        )
    }

    /// Build a one-function module with a single virtualCall on a receiver
    /// whose static type is `receiverTypeName` (e.g. "List", "Set", "Map"),
    /// run the lowering pass, and return the resulting callees.
    private func buildAndLowerVirtualCall(
        receiverTypeName: String,
        callee: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String] {
        let interner = StringInterner()
        let arena = KIRArena()
        let (ctx, types, symbols) = makeKIRContextWithSema(interner: interner)

        let symbolID = defineNominalSymbol(
            name: receiverTypeName, interner: interner, symbols: symbols
        )
        let receiverType = types.make(.classType(ClassType(classSymbol: symbolID)))

        let paramExpr = arena.appendExpr(.symbolRef(SymbolID(rawValue: 100)), type: receiverType)
        let resultExpr = arena.appendExpr(.temporary(1))

        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("foo"),
            params: [KIRParameter(symbol: SymbolID(rawValue: 100), type: receiverType)],
            returnType: types.unitType,
            body: [
                .constValue(result: paramExpr, value: .symbolRef(SymbolID(rawValue: 100))),
                .virtualCall(
                    symbol: nil,
                    callee: interner.intern(callee),
                    receiver: paramExpr,
                    arguments: [],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .vtable(slot: 0)
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)

        try CollectionLiteralLoweringPass().run(module: module, ctx: ctx)

        return calleesInDecl(declID, module: module, interner: interner)
    }

    func testVirtualCallOnListTypedParameterRewritesToKkListSize() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "List", callee: "size")
        XCTAssertTrue(
            callees.contains("kk_list_size"),
            "virtualCall(size) on List-typed parameter should be rewritten to kk_list_size, got: \(callees)"
        )
    }

    func testVirtualCallOnSetTypedParameterRewritesToKkSetSize() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "Set", callee: "size")
        XCTAssertTrue(
            callees.contains("kk_set_size"),
            "virtualCall(size) on Set-typed parameter should be rewritten to kk_set_size, got: \(callees)"
        )
    }

    func testVirtualCallOnMapTypedParameterRewritesToKkMapSize() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "Map", callee: "size")
        XCTAssertTrue(
            callees.contains("kk_map_size"),
            "virtualCall(size) on Map-typed parameter should be rewritten to kk_map_size, got: \(callees)"
        )
    }

    func testVirtualCallOnMutableListTypedParameterRewritesToKkListIsEmpty() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "MutableList", callee: "isEmpty")
        XCTAssertTrue(
            callees.contains("kk_list_is_empty"),
            "virtualCall(isEmpty) on MutableList-typed parameter should be rewritten to kk_list_is_empty, got: \(callees)"
        )
    }

    // MARK: - LOWERING-001: Extended non-tracked receiver tests

    /// Build a one-function module with a virtualCall that has arguments,
    /// on a receiver whose static type is `receiverTypeName`.
    private func buildAndLowerVirtualCallWithArgs(
        receiverTypeName: String,
        callee: String,
        argCount: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String] {
        let interner = StringInterner()
        let arena = KIRArena()
        let (ctx, types, symbols) = makeKIRContextWithSema(interner: interner)

        let symbolID = defineNominalSymbol(
            name: receiverTypeName, interner: interner, symbols: symbols
        )
        let receiverType = types.make(.classType(ClassType(classSymbol: symbolID)))

        let paramExpr = arena.appendExpr(.symbolRef(SymbolID(rawValue: 100)), type: receiverType)
        let resultExpr = arena.appendExpr(.temporary(1))

        var argExprs: [KIRExprID] = []
        var bodyInstructions: [KIRInstruction] = [
            .constValue(result: paramExpr, value: .symbolRef(SymbolID(rawValue: 100)))
        ]
        for i in 0..<argCount {
            let argExpr = arena.appendExpr(.temporary(Int32(10 + i)))
            argExprs.append(argExpr)
            bodyInstructions.append(.constValue(result: argExpr, value: .intLiteral(Int64(i))))
        }
        bodyInstructions.append(.virtualCall(
            symbol: nil,
            callee: interner.intern(callee),
            receiver: paramExpr,
            arguments: argExprs,
            result: resultExpr,
            canThrow: false,
            thrownResult: nil,
            dispatch: .vtable(slot: 0)
        ))
        bodyInstructions.append(.returnUnit)

        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("foo"),
            params: [KIRParameter(symbol: SymbolID(rawValue: 100), type: receiverType)],
            returnType: types.unitType,
            body: bodyInstructions,
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)

        try CollectionLiteralLoweringPass().run(module: module, ctx: ctx)

        return calleesInDecl(declID, module: module, interner: interner)
    }

    func testVirtualCallOnArrayTypedParameterRewritesToKkArrayToList() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "Array", callee: "toList")
        XCTAssertTrue(
            callees.contains("kk_array_toList"),
            "virtualCall(toList) on Array-typed parameter should be rewritten to kk_array_toList, got: \(callees)"
        )
    }

    func testVirtualCallOnArrayTypedParameterRewritesToKkArraySize() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "Array", callee: "size")
        XCTAssertTrue(
            callees.contains("kk_array_size"),
            "virtualCall(size) on Array-typed parameter should be rewritten to kk_array_size, got: \(callees)"
        )
    }

    func testVirtualCallOnArrayTypedParameterRewritesToKkArrayAll() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "Array", callee: "all", argCount: 1
        )
        XCTAssertTrue(
            callees.contains("kk_array_all"),
            "virtualCall(all) on Array-typed parameter should be rewritten to kk_array_all, got: \(callees)"
        )
    }

    func testVirtualCallOnListTypedParameterRewritesToKkListAsSequence() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "List", callee: "asSequence")
        XCTAssertTrue(
            callees.contains("kk_list_asSequence"),
            "virtualCall(asSequence) on List-typed parameter should be rewritten to kk_list_asSequence, got: \(callees)"
        )
    }

    func testVirtualCallOnListTypedParameterRewritesToKkListContains() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "List", callee: "contains", argCount: 1
        )
        XCTAssertTrue(
            callees.contains("kk_list_contains"),
            "virtualCall(contains) on List-typed parameter should be rewritten to kk_list_contains, got: \(callees)"
        )
    }

    func testVirtualCallOnSetTypedParameterRewritesToKkSetContains() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "Set", callee: "contains", argCount: 1
        )
        XCTAssertTrue(
            callees.contains("kk_set_contains"),
            "virtualCall(contains) on Set-typed parameter should be rewritten to kk_set_contains, got: \(callees)"
        )
    }

    func testVirtualCallOnSetTypedParameterRewritesToKkSetIsEmpty() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "Set", callee: "isEmpty")
        XCTAssertTrue(
            callees.contains("kk_set_is_empty"),
            "virtualCall(isEmpty) on Set-typed parameter should be rewritten to kk_set_is_empty, got: \(callees)"
        )
    }

    func testVirtualCallOnMapTypedParameterRewritesToKkMapIsEmpty() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "Map", callee: "isEmpty")
        XCTAssertTrue(
            callees.contains("kk_map_is_empty"),
            "virtualCall(isEmpty) on Map-typed parameter should be rewritten to kk_map_is_empty, got: \(callees)"
        )
    }

    func testVirtualCallOnListTypedParameterRewritesToKkListReversed() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "List", callee: "reversed")
        XCTAssertTrue(
            callees.contains("kk_list_reversed"),
            "virtualCall(reversed) on List-typed parameter should be rewritten to kk_list_reversed, got: \(callees)"
        )
    }

    func testVirtualCallOnListTypedParameterRewritesToKkListSorted() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "List", callee: "sorted")
        XCTAssertTrue(
            callees.contains("kk_list_sorted"),
            "virtualCall(sorted) on List-typed parameter should be rewritten to kk_list_sorted, got: \(callees)"
        )
    }

    func testVirtualCallOnListTypedParameterRewritesToKkListDistinct() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "List", callee: "distinct")
        XCTAssertTrue(
            callees.contains("kk_list_distinct"),
            "virtualCall(distinct) on List-typed parameter should be rewritten to kk_list_distinct, got: \(callees)"
        )
    }

    func testVirtualCallOnListTypedParameterRewritesToKkListIndexOf() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "List", callee: "indexOf", argCount: 1
        )
        XCTAssertTrue(
            callees.contains("kk_list_indexOf"),
            "virtualCall(indexOf) on List-typed parameter should be rewritten to kk_list_indexOf, got: \(callees)"
        )
    }

    func testVirtualCallOnListTypedParameterRewritesToKkListTake() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "List", callee: "take", argCount: 1
        )
        XCTAssertTrue(
            callees.contains("kk_list_take"),
            "virtualCall(take) on List-typed parameter should be rewritten to kk_list_take, got: \(callees)"
        )
    }

    func testVirtualCallOnListTypedParameterRewritesToKkListDrop() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "List", callee: "drop", argCount: 1
        )
        XCTAssertTrue(
            callees.contains("kk_list_drop"),
            "virtualCall(drop) on List-typed parameter should be rewritten to kk_list_drop, got: \(callees)"
        )
    }

    func testVirtualCallOnListTypedParameterRewritesToKkListDropLastWhile() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "List", callee: "dropLastWhile", argCount: 1
        )
        XCTAssertTrue(
            callees.contains("kk_list_dropLastWhile"),
            "virtualCall(dropLastWhile) on List-typed parameter should be rewritten to kk_list_dropLastWhile, got: \(callees)"
        )
    }

    func testVirtualCallOnSequenceTypedParameterRewritesToKkSequenceToList() throws {
        let callees = try buildAndLowerVirtualCall(receiverTypeName: "Sequence", callee: "toList")
        XCTAssertTrue(
            callees.contains("kk_sequence_to_list"),
            "virtualCall(toList) on Sequence-typed parameter should be rewritten to kk_sequence_to_list, got: \(callees)"
        )
    }

    func testVirtualCallOnSequenceTypedParameterRewritesToKkSequenceToCollection() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "Sequence", callee: "toCollection", argCount: 1
        )
        XCTAssertTrue(
            callees.contains("kk_sequence_toCollection"),
            "virtualCall(toCollection) on Sequence-typed parameter should be rewritten to kk_sequence_toCollection, got: \(callees)"
        )
    }

    func testVirtualCallOnSequenceTypedParameterRewritesToKkSequenceMapTo() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "Sequence", callee: "mapTo", argCount: 2
        )
        XCTAssertTrue(
            callees.contains("kk_sequence_mapTo"),
            "virtualCall(mapTo) on Sequence-typed parameter should be rewritten to kk_sequence_mapTo, got: \(callees)"
        )
    }

    func testVirtualCallOnSequenceTypedParameterRewritesToKkSequenceMapNotNullTo() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "Sequence", callee: "mapNotNullTo", argCount: 2
        )
        XCTAssertTrue(
            callees.contains("kk_sequence_mapNotNullTo"),
            "virtualCall(mapNotNullTo) on Sequence-typed parameter should be rewritten to kk_sequence_mapNotNullTo, got: \(callees)"
        )
    }

    func testVirtualCallOnSequenceTypedParameterRewritesToKkSequenceMapIndexedTo() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "Sequence", callee: "mapIndexedTo", argCount: 2
        )
        XCTAssertTrue(
            callees.contains("kk_sequence_mapIndexedTo"),
            "virtualCall(mapIndexedTo) on Sequence-typed parameter should be rewritten to kk_sequence_mapIndexedTo, got: \(callees)"
        )
    }

    func testVirtualCallOnSequenceTypedParameterRewritesToKkSequenceMapIndexedNotNullTo() throws {
        let callees = try buildAndLowerVirtualCallWithArgs(
            receiverTypeName: "Sequence", callee: "mapIndexedNotNullTo", argCount: 2
        )
        XCTAssertTrue(
            callees.contains("kk_sequence_mapIndexedNotNullTo"),
            "virtualCall(mapIndexedNotNullTo) on Sequence-typed parameter should be rewritten to kk_sequence_mapIndexedNotNullTo, got: \(callees)"
        )
    }


    func testWithoutSemaContextVirtualCallIsNotRewritten() throws {
        let interner = StringInterner()
        let arena = KIRArena()

        // Create a parameter expression with a type but NO sema context.
        let types = TypeSystem()
        let dummySymbol = SymbolID(rawValue: 999)
        let listType = types.make(.classType(ClassType(classSymbol: dummySymbol)))

        let paramExpr = arena.appendExpr(.symbolRef(SymbolID(rawValue: 100)), type: listType)
        let resultExpr = arena.appendExpr(.temporary(1))

        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("foo"),
            params: [KIRParameter(symbol: SymbolID(rawValue: 100), type: listType)],
            returnType: types.unitType,
            body: [
                .constValue(result: paramExpr, value: .symbolRef(SymbolID(rawValue: 100))),
                .virtualCall(
                    symbol: nil,
                    callee: interner.intern("size"),
                    receiver: paramExpr,
                    arguments: [],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .vtable(slot: 0)
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)
        // Context without sema — should NOT rewrite.
        let ctx = makeKIRContext(interner: interner)

        try CollectionLiteralLoweringPass().run(module: module, ctx: ctx)

        // Virtual call should remain as-is (no kk_list_size call generated).
        guard case let .function(resultFn) = module.arena.decl(declID) else {
            XCTFail("Expected function"); return
        }
        let hasVirtualCall = resultFn.body.contains { instr in
            if case .virtualCall = instr { return true }
            return false
        }
        XCTAssertTrue(
            hasVirtualCall,
            "Without sema context, virtual call should remain unrewritten"
        )
    }
}
