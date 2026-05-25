@testable import CompilerCore
import XCTest

final class WasmUnsafePointerTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Pointer surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func symbol(
        _ path: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        sema.symbols.lookup(fqName: path.map { interner.intern($0) })
    }

    private func pointerFQName(interner: StringInterner) -> [InternedString] {
        ["kotlin", "wasm", "unsafe", "Pointer"].map { interner.intern($0) }
    }

    private func pointerType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let pointerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: pointerFQName(interner: interner)))
        return sema.types.make(.classType(ClassType(
            classSymbol: pointerSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func pointerMember(
        named name: String,
        parameterTypes: [TypeID],
        sema: SemaModule,
        interner: StringInterner
    ) throws -> SymbolID {
        let pointerType = try pointerType(sema: sema, interner: interner)
        return try XCTUnwrap(
            sema.symbols.lookupAll(fqName: pointerFQName(interner: interner) + [interner.intern(name)]).first { symbolID in
                guard sema.symbols.symbol(symbolID)?.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.receiverType == pointerType && signature.parameterTypes == parameterTypes
            },
            "Pointer.\(name) with parameters \(parameterTypes) must be registered"
        )
    }

    func testPointerClassIsRegisteredAsValueClass() throws {
        let (sema, interner) = try makeSema()
        let pointerSymbol = try XCTUnwrap(
            symbol(["kotlin", "wasm", "unsafe", "Pointer"], sema: sema, interner: interner),
            "kotlin.wasm.unsafe.Pointer must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(pointerSymbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.valueType))
        XCTAssertEqual(sema.symbols.valueClassUnderlyingType(for: pointerSymbol), sema.types.uintType)
    }

    func testPointerConstructorAndAddressPropertyUseUInt() throws {
        let (sema, interner) = try makeSema()
        let pointerPath = pointerFQName(interner: interner)
        let pointerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: pointerPath))
        let pointerType = try pointerType(sema: sema, interner: interner)

        let constructor = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: pointerPath + [interner.intern("<init>")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .constructor
            },
            "Pointer constructor must be registered"
        )
        let constructorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))
        XCTAssertEqual(sema.symbols.parentSymbol(for: constructor), pointerSymbol)
        XCTAssertEqual(constructorSignature.parameterTypes, [sema.types.uintType])
        XCTAssertEqual(constructorSignature.returnType, pointerType)
        XCTAssertEqual(constructorSignature.valueParameterSymbols.count, 1)
        XCTAssertEqual(
            sema.symbols.propertyType(for: constructorSignature.valueParameterSymbols[0]),
            sema.types.uintType
        )

        let addressProperty = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: pointerPath + [interner.intern("address")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
            },
            "Pointer.address must be registered"
        )
        XCTAssertEqual(sema.symbols.parentSymbol(for: addressProperty), pointerSymbol)
        XCTAssertEqual(sema.symbols.propertyType(for: addressProperty), sema.types.uintType)
    }

    func testPointerLoadAndStoreMembersUsePrimitiveTypes() throws {
        let (sema, interner) = try makeSema()

        let loadExpectations: [(name: String, returnType: TypeID)] = [
            ("loadByte", sema.types.intType),
            ("loadShort", sema.types.intType),
            ("loadInt", sema.types.intType),
            ("loadLong", sema.types.longType),
        ]
        for expectation in loadExpectations {
            let member = try pointerMember(
                named: expectation.name,
                parameterTypes: [],
                sema: sema,
                interner: interner
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: member))
            XCTAssertEqual(signature.returnType, expectation.returnType)
        }

        let storeExpectations: [(name: String, parameterType: TypeID)] = [
            ("storeByte", sema.types.intType),
            ("storeShort", sema.types.intType),
            ("storeInt", sema.types.intType),
            ("storeLong", sema.types.longType),
        ]
        for expectation in storeExpectations {
            let member = try pointerMember(
                named: expectation.name,
                parameterTypes: [expectation.parameterType],
                sema: sema,
                interner: interner
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: member))
            XCTAssertEqual(signature.returnType, sema.types.unitType)
            XCTAssertEqual(signature.valueParameterSymbols.count, 1)
            XCTAssertEqual(
                sema.symbols.propertyType(for: signature.valueParameterSymbols[0]),
                expectation.parameterType
            )
        }
    }

    func testPointerArithmeticOperatorsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let pointerType = try pointerType(sema: sema, interner: interner)

        for name in ["plus", "minus"] {
            for parameterType in [sema.types.intType, sema.types.uintType] {
                let member = try pointerMember(
                    named: name,
                    parameterTypes: [parameterType],
                    sema: sema,
                    interner: interner
                )
                let info = try XCTUnwrap(sema.symbols.symbol(member))
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: member))

                XCTAssertTrue(info.flags.contains(.operatorFunction))
                XCTAssertEqual(signature.returnType, pointerType)
                XCTAssertEqual(signature.valueParameterSymbols.count, 1)
                XCTAssertEqual(
                    sema.symbols.propertyType(for: signature.valueParameterSymbols[0]),
                    parameterType
                )
            }
        }
    }

    func testPointerSurfaceResolvesInSource() throws {
        let source = """
        import kotlin.wasm.unsafe.Pointer

        fun readPointer(pointer: Pointer): Int = pointer.loadInt()
        fun pointerAddress(pointer: Pointer): UInt = pointer.address
        fun writePointer(pointer: Pointer, value: Long) {
            pointer.storeLong(value)
        }
        """
        let (sema, interner) = try makeSema(source: source)

        let expectedReturnTypes: [(name: String, type: TypeID)] = [
            ("readPointer", sema.types.intType),
            ("pointerAddress", sema.types.uintType),
            ("writePointer", sema.types.unitType),
        ]
        for expectation in expectedReturnTypes {
            let functionSymbol = try XCTUnwrap(
                symbol([expectation.name], sema: sema, interner: interner),
                "\(expectation.name) must be registered"
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
            XCTAssertEqual(signature.returnType, expectation.type)
        }
    }
}
