#if canImport(Testing)
@testable import CompilerCore
import Testing

// MARK: - STDLIB-NATIVE-CONCURRENT-001: kotlin.native.concurrent API inventory

@Suite
struct NativeConcurrentAPISurfaceInventoryTests {
    private struct TopLevelEntry: Hashable {
        let name: String
        let kind: SymbolKind
        let todo: String?
    }

    private static let implementedTopLevelEntries: Set<TopLevelEntry> = [
        TopLevelEntry(name: "AtomicInt", kind: .class, todo: nil),
        TopLevelEntry(name: "AtomicLong", kind: .class, todo: nil),
        TopLevelEntry(name: "AtomicNativePtr", kind: .class, todo: nil),
        TopLevelEntry(name: "AtomicReference", kind: .class, todo: nil),
        TopLevelEntry(name: "Continuation0", kind: .class, todo: nil),
        TopLevelEntry(name: "Continuation1", kind: .class, todo: nil),
        TopLevelEntry(name: "Continuation2", kind: .class, todo: nil),
        TopLevelEntry(name: "DetachedObjectGraph", kind: .class, todo: nil),
        TopLevelEntry(name: "FreezableAtomicReference", kind: .class, todo: nil),
        TopLevelEntry(name: "FreezingException", kind: .class, todo: nil),
        TopLevelEntry(name: "Future", kind: .class, todo: nil),
        TopLevelEntry(name: "FutureState", kind: .enumClass, todo: nil),
        TopLevelEntry(name: "InvalidMutabilityException", kind: .class, todo: nil),
        TopLevelEntry(name: "MutableData", kind: .class, todo: nil),
        TopLevelEntry(name: "ObsoleteWorkersApi", kind: .annotationClass, todo: nil),
        TopLevelEntry(name: "SharedImmutable", kind: .annotationClass, todo: nil),
        TopLevelEntry(name: "ThreadLocal", kind: .annotationClass, todo: nil),
        TopLevelEntry(name: "TransferMode", kind: .enumClass, todo: nil),
        TopLevelEntry(name: "Worker", kind: .class, todo: nil),
        TopLevelEntry(name: "WorkerBoundReference", kind: .class, todo: nil),
        TopLevelEntry(name: "atomicLazy", kind: .function, todo: nil),
        TopLevelEntry(name: "attachObjectGraphInternal", kind: .function, todo: nil),
        TopLevelEntry(name: "callContinuation0", kind: .function, todo: nil),
        TopLevelEntry(name: "callContinuation1", kind: .function, todo: nil),
        TopLevelEntry(name: "callContinuation2", kind: .function, todo: nil),
        TopLevelEntry(name: "consumeFuture", kind: .function, todo: nil),
        TopLevelEntry(name: "detachObjectGraphInternal", kind: .function, todo: nil),
        TopLevelEntry(name: "executeImpl", kind: .function, todo: nil),
        TopLevelEntry(name: "freeze", kind: .function, todo: nil),
        TopLevelEntry(name: "waitForMultipleFutures", kind: .function, todo: nil),
        TopLevelEntry(name: "waitWorkerTermination", kind: .function, todo: nil),
        TopLevelEntry(name: "withWorker", kind: .function, todo: nil),
    ]

    private static let ksp1216TopLevelNames: Set<String> = [
        "AtomicInt", "AtomicLong", "AtomicNativePtr", "AtomicReference",
        "Continuation0", "Continuation1", "Continuation2", "DetachedObjectGraph",
        "FreezableAtomicReference", "FreezingException", "Future", "FutureState",
        "InvalidMutabilityException", "MutableData", "ObsoleteWorkersApi",
        "SharedImmutable", "ThreadLocal", "TransferMode", "Worker",
        "WorkerBoundReference", "atomicLazy", "attachObjectGraphInternal",
        "consumeFuture", "detachObjectGraphInternal", "executeImpl", "freeze",
        "waitForMultipleFutures", "waitWorkerTermination", "withWorker",
    ]

    private static let knownGapTopLevelEntries: Set<TopLevelEntry> = []

    private static let packagePath = ["kotlin", "native", "concurrent"]

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    @Test
    func testTargetInventoryHasExpectedShape() {
        // Structural invariants only — no magic totals. A previous version asserted exact
        // sizes (`== 31`, `== 28`, `== 3`) which forced every PR adding/promoting a stub
        // to update three integers and was a major merge-conflict source.
        let targetEntries = Self.implementedTopLevelEntries.union(Self.knownGapTopLevelEntries)
        let targetNames = Set(targetEntries.map(\.name))

        // Each TopLevelEntry must have a unique name (no two entries share a `name`).
        #expect(targetEntries.count == targetNames.count)
        #expect(targetEntries.count == 32)
        #expect(Self.implementedTopLevelEntries.count == 32)
        #expect(Self.knownGapTopLevelEntries.count == 0)
        #expect(Self.ksp1216TopLevelNames.count == 29)
        #expect(Self.ksp1216TopLevelNames.isSubset(of: targetNames))
    }

    @Test
    func testImplementedTopLevelEntriesAreRegistered() throws {
        let (sema, interner) = try sharedSema()
        let package = Self.packagePath.map { interner.intern($0) }

        for entry in Self.implementedTopLevelEntries {
            let symbol = try #require(
                sema.symbols.lookup(fqName: package + [interner.intern(entry.name)]),
                "\(entry.name) should be registered in kotlin.native.concurrent"
            )
            #expect(
                sema.symbols.symbol(symbol)?.kind == entry.kind,
                "\(entry.name) should be registered as \(entry.kind)"
            )
        }
    }

    @Test
    func testCurrentPublishedTopLevelNamesStayWithinInventory() throws {
        let (sema, interner) = try sharedSema()
        let package = Self.packagePath.map { interner.intern($0) }
        let targetNames = Set(Self.implementedTopLevelEntries.union(Self.knownGapTopLevelEntries).map(\.name))
        let currentNames = Set(sema.symbols.allSymbols().compactMap { symbol -> String? in
            guard symbol.fqName.count == package.count + 1,
                  Array(symbol.fqName.prefix(package.count)) == package,
                  symbol.kind != .package
            else {
                return nil
            }
            return interner.resolve(symbol.name)
        })

        #expect(currentNames.subtracting(targetNames) == [])
    }

    @Test
    func testKnownGapEntriesRemainAbsentUntilTheirTodoIsImplemented() throws {
        let (sema, interner) = try sharedSema()
        let package = Self.packagePath.map { interner.intern($0) }

        for entry in Self.knownGapTopLevelEntries {
            let symbols = sema.symbols.lookupAll(fqName: package + [interner.intern(entry.name)])
            #expect(
                symbols.isEmpty,
                "\(entry.name) is tracked by \(entry.todo ?? "unknown TODO") and should update this inventory when implemented"
            )
        }
    }

    @Test
    func testKnownGapTodosAreNativeConcurrentItems() {
        let todos = Set(Self.knownGapTopLevelEntries.compactMap(\.todo))
        #expect(todos == [])
    }
}
#endif
