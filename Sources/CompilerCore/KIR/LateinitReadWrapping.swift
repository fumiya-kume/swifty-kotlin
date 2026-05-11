/// If the symbol being read is a lateinit property, wrap the load with a
/// `kk_lateinit_get_or_throw` call so an `UninitializedPropertyAccessException`
/// is raised when the underlying storage is still the sentinel.
///
/// Shared between `ExprLowerer` (for stored-property reads) and
/// `CallLowerer` (for member-access reads). Both callers used the same
/// implementation; this file is the single source of truth.
func wrapLateinitReadIfNeeded(
    _ valueExpr: KIRExprID,
    symbol: SymbolID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) -> KIRExprID {
    guard let symbolInfo = sema.symbols.symbol(symbol),
          symbolInfo.flags.contains(.lateinitProperty)
    else {
        return valueExpr
    }
    let propertyNameExpr = arena.appendExpr(
        .stringLiteral(symbolInfo.name),
        type: sema.types.make(.primitive(.string, .nonNull))
    )
    instructions.append(.constValue(result: propertyNameExpr, value: .stringLiteral(symbolInfo.name)))
    let result = arena.appendExpr(
        .temporary(Int32(arena.expressions.count)),
        type: arena.exprType(valueExpr) ?? sema.types.anyType
    )
    let thrownResult = arena.appendExpr(
        .temporary(Int32(arena.expressions.count)),
        type: sema.types.nullableAnyType
    )
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("kk_lateinit_get_or_throw"),
        arguments: [valueExpr, propertyNameExpr],
        result: result,
        canThrow: true,
        thrownResult: thrownResult
    ))
    return result
}
