#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
@testable import GoldenHarnessSupport
import Foundation
import Testing

/// RF-GOLDEN-002 — origin classification independent of `declSite` and the
/// `synthetic` flag. The golden format does not change yet; these tests pin
/// the classifier against the cases named in the roadmap: nil-`declSite`
/// `Pair`, fixture-synthesized declarations, member aliases, a user
/// `package kotlin`, user extensions on stdlib receivers, imported libraries
/// and genuinely unresolvable symbols.
@Suite("GoldenHarness.SymbolOrigin")
struct GoldenHarnessSymbolOriginTests {
    private func classifier(for ctx: CompilationContext) throws -> GoldenSymbolOriginClassifier {
        let sema = try #require(ctx.sema)
        return GoldenSymbolOriginClassifier(
            sema: sema,
            sourceManager: ctx.sourceManager,
            interner: ctx.interner
        )
    }

    private func lookup(
        _ fqName: String,
        ctx: CompilationContext
    ) throws -> SymbolID {
        let interner = ctx.interner
        let sema = try #require(ctx.sema)
        let fq = fqName.split(separator: ".").map { interner.intern(String($0)) }
        let matches = sema.symbols.lookupAll(fqName: fq)
        return try #require(matches.first, "no symbol for \(fqName)")
    }

    /// `kotlin.Pair` keeps `declSite == nil` for compatibility, but its
    /// registration-time source file is bundled stdlib — the classifier must
    /// still identify it without trusting `declSite`.
    @Test
    func nilDeclSitePairClassifiesAsBundledSource() throws {
        let ctx = makeContextFromSource("fun main() { Pair(1, \"a\") }\n")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let pair = try lookup("kotlin.Pair", ctx: ctx)
        let pairSymbol = try #require(sema.symbols.symbol(pair))
        #expect(pairSymbol.declSite == nil, Comment(rawValue: "Pair gained a declSite — update the contract"))
        #expect(try classifier(for: ctx).origin(of: pair) == .bundledSource)
    }

    /// Fixture-synthesized declarations — data-class `copy`, object-literal
    /// classes and local variables — are fixture-owned even though they carry
    /// `flags=synthetic`.
    @Test
    func fixtureSyntheticsClassifyAsFixture() throws {
        let ctx = makeContextFromSource("""
        package sample
        data class Name(val value: String)
        fun main() {
            val alias = object { val x = 1 }
            val local = Name("a").copy(value = "b")
        }
        """)
        try runSema(ctx)
        let classify = try classifier(for: ctx)

        let copy = try lookup("sample.Name.copy", ctx: ctx)
        let copySymbol = try #require(ctx.sema?.symbols.symbol(copy))
        #expect(copySymbol.flags.contains(.synthetic))
        #expect(classify.origin(of: copy) == .fixture)

        let main = try lookup("sample.main", ctx: ctx)
        #expect(classify.origin(of: main) == .fixture)
    }

    /// A fixture may declare `package kotlin` members or extensions on stdlib
    /// receivers — decl-site / source-file provenance must keep them
    /// `.fixture`, never reclassifying by package prefix or receiver owner.
    @Test
    func userDeclaredKotlinPackageAndStdlibReceiverExtensionStayFixture() throws {
        let ctx = makeContextFromSource("""
        package kotlin
        fun userFn(): Int = 1
        fun kotlin.collections.List<Int>.myExt(): Int = 2
        """)
        try runSema(ctx)
        let classify = try classifier(for: ctx)

        #expect(try classify.origin(of: lookup("kotlin.userFn", ctx: ctx)) == .fixture)
        #expect(try classify.origin(of: lookup("kotlin.myExt", ctx: ctx)) == .fixture)
    }

