@testable import CompilerCore
import XCTest

extension NameManglerTests {
    func testMangledSignatureForProperty() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("x"),
            fqName: [interner.intern("x")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setPropertyType(intType, for: sym)

        let sig = try mangler.mangledSignature(
            for: XCTUnwrap(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "I")
    }

    func testMangledSignatureForPropertyWithoutTypeReturnsUnderscore() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("noProp"),
            fqName: [interner.intern("noProp")],
            declSite: nil,
            visibility: .public
        )

        let sig = try mangler.mangledSignature(
            for: XCTUnwrap(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "_")
    }

    func testMangledSignatureForTypeAlias() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .typeAlias,
            name: interner.intern("MyInt"),
            fqName: [interner.intern("MyInt")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setTypeAliasUnderlyingType(intType, for: sym)

        let sig = try mangler.mangledSignature(
            for: XCTUnwrap(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "I")
    }

    func testMangledSignatureForTypeAliasWithoutTypeReturnsUnderscore() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .typeAlias,
            name: interner.intern("NoTA"),
            fqName: [interner.intern("NoTA")],
            declSite: nil,
            visibility: .public
        )

        let sig = try mangler.mangledSignature(
            for: XCTUnwrap(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "_")
    }

    func testMangledSignatureForClassReturnsUnderscore() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .class,
            name: interner.intern("C"),
            fqName: [interner.intern("C")],
            declSite: nil,
            visibility: .public
        )

        let sig = try mangler.mangledSignature(
            for: XCTUnwrap(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "_")
    }

    // MARK: - FQ Name Encoding

    func testMangleFQNameMultipleComponents() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("baz"),
            fqName: [interner.intern("com"), interner.intern("example"), interner.intern("baz")],
            declSite: nil,
            visibility: .public
        )
        let result = try mangler.mangle(
            moduleName: "M", symbol: XCTUnwrap(symbols.symbol(sym)),
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("3com"))
        XCTAssertTrue(result.contains("7example"))
        XCTAssertTrue(result.contains("3baz"))
    }

    // MARK: - Suspend Function Signature

    func testMangledSignatureForSuspendFunction() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("suspendFn"),
            fqName: [interner.intern("suspendFn")],
            declSite: nil,
            visibility: .public,
            flags: .suspendFunction
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: intType, isSuspend: true),
            for: sym
        )

        let sig = try mangler.mangledSignature(
            for: XCTUnwrap(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        XCTAssertTrue(sig.hasPrefix("SF"))
    }

    // MARK: - Nullable Type Encoding

    func testMangledSignatureNullableType() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("nullProp"),
            fqName: [interner.intern("nullProp")],
            declSite: nil,
            visibility: .public
        )
        let nullableInt = types.make(.primitive(.int, .nullable))
        symbols.setPropertyType(nullableInt, for: sym)

        let sig = try mangler.mangledSignature(
            for: XCTUnwrap(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        XCTAssertTrue(sig.contains("Q<"))
    }

    // MARK: - All Primitive Encodings

    func testMangledSignatureAllPrimitives() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let primitives: [(PrimitiveType, String)] = [
            (.boolean, "Z"), (.char, "C"), (.int, "I"),
            (.long, "J"), (.float, "F"), (.double, "D"),
            (.string, "Lkotlin_String;"),
        ]

        for (prim, expected) in primitives {
            let sym = symbols.define(
                kind: .property,
                name: interner.intern("p_\(prim.rawValue)"),
                fqName: [interner.intern("p_\(prim.rawValue)")],
                declSite: nil,
                visibility: .public
            )
            let type = types.make(.primitive(prim, .nonNull))
            symbols.setPropertyType(type, for: sym)

            let sig = try mangler.mangledSignature(
                for: XCTUnwrap(symbols.symbol(sym)),
                symbols: symbols,
                types: types
            )
            XCTAssertEqual(sig, expected, "Primitive \(prim) should encode to \(expected)")
        }
    }

    // MARK: - Special Type Encodings

    func testMangledSignatureUnitType() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("unitFn"),
            fqName: [interner.intern("unitFn")],
            declSite: nil,
            visibility: .public
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: types.unitType),
            for: sym
        )

        let sig = try mangler.mangledSignature(
            for: XCTUnwrap(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        XCTAssertTrue(sig.contains("U"))
    }

    func testMangledSignatureNothingType() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("nothingFn"),
            fqName: [interner.intern("nothingFn")],
            declSite: nil,
            visibility: .public
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: types.nothingType),
            for: sym
        )

        let sig = try mangler.mangledSignature(
            for: XCTUnwrap(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        XCTAssertTrue(sig.contains("N"))
    }

    func testMangledSignatureAnyType() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("anyProp"),
            fqName: [interner.intern("anyProp")],
            declSite: nil,
            visibility: .public
        )
        symbols.setPropertyType(types.anyType, for: sym)

        let sig = try mangler.mangledSignature(
            for: XCTUnwrap(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "A")
    }

    func testMangledSignatureErrorType() throws {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("errProp"),
            fqName: [interner.intern("errProp")],
            declSite: nil,
            visibility: .public
        )
        symbols.setPropertyType(types.errorType, for: sym)

        let sig = try mangler.mangledSignature(
            for: XCTUnwrap(symbols.symbol(sym)),
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "E")
    }
}
