@testable import CompilerCore
import Foundation
import Testing

@Suite
struct BundledDeclarationIndexTests {
    @Test
    func astBuildQualifiesSamePackageNestedReceiverPaths() throws {
        let (ast, ctx) = try buildBundledAST(
            """
            package kotlin.collections

            class Outer {
                class Inner
            }

            fun Outer.Inner.touch(count: Int) {}
            """
        )

        let index = BundledDeclarationIndex.build(ast: ast, sourceManager: ctx.sourceManager, interner: ctx.interner)
        let qualifiedOwner = intern(["kotlin", "collections", "Outer", "Inner"], ctx.interner)
        let unqualifiedOwner = intern(["Outer", "Inner"], ctx.interner)
        let touch = ctx.interner.intern("touch")

        #expect(index.contains(owner: qualifiedOwner, name: touch, arity: 1))
        #expect(!index.contains(owner: unqualifiedOwner, name: touch, arity: 1))
    }

    @Test
    func astBuildCollectsNestedInterfaceMembers() throws {
        let (ast, ctx) = try buildBundledAST(
            """
            package kotlin.collections

            class Outer {
                interface Cursor {
                    fun advance()
                }
            }
            """
        )

        let index = BundledDeclarationIndex.build(ast: ast, sourceManager: ctx.sourceManager, interner: ctx.interner)
        let owner = intern(["kotlin", "collections", "Outer", "Cursor"], ctx.interner)
        let advance = ctx.interner.intern("advance")

        #expect(index.contains(owner: owner, name: advance, arity: 0))
    }

