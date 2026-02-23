import XCTest
@testable import CompilerCore

final class NameManglerTests: XCTestCase {

    // MARK: - Basic Mangling

    func testMangleProducesKKPrefix() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("foo"),
            fqName: [interner.intern("foo")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: sym
        )

        let result = mangler.mangle(
            moduleName: "TestModule",
            symbol: symbols.symbol(sym)!,
            symbols: symbols,
            types: types,
            nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.hasPrefix("_KK_TestModule__"))
    }

    func testMangleWithExplicitSignature() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("bar"),
            fqName: [interner.intern("bar")],
            declSite: nil,
            visibility: .public
        )

        let result = mangler.mangle(
            moduleName: "M",
            symbol: symbols.symbol(sym)!,
            signature: "SIG",
            nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.hasPrefix("_KK_M__"))
        XCTAssertTrue(result.contains("__F__SIG__"))
    }

    func testMangleIsDeterministic() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("f"),
            fqName: [interner.intern("f")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: intType),
            for: sym
        )

        let r1 = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            symbols: symbols, types: types, nameResolver: { interner.resolve($0) }
        )
        let r2 = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            symbols: symbols, types: types, nameResolver: { interner.resolve($0) }
        )
        XCTAssertEqual(r1, r2)
    }

    func testMangleContainsHashSuffix() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("test"),
            fqName: [interner.intern("test")],
            declSite: nil,
            visibility: .public
        )

        let result = mangler.mangle(
            moduleName: "M",
            symbol: symbols.symbol(sym)!,
            signature: "_",
            nameResolver: { interner.resolve($0) }
        )
        // Result ends with __<8 hex chars>
        let parts = result.split(separator: "_").filter { !$0.isEmpty }
        let lastPart = String(parts.last!)
        XCTAssertEqual(lastPart.count, 8)
        XCTAssertTrue(lastPart.allSatisfy { $0.isHexDigit })
    }

    // MARK: - Kind Codes

    func testMangleKindCodeForFunction() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("fn"),
            fqName: [interner.intern("fn")],
            declSite: nil,
            visibility: .public
        )
        let result = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("__F__"))
    }

    func testMangleKindCodeForClass() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .class,
            name: interner.intern("MyClass"),
            fqName: [interner.intern("MyClass")],
            declSite: nil,
            visibility: .public
        )
        let result = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("__C__"))
    }

    func testMangleKindCodeForConstructor() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .constructor,
            name: interner.intern("init"),
            fqName: [interner.intern("MyClass"), interner.intern("init")],
            declSite: nil,
            visibility: .public
        )
        let result = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("__K__"))
    }

    func testMangleKindCodeForProperty() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("prop"),
            fqName: [interner.intern("prop")],
            declSite: nil,
            visibility: .public
        )
        let result = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("__P__"))
    }

    func testMangleKindCodeForObject() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .object,
            name: interner.intern("Obj"),
            fqName: [interner.intern("Obj")],
            declSite: nil,
            visibility: .public
        )
        let result = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("__O__"))
    }

    func testMangleKindCodeForInterface() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .interface,
            name: interner.intern("I"),
            fqName: [interner.intern("I")],
            declSite: nil,
            visibility: .public
        )
        let result = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("__I__"))
    }

    func testMangleKindCodeForEnumClass() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .enumClass,
            name: interner.intern("E"),
            fqName: [interner.intern("E")],
            declSite: nil,
            visibility: .public
        )
        let result = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("__E__"))
    }

    func testMangleKindCodeForTypeAlias() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .typeAlias,
            name: interner.intern("TA"),
            fqName: [interner.intern("TA")],
            declSite: nil,
            visibility: .public
        )
        let result = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("__T__"))
    }

    // MARK: - Getter / Setter DeclKind

    func testMangleGetterDeclKindOverridesKindCode() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("p"),
            fqName: [interner.intern("p")],
            declSite: nil,
            visibility: .public
        )
        let result = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            signature: "_", declKind: .getter,
            nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("__G__"))
    }

    func testMangleSetterDeclKindOverridesKindCode() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()

        let sym = symbols.define(
            kind: .property,
            name: interner.intern("p"),
            fqName: [interner.intern("p")],
            declSite: nil,
            visibility: .public
        )
        let result = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            signature: "_", declKind: .setter,
            nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("__S__"))
    }

    // MARK: - mangledSignature

    func testMangledSignatureForFunctionWithSignature() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("add"),
            fqName: [interner.intern("add")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType, intType], returnType: intType),
            for: sym
        )

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types,
            nameResolver: { interner.resolve($0) }
        )
        // Should contain encoded function type with Int params
        XCTAssertTrue(sig.contains("I"))
    }

    func testMangledSignatureForFunctionWithoutSignatureReturnsUnderscore() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let sym = symbols.define(
            kind: .function,
            name: interner.intern("noSig"),
            fqName: [interner.intern("noSig")],
            declSite: nil,
            visibility: .public
        )

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "_")
    }

    func testMangledSignatureForProperty() {
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

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "I")
    }

    func testMangledSignatureForPropertyWithoutTypeReturnsUnderscore() {
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

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "_")
    }

    func testMangledSignatureForTypeAlias() {
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

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "I")
    }

    func testMangledSignatureForTypeAliasWithoutTypeReturnsUnderscore() {
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

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "_")
    }

    func testMangledSignatureForClassReturnsUnderscore() {
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

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "_")
    }

    // MARK: - FQ Name Encoding

    func testMangleFQNameMultipleComponents() {
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
        let result = mangler.mangle(
            moduleName: "M", symbol: symbols.symbol(sym)!,
            signature: "_", nameResolver: { interner.resolve($0) }
        )
        XCTAssertTrue(result.contains("3com"))
        XCTAssertTrue(result.contains("7example"))
        XCTAssertTrue(result.contains("3baz"))
    }

    // MARK: - Suspend Function Signature

    func testMangledSignatureForSuspendFunction() {
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

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertTrue(sig.hasPrefix("SF"))
    }

    // MARK: - Nullable Type Encoding

    func testMangledSignatureNullableType() {
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

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertTrue(sig.contains("Q<"))
    }

    // MARK: - All Primitive Encodings

    func testMangledSignatureAllPrimitives() {
        let mangler = NameMangler()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let primitives: [(PrimitiveType, String)] = [
            (.boolean, "Z"), (.char, "C"), (.int, "I"),
            (.long, "J"), (.float, "F"), (.double, "D"),
            (.string, "Lkotlin_String;")
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

            let sig = mangler.mangledSignature(
                for: symbols.symbol(sym)!,
                symbols: symbols,
                types: types
            )
            XCTAssertEqual(sig, expected, "Primitive \(prim) should encode to \(expected)")
        }
    }

    // MARK: - Special Type Encodings

    func testMangledSignatureUnitType() {
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

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertTrue(sig.contains("U"))
    }

    func testMangledSignatureNothingType() {
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

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertTrue(sig.contains("N"))
    }

    func testMangledSignatureAnyType() {
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

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "A")
    }

    func testMangledSignatureErrorType() {
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

        let sig = mangler.mangledSignature(
            for: symbols.symbol(sym)!,
            symbols: symbols,
            types: types
        )
        XCTAssertEqual(sig, "E")
    }
}
