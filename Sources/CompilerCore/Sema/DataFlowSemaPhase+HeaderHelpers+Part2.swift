import Foundation


extension DataFlowSemaPhase {
    func validateConstructorDelegation(
        ast: ASTModule,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case .classDecl(let classDecl) = decl,
                      let classSymbol = symbols.symbols(atDeclSite: classDecl.range).first(where: { id in
                          guard let sym = symbols.symbol(id) else { return false }
                          return sym.kind == .class || sym.kind == .enumClass || sym.kind == .annotationClass
                      }) else {
                    continue
                }
                for secondaryCtor in classDecl.secondaryConstructors {
                    guard let delegation = secondaryCtor.delegationCall,
                          delegation.kind == .super_ else {
                        continue
                    }
                    let superTypes = symbols.directSupertypes(for: classSymbol)
                    let classSupertypes = superTypes.filter {
                        let kind = symbols.symbol($0)?.kind
                        return kind == .class || kind == .enumClass
                    }
                    if classSupertypes.isEmpty {
                        diagnostics.error(
                            "KSWIFTK-SEMA-0021",
                            "Cannot delegate to super: class has no superclass.",
                            range: delegation.range
                        )
                    }
                }
            }
        }
    }
}
