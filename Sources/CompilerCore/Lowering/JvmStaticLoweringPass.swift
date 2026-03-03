import Foundation

/// ANNO-001: @JvmStatic lowering pass.
///
/// For each companion-object member function annotated with `@JvmStatic`,
/// synthesise a forwarding function on the enclosing class that delegates
/// to the companion member.  This makes the function callable as if it were
/// a static member of the outer class (e.g. `MyClass.foo()` instead of
/// `MyClass.Companion.foo()`).
///
/// Must run **before** `ABILoweringPass` so that the forwarding stubs
/// participate in boxing/unboxing as normal functions.
final class JvmStaticLoweringPass: LoweringPass {
    static let name = "JvmStaticLowering"

    func shouldRun(module _: KIRModule, ctx: KIRContext) -> Bool {
        // Only run when sema is available (needed to query annotations).
        ctx.sema != nil
    }

    // swiftlint:disable:next function_body_length
    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let symbols = sema.symbols
        let interner = ctx.interner
        let arena = module.arena

        // Collect new forwarding function declarations to append after iteration.
        var newDecls: [KIRDecl] = []

        for decl in arena.declarations {
            guard case let .function(function) = decl else { continue }

            let funcSymbol = function.symbol
            let annotations = symbols.annotations(for: funcSymbol)

            // Check for @JvmStatic annotation.
            let hasJvmStatic = annotations.contains { ann in
                ann.annotationFQName == "JvmStatic"
                    || ann.annotationFQName == "kotlin.jvm.JvmStatic"
            }
            guard hasJvmStatic else { continue }

            // Verify the function's parent is a companion object.
            guard let parentSymbol = symbols.parentSymbol(for: funcSymbol),
                  let parentInfo = symbols.symbol(parentSymbol),
                  parentInfo.kind == .object
            else {
                continue
            }

            // Find the enclosing class that owns the companion object.
            guard let grandparentSymbol = symbols.parentSymbol(for: parentSymbol),
                  let grandparentInfo = symbols.symbol(grandparentSymbol),
                  grandparentInfo.kind == .class || grandparentInfo.kind == .interface
            else {
                continue
            }

            // Synthesise a forwarding function on the enclosing class.
            // The forwarding function has the same signature and simply
            // delegates to the companion member by calling it.
            let funcInfo = symbols.symbol(funcSymbol)
            let funcName = funcInfo.map { interner.resolve($0.name) } ?? "unknown"

            // Create a synthetic symbol ID for the forwarding stub by building
            // a unique FQ name under the enclosing class.
            let forwardingName = interner.intern("__jvmstatic_\(funcName)_\(funcSymbol.rawValue)")

            // Build the forwarding body: call the companion member and return.
            let resultExpr = arena.appendExpr(
                .temporary(Int32(arena.expressions.count)),
                type: function.returnType
            )

            var forwardingBody: [KIRInstruction] = [.beginBlock]

            // Forward all parameters as arguments.
            let argExprs: [KIRExprID] = function.params.map { param in
                arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            }

            forwardingBody.append(.call(
                symbol: funcSymbol,
                callee: function.name,
                arguments: argExprs,
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ))

            // Return the result of the forwarding call.
            if function.returnType == sema.types.unitType {
                forwardingBody.append(.returnUnit)
            } else {
                forwardingBody.append(.returnValue(resultExpr))
            }
            forwardingBody.append(.endBlock)

            let forwardingFunction = KIRFunction(
                symbol: funcSymbol, // Reuse the same symbol so call sites resolve.
                name: forwardingName,
                params: function.params,
                returnType: function.returnType,
                body: forwardingBody,
                isSuspend: function.isSuspend,
                isInline: function.isInline,
                sourceRange: function.sourceRange
            )

            newDecls.append(.function(forwardingFunction))
        }

        // Append forwarding declarations to the module.
        for decl in newDecls {
            _ = arena.appendDecl(decl)
        }

        module.recordLowering(Self.name)
    }
}
