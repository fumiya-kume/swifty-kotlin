@testable import CompilerCore
import XCTest

// MARK: - STDLIB-NATIVE-CONCURRENT-001: kotlin.native.concurrent API inventory

final class NativeConcurrentAPISurfaceInventoryTests: XCTestCase {
    private struct TopLevelEntry: Hashable {
        let name: String
        let kind: SymbolKind
        let todo: String?
    }

    private static let implementedTopLevelEntries: Set<TopLevelEntry> = [
        TopLevelEntry(name: "AtomicReference", kind: .class, todo: nil),
        TopLevelEntry(name: "DetachedObjectGraph", kind: .class, todo: nil),
        TopLevelEntry(name: "FreezingException", kind: .class, todo: nil),
        TopLevelEntry(name: "Future", kind: .class, todo: nil),
        TopLevelEntry(name: "FutureState", kind: .enumClass, todo: nil),
        TopLevelEntry(name: "SharedImmutable", kind: .annotationClass, todo: nil),
        TopLevelEntry(name: "ThreadLocal", kind: .annotationClass, todo: nil),
        TopLevelEntry(name: "TransferMode", kind: .enumClass, todo: nil),
        TopLevelEntry(name: "Worker", kind: .class, todo: nil),
        TopLevelEntry(name: "attach", kind: .function, todo: nil),
    ]

    private static let knownGapTopLevelEntries: Set<TopLevelEntry> = [
        TopLevelEntry(name: "AtomicInt", kind: .class, todo: "STDLIB-NATIVE-CONCURRENT-015"),
        TopLevelEntry(name: "AtomicLong", kind: .class, todo: "STDLIB-NATIVE-CONCURRENT-015"),
        TopLevelEntry(name: "AtomicNativePtr", kind: .class, todo: "STDLIB-NATIVE-CONCURRENT-015"),
        TopLevelEntry(name: "Continuation0", kind: .class, todo: "STDLIB-NATIVE-CONCURRENT-010"),
        TopLevelEntry(name: "Continuation1", kind: .class, todo: "STDLIB-NATIVE-CONCURRENT-010"),
        TopLevelEntry(name: "Continuation2", kind: .class, todo: "STDLIB-NATIVE-CONCURRENT-010"),
        TopLevelEntry(name: "FreezableAtomicReference", kind: .class, todo: "STDLIB-NATIVE-CONCURRENT-016"),
        TopLevelEntry(name: "InvalidMutabilityException", kind: .class, todo: "STDLIB-NATIVE-CONCURRENT-006"),
        TopLevelEntry(name: "MutableData", kind: .class, todo: "STDLIB-NATIVE-CONCURRENT-017"),
        TopLevelEntry(name: "ObsoleteWorkersApi", kind: .annotationClass, todo: "STDLIB-NATIVE-CONCURRENT-018"),
        TopLevelEntry(name: "WorkerBoundReference", kind: .class, todo: "STDLIB-NATIVE-CONCURRENT-007"),
        TopLevelEntry(name: "atomicLazy", kind: .function, todo: "STDLIB-NATIVE-CONCURRENT-008"),
        TopLevelEntry(name: "callContinuation0", kind: .function, todo: "STDLIB-NATIVE-CONCURRENT-011"),
        TopLevelEntry(name: "callContinuation1", kind: .function, todo: "STDLIB-NATIVE-CONCURRENT-011"),
        TopLevelEntry(name: "callContinuation2", kind: .function, todo: "STDLIB-NATIVE-CONCURRENT-011"),
        TopLevelEntry(name: "ensureNeverFrozen", kind: .function, todo: "STDLIB-NATIVE-CONCURRENT-009"),
        TopLevelEntry(name: "freeze", kind: .function, todo: "STDLIB-NATIVE-CONCURRENT-019"),
        TopLevelEntry(name: "isFrozen", kind: .property, todo: "STDLIB-NATIVE-CONCURRENT-019"),
        TopLevelEntry(name: "waitForMultipleFutures", kind: .function, todo: "STDLIB-NATIVE-CONCURRENT-012"),
        TopLevelEntry(name: "waitWorkerTermination", kind: .function, todo: "STDLIB-NATIVE-CONCURRENT-013"),
        TopLevelEntry(name: "withWorker", kind: .function, todo: "STDLIB-NATIVE-CONCURRENT-014"),
    ]

    private static let packagePath = ["kotlin", "native", "concurrent"]

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testTargetInventoryHasExpectedShape() {
        let targetEntries = Self.implementedTopLevelEntries.union(Self.knownGapTopLevelEntries)
        let targetNames = Set(targetEntries.map(\.name))

        XCTAssertEqual(targetEntries.count, targetNames.count)
        XCTAssertEqual(targetEntries.count, 31)
        XCTAssertEqual(Self.implementedTopLevelEntries.count, 10)
        XCTAssertEqual(Self.knownGapTopLevelEntries.count, 21)
    }

    func testImplementedTopLevelEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let package = Self.packagePath.map { interner.intern($0) }

        for entry in Self.implementedTopLevelEntries {
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: package + [interner.intern(entry.name)]),
                "\(entry.name) should be registered in kotlin.native.concurrent"
            )
            XCTAssertEqual(
                sema.symbols.symbol(symbol)?.kind,
                entry.kind,
                "\(entry.name) should be registered as \(entry.kind)"
            )
        }
    }

    func testCurrentPublishedTopLevelNamesStayWithinInventory() throws {
        let (sema, interner) = try makeSema()
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

        XCTAssertEqual(currentNames.subtracting(targetNames), [])
    }

    func testKnownGapEntriesRemainAbsentUntilTheirTodoIsImplemented() throws {
        let (sema, interner) = try makeSema()
        let package = Self.packagePath.map { interner.intern($0) }

        for entry in Self.knownGapTopLevelEntries {
            let symbols = sema.symbols.lookupAll(fqName: package + [interner.intern(entry.name)])
            XCTAssertTrue(
                symbols.isEmpty,
                "\(entry.name) is tracked by \(entry.todo ?? "unknown TODO") and should update this inventory when implemented"
            )
        }
    }

    func testKnownGapTodosAreNativeConcurrentItems() {
        let todos = Set(Self.knownGapTopLevelEntries.compactMap(\.todo))
        XCTAssertEqual(
            todos,
            [
                "STDLIB-NATIVE-CONCURRENT-006",
                "STDLIB-NATIVE-CONCURRENT-007",
                "STDLIB-NATIVE-CONCURRENT-008",
                "STDLIB-NATIVE-CONCURRENT-009",
                "STDLIB-NATIVE-CONCURRENT-010",
                "STDLIB-NATIVE-CONCURRENT-011",
                "STDLIB-NATIVE-CONCURRENT-012",
                "STDLIB-NATIVE-CONCURRENT-013",
                "STDLIB-NATIVE-CONCURRENT-014",
                "STDLIB-NATIVE-CONCURRENT-015",
                "STDLIB-NATIVE-CONCURRENT-016",
                "STDLIB-NATIVE-CONCURRENT-017",
                "STDLIB-NATIVE-CONCURRENT-018",
                "STDLIB-NATIVE-CONCURRENT-019",
            ]
        )
    }
}
