@testable import CompilerCore
import Foundation

/// Ownership/origin classification for Sema golden output (RF-GOLDEN-002).
///
/// The classification deliberately does NOT trust `declSite` or the
/// `synthetic` flag as identity: bundled source-backed declarations keep
/// `declSite == nil` for compatibility (e.g. `kotlin.Pair`), and fixture code
/// synthesizes declarations (data-class members, object literals, accessors)
/// that are still fixture-owned. Instead it uses registration-time facts that
/// production semantics do not depend on:
///
///   1. `SymbolTable.sourceFileID` — recorded at declaration collection for
///      every source-declared symbol — mapped through `SourceManager.origin`.
///   2. `declSite`'s file — the declared range's home file.
///   3. `.importedLibrary` — set when a symbol comes from a compiled library.
///   4. The source-backed member-alias shape (KSP-443): a nil-site synthetic
///      function sharing parent + signature + `externalLinkName` with a
///      source-backed sibling.
///   5. `parentSymbol` chains for parameters / accessors / nested decls.
///   6. Package membership: a nil-site symbol under a package whose declared
///      members come from bundled sources is a bundled synthetic stub.
///
/// Anything unresolvable becomes `.unknown` — never silently folded into an
/// "external" bucket.
enum GoldenSymbolOrigin: String, Sendable {
    /// Declared in a user input file — includes fixture-synthesized
    /// declarations (data-class members, object literals, accessors, locals)
    /// whose site/file is the user's own source.
    case fixture
    /// Declared in bundled or residual stdlib source (`SourceOrigin
    /// .bundledStdlib` / `.residualStdlib`) — even when `declSite` is nil.
    case bundledSource
    /// No source anywhere: a synthetic stdlib stub produced by the bundled
    /// declaration machinery (e.g. residual `kk_*` runtime shells).
    case stdlibStub
    /// Nil-site synthetic member alias of a source-backed bundled declaration
    /// (KSP-443 runtime-link aliases).
    case sourceBackedAlias
    /// Loaded from a compiled library (`.importedLibrary`), including stdlib
    /// artifacts — distinct from bundled *source*.
    case importedLibrary
    /// Origin could not be determined. Callers must surface this rather than
    /// treat it as external.
    case unknown
}

final class GoldenSymbolOriginClassifier {
    private let sema: SemaModule
    private let sourceManager: SourceManager
    private let interner: StringInterner

    private var memo: [Int32: GoldenSymbolOrigin] = [:]
    /// `name → [source-backed candidates]` for the member-alias sibling check.
    private var sourceBackedFunctionsByName: [InternedString: [SemanticSymbol]]?

    init(sema: SemaModule, sourceManager: SourceManager, interner: StringInterner) {
        self.sema = sema
        self.sourceManager = sourceManager
        self.interner = interner
    }

    func origin(of symbolID: SymbolID) -> GoldenSymbolOrigin {
        if let cached = memo[symbolID.rawValue] {
            return cached
        }
        // Recursion guard: mark in-flight symbols as unknown so a cyclic
        // parent chain terminates instead of recursing forever.
        memo[symbolID.rawValue] = .unknown
        let resolved = resolveOrigin(of: symbolID)
        memo[symbolID.rawValue] = resolved
        return resolved
    }

    private func resolveOrigin(of symbolID: SymbolID) -> GoldenSymbolOrigin {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return .unknown
        }

        // 1. Registration-time file membership, then the declared range's
        //    file. Both map through `SourceOrigin`, not decl-site presence.
        if let fileID = sema.symbols.sourceFileID(for: symbolID) ?? symbol.declSite?.start.file {
            switch sourceManager.origin(of: fileID) {
            case .user:
                return .fixture
            case .bundledStdlib, .residualStdlib:
                return .bundledSource
            case nil:
                return .unknown
            }
        }

        // 2. Compiled-library imports carry their own registration flag.
        if symbol.flags.contains(.importedLibrary) {
            return .importedLibrary
        }

        // 3. KSP-443 member alias: nil-site synthetic function that shares
        //    parent, signature and externalLinkName with a source-backed
        //    declaration.
        if isSourceBackedMemberAlias(symbol) {
            return .sourceBackedAlias
        }

        // 4. Value/type parameters, accessors and nested synthetic members
        //    inherit the origin of their owner when it is classifiable.
        if let parent = sema.symbols.parentSymbol(for: symbolID),
           let parentSymbol = sema.symbols.symbol(parent),
           parentSymbol.kind != .package {
            let parentOrigin = origin(of: parent)
            if parentOrigin != .unknown {
                return parentOrigin
            }
        }

        // 5. Nil-site symbols under a package are stdlib stubs when the
        //    package's declared members trace to bundled sources. A package
        //    whose members are user-declared does not produce nil-site
        //    symbols, so this never misclassifies a `package kotlin` fixture.
        if case let packageOrigin = packageHomeOrigin(of: Array(symbol.fqName.dropLast())),
           packageOrigin == .bundledSource {
            return .stdlibStub
        }

        return .unknown
    }

    // MARK: - Member alias detection

    private func isSourceBackedMemberAlias(_ symbol: SemanticSymbol) -> Bool {
        guard symbol.kind == .function,
              symbol.declSite == nil,
              symbol.flags.contains(.synthetic),
              let parent = sema.symbols.parentSymbol(for: symbol.id),
              let signature = sema.symbols.functionSignature(for: symbol.id),
              let linkName = sema.symbols.externalLinkName(for: symbol.id),
              !linkName.isEmpty
        else {
            return false
        }
        if sourceBackedFunctionsByName == nil {
            var index: [InternedString: [SemanticSymbol]] = [:]
            for candidate in sema.symbols.allSymbols()
            where candidate.kind == .function
                && !candidate.flags.contains(.synthetic)
                && candidate.declSite != nil {
                index[candidate.name, default: []].append(candidate)
            }
            sourceBackedFunctionsByName = index
        }
        return (sourceBackedFunctionsByName?[symbol.name] ?? []).contains { candidate in
            candidate.id != symbol.id
                && candidate.fqName != symbol.fqName
                && sema.symbols.parentSymbol(for: candidate.id) == parent
                && sema.symbols.functionSignature(for: candidate.id) == signature
                && sema.symbols.externalLinkName(for: candidate.id) == linkName
        }
    }

    // MARK: - Package home

    /// Classifies a package's home by its directly-declared members: bundled
    /// when any member traces to bundled stdlib source, fixture when any member
    /// traces to user source, otherwise unknown.
    private func packageHomeOrigin(of packageFQName: [InternedString]) -> GoldenSymbolOrigin {
        guard !packageFQName.isEmpty else { return .unknown }
        let members = sema.symbols.children(ofFQName: packageFQName)
        var sawUser = false
        for memberID in members {
            guard let member = sema.symbols.symbol(memberID) else { continue }
            if let fileID = sema.symbols.sourceFileID(for: memberID) ?? member.declSite?.start.file {
                switch sourceManager.origin(of: fileID) {
                case .user:
                    sawUser = true
                case .bundledStdlib, .residualStdlib:
                    return .bundledSource
                case nil:
                    continue
                }
            }
        }
        return sawUser ? .fixture : .unknown
    }
}
