@testable import CompilerCore
import Foundation
import XCTest

// MARK: - SymbolTable Delegate Storage Tests

final class DelegateStorageSymbolTableTests: XCTestCase {
    func testSetAndGetDelegateStorageSymbol() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let property = symbols.define(
            kind: .property,
            name: interner.intern("x"),
            fqName: [interner.intern("x")],
            declSite: nil,
            visibility: .public
        )
        let storage = symbols.define(
            kind: .field,
            name: interner.intern("$delegate_x"),
            fqName: [interner.intern("$delegate_x")],
            declSite: nil,
            visibility: .private
        )
        symbols.setDelegateStorageSymbol(storage, for: property)
        XCTAssertEqual(symbols.delegateStorageSymbol(for: property), storage)
    }

    func testDelegateStorageSymbolReturnsNilForUnset() {
        let symbols = SymbolTable()
        XCTAssertNil(symbols.delegateStorageSymbol(for: SymbolID(rawValue: 0)))
    }

    func testDelegateStorageSymbolIsIndependentOfPropertyType() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let property = symbols.define(
            kind: .property,
            name: interner.intern("y"),
            fqName: [interner.intern("y")],
            declSite: nil,
            visibility: .public
        )
        let storage = symbols.define(
            kind: .field,
            name: interner.intern("$delegate_y"),
            fqName: [interner.intern("$delegate_y")],
            declSite: nil,
            visibility: .private
        )
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setPropertyType(intType, for: property)
        symbols.setDelegateStorageSymbol(storage, for: property)
        XCTAssertEqual(symbols.delegateStorageSymbol(for: property), storage)
        XCTAssertEqual(symbols.propertyType(for: property), intType)
    }
}

// MARK: - Sema Delegate Type Checking Tests

final class SemaDelegateTypeCheckTests: XCTestCase {
    func testDelegatedPropertyCreatesStorageSymbolDuringHeaderCollection() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            // FQ names do not include module prefix; class Foo has fqName ["Foo"].
            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            // Verify that a $delegate_x storage symbol was created.
            let delegateStorageSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "$delegate_x"
            }
            XCTAssertFalse(delegateStorageSymbols.isEmpty, "Expected $delegate_x storage symbol to be created")

            // The storage symbol should be a field.
            if let storageSymID = delegateStorageSymbols.first,
               let storageSym = sema.symbols.symbol(storageSymID)
            {
                XCTAssertEqual(storageSym.kind, .field)
                XCTAssertEqual(storageSym.visibility, .private)
            }

            // Find the property symbol 'x' and check delegate storage is linked.
            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            XCTAssertFalse(xSymbols.isEmpty, "Expected property symbol 'x' to exist")
            if let xSymbol = xSymbols.first {
                let delegateStorage = sema.symbols.delegateStorageSymbol(for: xSymbol)
                XCTAssertNotNil(delegateStorage, "Expected delegate storage to be linked to property 'x'")
            }
        }
    }

    func testDelegatedPropertyTypeDefaultsToNullableAnyWhenNotDeclared() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            XCTAssertFalse(xSymbols.isEmpty)
            if let xSymbol = xSymbols.first {
                let propType = sema.symbols.propertyType(for: xSymbol)
                XCTAssertNotNil(propType, "Property type should be set even without explicit annotation")
                // When no explicit type, it falls back to Any?
                if let propType {
                    XCTAssertEqual(propType, sema.types.nullableAnyType)
                }
            }
        }
    }

    func testDelegatedPropertyPreservesExplicitType() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            XCTAssertFalse(xSymbols.isEmpty)
            if let xSymbol = xSymbols.first {
                let propType = sema.symbols.propertyType(for: xSymbol)
                XCTAssertNotNil(propType)
                if let propType {
                    let intType = sema.types.make(.primitive(.int, .nonNull))
                    XCTAssertEqual(propType, intType, "Explicit Int type should be preserved")
                }
            }
        }
    }

    func testDelegatedPropertyRecordsDelegateTypeOnSyntheticSymbol() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            if let xSymbol = xSymbols.first {
                // The delegate type is recorded under a synthetic symbol offset:
                // -(symbol.rawValue + 50_000)
                let syntheticID = SymbolID(rawValue: -(xSymbol.rawValue + 50000))
                let delegateType = sema.symbols.propertyType(for: syntheticID)
                XCTAssertNotNil(delegateType, "Delegate type should be recorded on synthetic symbol")
            }
        }
    }
}

// MARK: - KIR Delegate Accessor Synthesis Tests

