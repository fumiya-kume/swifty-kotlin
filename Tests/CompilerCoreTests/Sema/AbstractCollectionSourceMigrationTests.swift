#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Focused source-backed surface and protected-member coverage for KSP-1026.
@Suite(.serialized)
struct AbstractCollectionSourceMigrationTests {
    private static nonisolated(unsafe) var sharedSema: (CompilationContext, SemaModule, StringInterner)?

    private func makeSharedSema() throws -> (CompilationContext, SemaModule, StringInterner) {
        if let shared = Self.sharedSema {
            return shared
        }

        var result: (CompilationContext, SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (ctx, sema, ctx.interner)
        }

        let shared = try #require(result)
        Self.sharedSema = shared
        return shared
    }

    @Test
    func testSourceBackedMembersAreRegisteredWithKotlinContract() throws {
        let (ctx, sema, interner) = try makeSharedSema()
        let collectionsPackage = ["kotlin", "collections"].map(interner.intern)
        let abstractCollection = try #require(
            sema.symbols.lookup(fqName: collectionsPackage + [interner.intern("AbstractCollection")])
        )
        let sourcePath = "__bundled_kotlin/collections/AbstractCollection.kt"

        func members(named name: String) -> [SymbolID] {
            sema.symbols.lookupAll(
                fqName: collectionsPackage + [interner.intern("AbstractCollection"), interner.intern(name)]
            ).filter { sema.symbols.parentSymbol(for: $0) == abstractCollection }
        }

        let toString = try #require(members(named: "toString").first)
        let toStringInfo = try #require(sema.symbols.symbol(toString))
        #expect(toStringInfo.visibility == .public)
        #expect(sema.symbols.externalLinkName(for: toString) == nil)
        #expect(sema.symbols.isSourceBackedSymbol(toString))
        #expect(sema.symbols.sourceFileID(for: toString).map { ctx.sourceManager.path(of: $0) } == sourcePath)
        #expect(sema.symbols.functionSignature(for: toString)?.parameterTypes.isEmpty == true)

        let toArray = members(named: "toArray")
        try #require(toArray.count == 2, "Expected both protected toArray overloads")
        #expect(toArray.allSatisfy { member in
            guard let info = sema.symbols.symbol(member),
                  let signature = sema.symbols.functionSignature(for: member)
            else {
                return false
            }
            return info.visibility == .protected
                && sema.symbols.externalLinkName(for: member) == nil
                && sema.symbols.isSourceBackedSymbol(member)
                && sema.symbols.sourceFileID(for: member).map { ctx.sourceManager.path(of: $0) } == sourcePath
                && signature.parameterTypes.count <= 1
        })
        #expect(toArray.contains { sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true })
        #expect(toArray.contains { sema.symbols.functionSignature(for: $0)?.parameterTypes.count == 1 })
    }

    @Test
    func testProtectedToArrayMembersTypeCheckThroughConcreteSubclass() throws {
        let source = """
        import kotlin.collections.AbstractCollection
        import kotlin.collections.Iterator

        private class ProbeIterator(private val values: Array<String?>) : Iterator<String?> {
            private var index = 0

            override fun hasNext(): Boolean = index < values.size

            override fun next(): String? {
                val value = values[index]
                index += 1
                return value
            }
        }

        class ProbeCollection : AbstractCollection<String?>() {
            private val values = arrayOf<String?>("one", null)

            override val size: Int
                get() = values.size

            override fun iterator(): Iterator<String?> = ProbeIterator(values)

            fun objectArray(): Array<Any?> = toArray()

            fun copyInto(array: Array<Any?>): Array<Any?> = toArray(array)
        }

        fun inspect(collection: ProbeCollection): String {
            val rendered = collection.toString()
            val objectArray = collection.objectArray()
            val typedArray = collection.copyInto(arrayOf<Any?>(null, null))
            return "$rendered:${objectArray.size}:${typedArray.size}"
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected KSP-1026 AbstractCollection members to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
        }
    }
}
#endif
