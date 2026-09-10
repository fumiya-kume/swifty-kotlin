#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-947: MutableSet is declared by bundled Kotlin source while its shared
/// runtime mutation bridges remain compiler-side symbols.
@Suite
struct MutableSetSourceMigrationTests {
    @Test
    func mutableSetNominalAndMutationSurfaceResolveFromBundledSource() throws {
        let source = """
        fun acceptSet(values: Set<Int>) {}
        fun acceptCollection(values: MutableCollection<Int>) {}
        fun acceptIterable(values: MutableIterable<Int>) {}

        fun probe(values: MutableSet<Int>) {
            acceptSet(values)
            acceptCollection(values)
            acceptIterable(values)
            values.add(1)
            values.addAll(listOf(2))
            values.remove(1)
            values.removeAll(listOf(2))
            values.retainAll(emptySet())
            values.clear()
            values += 3
            values -= 3
            values += listOf(4)
            values -= listOf(4)
            values.iterator()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            let diagnosticSummary = errors.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                errors.isEmpty,
                "Expected MutableSet inheritance and mutation calls to type-check: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let collections = ["kotlin", "collections"].map(ctx.interner.intern)
            let mutableSet = try #require(
                sema.symbols.lookup(fqName: collections + [ctx.interner.intern("MutableSet")])
            )
            let set = try #require(sema.symbols.lookup(fqName: collections + [ctx.interner.intern("Set")]))
            let mutableCollection = try #require(
                sema.symbols.lookup(fqName: collections + [ctx.interner.intern("MutableCollection")])
            )
            let mutableIterable = try #require(
                sema.symbols.lookup(fqName: collections + [ctx.interner.intern("MutableIterable")])
            )

            let mutableSetInfo = try #require(sema.symbols.symbol(mutableSet))
            #expect(mutableSetInfo.kind == .interface)
            #expect(!mutableSetInfo.flags.contains(.synthetic))
            #expect(sema.types.nominalTypeParameterVariances(for: mutableSet) == [.invariant])
            #expect(sema.symbols.directSupertypes(for: mutableSet).contains(set))
            #expect(sema.symbols.directSupertypes(for: mutableSet).contains(mutableCollection))
            // MutableCollection's source migration is a separate task; retain
            // the current direct edge so MutableSet remains MutableIterable.
            #expect(sema.symbols.directSupertypes(for: mutableSet).contains(mutableIterable))
            #expect(sema.symbols.supertypeTypeArgs(for: mutableSet, supertype: set).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: mutableSet, supertype: mutableCollection).count == 1)
            #expect(sema.symbols.supertypeTypeArgs(for: mutableSet, supertype: mutableIterable).count == 1)
            #expect(
                sema.symbols.sourceFileID(for: mutableSet).map { ctx.sourceManager.path(of: $0) }
                    == "__bundled_kotlin/collections/MutableSet.kt"
            )

            let bridgeNames = [
                "add": "__kk_mutable_set_add",
                "addAll": "__kk_mutable_set_addAll",
                "clear": "__kk_mutable_set_clear",
                "remove": "__kk_mutable_set_remove",
                "removeAll": "__kk_mutable_set_removeAll",
                "retainAll": "__kk_mutable_set_retainAll",
            ]
            for (memberName, expectedLink) in bridgeNames {
                let member = try #require(
                    sema.symbols.lookup(fqName: collections + [ctx.interner.intern("MutableSet"), ctx.interner.intern(memberName)])
                )
                #expect(sema.symbols.symbol(member)?.flags.contains(.synthetic) == true)
                #expect(sema.symbols.externalLinkName(for: member) == expectedLink)
            }

            let compoundBridgeNames = [
                "plusAssign": Set(["__kk_mutable_set_add", "__kk_mutable_set_addAll"]),
                "minusAssign": Set(["__kk_mutable_set_remove", "__kk_mutable_set_removeAll"]),
            ]
            for (memberName, expectedLinks) in compoundBridgeNames {
                let members = sema.symbols.lookupAll(
                    fqName: collections + [ctx.interner.intern("MutableSet"), ctx.interner.intern(memberName)]
                )
                #expect(members.count == 2)
                #expect(members.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.synthetic) == true })
                #expect(Set(members.compactMap(sema.symbols.externalLinkName)) == expectedLinks)
            }
        }
    }
}
#endif
