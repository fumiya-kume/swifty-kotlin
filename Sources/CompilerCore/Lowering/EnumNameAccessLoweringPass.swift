import Foundation

/// Rewrites (valueOf result).name to $enumOrdinalToName(ordinal). Runs after
/// DataEnumSealedSynthesisPass which creates the $enumOrdinalToName helper.
final class EnumNameAccessLoweringPass: LoweringPass {
    static let name = "EnumNameAccessLowering"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        let nameCallee = ctx.interner.intern("name")
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                switch instruction {
                case let .call(_, callee, args, _, _, _, _):
                    if callee == nameCallee, args.count == 1 { return true }
                case let .virtualCall(_, callee, _, args, _, _, _, _):
                    if callee == nameCallee, args.isEmpty { return true }
                default:
                    break
                }
            }
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }
        let nameCallee = ctx.interner.intern("name")
        let stringType = sema.types.make(.primitive(.string, .nonNull))

        module.arena.transformFunctions { function in
            var newBody: [KIRInstruction] = []
            for instruction in function.body {
                let receiverAndResult: (KIRExprID?, KIRExprID?) = switch instruction {
                case let .call(_, callee, arguments, result, _, _, _):
                    if callee == nameCallee, arguments.count == 1 {
                        (arguments[0], result)
                    } else {
                        (nil, nil)
                    }
                case let .virtualCall(_, callee, receiver, _, result, _, _, _):
                    if callee == nameCallee { (receiver, result) } else { (nil, nil) }
                default:
                    (nil, nil)
                }
                let (receiverExpr, result) = receiverAndResult
                guard let receiver = receiverExpr else {
                    newBody.append(instruction)
                    continue
                }
                let classSymbol: SymbolID? = {
                    if let argType = module.arena.exprType(receiver),
                       case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(argType)),
                       let sym = sema.symbols.symbol(classType.classSymbol),
                       sym.kind == .enumClass
                    {
                        return classType.classSymbol
                    }
                    if case let .call(sym, _, args, _, _, _, _) = instruction,
                       let propSym = sym,
                       args.count == 1,
                       let propInfo = sema.symbols.symbol(propSym),
                       (propInfo.kind == .property || propInfo.kind == .field),
                       propInfo.name == nameCallee,
                       let parent = sema.symbols.parentSymbol(for: propSym),
                       let parentInfo = sema.symbols.symbol(parent),
                       parentInfo.kind == .enumClass
                    {
                        return parent
                    }
                    if case let .virtualCall(sym, _, _, _, _, _, _, _) = instruction,
                       let propSym = sym,
                       let propInfo = sema.symbols.symbol(propSym),
                       (propInfo.kind == .property || propInfo.kind == .field),
                       propInfo.name == nameCallee,
                       let parent = sema.symbols.parentSymbol(for: propSym),
                       let parentInfo = sema.symbols.symbol(parent),
                       parentInfo.kind == .enumClass
                    {
                        return parent
                    }
                    return nil
                }()
                if let classSymbol,
                   let classSym = sema.symbols.symbol(classSymbol)
                {
                    let helperName = ctx.interner.intern("$enumOrdinalToName")
                    let fqName = classSym.fqName + [helperName]
                    if let helperSymbol = sema.symbols.lookupAll(fqName: fqName).first(where: { id in
                        sema.symbols.symbol(id).map { $0.kind == .function } ?? false
                    }) {
                        let targetResult = result ?? module.arena.appendExpr(
                            .temporary(Int32(module.arena.expressions.count)),
                            type: stringType
                        )
                        newBody.append(.call(
                            symbol: helperSymbol,
                            callee: helperName,
                            arguments: [receiver],
                            result: targetResult,
                            canThrow: false,
                            thrownResult: nil,
                            isSuperCall: false
                        ))
                        continue
                    }
                }
                newBody.append(instruction)
            }
            var updated = function
            updated.replaceBody(newBody)
            return updated
        }
        module.recordLowering(Self.name)
    }
}
