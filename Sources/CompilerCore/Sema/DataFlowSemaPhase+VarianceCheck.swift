
extension DataFlowSemaPhase {
    // Validates declaration-site variance constraints for all classes and interfaces.
    // Kotlin rules:
    // - `out T` (covariant): T may only appear in out positions (return types, val property types).
    // - `in T` (contravariant): T may only appear in in positions (function parameters).
    // - Private members are exempt from variance checks (Kotlin spec).
    // - Constructor parameters are exempt from variance checks.
    // swiftlint:disable:next function_parameter_count
    func validateDeclarationSiteVariance(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types _: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let env = VarianceCheckEnv(ast: ast, symbols: symbols, bindings: bindings,
                                   diagnostics: diagnostics, interner: interner)
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateVarianceForDecl(declID: declID, env: env)
            }
        }
    }

    /// Represents the expected position for variance checking.
    private enum VariancePosition {
        /// Covariant position: return types, val property types, out type args
        case out
        /// Contravariant position: function parameters, in type args
        case contravariant

        var flipped: VariancePosition {
            switch self {
            case .out: .contravariant
            case .contravariant: .out
            }
        }
    }

    /// Bundles the immutable context needed by every variance-check helper.
    private struct VarianceCheckEnv {
        let ast: ASTModule
        let symbols: SymbolTable
        let bindings: BindingTable
        let diagnostics: DiagnosticEngine
        let interner: StringInterner
    }

    // MARK: - Declaration dispatch

    private func validateVarianceForDecl(declID: DeclID, env: VarianceCheckEnv) {
        guard let decl = env.ast.arena.decl(declID) else { return }
        switch decl {
        case let .classDecl(classDecl):
            validateVarianceForClassDecl(classDecl, env: env)
        case let .interfaceDecl(interfaceDecl):
            validateVarianceForInterfaceDecl(interfaceDecl, env: env)
        default:
            break
        }
    }

    private func validateVarianceForClassDecl(_ classDecl: ClassDecl, env: VarianceCheckEnv) {
        let varianceMap = buildVarianceMap(typeParams: classDecl.typeParams)
        guard !varianceMap.isEmpty else { return }

        validateMemberFunctions(classDecl.memberFunctions, varianceMap: varianceMap, env: env)
        validateMemberProperties(classDecl.memberProperties, varianceMap: varianceMap, env: env)

        for nestedDeclID in classDecl.nestedClasses {
            validateVarianceForDecl(declID: nestedDeclID, env: env)
        }
    }

    private func validateVarianceForInterfaceDecl(_ iface: InterfaceDecl, env: VarianceCheckEnv) {
        let varianceMap = buildVarianceMap(typeParams: iface.typeParams)
        guard !varianceMap.isEmpty else { return }

        validateMemberFunctions(iface.memberFunctions, varianceMap: varianceMap, env: env)
        validateMemberProperties(iface.memberProperties, varianceMap: varianceMap, env: env)

        for nestedDeclID in iface.nestedClasses {
            validateVarianceForDecl(declID: nestedDeclID, env: env)
        }
    }

    // MARK: - Member iteration

    private func validateMemberFunctions(
        _ funDeclIDs: [DeclID],
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv
    ) {
        for funDeclID in funDeclIDs {
            guard let funDecl = env.ast.arena.decl(funDeclID),
                  case let .funDecl(fun) = funDecl,
                  !fun.modifiers.contains(.private)
            else { continue }
            validateFunctionVariance(fun, varianceMap: varianceMap, env: env)
        }
    }

    private func validateMemberProperties(
        _ propDeclIDs: [DeclID],
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv
    ) {
        for propDeclID in propDeclIDs {
            guard let propDecl = env.ast.arena.decl(propDeclID),
                  case let .propertyDecl(prop) = propDecl,
                  !prop.modifiers.contains(.private)
            else { continue }
            validatePropertyVariance(prop, varianceMap: varianceMap, env: env)
        }
    }

    // MARK: - Helpers

    private func buildVarianceMap(typeParams: [TypeParamDecl]) -> [InternedString: TypeVariance] {
        var varianceMap: [InternedString: TypeVariance] = [:]
        for typeParam in typeParams where typeParam.variance != .invariant {
            varianceMap[typeParam.name] = typeParam.variance
        }
        return varianceMap
    }

    private func validateFunctionVariance(
        _ funDecl: FunDecl,
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv
    ) {
        for valueParam in funDecl.valueParams {
            if let typeRefID = valueParam.type {
                checkTypeRefVariance(typeRefID, position: .contravariant,
                                     varianceMap: varianceMap, env: env, memberRange: funDecl.range)
            }
        }
        if let returnTypeRef = funDecl.returnType {
            checkTypeRefVariance(returnTypeRef, position: .out,
                                 varianceMap: varianceMap, env: env, memberRange: funDecl.range)
        }
    }

    private func validatePropertyVariance(
        _ propertyDecl: PropertyDecl,
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv
    ) {
        guard let typeRefID = propertyDecl.type else { return }
        if propertyDecl.isVar {
            checkTypeRefVariance(typeRefID, position: .contravariant,
                                 varianceMap: varianceMap, env: env, memberRange: propertyDecl.range)
        }
        checkTypeRefVariance(typeRefID, position: .out,
                             varianceMap: varianceMap, env: env, memberRange: propertyDecl.range)
    }

    // MARK: - Type reference variance checking

    private func checkTypeRefVariance(
        _ typeRefID: TypeRefID,
        position: VariancePosition,
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv,
        memberRange: SourceRange
    ) {
        guard let typeRef = env.ast.arena.typeRef(typeRefID) else { return }
        switch typeRef {
        case let .named(path, typeArgs, _):
            checkNamedTypeVariance(path: path, typeArgs: typeArgs, position: position,
                                   varianceMap: varianceMap, env: env, memberRange: memberRange)
        case let .functionType(paramTypeRefs, returnTypeRef, _, _):
            checkFunctionTypeVariance(params: paramTypeRefs, ret: returnTypeRef,
                                      position: position, varianceMap: varianceMap,
                                      env: env, memberRange: memberRange)
        case let .intersection(parts):
            for partRef in parts {
                checkTypeRefVariance(partRef, position: position,
                                     varianceMap: varianceMap, env: env, memberRange: memberRange)
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func checkNamedTypeVariance(
        path: [InternedString],
        typeArgs: [TypeArgRef],
        position: VariancePosition,
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv,
        memberRange: SourceRange
    ) {
        if let name = path.last, let declaredVariance = varianceMap[name] {
            emitVarianceViolation(paramName: env.interner.resolve(name),
                                  declaredVariance: declaredVariance,
                                  position: position, diagnostics: env.diagnostics, range: memberRange)
        }
        for typeArg in typeArgs {
            let (innerRefID, innerPosition) = typeArgProjection(typeArg, position: position)
            guard let refID = innerRefID else { continue }
            checkTypeRefVariance(refID, position: innerPosition,
                                 varianceMap: varianceMap, env: env, memberRange: memberRange)
        }
    }

    private func typeArgProjection(
        _ typeArg: TypeArgRef, position: VariancePosition
    ) -> (TypeRefID?, VariancePosition) {
        switch typeArg {
        case let .invariant(ref): (ref, position)
        case let .out(ref): (ref, position)
        case let .in(ref): (ref, position.flipped)
        case .star: (nil, position)
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func checkFunctionTypeVariance(
        params: [TypeRefID],
        ret: TypeRefID,
        position: VariancePosition,
        varianceMap: [InternedString: TypeVariance],
        env: VarianceCheckEnv,
        memberRange: SourceRange
    ) {
        for paramRef in params {
            checkTypeRefVariance(paramRef, position: position.flipped,
                                 varianceMap: varianceMap, env: env, memberRange: memberRange)
        }
        checkTypeRefVariance(ret, position: position,
                             varianceMap: varianceMap, env: env, memberRange: memberRange)
    }

    private func emitVarianceViolation(
        paramName: String,
        declaredVariance: TypeVariance,
        position: VariancePosition,
        diagnostics: DiagnosticEngine,
        range: SourceRange?
    ) {
        switch (declaredVariance, position) {
        case (.out, .contravariant):
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
