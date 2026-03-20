/// VAL-001: Value class unboxing lowering pass.
///
/// This pass rewrites KIR instructions that reference value class types so that
/// at the ABI level they operate on the underlying primitive type directly,
/// eliminating heap allocation:
///
/// - **Constructor calls** (`kk_object_new` + `<init>` call) for a value class
///   are replaced with a simple copy of the single argument to the result.
///   `Meter(42)` -> `copy(42, result)`.
///
/// - **Property getter calls** via `kk_array_get_inbounds` on value class
///   receivers are replaced with a copy of the receiver to the result.
///   `m.amount` -> `copy(m, result)`.
///
/// This pass must run **before** PropertyLoweringPass and ABILoweringPass.
final class ValueClassUnboxingPass: LoweringPass {
    static let name = "ValueClassUnboxing"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        guard let sema = ctx.sema else { return false }
        let symbols = sema.symbols
        for decl in module.arena.declarations {
            guard case let .nominalType(nominal) = decl else { continue }
            guard let sym = symbols.symbol(nominal.symbol),
                  sym.flags.contains(.valueType),
                  symbols.valueClassUnderlyingType(for: nominal.symbol) != nil
            else { continue }
            return true
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let symbols = sema.symbols
        let types = sema.types

        // Collect value class info: constructor symbols, underlying types,
        // and the set of class symbols that are value classes.
        var valueClassCtors: Set<SymbolID> = []
        var valueClassSymbols: Set<SymbolID> = []

        for decl in module.arena.declarations {
            guard case let .nominalType(nominal) = decl else { continue }
            guard let sym = symbols.symbol(nominal.symbol),
                  sym.flags.contains(.valueType),
                  symbols.valueClassUnderlyingType(for: nominal.symbol) != nil
            else { continue }

            valueClassSymbols.insert(nominal.symbol)

            let children = symbols.children(ofFQName: sym.fqName)
            for childID in children {
                guard let child = symbols.symbol(childID) else { continue }
                if child.kind == .constructor {
                    valueClassCtors.insert(childID)
                }
            }
        }

        guard !valueClassSymbols.isEmpty else {
            module.recordLowering(Self.name)
            return
        }

        let kk_object_new = ctx.interner.intern("kk_object_new")
        let kk_array_get_inbounds = ctx.interner.intern("kk_array_get_inbounds")

        module.arena.transformFunctions { function in
            var updated = function
            let newBody = self.rewriteBody(
                function.body,
                arena: module.arena,
                types: types,
                valueClassCtors: valueClassCtors,
                valueClassSymbols: valueClassSymbols,
                kk_object_new: kk_object_new,
                kk_array_get_inbounds: kk_array_get_inbounds
            )
            updated.replaceBody(newBody)
            return updated
        }

        module.recordLowering(Self.name)
    }

    /// Returns true if the given expression has a type that is a non-null
    /// value class instance.
    private func isValueClassExpr(
        _ expr: KIRExprID,
        arena: KIRArena,
        types: TypeSystem,
        valueClassSymbols: Set<SymbolID>
    ) -> Bool {
        guard let type = arena.exprType(expr) else { return false }
        if case let .classType(classType) = types.kind(of: type),
           classType.nullability == .nonNull,
           valueClassSymbols.contains(classType.classSymbol)
        {
            return true
        }
        return false
    }

