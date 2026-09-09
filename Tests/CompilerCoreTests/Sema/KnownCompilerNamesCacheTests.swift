#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

private final class CapturedCompilerNameIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[InternedString]] = []

    func append(_ ids: [InternedString]) {
        lock.lock()
        defer { lock.unlock() }
        values.append(ids)
    }

    func snapshot() -> [[InternedString]] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@Suite
struct KnownCompilerNamesCacheTests {
    @Test func preservesExistingIDsAndRegistrationOrder() {
        let interner = StringInterner()
        #expect(interner.snapshotValues().isEmpty)
        let userName = interner.intern("userName")
        let existingList = interner.intern("List")

        let first = KnownCompilerNames(interner: interner)
        let registeredNames = interner.snapshotValues()
        let laterName = interner.intern("laterName")
        let second = KnownCompilerNames(interner: interner)

        #expect(first.list == existingList)
        #expect(second.list == existingList)
        #expect(first.kotlinCollectionsListFQName == second.kotlinCollectionsListFQName)
        #expect(first.atomicScalarFactoryFQNames == second.atomicScalarFactoryFQNames)
        #expect(interner.resolve(userName) == "userName")
        #expect(interner.resolve(laterName) == "laterName")
        #expect(interner.snapshotValues() == registeredNames + ["laterName"])
    }

    @Test func keepsIndependentInternerIDsSeparate() {
        let firstInterner = StringInterner()
        firstInterner.preload(["kotlin", "collections", "List"])
        let secondInterner = StringInterner()
        secondInterner.preload(["unrelated"])

        let first = KnownCompilerNames(interner: firstInterner)
        let second = KnownCompilerNames(interner: secondInterner)
        let firstAgain = KnownCompilerNames(interner: firstInterner)

        #expect(first.list != second.list)
        #expect(firstAgain.list == first.list)
        #expect(first.kotlinCollectionsListFQName.map(firstInterner.resolve) == ["kotlin", "collections", "List"])
        #expect(second.kotlinCollectionsListFQName.map(secondInterner.resolve) == ["kotlin", "collections", "List"])
        #expect(firstAgain.atomicScalarFactoryFQNames == first.atomicScalarFactoryFQNames)
    }

    @Test func concurrentFirstAccessCoexistsWithInterning() throws {
        let interner = StringInterner()
        let group = DispatchGroup()
        let captured = CapturedCompilerNameIDs()

        for index in 0 ..< 16 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                let custom = interner.intern("custom_\(index)")
                let names = KnownCompilerNames(interner: interner)
                captured.append([names.byte, names.main] + names.kotlinCollectionsListFQName + [custom])
            }
        }

        try #require(group.wait(timeout: .now() + .seconds(60)) == .success)
        let results = captured.snapshot()
        #expect(results.count == 16)
        for ids in results {
            #expect(ids.prefix(5).map(interner.resolve) == ["Byte", "main", "kotlin", "collections", "List"])
        }
        #expect(Set(results.compactMap(\.last).map(interner.resolve)) == Set((0 ..< 16).map { "custom_\($0)" }))
    }
}
#endif
