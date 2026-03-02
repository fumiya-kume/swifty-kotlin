import Foundation

extension DataFlowSemaPhase {
    /// Validates declaration-site variance constraints for all classes and interfaces.
    ///
    /// Kotlin rules:
    /// - `out T` (covariant): T may only appear in **out** positions (return types, val property types).
    ///   Appearing in **in** positions (function parameters, var property setter) is illegal.
    /// - `in T` (contravariant): T may only appear in **in** positions (function parameters).
    ///   Appearing in **out** positions (return types, val/var property types) is illegal.
    /// - **Private members are exempt** from variance checks (Kotlin spec).
    /// - Constructor parameters are exempt from variance checks.
    func validateDeclarationSiteVariance(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateVarianceForDecl(
                    declID: declID,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        }
    }

    private func validateVarianceForDecl(
        declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let decl = ast.arena.decl(declID) else { return }

        switch decl {
        case let .classDecl(classDecl):
            validateVarianceForClassDecl(
                classDecl,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner
            )
        case let .interfaceDecl(interfaceDecl):
            validateVarianceForInterfaceDecl(
                interfaceDecl,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner
            )
        default:
            break
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func validateVarianceForClassDecl(
        _ classDecl: ClassDecl,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let varianceMap = buildVarianceMap(typeParams: classDecl.typeParams)
        guard !varianceMap.isEmpty else { return }

        for funDeclID in classDecl.memberFunctions {
            guard let funDecl = ast.arena.decl(funDeclID),
                  case let .funDecl(fun) = funDecl
            else { continue }
            if fun.modifiers.contains(.private) { continue }

            validateFunctionVariance(
                fun,
                varianceMap: varianceMap,
                ast: ast,
                diagnostics: diagnostics,
                interner: interner
            )
        }

        for propDeclID in classDecl.memberProperties {
            guard let propDecl = ast.arena.decl(propDeclID),
                  case let .propertyDecl(prop) = propDecl
            else { continue }
            if prop.modifiers.contains(.private) { continue }

            validatePropertyVariance(
                prop,
                varianceMap: varianceMap,
                ast: ast,
                diagnostics: diagnostics,
                interner: interner
            )
        }

        for nestedDeclID in classDecl.nestedClasses {
            validateVarianceForDecl(
                declID: nestedDeclID,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner
            )
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func validateVarianceForInterfaceDecl(
        _ interfaceDecl: InterfaceDecl,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let varianceMap = buildVarianceMap(typeParams: interfaceDecl.typeParams)
        guard !varianceMap.isEmpty else { return }

        for funDeclID in interfaceDecl.memberFunctions {
            guard let funDecl = ast.arena.decl(funDeclID),
                  case let .funDecl(fun) = funDecl
            else { continue }
            if fun.modifiers.contains(.private) { continue }

            validateFunctionVariance(
                fun,
                varianceMap: varianceMap,
                ast: ast,
                diagnostics: diagnostics,
                interner: interner
            )
        }

        for propDeclID in interfaceDecl.memberProperties {
            guard let propDecl = ast.arena.decl(propDeclID),
                  case let .propertyDecl(prop) = propDecl
            else { continue }
            if prop.modifiers.contains(.private) { continue }

            validatePropertyVariance(
                prop,
                varianceMap: varianceMap,
                ast: ast,
                diagnostics: diagnostics,
                interner: interner
            )
        }

        for nestedDeclID in interfaceDecl.nestedClasses {
            validateVarianceForDecl(
                declID: nestedDeclID,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner
            )
        }
    }

    /// Builds a map from type parameter name to its declared variance for parameters
    /// that have non-invariant variance (`out` or `in`).
    private func buildVarianceMap(
        typeParams: [TypeParamDecl]
    ) -> [InternedString: TypeVariance] {
        var varianceMap: [InternedString: TypeVariance] = [:]
        for typeParam in typeParams {
            if typeParam.variance != .invariant {
                varianceMap[typeParam.name] = typeParam.variance
            }
        }
        return varianceMap
    }

    /// Represents the expected position for variance checking.
    private enum VariancePosition {
        /// Covariant position: return types, val property types, out type args
        case out
        /// Contravariant position: function parameters, in type args
        case `in`

        /// Flips the position (used for contravariant nesting).
        var flipped: VariancePosition {
            switch self {
            case .out: return .in
            case .in: return .out
            }
        }
    }

    private func validateFunctionVariance(
        _ funDecl: FunDecl,
        varianceMap: [InternedString: TypeVariance],
        ast: ASTModule,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        // Check parameters (in position)
        for valueParam in funDecl.valueParams {
            if let typeRefID = valueParam.type {
                checkTypeRefVariance(
                    typeRefID: typeRefID,
                    position: .in,
                    varianceMap: varianceMap,
                    ast: ast,
                    diagnostics: diagnostics,
                    interner: interner,
                    memberRange: funDecl.range
                )
            }
        }

        // Check return type (out position)
        if let returnTypeRef = funDecl.returnType {
            checkTypeRefVariance(
                typeRefID: returnTypeRef,
                position: .out,
                varianceMap: varianceMap,
                ast: ast,
                diagnostics: diagnostics,
                interner: interner,
                memberRange: funDecl.range
            )
        }
    }

    private func validatePropertyVariance(
        _ propertyDecl: PropertyDecl,
        varianceMap: [InternedString: TypeVariance],
        ast: ASTModule,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let typeRefID = propertyDecl.type else { return }

        if propertyDecl.isVar {
            // var properties: the type is in both in and out positions
            checkTypeRefVariance(
                typeRefID: typeRefID,
                position: .in,
                varianceMap: varianceMap,
                ast: ast,
                diagnostics: diagnostics,
                interner: interner,
                memberRange: propertyDecl.range
            )
            checkTypeRefVariance(
                typeRefID: typeRefID,
                position: .out,
                varianceMap: varianceMap,
                ast: ast,
                diagnostics: diagnostics,
                interner: interner,
                memberRange: propertyDecl.range
            )
        } else {
            // val properties: the type is only in out position (read-only)
            checkTypeRefVariance(
                typeRefID: typeRefID,
                position: .out,
                varianceMap: varianceMap,
                ast: ast,
                diagnostics: diagnostics,
                interner: interner,
                memberRange: propertyDecl.range
            )
        }
    }

    /// Checks a type reference for variance violations.
    ///
    /// - `out T` in an `in` position → error
    /// - `in T` in an `out` position → error
    // swiftlint:disable:next function_parameter_count
    private func checkTypeRefVariance(
        typeRefID: TypeRefID,
        position: VariancePosition,
        varianceMap: [InternedString: TypeVariance],
        ast: ASTModule,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        memberRange: SourceRange
    ) {
        guard let typeRef = ast.arena.typeRef(typeRefID) else { return }

        switch typeRef {
        case let .named(path, typeArgs, _):
            // For a named type, check if the last path component is a type parameter
            // with declared variance. Single-element paths are the typical case for
            // type parameter references like `T`.
            if let name = path.last, let declaredVariance = varianceMap[name] {
                let resolvedName = interner.resolve(name)
                checkVarianceViolation(
                    paramName: resolvedName,
                    declaredVariance: declaredVariance,
                    position: position,
                    diagnostics: diagnostics,
                    range: memberRange
                )
            }

            // Recurse into type arguments
            for typeArg in typeArgs {
                switch typeArg {
                case let .invariant(innerRefID):
                    checkTypeRefVariance(
                        typeRefID: innerRefID,
                        position: position,
                        varianceMap: varianceMap,
                        ast: ast,
                        diagnostics: diagnostics,
                        interner: interner,
                        memberRange: memberRange
                    )
                case let .out(innerRefID):
                    checkTypeRefVariance(
                        typeRefID: innerRefID,
                        position: position,
                        varianceMap: varianceMap,
                        ast: ast,
                        diagnostics: diagnostics,
                        interner: interner,
                        memberRange: memberRange
                    )
                case let .in(innerRefID):
                    checkTypeRefVariance(
                        typeRefID: innerRefID,
                        position: position.flipped,
                        varianceMap: varianceMap,
                        ast: ast,
                        diagnostics: diagnostics,
                        interner: interner,
                        memberRange: memberRange
                    )
                case .star:
                    break
                }
            }

        case let .functionType(paramTypeRefs, returnTypeRef, _, _):
            // Function type parameters are in contravariant position
            for paramRef in paramTypeRefs {
                checkTypeRefVariance(
                    typeRefID: paramRef,
                    position: position.flipped,
                    varianceMap: varianceMap,
                    ast: ast,
                    diagnostics: diagnostics,
                    interner: interner,
                    memberRange: memberRange
                )
            }
            // Function return type is in covariant position
            checkTypeRefVariance(
                typeRefID: returnTypeRef,
                position: position,
                varianceMap: varianceMap,
                ast: ast,
                diagnostics: diagnostics,
                interner: interner,
                memberRange: memberRange
            )

        case let .intersection(parts):
            for partRef in parts {
                checkTypeRefVariance(
                    typeRefID: partRef,
                    position: position,
                    varianceMap: varianceMap,
                    ast: ast,
                    diagnostics: diagnostics,
                    interner: interner,
                    memberRange: memberRange
                )
            }
        }
    }

    private func checkVarianceViolation(
        paramName: String,
        declaredVariance: TypeVariance,
        position: VariancePosition,
        diagnostics: DiagnosticEngine,
        range: SourceRange?
    ) {
        switch (declaredVariance, position) {
        case (.out, .in):
            diagnostics.error(
                "KSWIFTK-SEMA-VARIANCE",
                "Type parameter \(paramName) is declared as 'out' but occurs in 'in' position",
                range: range
            )
        case (.in, .out):
            diagnostics.error(
                "KSWIFTK-SEMA-VARIANCE",
                "Type parameter \(paramName) is declared as 'in' but occurs in 'out' position",
                range: range
            )
        default:
            break
        }
    }
}
