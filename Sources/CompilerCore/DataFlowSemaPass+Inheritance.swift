import Foundation

extension DataFlowSemaPassPhase {
    func bindInheritanceEdges(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let symbol = bindings.declSymbols[declID],
                      let decl = ast.arena.decl(declID) else {
                    continue
                }
                let superTypeRefs: [TypeRefID]
                switch decl {
                case .classDecl(let classDecl):
                    superTypeRefs = classDecl.superTypes
                case .objectDecl(let objectDecl):
                    superTypeRefs = objectDecl.superTypes
                default:
                    continue
                }

                var superSymbols: [SymbolID] = []
                for superTypeRef in superTypeRefs {
                    if let superSymbol = resolveNominalSymbolFromTypeRef(
                        superTypeRef,
                        currentPackage: file.packageFQName,
                        ast: ast,
                        symbols: symbols
                    ) {
                        superSymbols.append(superSymbol)
                    }
                }
                let uniqueSuperSymbols = Array(Set(superSymbols)).sorted(by: { $0.rawValue < $1.rawValue })
                symbols.setDirectSupertypes(uniqueSuperSymbols, for: symbol)
            }
        }
    }

    private func resolveNominalSymbolFromTypeRef(
        _ typeRefID: TypeRefID,
        currentPackage: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable
    ) -> SymbolID? {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }
        let path: [InternedString]
        switch typeRef {
        case .named(let refPath, _):
            path = refPath
        }
        guard !path.isEmpty else {
            return nil
        }

        var candidatePaths: [[InternedString]] = [path]
        if path.count == 1 && !currentPackage.isEmpty {
            candidatePaths.append(currentPackage + path)
        }

        for candidatePath in candidatePaths {
            if let symbol = symbols.lookupAll(fqName: candidatePath)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id {
                return symbol
            }
        }
        return nil
    }

    func isNominalTypeSymbol(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            return true
        default:
            return false
        }
    }
}
