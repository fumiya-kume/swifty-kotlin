#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ListIteratorSourceMigrationTests {
    private func makeSema(source: String = "fun noop() {}") throws -> CompilationContext {
        var result: CompilationContext?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, Comment(rawValue: "ListIterator source should resolve cleanly, got: \(diagnostics)"))
            result = ctx
        }
        return try #require(result)
    }

    @Test
    func testListIteratorSurfaceIsSourceBacked() throws {
        let ctx = try makeSema()
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let collections = ["kotlin", "collections"].map(interner.intern)
        let listIteratorFQName = collections + [interner.intern("ListIterator")]
        let iteratorFQName = collections + [interner.intern("Iterator")]
        let listIterator = try #require(sema.symbols.lookup(fqName: listIteratorFQName))
        let iterator = try #require(sema.symbols.lookup(fqName: iteratorFQName))
        let listIteratorInfo = try #require(sema.symbols.symbol(listIterator))

        #expect(listIteratorInfo.kind == .interface)
        #expect(!listIteratorInfo.flags.contains(.synthetic))
        #expect(sema.types.nominalTypeParameterVariances(for: listIterator) == [.out])
        #expect(sema.symbols.directSupertypes(for: listIterator) == [iterator])

        for name in ["hasNext", "hasPrevious", "next", "nextIndex", "previous", "previousIndex"] {
            let member = try #require(
                sema.symbols.lookup(fqName: listIteratorFQName + [interner.intern(name)])
            )
            let memberInfo = try #require(sema.symbols.symbol(member))
            #expect(!memberInfo.flags.contains(.synthetic), "ListIterator.\(name) must be source-backed")
            #expect(sema.symbols.sourceFileID(for: member) != nil)
            #expect(sema.symbols.externalLinkName(for: member) == nil)
        }
    }

    @Test
    func testCustomImplementationAndTypedListIteratorCallsResolve() throws {
        let source = """
        private class ProbeListIterator : ListIterator<Int> {
            private var cursor = 0

            override fun hasNext(): Boolean = cursor < 2
            override fun next(): Int {
                val value = cursor + 10
                cursor += 1
                return value
            }
            override fun hasPrevious(): Boolean = cursor > 0
            override fun previous(): Int {
                cursor -= 1
                return cursor + 10
            }
            override fun nextIndex(): Int = cursor
            override fun previousIndex(): Int = cursor - 1
        }

        fun consume(iterator: ListIterator<Int>): Int {
            val next = if (iterator.hasNext()) iterator.next() else iterator.previous()
            return next + iterator.nextIndex() + iterator.previousIndex()
        }

        fun makeIterator(): ListIterator<Int> = ProbeListIterator()
        """
        let ctx = try makeSema(source: source)
        let sema = try #require(ctx.sema)
        #expect(!ctx.diagnostics.hasError)

        let userCallNames = ["nextIndex", "previousIndex"]
        let ast = try #require(ctx.ast)
        for name in userCallNames {
            let call = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .memberCall(_, callee, _, args, range) = ast.arena.expr(exprID),
                      args.isEmpty,
                      !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                else { return nil }
                return ctx.interner.resolve(callee) == name ? exprID : nil
            }.last)
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            let chosenInfo = try #require(sema.symbols.symbol(chosen))
            #expect(!chosenInfo.flags.contains(.synthetic))
        }
    }
}
#endif
