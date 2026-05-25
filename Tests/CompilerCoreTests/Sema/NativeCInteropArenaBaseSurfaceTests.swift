@testable import CompilerCore
import Foundation
import XCTest

final class NativeCInteropArenaBaseSurfaceTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected C interop ArenaBase surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func symbol(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
        try XCTUnwrap(
            sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) }),
            "\(fqPath.joined(separator: ".")) must be registered",
            file: file,
            line: line
        )
    }

    private func classType(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        let classSymbol = try symbol(fqPath, sema: sema, interner: interner, file: file, line: line)
        return sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func arenaBaseMemberSignature(
        named name: String,
        parameters: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (SymbolID, FunctionSignature) {
        let arenaBaseSymbol = try symbol(["kotlinx", "cinterop", "ArenaBase"], sema: sema, interner: interner, file: file, line: line)
        let ownerFQName = try XCTUnwrap(sema.symbols.symbol(arenaBaseSymbol)?.fqName, file: file, line: line)
        let receiver = try classType(["kotlinx", "cinterop", "ArenaBase"], sema: sema, interner: interner, file: file, line: line)
        let candidates = sema.symbols.lookupAll(fqName: ownerFQName + [interner.intern(name)])
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                continue
            }
            if signature.receiverType == receiver
                && signature.parameterTypes == parameters
                && signature.returnType == returnType
            {
                return (candidate, signature)
            }
        }

        XCTFail("Expected ArenaBase.\(name) signature, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })", file: file, line: line)
        throw XCTestError(.failureWhileWaiting)
    }

    func testArenaBaseClassAndSupportSymbolsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let arenaBaseSymbol = try symbol(["kotlinx", "cinterop", "ArenaBase"], sema: sema, interner: interner)
        let autofreeScopeSymbol = try symbol(["kotlinx", "cinterop", "AutofreeScope"], sema: sema, interner: interner)
        let deferScopeSymbol = try symbol(["kotlinx", "cinterop", "DeferScope"], sema: sema, interner: interner)
        let nativeFreeablePlacementSymbol = try symbol(["kotlinx", "cinterop", "NativeFreeablePlacement"], sema: sema, interner: interner)
        let nativePlacementSymbol = try symbol(["kotlinx", "cinterop", "NativePlacement"], sema: sema, interner: interner)
        let memScopeSymbol = try symbol(["kotlinx", "cinterop", "MemScope"], sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(arenaBaseSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.symbol(arenaBaseSymbol)?.flags.contains(.openType) == true)
        XCTAssertEqual(sema.symbols.symbol(autofreeScopeSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.symbol(autofreeScopeSymbol)?.flags.contains(.abstractType) == true)
        XCTAssertEqual(sema.symbols.symbol(deferScopeSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.symbol(deferScopeSymbol)?.flags.contains(.openType) == true)
        XCTAssertEqual(sema.symbols.symbol(nativeFreeablePlacementSymbol)?.kind, .interface)
        XCTAssertEqual(sema.symbols.directSupertypes(for: arenaBaseSymbol), [autofreeScopeSymbol])
        XCTAssertEqual(sema.symbols.directSupertypes(for: autofreeScopeSymbol), [deferScopeSymbol, nativePlacementSymbol])
        XCTAssertEqual(sema.symbols.directSupertypes(for: nativeFreeablePlacementSymbol), [nativePlacementSymbol])
        XCTAssertEqual(sema.symbols.directSupertypes(for: memScopeSymbol), [arenaBaseSymbol])
    }

    func testArenaBaseConstructorUsesNativeFreeablePlacementDefault() throws {
        let (sema, interner) = try makeSema()
        let arenaBaseSymbol = try symbol(["kotlinx", "cinterop", "ArenaBase"], sema: sema, interner: interner)
        let arenaBaseFQName = try XCTUnwrap(sema.symbols.symbol(arenaBaseSymbol)?.fqName)
        let arenaBaseType = try classType(["kotlinx", "cinterop", "ArenaBase"], sema: sema, interner: interner)
        let parentType = try classType(["kotlinx", "cinterop", "NativeFreeablePlacement"], sema: sema, interner: interner)
        let constructors = sema.symbols.lookupAll(fqName: arenaBaseFQName + [interner.intern("<init>")])

        let signature = try XCTUnwrap(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [parentType] && $0.returnType == arenaBaseType
        })
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [true])
    }

    func testArenaBaseAllocOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let nativePointedType = try classType(["kotlinx", "cinterop", "NativePointed"], sema: sema, interner: interner)

        let (longAlloc, _) = try arenaBaseMemberSignature(
            named: "alloc",
            parameters: [sema.types.longType, sema.types.intType],
            returnType: nativePointedType,
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(sema.symbols.symbol(longAlloc)?.flags.contains(.overrideMember) == true)

        let (intAlloc, _) = try arenaBaseMemberSignature(
            named: "alloc",
            parameters: [sema.types.intType, sema.types.intType],
            returnType: nativePointedType,
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(sema.symbols.symbol(intAlloc)?.flags.contains(.openType) == true)
    }

    func testArenaBaseResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlinx.cinterop.ArenaBase
        import kotlinx.cinterop.NativePointed

        fun probe(): NativePointed {
            val arena = ArenaBase()
            return arena.alloc(8, 4)
        }
        """)
    }
}
