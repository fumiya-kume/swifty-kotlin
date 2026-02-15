import XCTest
@testable import CompilerCore

final class KIRModelsCoverageTests: XCTestCase {
    func testArenaAppendLookupTransformAndModuleDerivedCounts() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let symA = symbols.define(
            kind: .function,
            name: interner.intern("alpha"),
            fqName: [interner.intern("pkg"), interner.intern("alpha")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let symB = symbols.define(
            kind: .function,
            name: interner.intern("beta"),
            fqName: [interner.intern("pkg"), interner.intern("beta")],
            declSite: nil,
            visibility: .public,
            flags: []
        )

        let arena = KIRArena()
        let expr0 = arena.appendExpr(.intLiteral(10))
        let expr1 = arena.appendExpr(.boolLiteral(true))
        let expr2 = arena.appendExpr(.stringLiteral(interner.intern("hi")))
        let expr3 = arena.appendExpr(.symbolRef(symA))
        let expr4 = arena.appendExpr(.temporary(4))
        let expr5 = arena.appendExpr(.unit)

        let fnA = KIRFunction(
            symbol: symA,
            name: interner.intern("alpha"),
            params: [KIRParameter(symbol: symA, type: TypeSystem().anyType)],
            returnType: TypeSystem().anyType,
            body: [
                .nop,
                .beginBlock,
                .constValue(result: expr0, value: .intLiteral(10)),
                .constValue(result: expr1, value: .boolLiteral(true)),
                .constValue(result: expr2, value: .stringLiteral(interner.intern("txt"))),
                .constValue(result: expr3, value: .symbolRef(symB)),
                .constValue(result: expr4, value: .temporary(4)),
                .constValue(result: expr5, value: .unit),
                .binary(op: .add, lhs: expr0, rhs: expr0, result: expr4),
                .call(symbol: symB, callee: interner.intern("beta"), arguments: [expr0], result: expr4, outThrown: false),
                .returnValue(expr4),
                .endBlock
            ],
            isSuspend: false,
            isInline: true
        )
        let fnB = KIRFunction(
            symbol: symB,
            name: interner.intern("beta"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let declFnA = arena.appendDecl(.function(fnA))
        _ = arena.appendDecl(.global(KIRGlobal(symbol: symA, type: TypeSystem().anyType)))
        _ = arena.appendDecl(.nominalType(KIRNominalType(symbol: symB)))
        _ = arena.appendDecl(.function(fnB))

        XCTAssertNotNil(arena.decl(declFnA))
        XCTAssertNil(arena.decl(KIRDeclID(rawValue: -1)))
        XCTAssertNil(arena.decl(KIRDeclID(rawValue: 999)))
        XCTAssertEqual(arena.expr(expr0), .intLiteral(10))
        XCTAssertNil(arena.expr(KIRExprID(rawValue: -1)))
        XCTAssertNil(arena.expr(KIRExprID(rawValue: 999)))

        arena.transformFunctions { fn in
            var copy = fn
            copy.body.append(.nop)
            return copy
        }

        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declFnA])], arena: arena)
        XCTAssertEqual(module.functionCount, 2)
        XCTAssertEqual(module.symbolCount, 2)

        module.recordLowering("NormalizeBlocks")
        module.recordLowering("OperatorLowering")
        let dump = module.dump(interner: interner, symbols: symbols)

        XCTAssertTrue(dump.contains("function alpha"))
        XCTAssertTrue(dump.contains("global"))
        XCTAssertTrue(dump.contains("type beta"))
        XCTAssertTrue(dump.contains("const r"))
        XCTAssertTrue(dump.contains("binary add"))
        XCTAssertTrue(dump.contains("call beta"))
        XCTAssertTrue(dump.contains("return r"))
        XCTAssertTrue(dump.contains("lowerings: NormalizeBlocks, OperatorLowering"))
    }
}