    private func rewriteBody(
        _ body: [KIRInstruction],
        arena: KIRArena,
        types: TypeSystem,
        valueClassCtors: Set<SymbolID>,
        valueClassSymbols: Set<SymbolID>,
        kk_object_new: InternedString,
        kk_array_get_inbounds: InternedString
    ) -> [KIRInstruction] {
        // First pass: identify which expressions are kk_object_new results
        // that feed into value class constructors. We need to track these to
        // remove the allocation instruction.
        //
        // The KIR pattern for `val m = Meter(42)` is:
        //   constValue slotCount = 1
        //   constValue classID = ...
        //   call kk_object_new(slotCount, classID) -> allocObj     [symbol: nil]
        //   ... (possibly kk_type_register_super/iface calls) ...
        //   call <init>(allocObj, 42) -> result                     [symbol: ctor]
        //
        // We want to:
        //   1. Remove the kk_object_new call (replace with nop)
        //   2. Remove the associated constValue instructions for slotCount and classID
        //   3. Replace the <init> call with: copy(42, result)
        //   4. Remove kk_type_register_* calls that use the classID

        // Track kk_object_new result expressions -> (slotCountExpr, classIDExpr)
        var allocExprs: Set<KIRExprID> = []
        // Track constValue exprs used only for kk_object_new args
        var allocConstExprs: Set<KIRExprID> = []
        // Track classID expressions used for kk_type_register_* calls
        var classIDExprs: Set<KIRExprID> = []

        // Scan for kk_object_new calls that produce value class typed results
        for instruction in body {
            if case let .call(_, callee, arguments, result, _, _, _) = instruction,
               callee == kk_object_new,
               let result,
               isValueClassExpr(result, arena: arena, types: types, valueClassSymbols: valueClassSymbols)
            {
                allocExprs.insert(result)
                // arguments[0] = slotCount, arguments[1] = classID
                if arguments.count >= 1 {
                    allocConstExprs.insert(arguments[0])
                }
                if arguments.count >= 2 {
                    allocConstExprs.insert(arguments[1])
                    classIDExprs.insert(arguments[1])
                }
            }
        }

        // Scan for kk_type_register_super/iface calls that reference the classID
        // of a value class allocation - collect the constValue expr used for childExpr
        var typeRegisterConstExprs: Set<KIRExprID> = []
        for instruction in body {
            if case let .call(_, callee, arguments, result, _, _, _) = instruction,
               let result
            {
                let calleeName = String(callee.rawValue)
                if calleeName.hasPrefix("kk_type_register_") {
                    // arguments[0] = childExpr (classID), arguments[1] = parentExpr
                    if arguments.count >= 1 {
                        for classIDExpr in classIDExprs {
                            if let classIDKind = arena.expr(classIDExpr),
                               let childKind = arena.expr(arguments[0]),
                               classIDKind == childKind
                            {
                                typeRegisterConstExprs.insert(result)
                                if arguments.count >= 2 {
                                    typeRegisterConstExprs.insert(arguments[1])
                                }
                                typeRegisterConstExprs.insert(arguments[0])
                            }
                        }
                    }
                }
            }
        }

        // Second pass: rewrite
        var result: [KIRInstruction] = []
        result.reserveCapacity(body.count)

        for instruction in body {
            switch instruction {
            // Remove kk_object_new calls for value class allocations
            case let .call(_, callee, _, callResult, _, _, _)
                where callee == kk_object_new
                    && callResult != nil
                    && allocExprs.contains(callResult!):
                result.append(.nop)
                continue

            // Remove constValue instructions that only feed into removed allocations
            case let .constValue(constResult, _)
                where allocConstExprs.contains(constResult):
                result.append(.nop)
                continue

            // Remove kk_type_register_* calls for value class allocations
            case let .call(_, callee, arguments, _, _, _, _)
                where {
                    let name = String(callee.rawValue)
                    guard name.hasPrefix("kk_type_register_") else { return false }
                    guard arguments.count >= 1 else { return false }
                    for classIDExpr in classIDExprs {
                        if let classIDKind = arena.expr(classIDExpr),
                           let childKind = arena.expr(arguments[0]),
                           classIDKind == childKind
                        {
                            return true
                        }
                    }
                    return false
                }():
                result.append(.nop)
                continue

            // Remove constValue instructions used only for type register calls
            case let .constValue(constResult, _)
                where typeRegisterConstExprs.contains(constResult):
                result.append(.nop)
                continue

            // Rewrite value class constructor calls:
            // call <init>(allocObj, value) -> result  =>  copy(value, result)
            case let .call(symbol, callee, arguments, callResult, canThrow, thrownResult, isSuperCall):
                if let symbol, valueClassCtors.contains(symbol),
                   let callResult
                {
                    if arguments.count == 2, allocExprs.contains(arguments[0]) {
                        // arguments[0] is the allocated receiver, arguments[1] is the value
                        result.append(.copy(from: arguments[1], to: callResult))
                        continue
                    } else if arguments.count == 1 {
                        // No explicit receiver
                        result.append(.copy(from: arguments[0], to: callResult))
                        continue
                    }
                }
                // Rewrite kk_array_get_inbounds on value class receivers:
                // call kk_array_get_inbounds(receiver, offset) -> result
                //   => copy(receiver, result)
                if callee == kk_array_get_inbounds,
                   let callResult,
                   arguments.count == 2,
                   isValueClassExpr(arguments[0], arena: arena, types: types, valueClassSymbols: valueClassSymbols)
                {
                    result.append(.copy(from: arguments[0], to: callResult))
                    continue
                }
                result.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: callResult,
                    canThrow: canThrow,
                    thrownResult: thrownResult,
                    isSuperCall: isSuperCall
                ))

            default:
                result.append(instruction)
            }
        }

        return result
    }
}
