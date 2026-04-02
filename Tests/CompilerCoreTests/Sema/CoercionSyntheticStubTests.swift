@testable import CompilerCore
import XCTest

final class CoercionSyntheticStubTests: XCTestCase {

    // MARK: - Helpers

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func coercionSymbols(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let fq = ["kotlin", "ranges", member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq)
    }

    // MARK: - Int coercion stubs

    func testIntCoercionStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [(member: String, paramTypes: [TypeID], link: String)] = [
            ("coerceIn", [sema.types.intType, sema.types.intType], "kk_int_coerceIn"),
            ("coerceAtLeast", [sema.types.intType], "kk_int_coerceAtLeast"),
            ("coerceAtMost", [sema.types.intType], "kk_int_coerceAtMost"),
        ]

        for entry in expected {
            let symbols = coercionSymbols(for: entry.member, sema: sema, interner: interner)
            let matchingSymbol = symbols.first { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == sema.types.intType
                    && sig.parameterTypes == entry.paramTypes
                    && sig.returnType == sema.types.intType
            }
            let sym = try XCTUnwrap(matchingSymbol, "Expected Int.\(entry.member) coercion stub")
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: sym),
                entry.link,
                "Int.\(entry.member) should link to \(entry.link)"
            )
        }
    }

    func testIntCoerceInSignatureHasTwoIntParameters() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceIn", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.intType
                && sig.parameterTypes == [sema.types.intType, sema.types.intType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Int.coerceIn stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.intType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.intType, sema.types.intType])
        XCTAssertEqual(sig.returnType, sema.types.intType)
    }

    func testIntCoerceAtLeastSignatureHasOneIntParameter() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceAtLeast", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.intType
                && sig.parameterTypes == [sema.types.intType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Int.coerceAtLeast stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.intType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.intType])
        XCTAssertEqual(sig.returnType, sema.types.intType)
    }

    func testIntCoerceAtMostSignatureHasOneIntParameter() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceAtMost", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.intType
                && sig.parameterTypes == [sema.types.intType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Int.coerceAtMost stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.intType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.intType])
        XCTAssertEqual(sig.returnType, sema.types.intType)
    }

    // MARK: - Long coercion stubs

    func testLongCoercionStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [(member: String, paramTypes: [TypeID], link: String)] = [
            ("coerceIn", [sema.types.longType, sema.types.longType], "kk_long_coerceIn"),
            ("coerceAtLeast", [sema.types.longType], "kk_long_coerceAtLeast"),
            ("coerceAtMost", [sema.types.longType], "kk_long_coerceAtMost"),
        ]

        for entry in expected {
            let symbols = coercionSymbols(for: entry.member, sema: sema, interner: interner)
            let matchingSymbol = symbols.first { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == sema.types.longType
                    && sig.parameterTypes == entry.paramTypes
                    && sig.returnType == sema.types.longType
            }
            let sym = try XCTUnwrap(matchingSymbol, "Expected Long.\(entry.member) coercion stub")
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: sym),
                entry.link,
                "Long.\(entry.member) should link to \(entry.link)"
            )
        }
    }

    func testLongCoerceInSignatureHasTwoLongParameters() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceIn", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.longType
                && sig.parameterTypes == [sema.types.longType, sema.types.longType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Long.coerceIn stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.longType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.longType, sema.types.longType])
        XCTAssertEqual(sig.returnType, sema.types.longType)
    }

    func testLongCoerceAtLeastSignatureHasOneLongParameter() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceAtLeast", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.longType
                && sig.parameterTypes == [sema.types.longType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Long.coerceAtLeast stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.longType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.longType])
        XCTAssertEqual(sig.returnType, sema.types.longType)
    }

    func testLongCoerceAtMostSignatureHasOneLongParameter() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceAtMost", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.longType
                && sig.parameterTypes == [sema.types.longType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Long.coerceAtMost stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.longType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.longType])
        XCTAssertEqual(sig.returnType, sema.types.longType)
    }

    // MARK: - Double coercion stubs

    func testDoubleCoercionStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [(member: String, paramTypes: [TypeID], link: String)] = [
            ("coerceIn", [sema.types.doubleType, sema.types.doubleType], "kk_double_coerceIn"),
            ("coerceAtLeast", [sema.types.doubleType], "kk_double_coerceAtLeast"),
            ("coerceAtMost", [sema.types.doubleType], "kk_double_coerceAtMost"),
        ]

        for entry in expected {
            let symbols = coercionSymbols(for: entry.member, sema: sema, interner: interner)
            let matchingSymbol = symbols.first { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == sema.types.doubleType
                    && sig.parameterTypes == entry.paramTypes
                    && sig.returnType == sema.types.doubleType
            }
            let sym = try XCTUnwrap(matchingSymbol, "Expected Double.\(entry.member) coercion stub")
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: sym),
                entry.link,
                "Double.\(entry.member) should link to \(entry.link)"
            )
        }
    }

    func testDoubleCoerceInSignatureHasTwoDoubleParameters() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceIn", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.doubleType
                && sig.parameterTypes == [sema.types.doubleType, sema.types.doubleType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Double.coerceIn stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.doubleType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.doubleType, sema.types.doubleType])
        XCTAssertEqual(sig.returnType, sema.types.doubleType)
    }

    func testDoubleCoerceAtLeastSignatureHasOneDoubleParameter() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceAtLeast", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.doubleType
                && sig.parameterTypes == [sema.types.doubleType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Double.coerceAtLeast stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.doubleType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.doubleType])
        XCTAssertEqual(sig.returnType, sema.types.doubleType)
    }

    func testDoubleCoerceAtMostSignatureHasOneDoubleParameter() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceAtMost", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.doubleType
                && sig.parameterTypes == [sema.types.doubleType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Double.coerceAtMost stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.doubleType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.doubleType])
        XCTAssertEqual(sig.returnType, sema.types.doubleType)
    }

    // MARK: - Float coercion stubs

    func testFloatCoercionStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [(member: String, paramTypes: [TypeID], link: String)] = [
            ("coerceIn", [sema.types.floatType, sema.types.floatType], "kk_float_coerceIn"),
            ("coerceAtLeast", [sema.types.floatType], "kk_float_coerceAtLeast"),
            ("coerceAtMost", [sema.types.floatType], "kk_float_coerceAtMost"),
        ]

        for entry in expected {
            let symbols = coercionSymbols(for: entry.member, sema: sema, interner: interner)
            let matchingSymbol = symbols.first { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == sema.types.floatType
                    && sig.parameterTypes == entry.paramTypes
                    && sig.returnType == sema.types.floatType
            }
            let sym = try XCTUnwrap(matchingSymbol, "Expected Float.\(entry.member) coercion stub")
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: sym),
                entry.link,
                "Float.\(entry.member) should link to \(entry.link)"
            )
        }
    }

    func testFloatCoerceInSignatureHasTwoFloatParameters() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceIn", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.floatType
                && sig.parameterTypes == [sema.types.floatType, sema.types.floatType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Float.coerceIn stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.floatType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.floatType, sema.types.floatType])
        XCTAssertEqual(sig.returnType, sema.types.floatType)
    }

    func testFloatCoerceAtLeastSignatureHasOneFloatParameter() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceAtLeast", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.floatType
                && sig.parameterTypes == [sema.types.floatType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Float.coerceAtLeast stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.floatType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.floatType])
        XCTAssertEqual(sig.returnType, sema.types.floatType)
    }

    func testFloatCoerceAtMostSignatureHasOneFloatParameter() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceAtMost", sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == sema.types.floatType
                && sig.parameterTypes == [sema.types.floatType]
        }
        let sym = try XCTUnwrap(matchingSymbol, "Expected Float.coerceAtMost stub")
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        XCTAssertEqual(sig.receiverType, sema.types.floatType)
        XCTAssertEqual(sig.parameterTypes, [sema.types.floatType])
        XCTAssertEqual(sig.returnType, sema.types.floatType)
    }

    // MARK: - Cross-type: all four types register distinct overloads

    func testAllFourTypesRegisterDistinctCoerceInOverloads() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceIn", sema: sema, interner: interner)
        let expectedReceiverTypes: Set<TypeID> = [
            sema.types.intType,
            sema.types.longType,
            sema.types.doubleType,
            sema.types.floatType,
        ]

        var foundReceiverTypes: Set<TypeID> = []
        for symbolID in symbols {
            if let sig = sema.symbols.functionSignature(for: symbolID),
               let receiver = sig.receiverType,
               expectedReceiverTypes.contains(receiver) {
                foundReceiverTypes.insert(receiver)
            }
        }

        XCTAssertEqual(
            foundReceiverTypes,
            expectedReceiverTypes,
            "coerceIn should have stubs for Int, Long, Double, and Float"
        )
    }

    func testAllFourTypesRegisterDistinctCoerceAtLeastOverloads() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceAtLeast", sema: sema, interner: interner)
        let expectedReceiverTypes: Set<TypeID> = [
            sema.types.intType,
            sema.types.longType,
            sema.types.doubleType,
            sema.types.floatType,
        ]

        var foundReceiverTypes: Set<TypeID> = []
        for symbolID in symbols {
            if let sig = sema.symbols.functionSignature(for: symbolID),
               let receiver = sig.receiverType,
               expectedReceiverTypes.contains(receiver) {
                foundReceiverTypes.insert(receiver)
            }
        }

        XCTAssertEqual(
            foundReceiverTypes,
            expectedReceiverTypes,
            "coerceAtLeast should have stubs for Int, Long, Double, and Float"
        )
    }

    func testAllFourTypesRegisterDistinctCoerceAtMostOverloads() throws {
        let (sema, interner) = try makeSema()

        let symbols = coercionSymbols(for: "coerceAtMost", sema: sema, interner: interner)
        let expectedReceiverTypes: Set<TypeID> = [
            sema.types.intType,
            sema.types.longType,
            sema.types.doubleType,
            sema.types.floatType,
        ]

        var foundReceiverTypes: Set<TypeID> = []
        for symbolID in symbols {
            if let sig = sema.symbols.functionSignature(for: symbolID),
               let receiver = sig.receiverType,
               expectedReceiverTypes.contains(receiver) {
                foundReceiverTypes.insert(receiver)
            }
        }

        XCTAssertEqual(
            foundReceiverTypes,
            expectedReceiverTypes,
            "coerceAtMost should have stubs for Int, Long, Double, and Float"
        )
    }

    // MARK: - Package parenting

    func testKotlinRangesPackageIsParentedUnderKotlinPackage() throws {
        let (sema, interner) = try makeSema()

        _ = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin")])
        )
        _ = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("ranges")])
        )
    }
}
