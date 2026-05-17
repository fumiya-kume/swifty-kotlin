/// Emits calls to register annotation metadata for a nominal type.
///
/// This shared helper keeps KClass annotation registration identical across
/// metadata, class-reference, and object-literal lowering paths.
func emitKClassAnnotationRegistration(
    objectSymbol: SymbolID,
    typeTokenExpr: KIRExprID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) {
    let annotations = sema.symbols.annotations(for: objectSymbol)
    guard !annotations.isEmpty else { return }

    let intType = sema.types.intType
    let stringType = sema.types.stringType

    for annotation in annotations {
        let nameInterned = interner.intern(annotation.annotationFQName)
        let nameExpr = arena.appendExpr(.stringLiteral(nameInterned), type: stringType)
        instructions.append(.constValue(result: nameExpr, value: .stringLiteral(nameInterned)))

        let argsEncoded = annotation.arguments.joined(separator: "|")
        let argsInterned = interner.intern(argsEncoded)
        let argsExpr = arena.appendExpr(.stringLiteral(argsInterned), type: stringType)
        instructions.append(.constValue(result: argsExpr, value: .stringLiteral(argsInterned)))

        let argCount = Int64(annotation.arguments.count)
        let argCountExpr = arena.appendExpr(.intLiteral(argCount), type: intType)
        instructions.append(.constValue(result: argCountExpr, value: .intLiteral(argCount)))

        let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_kclass_register_single_annotation"),
            arguments: [typeTokenExpr, nameExpr, argsExpr, argCountExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))
    }
}
