import Foundation

@discardableResult
func emitMutableCaptureCellInitialization(
    driver: KIRLoweringDriver,
    symbol: SymbolID,
    currentValue: KIRExprID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) -> KIRExprID {
    let countExpr = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
    instructions.append(.constValue(result: countExpr, value: .intLiteral(1)))

    let cellExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("kk_array_new"),
        arguments: [countExpr],
        result: cellExpr,
        canThrow: false,
        thrownResult: nil
    ))

    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))

    let setResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.anyType)
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("kk_array_set"),
        arguments: [cellExpr, zeroExpr, currentValue],
        result: setResult,
        canThrow: false,
        thrownResult: nil
    ))

    driver.ctx.setMutableCaptureCell(cellExpr, for: symbol)
    return cellExpr
}
