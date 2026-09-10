@testable import CompilerCore
import Testing

/// KSP-1036: AbstractMutableList's default mutable-list surface is bundled
/// Kotlin source, including its protected modification counter.
@Suite
struct AbstractMutableListSourceMigrationTests {
    @Test
    func abstractMutableListMembersAreSourceBacked() throws {
        let source = """
        import kotlin.collections.AbstractMutableList
        import kotlin.collections.List

        class ConcreteProbe : AbstractMutableList<Int>() {
            override val size: Int
                get() = 0
            override fun get(index: Int): Int = 0
            override fun set(index: Int, element: Int): Int = 0
            override fun add(index: Int, element: Int) {}
            override fun removeAt(index: Int): Int = 0

            fun clearRange() {
                removeRange(0, size)
            }
        }

        fun exercise(values: ConcreteProbe) {
            values.add(1)
            values.add(0, 1)
            values.addAll(0, listOf(1))
            values.clear()
            values.contains(1)
            values.indexOf(1)
            values.lastIndexOf(1)
            values.iterator()
            values.listIterator()
            values.listIterator(0)
            values.removeAll(listOf(1))
            values.retainAll(listOf(1))
            values.subList(0, 0)
            values.equals(values)
            values.hashCode()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Expected ConcreteProbe to use the source-backed AbstractMutableList defaults, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let abstractMutableListFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("AbstractMutableList"),
            ]
            let sourcePath = "__bundled_kotlin/collections/AbstractMutableList.kt"
            let abstractMutableList = try #require(
                sema.symbols.lookupAll(fqName: abstractMutableListFQName).first { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          !symbol.flags.contains(.synthetic),
                          let fileID = sema.symbols.sourceFileID(for: candidate)
                    else {
                        return false
                    }
                    return ctx.sourceManager.path(of: fileID) == sourcePath
                }
            )

            let abstractMutableListInfo = try #require(sema.symbols.symbol(abstractMutableList))
            #expect(abstractMutableListInfo.kind == .class)
            #expect(!abstractMutableListInfo.flags.contains(.synthetic))
            // Compatibility shells for bundled nominal types intentionally keep
            // a nil declSite, so source provenance is asserted through sourceFileID.
            let abstractMutableListFile = try #require(sema.symbols.sourceFileID(for: abstractMutableList))
            #expect(ctx.sourceManager.path(of: abstractMutableListFile) == sourcePath)

            let expectedMembers: [(String, Int)] = [
                ("add", 1),
                ("add", 2),
                ("addAll", 2),
                ("clear", 0),
                ("contains", 1),
                ("equals", 1),
                ("hashCode", 0),
                ("indexOf", 1),
                ("iterator", 0),
                ("lastIndexOf", 1),
                ("listIterator", 0),
                ("listIterator", 1),
                ("removeAll", 1),
                ("removeAt", 1),
                ("removeRange", 2),
                ("retainAll", 1),
                ("set", 2),
                ("subList", 2),
            ]

            for (memberName, arity) in expectedMembers {
                let candidates = sema.symbols.lookupAll(
                    fqName: abstractMutableListFQName + [interner.intern(memberName)]
                ).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.parentSymbol(for: candidate) == abstractMutableList,
                          !symbol.flags.contains(.synthetic),
                          sema.symbols.isSourceBackedSymbol(candidate),
                          let fileID = sema.symbols.sourceFileID(for: candidate),
                          let signature = sema.symbols.functionSignature(for: candidate)
                    else {
                        return false
                    }
                    return ctx.sourceManager.path(of: fileID) == sourcePath
                        && signature.parameterTypes.count == arity
                        && sema.symbols.externalLinkName(for: candidate) == nil
                }
                #expect(
                    candidates.count == 1,
                    "Expected one source-backed AbstractMutableList.\(memberName) overload with arity \(arity), got \(candidates)"
                )
            }

            let modCount = try #require(
                sema.symbols.lookupAll(
                    fqName: abstractMutableListFQName + [interner.intern("modCount")]
                ).first { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .property,
                          sema.symbols.parentSymbol(for: candidate) == abstractMutableList,
                          !symbol.flags.contains(.synthetic),
                          sema.symbols.isSourceBackedSymbol(candidate),
                          let fileID = sema.symbols.sourceFileID(for: candidate)
                    else {
                        return false
                    }
                    return ctx.sourceManager.path(of: fileID) == sourcePath
                        && sema.symbols.externalLinkName(for: candidate) == nil
                }
            )
            let modCountInfo = try #require(sema.symbols.symbol(modCount))
            #expect(modCountInfo.visibility == .protected)
            #expect(modCountInfo.flags.contains(.mutable))
            #expect(sema.symbols.propertyType(for: modCount) == sema.types.intType)

            let concreteAddCall = try #require(firstMemberCall(in: ast, ctx: ctx) { name, arity in
                name == "add" && arity == 1
            })
            let concreteAddCallee = try #require(sema.bindings.callBinding(for: concreteAddCall)?.chosenCallee)
            #expect(
                sema.symbols.symbol(concreteAddCallee)?.fqName == abstractMutableListFQName + [interner.intern("add")]
            )
            #expect(sema.symbols.isSourceBackedSymbol(concreteAddCallee))
            #expect(sema.symbols.externalLinkName(for: concreteAddCallee) == nil)
        }
    }
}

private func firstMemberCall(
    in ast: ASTModule,
    ctx: CompilationContext,
    where predicate: (String, Int) -> Bool
) -> ExprID? {
    for index in ast.arena.exprs.indices {
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID),
              case let .memberCall(_, callee, _, args, range) = expr,
              !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
        else {
            continue
        }
        let name = ctx.interner.resolve(callee)
        if predicate(name, args.count) {
            return exprID
        }
    }
    return nil
}
