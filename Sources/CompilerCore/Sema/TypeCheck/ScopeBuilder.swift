import Foundation

struct TypeCheckScopeBuilder {
    func buildFileScopes(
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> [Int32: FileScope] {
        var topLevelSymbolsByPackage = collectTopLevelSymbolsByPackage(ast: ast, sema: sema)
        let librarySymbolsByPackage = collectLibraryTopLevelSymbolsByPackage(sema: sema, interner: interner)
        for (packagePath, symbols) in librarySymbolsByPackage {
            topLevelSymbolsByPackage[packagePath, default: []].append(contentsOf: symbols)
        }
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
                topLevelSymbolsByPackage: topLevelSymbolsByPackage,
                diagnostics: sema.diagnostics,
                interner: interner
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
        topLevelSymbolsByPackage: [[InternedString]: [SymbolID]],
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        var usedAliasNames: Set<InternedString> = []

        for importDecl in file.imports {
            if let alias = importDecl.alias {
                if interner.resolve(alias).isEmpty {
                    continue
                }

                let resolved = sema.symbols.lookupAll(fqName: importDecl.path)

                let isPackageOnlyImport = !resolved.isEmpty && resolved.allSatisfy {
                    sema.symbols.symbol($0)?.kind == .package
                }

                if isPackageOnlyImport {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0022",
                        "Cannot use alias on wildcard import.",
                        range: importDecl.range
                    )
                    continue
                }

                if resolved.isEmpty {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "Unresolved import path.",
                        range: importDecl.range
                    )
                    continue
                }

                if usedAliasNames.contains(alias) {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0023",
                        "Import alias conflicts with a previous import alias in the same file.",
                        range: importDecl.range
                    )
                    continue
                }

                let importedSymbols = resolved.filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID) else {
                        return false
                    }
                    return symbol.kind != .package
                }

                for importedSymbol in importedSymbols {
                    explicitImportScope.insertWithAlias(importedSymbol, asName: alias)
                }

                usedAliasNames.insert(alias)
                continue
            }

            let resolved = sema.symbols.lookupAll(fqName: importDecl.path)
            if resolved.isEmpty {
                let packageSymbols = topLevelSymbolsByPackage[importDecl.path] ?? []
                if !packageSymbols.isEmpty {
                    for packageSymbol in packageSymbols {
                        wildcardImportScope.insert(packageSymbol)
                    }
                }
                continue
            }

            let hasPackageImport = resolved.contains { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .package
            }
            let importedSymbols = resolved.filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                return symbol.kind != .package
            }
            if !importedSymbols.isEmpty, !hasPackageImport {
                for importedSymbol in importedSymbols {
                    explicitImportScope.insert(importedSymbol)
                }
                continue
            }
            if !importedSymbols.isEmpty, hasPackageImport {
                for importedSymbol in importedSymbols {
                    explicitImportScope.insert(importedSymbol)
                }
            }

            if hasPackageImport {
                for importedSymbol in topLevelSymbolsByPackage[importDecl.path] ?? [] {
                    wildcardImportScope.insert(importedSymbol)
                }
            }
        }
    }

    func collectLibraryTopLevelSymbolsByPackage(
        sema: SemaModule,
        interner: StringInterner
    ) -> [[InternedString]: [SymbolID]] {
        var knownPackages: Set<[InternedString]> = []
        for packageID in sema.symbols.symbols(ofKind: .package) {
            guard let packageSymbol = sema.symbols.symbol(packageID) else { continue }
            knownPackages.insert(packageSymbol.fqName)
        }

        var mapping: [[InternedString]: [SymbolID]] = [:]
        let allSymbols = sema.symbols.allSymbols()
        for symbol in allSymbols {
            guard symbol.kind != .package,
                  symbol.fqName.count >= 1
            else {
                continue
            }
            // Skip extension functions (those with a receiverType) -- they are
            // resolved via member-call inference, not top-level scope lookup.
            if symbol.kind == .function,
               let sig = sema.symbols.functionSignature(for: symbol.id),
               sig.receiverType != nil
            {
                continue
            }
            let candidatePackage: [InternedString] = if symbol.kind == .property,
                sema.symbols.extensionPropertyReceiverType(for: symbol.id) != nil,
                let companionSymbol = sema.symbols.parentSymbol(for: symbol.id),
                let companionInfo = sema.symbols.symbol(companionSymbol),
                companionInfo.kind == .object,
                companionInfo.name == interner.intern("Companion"),
                let ownerSymbol = sema.symbols.parentSymbol(for: companionSymbol),
                let ownerInfo = sema.symbols.symbol(ownerSymbol),
                !ownerInfo.fqName.isEmpty
            {
                Array(ownerInfo.fqName.dropLast())
            } else if symbol.fqName.count == 1 {
                []
            } else {
                Array(symbol.fqName.dropLast())
            }
            if !candidatePackage.isEmpty,
               !knownPackages.contains(candidatePackage),
               !symbol.flags.contains(.synthetic)
            {
                continue
            }
            mapping[candidatePackage, default: []].append(symbol.id)
        }
        return mapping
    }

    func makeDefaultImportPackages(interner: StringInterner) -> [[InternedString]] {
        let packages: [[String]] = [
            ["kotlin"],
            ["kotlin", "annotation"],
            ["kotlin", "collections"],
            ["kotlin", "comparisons"],
            // kotlin.math is not a Kotlin default import; importing it here broke
            // member resolution for java.security.Signature.sign vs kotlin.math.sign.
            ["kotlin", "io"],
            ["kotlin", "ranges"],
            ["kotlin", "sequences"],
            ["kotlin", "text"],
            ["kotlin", "system"],
        ]
        return packages.map { segments in
            segments.map { interner.intern($0) }
        }
    }
}
