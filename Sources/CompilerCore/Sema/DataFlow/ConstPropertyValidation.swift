import Foundation

extension DataFlowSemaPhase {
    func validateConstPropertyDeclaration(
        _ propertyDecl: PropertyDecl,
        propertySymbol: SymbolID,
        resolvedType: TypeID,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine
    ) {
        guard propertyDecl.modifiers.contains(.const) else {
            return
        }

        if propertyDecl.isVar {
            diagnostics.error(
                "KSWIFTK-SEMA-0080",
                "'const' modifier is not applicable to 'var'.",
                range: propertyDecl.range
            )
        }
        if propertyDecl.initializer == nil {
            diagnostics.error(
                "KSWIFTK-SEMA-0081",
                "'const val' must have an initializer.",
                range: propertyDecl.range
            )
        }
        // When we have an explicit type annotation, validate that the resolved
        // type is a non-null primitive or String.  For inferred types the
        // header phase still has `Any?` as a placeholder, so we only run the
        // check when a concrete annotated type is available.
        if propertyDecl.type != nil {
            let isConstCompatible = switch types.kind(of: resolvedType) {
            case let .primitive(_, nullability):
                nullability == .nonNull
            default:
                false
            }
            if !isConstCompatible {
                diagnostics.error(
                    "KSWIFTK-SEMA-0082",
                    "'const val' type must be a primitive type or String.",
                    range: propertyDecl.range
                )
            }
        }
        // Record the compile-time constant value from the initializer.
        // When no explicit type annotation is present, also validate that
        // the initializer is a compile-time constant literal; if not,
        // reject the declaration since const val requires a constant.
        if let initExpr = propertyDecl.initializer {
            let constCollector = ConstantCollector()
            if let constKind = constCollector.literalConstantExpr(initExpr, ast: ast) {
                symbols.setConstValueExprKind(constKind, for: propertySymbol)
            } else {
                diagnostics.error(
                    "KSWIFTK-SEMA-0083",
                    "'const val' initializer must be a compile-time constant expression.",
                    range: propertyDecl.range
                )
            }
        }
    }
}