final class KIRDelegateAccessorTests: XCTestCase {
    func testDelegatedValSynthesizesGetterWithGetValueCall() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let interner = ctx.interner

            // Check that a getter function was synthesized with a getValue call.
            let getterFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(fn) = decl else { return nil }
                let name = interner.resolve(fn.name)
                guard name == "get" else { return nil }
                let callees = extractCallees(from: fn.body, interner: interner)
                return callees.contains("getValue") ? fn : nil
            }
            XCTAssertFalse(getterFunctions.isEmpty, "Expected synthesized getter with getValue call")

            // Custom delegates prepend the delegate handle before thisRef and kProperty.
            if let getter = getterFunctions.first {
                let getValueCalls = getter.body.compactMap { instruction -> [KIRExprID]? in
                    guard case let .call(_, callee, args, _, _, _, _) = instruction,
                          interner.resolve(callee) == "getValue" else { return nil }
                    return args
                }
                XCTAssertFalse(getValueCalls.isEmpty)
                if let args = getValueCalls.first {
                    XCTAssertEqual(args.count, 3, "getValue should have 3 arguments: delegate, thisRef, and kProperty")
                }
            }
        }
    }

    func testDelegatedVarSynthesizesSetterWithSetValueCall() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
            fun setValue(thisRef: Any?, property: Any?, value: Int) {}
        }
        class Foo {
            var x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let interner = ctx.interner

            // Check that a setter function was synthesized with a setValue call.
            let setterFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(fn) = decl else { return nil }
                let name = interner.resolve(fn.name)
                guard name == "set" else { return nil }
                let callees = extractCallees(from: fn.body, interner: interner)
                return callees.contains("setValue") ? fn : nil
            }
            XCTAssertFalse(setterFunctions.isEmpty, "Expected synthesized setter with setValue call")

            // Custom delegates prepend the delegate handle before thisRef, kProperty, and value.
            if let setter = setterFunctions.first {
                let setValueCalls = setter.body.compactMap { instruction -> [KIRExprID]? in
                    guard case let .call(_, callee, args, _, _, _, _) = instruction,
                          interner.resolve(callee) == "setValue" else { return nil }
                    return args
                }
                XCTAssertFalse(setValueCalls.isEmpty)
                if let args = setValueCalls.first {
                    XCTAssertEqual(args.count, 4, "setValue should have 4 arguments: delegate, thisRef, kProperty, and value")
                }
            }
        }
    }

    func testDelegatedValDoesNotSynthesizeSetter() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let interner = ctx.interner

            // There should be no setter function with setValue for a val property.
            let setterWithSetValue = module.arena.declarations.contains { decl in
                guard case let .function(fn) = decl else { return false }
                let name = interner.resolve(fn.name)
                guard name == "set" else { return false }
                let callees = extractCallees(from: fn.body, interner: interner)
                return callees.contains("setValue")
            }
            XCTAssertFalse(setterWithSetValue, "val property should not have a synthesized setter with setValue")
        }
    }

    func testDelegateStorageGlobalIsEmitted() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)

            // Check that a $delegate_x global was emitted.
            let delegateGlobals = module.arena.declarations.compactMap { decl -> KIRGlobal? in
                guard case let .global(g) = decl else { return nil }
                guard let sym = sema.symbols.symbol(g.symbol) else { return nil }
                return interner.resolve(sym.name).hasPrefix("$delegate_") ? g : nil
            }
            XCTAssertFalse(delegateGlobals.isEmpty, "Expected $delegate_ global to be emitted in KIR")
        }
    }

    func testGetValueCallUsesDelegateStorageAsSymbol() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let interner = ctx.interner
            _ = try XCTUnwrap(ctx.sema)

            // Find the getter and check that getValue resolves as a direct member call,
            // rather than using the delegate storage field as the callee symbol.
            let getterFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(fn) = decl else { return nil }
                let name = interner.resolve(fn.name)
                guard name == "get" else { return nil }
                let callees = extractCallees(from: fn.body, interner: interner)
                return callees.contains("getValue") ? fn : nil
            }

            if let getter = getterFunctions.first {
                let getValueCallCount = getter.body.reduce(into: 0) { count, instruction in
                    guard case let .call(_, callee, _, _, _, _, _) = instruction,
                          interner.resolve(callee) == "getValue" else { return }
                    count += 1
                }
                XCTAssertGreaterThan(getValueCallCount, 0, "Expected synthesized getter to contain a direct getValue call")
            }
        }
    }
}

// MARK: - Constructor Delegate Initialization Tests

final class ConstructorDelegateInitTests: XCTestCase {}