    @Test
    func symbolTableBuildUsesInterfaceReceiverFQName() throws {
        let sourceManager = SourceManager()
        let fileID = sourceManager.addFile(path: "__bundled_interface.kt", contents: Data("".utf8), origin: .bundledStdlib)
        let range = SourceRange(
            start: SourceLocation(file: fileID, offset: 0),
            end: SourceLocation(file: fileID, offset: 0)
        )
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let interfaceName = interner.intern("Cursor")
        let ownerFQName = intern(["kotlin", "collections", "Cursor"], interner)
        let interfaceID = symbols.define(
            kind: .interface,
            name: interfaceName,
            fqName: ownerFQName,
            declSite: range,
            visibility: .public
        )
        let functionName = interner.intern("advance")
        let functionID = symbols.define(
            kind: .function,
            name: functionName,
            fqName: intern(["kotlin", "collections", "advance"], interner),
            declSite: range,
            visibility: .public
        )
        let receiverType = types.make(.classType(ClassType(classSymbol: interfaceID)))
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType
            ),
            for: functionID
        )

        let index = BundledDeclarationIndex.build(
            sourceManager: sourceManager,
            symbols: symbols,
            types: types
        )

        #expect(index.contains(owner: ownerFQName, name: functionName, arity: 0))
    }

    @Test
    func fullSemaSkipsSyntheticStubsCoveredByBundledKotlinCollectionsSource() throws {
        let ctx = makeContextFromSource(
            """
            fun useBundledListHOFs(values: List<Int>): Boolean {
                val joined = values.joinToString(",") { it.toString() }
                return values.count { it > 0 } > 0 &&
                    values.any { it > 1 } &&
                    values.all { it >= 0 } &&
                    joined.isNotEmpty()
            }
            """,
            allowDefaultStdlibLibrary: false
        )
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected bundled collection HOFs to type-check, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try #require(ctx.sema)
        let listOwner = intern(["kotlin", "collections", "List"], ctx.interner)
        let iterableOwner = intern(["kotlin", "collections", "Iterable"], ctx.interner)
        let collectionsPackage = intern(["kotlin", "collections"], ctx.interner)
        let bundledPath = "__bundled_kotlin/collections/ListSearchHOF.kt"

        for member in ["count", "any", "all"] {
            let name = ctx.interner.intern(member)
            let bundledMembers = matchingExtensionFunctions(
                packageFQName: collectionsPackage,
                receiverOwner: listOwner,
                name: name,
                arity: 1,
                sema: sema
            )
            #expect(
                bundledMembers.contains {
                    guard let symbol = sema.symbols.symbol($0),
                          !symbol.flags.contains(.synthetic)
                    else {
                        return false
                    }
                    return sourcePath(for: $0, sema: sema, ctx: ctx) == bundledPath
                },
                "Expected List.\(member)(predicate) from bundled Kotlin source"
            )
            #expect(
                !matchingFunctions(
                    owner: listOwner,
                    name: name,
                    arity: 1,
                    sema: sema
                ).contains {
                    sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
                },
                "Expected no synthetic List.\(member)(predicate) stub"
            )
        }

        for (member, linkName) in [("any", "__kk_iterable_any"), ("all", "__kk_iterable_all")] {
            let name = ctx.interner.intern(member)
            let syntheticPredicateMembers = matchingFunctions(
                owner: iterableOwner,
                name: name,
                arity: 1,
                sema: sema
            ).filter {
                sema.symbols.symbol($0)?.flags.contains(.synthetic) == true &&
                    sema.symbols.externalLinkName(for: $0) == linkName
            }
            #expect(
                syntheticPredicateMembers.isEmpty,
                "Expected bundled List.\(member)(predicate) to suppress \(linkName)"
            )
        }

        // KSP-435: Iterable.any() is bundled Kotlin source (Iterables.kt).
        let anyZeroArgSynthetic = matchingFunctions(
            owner: iterableOwner,
            name: ctx.interner.intern("any"),
            arity: 0,
            sema: sema
        ).contains {
            sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
        }
        #expect(!anyZeroArgSynthetic, "Expected Iterable.any() synthetic stub to be removed")

        let syntheticCountLinks = sema.symbols.allSymbols().filter { symbol in
            guard let linkName = sema.symbols.externalLinkName(for: symbol.id) else {
                return false
            }
            return linkName == "kk_iterable_count" || linkName == "kk_list_count"
        }
        #expect(syntheticCountLinks.isEmpty, "Expected no synthetic collection count stub link")

        let joinToStringName = ctx.interner.intern("joinToString")

        let listJoinDefaults = matchingFunctions(
            owner: listOwner,
            name: joinToStringName,
            arity: 3,
            sema: sema
        ).filter {
            sema.symbols.symbol($0)?.flags.contains(.synthetic) == true &&
                sema.symbols.externalLinkName(for: $0) == "kk_list_joinToString"
        }
        #expect(
            listJoinDefaults.isEmpty,
            "Expected bundled List.joinToString to suppress the synthetic default stub"
        )

        // KSP-435: Iterable.joinToString is bundled Kotlin source (Iterables.kt).
        let iterableJoinDefaults = matchingFunctions(
            owner: iterableOwner,
            name: joinToStringName,
            arity: 3,
            sema: sema
        ).filter {
            sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
        }
        #expect(
            iterableJoinDefaults.isEmpty,
            "Expected bundled Iterable.joinToString to suppress the synthetic default stub"
        )

        let listJoinTransforms = matchingFunctions(
            owner: listOwner,
            name: joinToStringName,
            arity: 4,
            sema: sema
        ).filter {
            sema.symbols.symbol($0)?.flags.contains(.synthetic) == true &&
                sema.symbols.externalLinkName(for: $0) == "kk_list_joinToString_transform"
        }
        #expect(
            listJoinTransforms.isEmpty,
            "Expected bundled Iterable.joinToString transform overloads to replace List synthetic stubs"
        )
    }

    @Test
    func syntheticBundledOverlapDiagnosticWarnsForGuardLeaks() throws {
        let (ast, ctx) = try buildBundledAST(
            """
            package kotlin.collections

            interface List<T> {
                fun any(predicate: (T) -> Boolean): Boolean
            }
            """
        )
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let listOwner = intern(["kotlin", "collections", "List"], ctx.interner)
        let listName = ctx.interner.intern("List")
        let anyName = ctx.interner.intern("any")
        let listSymbol = symbols.define(
            kind: .interface,
            name: listName,
            fqName: listOwner,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let listType = types.make(.classType(ClassType(classSymbol: listSymbol)))
        let anySymbol = symbols.define(
            kind: .function,
            name: anyName,
            fqName: listOwner + [anyName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(listSymbol, for: anySymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: listType,
                parameterTypes: [types.anyType],
                returnType: types.booleanType
            ),
            for: anySymbol
        )

        let bundledIndex = BundledDeclarationIndex.build(
            ast: ast,
            symbols: symbols,
            types: types,
            sourceManager: ctx.sourceManager,
            interner: ctx.interner
        )
        bundledIndex.warnSyntheticOverlaps(
            symbols: symbols,
            types: types,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )

        let descriptor = DiagnosticRegistry.lookup("KSWIFTK-SEMA-0102")
        #expect(descriptor?.defaultSeverity == .warning)
        let warnings = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0102" }
        #expect(warnings.count == 1)
        #expect(warnings.first?.severity == .warning)
        #expect(warnings.first?.message.contains("Synthetic stub 'any'") == true)
        #expect(warnings.first?.message.contains("'kotlin.collections.List' (arity 1)") == true)
    }

    @Test(arguments: ["matching", "otherOwner", "otherSignature", "otherLink", "otherName"])
    func syntheticAliasRequiresMatchingSourceMember(variant: String) throws {
        let sourceManager = SourceManager()
        let fileID = sourceManager.addFile(
            path: "__bundled_sequence_source.kt",
            contents: Data("".utf8),
            origin: .bundledStdlib
        )
        let range = SourceRange(
            start: SourceLocation(file: fileID, offset: 0),
            end: SourceLocation(file: fileID, offset: 0)
        )
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let ownerFQName = intern(["kotlin", "sequences", "Sequence"], interner)
        let ownerName = interner.intern("Sequence")
        let ownerSymbol = symbols.define(
            kind: .interface,
            name: ownerName,
            fqName: ownerFQName,
            declSite: range,
            visibility: .public
        )
        let receiverType = types.make(.classType(ClassType(classSymbol: ownerSymbol)))
        let memberName = interner.intern("toHashSet")
        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: types.anyType
        )
        let sourceName = variant == "otherName" ? interner.intern("otherMember") : memberName
        let sourceSymbol = symbols.define(
            kind: .function,
            name: sourceName,
            fqName: intern(["kotlin", "sequences"], interner) + [sourceName],
            declSite: range,
            visibility: .public
        )
        symbols.setParentSymbol(ownerSymbol, for: sourceSymbol)
        if variant == "otherOwner" {
            let otherOwner = symbols.define(
                kind: .interface, name: interner.intern("Other"),
                fqName: intern(["sample", "Other"], interner), declSite: range, visibility: .public
            )
            symbols.setParentSymbol(otherOwner, for: sourceSymbol)
        }
        symbols.setFunctionSignature(
            variant == "otherSignature"
                ? FunctionSignature(receiverType: receiverType, parameterTypes: [], returnType: types.intType)
                : signature,
            for: sourceSymbol
        )
        symbols.setExternalLinkName(
            variant == "otherLink" ? "different_link_name" : "kk_sequence_toHashSet",
            for: sourceSymbol
        )

        let aliasSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: ownerFQName + [memberName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: aliasSymbol)
        symbols.setFunctionSignature(signature, for: aliasSymbol)
        symbols.setExternalLinkName("kk_sequence_toHashSet", for: aliasSymbol)

        var bundledIndex = BundledDeclarationIndex.empty
        bundledIndex.insert(
            BundledMemberKey(ownerFQName: ownerFQName, name: memberName, arity: 0)
        )
        let diagnostics = DiagnosticEngine()
        bundledIndex.warnSyntheticOverlaps(
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner
        )

        let warnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0102" }
        #expect(warnings.count == (variant == "matching" ? 0 : 1))
    }

    @Test
    func comparisonsCompareByRetainsAllThreeBundledArities() {
        // A duplicated `ownerFQName == ["kotlin", "comparisons"]` branch inside
        // isRuntimeBackedSyntheticRetainedOverlap used to make the second branch
        // (an older, narrower KSP-309 arity-1/2-only check) permanently
        // unreachable. Pin the surviving KSP-461 behavior directly so a future
        // edit to the comparisons routing can't silently drop the arity-3 case
        // (compareBy(selector1, selector2, selector3)), which the dead branch
        // never covered even when it still existed.
        let interner = StringInterner()
        let ownerFQName = intern(["kotlin", "comparisons"], interner)
        let compareByName = interner.intern("compareBy")

        for arity in [1, 2, 3] {
            let key = BundledMemberKey(ownerFQName: ownerFQName, name: compareByName, arity: arity)
            #expect(
                BundledDeclarationIndex.isRuntimeBackedSyntheticRetainedOverlap(key, interner: interner),
                "compareBy(arity \(arity)) is bundled in Comparators.kt and must be a retained overload"
            )
        }

        for arity in [0, 4] {
            let key = BundledMemberKey(ownerFQName: ownerFQName, name: compareByName, arity: arity)
            #expect(
                !BundledDeclarationIndex.isRuntimeBackedSyntheticRetainedOverlap(key, interner: interner),
                "compareBy(arity \(arity)) has no bundled overload and must not be marked retained"
            )
        }

        let unrelatedName = interner.intern("compareValues")
        let unrelatedKey = BundledMemberKey(ownerFQName: ownerFQName, name: unrelatedName, arity: 2)
        #expect(!BundledDeclarationIndex.isRuntimeBackedSyntheticRetainedOverlap(unrelatedKey, interner: interner))
    }

    @Test
    func astBuildResolvesDefaultImportedReceiverTypes() throws {
        let (ast, ctx) = try buildBundledAST(sources: [
            "package kotlin.collections\n\ninterface List<T>",
            """
            package kotlin.text

            fun <T> List<T>.joinToString(
                separator: String = ", ",
                prefix: String = "",
                postfix: String = ""
            ): String = TODO()
            """
        ])

        let index = BundledDeclarationIndex.build(
            ast: ast,
            sourceManager: ctx.sourceManager,
            interner: ctx.interner
        )

        let listOwner = intern(["kotlin", "collections", "List"], ctx.interner)
        let iterableOwner = intern(["kotlin", "collections", "Iterable"], ctx.interner)
        let joinToString = ctx.interner.intern("joinToString")

        #expect(index.contains(owner: listOwner, name: joinToString, arity: 3))
        #expect(index.contains(owner: iterableOwner, name: joinToString, arity: 3))
    }

    private func buildBundledAST(_ source: String) throws -> (ASTModule, CompilationContext) {
        let path = "__bundled_test.kt"
        let ctx = makeCompilationContext(inputs: [path])
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .bundledStdlib)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        return (try #require(ctx.ast), ctx)
    }

    private func buildBundledAST(sources: [String]) throws -> (ASTModule, CompilationContext) {
        let ctx = makeCompilationContext(inputs: [])
        for (index, source) in sources.enumerated() {
            let path = "__bundled_test_\(index).kt"
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .bundledStdlib)
        }
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        return (try #require(ctx.ast), ctx)
    }

    private func intern(_ parts: [String], _ interner: StringInterner) -> [InternedString] {
        parts.map { interner.intern($0) }
    }

    private func matchingFunctions(
        owner: [InternedString],
        name: InternedString,
        arity: Int,
        sema: SemaModule
    ) -> [SymbolID] {
        sema.symbols.lookupAll(fqName: owner + [name]).filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes.count == arity
        }
    }

    private func matchingExtensionFunctions(
        packageFQName: [InternedString],
        receiverOwner: [InternedString],
        name: InternedString,
        arity: Int,
        sema: SemaModule
    ) -> [SymbolID] {
        sema.symbols.lookupAll(fqName: packageFQName + [name]).filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: symbolID),
                  signature.parameterTypes.count == arity,
                  let receiverType = signature.receiverType,
                  let actualOwner = nominalOwnerFQName(for: receiverType, sema: sema)
            else {
                return false
            }
            return actualOwner == receiverOwner
        }
    }

    private func nominalOwnerFQName(for typeID: TypeID, sema: SemaModule) -> [InternedString]? {
        switch sema.types.kind(of: sema.types.makeNonNullable(typeID)) {
        case let .classType(classType):
            sema.symbols.symbol(classType.classSymbol)?.fqName
        default:
            nil
        }
    }

    private func sourcePath(
        for symbolID: SymbolID,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> String? {
        let fileID = sema.symbols.sourceFileID(for: symbolID)
            ?? sema.symbols.symbol(symbolID)?.declSite?.start.file
        guard let fileID else {
            return nil
        }
        return ctx.sourceManager.path(of: fileID)
    }
}
