import Foundation

extension DataFlowSemaPhase {
    func validateExperimentalTypeInferenceOptIn(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateExperimentalTypeInferenceOptIn(
                    declID: declID,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics
                )
            }
        }
    }

    private func validateExperimentalTypeInferenceOptIn(
        declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }

        if let symbol = bindings.declSymbols[declID] {
            validateExperimentalTypeInferenceOptIn(
                decl: decl,
                symbol: symbol,
                symbols: symbols,
                diagnostics: diagnostics
            )
        }

        for childDeclID in nestedDeclarationIDs(in: decl) {
            validateExperimentalTypeInferenceOptIn(
                declID: childDeclID,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics
            )
        }
    }

    private func validateExperimentalTypeInferenceOptIn(
        decl: Decl,
        symbol: SymbolID,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        let annotations = symbols.annotations(for: symbol)
        guard annotations.contains(where: {
            KnownCompilerAnnotation.overloadResolutionByLambdaReturnType.matches($0.annotationFQName)
        }) else {
            return
        }

        guard !annotations.contains(where: isExperimentalTypeInferenceOptInAnnotation) else {
            return
        }

        diagnostics.error(
            "KSWIFTK-SEMA-OPTIN",
            "Declaration annotated with '@OverloadResolutionByLambdaReturnType' must also be annotated with '@OptIn(kotlin.experimental.ExperimentalTypeInference::class)'.",
            range: declarationRange(for: decl)
        )
    }

    private func nestedDeclarationIDs(in decl: Decl) -> [DeclID] {
        switch decl {
        case let .classDecl(classDecl):
            classDecl.memberFunctions
                + classDecl.memberProperties
                + classDecl.nestedClasses
                + classDecl.nestedObjects
        case let .interfaceDecl(interfaceDecl):
            interfaceDecl.memberFunctions
                + interfaceDecl.memberProperties
                + interfaceDecl.nestedClasses
                + interfaceDecl.nestedObjects
        case let .objectDecl(objectDecl):
            objectDecl.memberFunctions
                + objectDecl.memberProperties
                + objectDecl.nestedClasses
                + objectDecl.nestedObjects
        default:
            []
        }
    }

    private func declarationRange(for decl: Decl) -> SourceRange? {
        switch decl {
        case let .classDecl(classDecl):
            classDecl.range
        case let .interfaceDecl(interfaceDecl):
            interfaceDecl.range
        case let .funDecl(funDecl):
            funDecl.range
        case let .propertyDecl(propertyDecl):
            propertyDecl.range
        case let .typeAliasDecl(typeAliasDecl):
            typeAliasDecl.range
        case let .objectDecl(objectDecl):
            objectDecl.range
        case let .enumEntryDecl(enumEntryDecl):
            enumEntryDecl.range
        }
    }

    private func isExperimentalTypeInferenceOptInAnnotation(
        _ annotation: MetadataAnnotationRecord
    ) -> Bool {
        if KnownCompilerAnnotation.experimentalTypeInference.matches(annotation.annotationFQName) {
            return true
        }
        guard KnownCompilerAnnotation.optIn.matches(annotation.annotationFQName) else {
            return false
        }

        return annotation.arguments.contains { argument in
            argument.contains(KnownCompilerAnnotation.experimentalTypeInference.simpleName)
                || argument.contains(KnownCompilerAnnotation.experimentalTypeInference.qualifiedName)
        }
    }
}
