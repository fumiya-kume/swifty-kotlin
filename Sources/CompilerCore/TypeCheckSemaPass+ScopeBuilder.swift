import Foundation

extension TypeCheckSemaPassPhase {
    func buildFileScopes(
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> [Int32: FileScope] {
        let topLevelSymbolsByPackage = collectTopLevelSymbolsByPackage(ast: ast, sema: sema)
        let defaultImportPackages = makeDefaultImportPackages(interner: interner)
        var fileScopes: [Int32: FileScope] = [:]

        for file in ast.sortedFiles {
            let defaultImportScope = ImportScope(parent: nil, symbols: sema.symbols)
            for packagePath in defaultImportPackages {
                for importedSymbol in topLevelSymbolsByPackage[packagePath] ?? [] {
                    defaultImportScope.insert(importedSymbol)
                }
            }

            let wildcardImportScope = ImportScope(parent: defaultImportScope, symbols: sema.symbols)
            let explicitImportScope = ImportScope(parent: wildcardImportScope, symbols: sema.symbols)
            populateImportScopes(
                for: file,
                sema: sema,
                explicitImportScope: explicitImportScope,
                wildcardImportScope: wildcardImportScope,
                topLevelSymbolsByPackage: topLevelSymbolsByPackage
            )

            let packageScope = PackageScope(parent: explicitImportScope, symbols: sema.symbols)
            for packageSymbol in topLevelSymbolsByPackage[file.packageFQName] ?? [] {
                packageScope.insert(packageSymbol)
            }

            let fileScope = FileScope(parent: packageScope, symbols: sema.symbols)
            fileScopes[file.fileID.rawValue] = fileScope
        }

        return fileScopes
    }

    func collectTopLevelSymbolsByPackage(
        ast: ASTModule,
        sema: SemaModule
    ) -> [[InternedString]: [SymbolID]] {
        var mapping: [[InternedString]: [SymbolID]] = [:]
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let symbol = sema.bindings.declSymbols[declID] else {
                    continue
                }
                mapping[file.packageFQName, default: []].append(symbol)
            }
        }
        return mapping
    }

    func populateImportScopes(
        for file: ASTFile,
        sema: SemaModule,
        explicitImportScope: ImportScope,
        wildcardImportScope: ImportScope,
        topLevelSymbolsByPackage: [[InternedString]: [SymbolID]]
    ) {
        for importDecl in file.imports {
            let resolved = sema.symbols.lookupAll(fqName: importDecl.path)
            if resolved.isEmpty {
                continue
            }

            let importedSymbols = resolved.filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                return symbol.kind != .package
            }
            if !importedSymbols.isEmpty {
                for importedSymbol in importedSymbols {
                    explicitImportScope.insert(importedSymbol)
                }
                continue
            }

            let hasPackageImport = resolved.contains { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .package
            }
            if hasPackageImport {
                for importedSymbol in topLevelSymbolsByPackage[importDecl.path] ?? [] {
                    wildcardImportScope.insert(importedSymbol)
                }
            }
        }
    }

    func makeDefaultImportPackages(interner: StringInterner) -> [[InternedString]] {
        let packages: [[String]] = [
            ["kotlin"],
            ["kotlin", "annotation"],
            ["kotlin", "collections"],
            ["kotlin", "comparisons"],
            ["kotlin", "io"],
            ["kotlin", "ranges"],
            ["kotlin", "sequences"],
            ["kotlin", "text"]
        ]
        return packages.map { segments in
            segments.map { interner.intern($0) }
        }
    }
}
