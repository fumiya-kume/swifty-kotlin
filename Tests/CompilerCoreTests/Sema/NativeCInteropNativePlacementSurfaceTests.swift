@testable import CompilerCore
import XCTest

final class NativeCInteropNativePlacementSurfaceTests: XCTestCase {
    func testNativePlacementInterfaceSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativePlacement surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) }),
                "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered"
            )
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }
        func cinteropType(_ path: String...) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(path),
                args: [],
                nullability: .nonNull
            )))
        }

        let nativePlacementSymbol = try cinteropSymbol("NativePlacement")
        let nativePlacementType = try cinteropType("NativePlacement")

        XCTAssertEqual(sema.symbols.symbol(nativePlacementSymbol)?.kind, .interface)
        XCTAssertEqual(sema.symbols.propertyType(for: nativePlacementSymbol), nativePlacementType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: nativePlacementSymbol), [])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: nativePlacementSymbol), [])
    }

    func testNativePlacementAllocMembersAreRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativePlacement alloc members to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let nativePlacementSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "NativePlacement"].map { interner.intern($0) })
        )
        let nativePointedSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "NativePointed"].map { interner.intern($0) })
        )
        let nativePlacementType = sema.types.make(.classType(ClassType(
            classSymbol: nativePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nativePointedType = sema.types.make(.classType(ClassType(
            classSymbol: nativePointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        let fqName = try XCTUnwrap(sema.symbols.symbol(nativePlacementSymbol)?.fqName)
        let allocMembers = sema.symbols.lookupAll(fqName: fqName + [interner.intern("alloc")])

        let longAlloc = try XCTUnwrap(allocMembers.first { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == nativePlacementType
                && signature.parameterTypes == [sema.types.longType, sema.types.intType]
                && signature.returnType == nativePointedType
        })
        XCTAssertTrue(sema.symbols.symbol(longAlloc)?.flags.contains(.abstractType) == true)

        let intAlloc = try XCTUnwrap(allocMembers.first { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == nativePlacementType
                && signature.parameterTypes == [sema.types.intType, sema.types.intType]
                && signature.returnType == nativePointedType
        })
        XCTAssertTrue(sema.symbols.symbol(intAlloc)?.flags.contains(.openType) == true)
    }

    func testNativePlacementAllocResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.NativePlacement
        import kotlinx.cinterop.NativePointed

        fun byInt(placement: NativePlacement): NativePointed {
            return placement.alloc(8, 4)
        }

        fun byLong(placement: NativePlacement): NativePointed {
            return placement.alloc(8L, 4)
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativePlacement.alloc to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
