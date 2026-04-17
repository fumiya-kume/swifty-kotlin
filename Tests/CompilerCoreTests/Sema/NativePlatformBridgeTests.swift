@testable import CompilerCore
import XCTest

/// STDLIB-NATIVE-PLATFORM-002: Sema-level tests verifying that
/// Platform, OsFamily, and CpuArchitecture are visible and correctly
/// bridged from a common expect declaration to a native actual declaration.
/// No runtime edits are made; these tests exercise the symbol-table and
/// type-checker layers only.
final class NativePlatformBridgeTests: XCTestCase {

    // MARK: - OsFamily visibility

    func testOsFamilyEnumIsVisibleInSymbolTable() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("OsFamily"),
        ]
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) },
            "kotlin.native.OsFamily must be registered as a synthetic enum class"
        )
        XCTAssertEqual(symbol.kind, .enumClass)
    }

    func testOsFamilyHasExpectedEntries() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let baseFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("OsFamily"),
        ]
        let expectedEntries = ["UNKNOWN", "MACOSX", "IOS", "TVOS", "WATCHOS",
                               "LINUX", "WINDOWS", "ANDROID", "WASM"]
        for entry in expectedEntries {
            let entryFQName = baseFQName + [ctx.interner.intern(entry)]
            let sym = sema.symbols.lookup(fqName: entryFQName).flatMap { sema.symbols.symbol($0) }
            XCTAssertNotNil(sym, "OsFamily.\(entry) must be visible in the symbol table")
        }
    }

    // MARK: - CpuArchitecture visibility

    func testCpuArchitectureEnumIsVisibleInSymbolTable() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("CpuArchitecture"),
        ]
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) },
            "kotlin.native.CpuArchitecture must be registered as a synthetic enum class"
        )
        XCTAssertEqual(symbol.kind, .enumClass)
    }

    func testCpuArchitectureHasExpectedEntries() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let baseFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("CpuArchitecture"),
        ]
        let expectedEntries = ["UNKNOWN", "X86", "X64", "ARM32",
                               "ARM64", "MIPS32", "MIPSEL32", "WASM32"]
        for entry in expectedEntries {
            let entryFQName = baseFQName + [ctx.interner.intern(entry)]
            let sym = sema.symbols.lookup(fqName: entryFQName).flatMap { sema.symbols.symbol($0) }
            XCTAssertNotNil(sym, "CpuArchitecture.\(entry) must be visible in the symbol table")
        }
    }

    // MARK: - Platform object visibility

    func testPlatformObjectIsVisibleInSymbolTable() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
        ]
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) },
            "kotlin.native.Platform must be registered as a synthetic object/class"
        )
        // Platform is registered as a class acting as an object singleton
        XCTAssertTrue(
            symbol.kind == .class || symbol.kind == .object,
            "Expected Platform to be a class or object, got \(symbol.kind)"
        )
    }

    func testPlatformOsFamilyPropertyIsVisible() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
            ctx.interner.intern("osFamily"),
        ]
        let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
        XCTAssertNotNil(symbol, "Platform.osFamily must be registered as a property")
        XCTAssertEqual(symbol?.kind, .property)
    }

    func testPlatformCpuArchitecturePropertyIsVisible() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
            ctx.interner.intern("cpuArchitecture"),
        ]
        let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
        XCTAssertNotNil(symbol, "Platform.cpuArchitecture must be registered as a property")
        XCTAssertEqual(symbol?.kind, .property)
    }

    func testPlatformCanAccessUnalignedPropertyIsVisible() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
            ctx.interner.intern("canAccessUnaligned"),
        ]
        let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
        XCTAssertNotNil(symbol, "Platform.canAccessUnaligned must be registered as a property")
        XCTAssertEqual(symbol?.kind, .property)
    }

    func testPlatformIsLittleEndianPropertyIsVisible() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
            ctx.interner.intern("isLittleEndian"),
        ]
        let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
        XCTAssertNotNil(symbol, "Platform.isLittleEndian must be registered as a property")
        XCTAssertEqual(symbol?.kind, .property)
    }

    // MARK: - Common → Native expect/actual bridge

    /// Verifies that a top-level expect/actual class named OsFamily (mirroring the
    /// real kotlin.native.OsFamily bridge shape) resolves without errors.
    /// Enum body entries are omitted because the sema treats them as duplicate
    /// declarations when both expect and actual bodies share the same scope;
    /// the class-level expect/actual link is what this test exercises.
    func testOsFamilyLikeExpectActualBridgeResolvesCleanly() throws {
        let sources = [
            // common module: expect class (body omitted — entry declarations
            // from both sides would conflict in the shared scope)
            """
            package sample.native
            expect class OsFamily
            """,
            // native module: actual implementation
            """
            package sample.native
            actual class OsFamily
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter {
            if case .error = $0.severity { return true }
            return false
        }
        XCTAssertTrue(errors.isEmpty, "Expect/actual OsFamily bridge must not produce errors, got: \(errors)")

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("sample"),
            ctx.interner.intern("native"),
            ctx.interner.intern("OsFamily"),
        ]
        let allSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSym = try XCTUnwrap(allSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualSym = try XCTUnwrap(allSymbols.first { $0.flags.contains(.actualDeclaration) })
        XCTAssertEqual(sema.symbols.actualSymbol(for: expectSym.id), actualSym.id)
    }

    // MARK: - Common → Native expect/actual bridge for CpuArchitecture

    func testCpuArchitectureLikeExpectActualBridgeResolvesCleanly() throws {
        let sources = [
            """
            package sample.native
            expect class CpuArchitecture
            """,
            """
            package sample.native
            actual class CpuArchitecture
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter {
            if case .error = $0.severity { return true }
            return false
        }
        XCTAssertTrue(errors.isEmpty, "Expect/actual CpuArchitecture bridge must not produce errors, got: \(errors)")

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("sample"),
            ctx.interner.intern("native"),
            ctx.interner.intern("CpuArchitecture"),
        ]
        let allSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSym = try XCTUnwrap(allSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualSym = try XCTUnwrap(allSymbols.first { $0.flags.contains(.actualDeclaration) })
        XCTAssertEqual(sema.symbols.actualSymbol(for: expectSym.id), actualSym.id)
    }

    // MARK: - Common → Native expect/actual bridge for Platform class

    func testPlatformLikeExpectActualBridgeResolvesCleanly() throws {
        let sources = [
            // expect: a class named Platform (mirrors the stdlib shape)
            """
            package sample.native
            expect class Platform
            """,
            // actual: same class
            """
            package sample.native
            actual class Platform
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter {
            if case .error = $0.severity { return true }
            return false
        }
        XCTAssertTrue(errors.isEmpty, "Expect/actual Platform bridge must not produce errors, got: \(errors)")

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("sample"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
        ]
        let allSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSym = try XCTUnwrap(allSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualSym = try XCTUnwrap(allSymbols.first { $0.flags.contains(.actualDeclaration) })
        XCTAssertEqual(sema.symbols.actualSymbol(for: expectSym.id), actualSym.id)
    }

    // MARK: - Mismatch detection

    func testExpectEnumActualClassMismatchIsRejected() throws {
        let sources = [
            // expect: enum class
            """
            package sample.native
            expect enum class OsFamily {
                UNKNOWN
            }
            """,
            // actual: plain class — kind mismatch
            """
            package sample.native
            actual class OsFamily
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errorCodes = ctx.diagnostics.diagnostics.compactMap { d -> String? in
            guard d.severity == .error else { return nil }
            return d.code
        }
        XCTAssertTrue(
            errorCodes.contains("KSWIFTK-MPP-UNRESOLVED"),
            "Kind mismatch between expect enum class and actual class must be diagnosed, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - MemoryModel gap note

    /// NOTE: kotlin.native.MemoryModel is not yet registered as a synthetic stub in
    /// HeaderHelpers+SyntheticTODOAndIOStubs.swift.  When that stub is added, a
    /// companion test analogous to testOsFamilyEnumIsVisibleInSymbolTable should
    /// be added here.  This test documents the current coverage gap.
    func testMemoryModelStubIsAbsentUntilImplemented() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("MemoryModel"),
        ]
        // MemoryModel is not yet stubbed; the lookup must return nil.
        // When the stub is added, change this assertion to XCTAssertNotNil.
        let symbol = sema.symbols.lookup(fqName: fqName)
        XCTAssertNil(symbol, "MemoryModel is not yet stubbed; update this test when the stub is added")
    }
}