    /// A bundled-source member alias (KSP-443): a nil-site synthetic function
    /// sharing parent, signature and `externalLinkName` with a source-backed
    /// sibling is `.sourceBackedAlias`, not `.stdlibStub` and not
    /// `.bundledSource`. The alias shape is constructed exactly as
    /// `HeaderCollection` does it: source decl at `pkg.ext` (bundled file,
    /// receiver-class parent, link name), alias at `Receiver.ext` with no
    /// site.
    @Test
    func sourceBackedMemberAliasIsDetected() {
        let (sema, symbols, types, interner) = makeSemaModule()
        let sourceManager = SourceManager()
        let bundledFile = sourceManager.addFile(
            path: "bundled/Sequences.kt",
            contents: Data("package kotlin.sequences\n".utf8),
            origin: .bundledStdlib
        )
        let pkgSeq = [interner.intern("kotlin"), interner.intern("sequences")]
        let seqFQ = pkgSeq + [interner.intern("Sequence")]
        let seqClass = symbols.define(
            kind: .interface,
            name: interner.intern("Sequence"),
            fqName: seqFQ,
            declSite: nil,
            visibility: .public
        )
        let linkName = "kk_sequence_toHashSet"
        let sourceRange = SourceRange(
            start: SourceLocation(file: bundledFile, offset: 24),
            end: SourceLocation(file: bundledFile, offset: 30)
        )
        let source = symbols.define(
            kind: .function,
            name: interner.intern("toHashSet"),
            fqName: pkgSeq + [interner.intern("toHashSet")],
            declSite: sourceRange,
            visibility: .public
        )
        symbols.setSourceFileID(bundledFile, for: source)
        symbols.setParentSymbol(seqClass, for: source)
        let signature = FunctionSignature(parameterTypes: [], returnType: types.unitType)
        symbols.setFunctionSignature(signature, for: source)
        symbols.setExternalLinkName(linkName, for: source)
        let alias = symbols.define(
            kind: .function,
            name: interner.intern("toHashSet"),
            fqName: seqFQ + [interner.intern("toHashSet")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(seqClass, for: alias)
        symbols.setFunctionSignature(signature, for: alias)
        symbols.setExternalLinkName(linkName, for: alias)

        let classify = GoldenSymbolOriginClassifier(
            sema: sema,
            sourceManager: sourceManager,
            interner: interner
        )
        #expect(classify.origin(of: source) == .bundledSource)
        #expect(classify.origin(of: alias) == .sourceBackedAlias)
    }

    /// Symbols registered from compiled libraries carry `.importedLibrary` —
    /// that is their origin even with no decl site.
    @Test
    func importedLibraryFlagClassifiesAsImported() {
        let (sema, symbols, _, interner) = makeSemaModule()
        let pkg = symbols.define(
            kind: .package,
            name: interner.intern("lib"),
            fqName: [interner.intern("lib")],
            declSite: nil,
            visibility: .public
        )
        let imported = symbols.define(
            kind: .function,
            name: interner.intern("foreignCall"),
            fqName: [interner.intern("lib"), interner.intern("foreignCall")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .importedLibrary]
        )
        symbols.setParentSymbol(pkg, for: imported)

        let classify = GoldenSymbolOriginClassifier(
            sema: sema,
            sourceManager: SourceManager(),
            interner: interner
        )
        #expect(classify.origin(of: imported) == .importedLibrary)
    }

    /// A nil-site synthetic member whose package is entirely user-declared —
    /// e.g. the no-source fallback shape — must not collapse into stdlib.
    /// With no resolvable provenance it is `.unknown`, never silently external.
    @Test
    func unresolvableOriginIsUnknown() {
        let (sema, symbols, _, interner) = makeSemaModule()
        let orphan = symbols.define(
            kind: .function,
            name: interner.intern("orphan"),
            fqName: [interner.intern("nowhere"), interner.intern("orphan")],
            declSite: nil,
            visibility: .public
        )
        let classify = GoldenSymbolOriginClassifier(
            sema: sema,
            sourceManager: SourceManager(),
            interner: interner
        )
        #expect(classify.origin(of: orphan) == .unknown)
    }

    /// A nil-site stub under a package whose declared members live in bundled
    /// sources is a `.stdlibStub` — the `kotlin` root namespace used by the
    /// bundled machinery.
    @Test
    func nilSiteMemberUnderBundledPackageIsStdlibStub() {
        let (sema, symbols, _, interner) = makeSemaModule()
        let sourceManager = SourceManager()
        let bundledFile = sourceManager.addFile(
            path: "bundled/Collections.kt",
            contents: Data("package kotlin.collections\nfun stub() = 0\n".utf8),
            origin: .bundledStdlib
        )
        let pkgName = interner.intern("kotlin.collections")
        let pkg = symbols.define(
            kind: .package,
            name: pkgName,
            fqName: [pkgName],
            declSite: nil,
            visibility: .public
        )
        let realDecl = symbols.define(
            kind: .function,
            name: interner.intern("real"),
            fqName: [pkgName, interner.intern("real")],
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(pkg, for: realDecl)
        symbols.setSourceFileID(bundledFile, for: realDecl)
        let stub = symbols.define(
            kind: .function,
            name: interner.intern("stubMember"),
            fqName: [pkgName, interner.intern("stubMember")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(pkg, for: stub)

        let classify = GoldenSymbolOriginClassifier(
            sema: sema,
            sourceManager: sourceManager,
            interner: interner
        )
        #expect(classify.origin(of: realDecl) == .bundledSource)
        #expect(classify.origin(of: stub) == .stdlibStub)
    }

    /// Value parameters under a fixture-owned synthetic declaration inherit the
    /// owner's origin through the parent chain.
    @Test
    func parameterInheritsOwnerOrigin() {
        let (sema, symbols, _, interner) = makeSemaModule()
        let sourceManager = SourceManager()
        let userFile = sourceManager.addFile(
            path: "input.kt",
            contents: Data("package sample\n".utf8),
            origin: .user
        )
        let owner = symbols.define(
            kind: .function,
            name: interner.intern("copy"),
            fqName: [interner.intern("sample"), interner.intern("Name"), interner.intern("copy")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setSourceFileID(userFile, for: owner)
        let param = symbols.define(
            kind: .valueParameter,
            name: interner.intern("value"),
            fqName: [interner.intern("sample"), interner.intern("Name"), interner.intern("copy"), interner.intern("$0"), interner.intern("value")],
            declSite: nil,
            visibility: .private
        )
        symbols.setParentSymbol(owner, for: param)

        let classify = GoldenSymbolOriginClassifier(
            sema: sema,
            sourceManager: sourceManager,
            interner: interner
        )
        #expect(classify.origin(of: param) == .fixture)
    }
}
#endif
