import Foundation

/// VAL-001: Value class unboxing lowering pass.
///
/// **Status: DISABLED** (`shouldRun` always returns `false`).
///
/// When enabled, this pass would rewrite KIR instructions that reference
/// value class types so that at the ABI level they operate on the
/// underlying primitive type directly:
///
/// - **Constructor calls** for a value class become a simple copy of the
///   single argument to the result.  `Meter(42)` -> `copy(42, result)`.
///
/// - **Property getter calls** for the single wrapped property become a
///   copy of the receiver to the result.  `m.amount` -> `copy(m, result)`.
///
/// This pass is currently disabled because KIR emission already lowers
/// property access to `kk_array_get_inbounds`, which expects a heap
/// object. Rewriting the constructor (which populates that heap object)
/// without also rewriting the property access causes a crash. A future
/// version should intercept both patterns atomically, at which point
/// `shouldRun` should be updated and `ABILoweringPass+BoxingRules`
/// should also re-enable value class unboxing.
///
/// When re-enabled, this pass must run **before** ABILoweringPass.
final class ValueClassUnboxingPass: LoweringPass {
    static let name = "ValueClassUnboxing"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        // Disabled -- see class-level doc comment for rationale.
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let symbols = sema.symbols

        // Collect constructor symbols and wrapped-property symbols for
        // value classes. Note: valueClassWrappedProperties stores
        // property/field symbol IDs (not getter function IDs).
        var valueClassCtors: Set<SymbolID> = []
        var valueClassWrappedProperties: Set<SymbolID> = []

        for decl in module.arena.declarations {
            guard case let .nominalType(nominal) = decl else {
                continue
            }
            guard let sym = symbols.symbol(nominal.symbol),
                  sym.flags.contains(.valueType),
                  let underlyingType = symbols.valueClassUnderlyingType(for: nominal.symbol)
            else {
                continue
            }
            // Find child symbols (constructors, properties) by fqName.
            let children = symbols.children(ofFQName: sym.fqName)
            for childID in children {
                guard let child = symbols.symbol(childID) else {
                    continue
                }
                if child.kind == .constructor {
                    valueClassCtors.insert(childID)
                }
                // Only collect the single primary-constructor-backed property,
                // not computed properties defined in the class body (e.g.
                // `val doubled: Int get() = amount * 2`).  We identify it by
                // matching its propertyType against the recorded underlying
                // type of the value class.
                if child.kind == .property || child.kind == .field {
                    if let propType = symbols.propertyType(for: childID),
                       propType == underlyingType
                    {
                        valueClassWrappedProperties.insert(childID)
                    }
                }
            }
        }

        guard !valueClassCtors.isEmpty || !valueClassWrappedProperties.isEmpty else {
            module.recordLowering(Self.name)
            return
        }

        module.arena.transformFunctions { function in
            var updated = function
            let newBody = self.rewriteBody(
                function.body,
                valueClassCtors: valueClassCtors,
                valueClassWrappedProperties: valueClassWrappedProperties
            )
            updated.replaceBody(newBody)
            return updated
        }

        module.recordLowering(Self.name)
    }

    private func rewriteBody(
        _ body: [KIRInstruction],
        valueClassCtors: Set<SymbolID>,
        valueClassWrappedProperties: Set<SymbolID>
    ) -> [KIRInstruction] {
        body.map { instruction in
            switch instruction {
            // Rewrite value class constructor calls:
            // call <init>(receiver, arg) result -> copy(arg, result)
            //
            // Value classes have exactly one primary constructor parameter, so
            // we only rewrite when the argument count is exactly 2 (receiver +
            // value) or exactly 1 (value only, no explicit receiver).  If the
            // arity does not match, leave the instruction unchanged so we do
            // not silently mis-compile unexpected calling conventions.
            case let .call(symbol, callee: _, arguments, result, canThrow: _, thrownResult: _, isSuperCall: _):
                if let symbol, valueClassCtors.contains(symbol),
                   let result
                {
                    if arguments.count == 2 {
                        // arguments[0] is receiver (the class instance), arguments[1] is the value
                        return .copy(from: arguments[1], to: result)
                    } else if arguments.count == 1 {
                        // arguments[0] is the value (no explicit receiver)
                        return .copy(from: arguments[0], to: result)
                    }
                    // Unexpected arity -- leave instruction as-is.
                }
                // Property getter via .call (non-virtual dispatch):
                // call getter(receiver) result -> copy(receiver, result)
                if let symbol, valueClassWrappedProperties.contains(symbol),
                   let result, arguments.count == 1
                {
                    return .copy(from: arguments[0], to: result)
                }
                return instruction

            // Rewrite property getter calls on value class:
            // virtualCall getter(receiver) result -> copy(receiver, result)
            case let .virtualCall(symbol, callee: _, receiver, arguments: _, result, canThrow: _, thrownResult: _, dispatch: _):
                if let symbol, valueClassWrappedProperties.contains(symbol),
                   let result
                {
                    return .copy(from: receiver, to: result)
                }
                return instruction

            default:
                return instruction
            }
        }
    }
}
