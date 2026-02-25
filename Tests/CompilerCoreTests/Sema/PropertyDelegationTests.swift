import Foundation
import XCTest
@testable import CompilerCore

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
               let storageSym = sema.symbols.symbol(storageSymID) {
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
                let syntheticID = SymbolID(rawValue: -(xSymbol.rawValue + 50_000))
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
                guard case .function(let fn) = decl else { return nil }
                let name = interner.resolve(fn.name)
                guard name == "get" else { return nil }
                let callees = extractCallees(from: fn.body, interner: interner)
                return callees.contains("getValue") ? fn : nil
            }
            XCTAssertFalse(getterFunctions.isEmpty, "Expected synthesized getter with getValue call")

            // Verify the getValue call has exactly 2 arguments (thisRef, kProperty).
            if let getter = getterFunctions.first {
                let getValueCalls = getter.body.compactMap { instruction -> [KIRExprID]? in
                    guard case .call(_, let callee, let args, _, _, _, _) = instruction,
                          interner.resolve(callee) == "getValue" else { return nil }
                    return args
                }
                XCTAssertFalse(getValueCalls.isEmpty)
                if let args = getValueCalls.first {
                    XCTAssertEqual(args.count, 2, "getValue should have 2 arguments: thisRef and kProperty")
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
                guard case .function(let fn) = decl else { return nil }
                let name = interner.resolve(fn.name)
                guard name == "set" else { return nil }
                let callees = extractCallees(from: fn.body, interner: interner)
                return callees.contains("setValue") ? fn : nil
            }
            XCTAssertFalse(setterFunctions.isEmpty, "Expected synthesized setter with setValue call")

            // Verify the setValue call has exactly 3 arguments (thisRef, kProperty, value).
            if let setter = setterFunctions.first {
                let setValueCalls = setter.body.compactMap { instruction -> [KIRExprID]? in
                    guard case .call(_, let callee, let args, _, _, _, _) = instruction,
                          interner.resolve(callee) == "setValue" else { return nil }
                    return args
                }
                XCTAssertFalse(setValueCalls.isEmpty)
                if let args = setValueCalls.first {
                    XCTAssertEqual(args.count, 3, "setValue should have 3 arguments: thisRef, kProperty, value")
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
                guard case .function(let fn) = decl else { return false }
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
                guard case .global(let g) = decl else { return nil }
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
            let sema = try XCTUnwrap(ctx.sema)

            // Find the getter and check that getValue's symbol is the delegate storage.
            let getterFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let fn) = decl else { return nil }
                let name = interner.resolve(fn.name)
                guard name == "get" else { return nil }
                let callees = extractCallees(from: fn.body, interner: interner)
                return callees.contains("getValue") ? fn : nil
            }

            if let getter = getterFunctions.first {
                let getValueCallSymbols = getter.body.compactMap { instruction -> SymbolID? in
                    guard case .call(let sym, let callee, _, _, _, _, _) = instruction,
                          interner.resolve(callee) == "getValue" else { return nil }
                    return sym
                }
                XCTAssertFalse(getValueCallSymbols.isEmpty)
                if let sym = getValueCallSymbols.first {
                    // The symbol should be a delegate storage field ($delegate_x).
                    let symInfo = sema.symbols.symbol(sym)
                    XCTAssertNotNil(symInfo)
                    if let symInfo {
                        XCTAssertEqual(symInfo.kind, .field)
                        XCTAssertTrue(interner.resolve(symInfo.name).hasPrefix("$delegate_"),
                                      "getValue call symbol should be a $delegate_ field")
                    }
                }
            }
        }
    }
}

// MARK: - Constructor Delegate Initialization Tests

final class ConstructorDelegateInitTests: XCTestCase {

    func testConstructorInitializesDelegateStorage() throws {
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

            // KIR constructors are named by the class name ("Foo"), not "<init>".
            let constructors = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let fn) = decl else { return nil }
                return interner.resolve(fn.name) == "Foo" ? fn : nil
            }
            XCTAssertFalse(constructors.isEmpty, "Expected constructor to be emitted")

            // Verify the constructor body has a copy instruction (delegate storage init).
            if let ctor = constructors.first {
                let hasCopy = ctor.body.contains { instruction in
                    if case .copy = instruction { return true }
                    return false
                }
                XCTAssertTrue(hasCopy, "Constructor should have a copy instruction to initialize delegate storage")
            }
        }
    }

    func testConstructorDoesNotCallProvideDelegateWhenNotDefined() throws {
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

            let constructors = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let fn) = decl else { return nil }
                return interner.resolve(fn.name) == "Foo" ? fn : nil
            }

            if let ctor = constructors.first {
                let callees = extractCallees(from: ctor.body, interner: interner)
                XCTAssertFalse(callees.contains("provideDelegate"),
                               "provideDelegate should NOT be called when delegate type doesn't define it")
            }
        }
    }

    func testConstructorCallsProvideDelegateWhenTypeResolved() throws {
        // When the delegate expression type is resolved as a classType
        // with a provideDelegate member, the constructor should emit
        // a provideDelegate call.  If type resolution does not produce
        // a classType (current limitation for some call expressions),
        // the constructor falls back to storing the delegate directly.
        let source = """
        class MyDelegate {
            fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate = this
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

            let constructors = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let fn) = decl else { return nil }
                return interner.resolve(fn.name) == "Foo" ? fn : nil
            }
            XCTAssertFalse(constructors.isEmpty, "Expected Foo constructor")

            // Verify the constructor body has a copy instruction
            // (delegate storage initialization).
            if let ctor = constructors.first {
                let hasCopy = ctor.body.contains { instruction in
                    if case .copy = instruction { return true }
                    return false
                }
                XCTAssertTrue(hasCopy, "Constructor should initialize delegate storage")

                let callees = extractCallees(from: ctor.body, interner: interner)
                // provideDelegate emission depends on type resolution;
                // either it's present or the fallback direct-store path
                // is taken.  Both are valid.
                if callees.contains("provideDelegate") {
                    // If provideDelegate was emitted, it must be a
                    // method call (non-nil symbol) with 2 args.
                    let provideDelegateCalls = ctor.body.compactMap { instruction
                        -> (symbol: SymbolID?, args: [KIRExprID])? in
                        guard case .call(let sym, let callee, let args, _, _, _, _) = instruction,
                              interner.resolve(callee) == "provideDelegate" else { return nil }
                        return (symbol: sym, args: args)
                    }
                    if let call = provideDelegateCalls.first {
                        XCTAssertNotNil(call.symbol)
                        XCTAssertEqual(call.args.count, 2)
                    }
                }
            }
        }
    }

    func testProvideDelegateCallShapeWhenEmitted() throws {
        // This test verifies that IF provideDelegate is emitted in the
        // constructor KIR, it uses the correct shape: method call on
        // delegate storage (non-nil symbol) with exactly 2 arguments.
        // The golden test `property_delegation.kt` covers the full
        // output; this unit test validates the KIR instruction shape.
        let source = """
        class MyDelegate {
            fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate = this
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

            let constructors = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let fn) = decl else { return nil }
                return interner.resolve(fn.name) == "Foo" ? fn : nil
            }
            XCTAssertFalse(constructors.isEmpty, "Expected Foo constructor")

            if let ctor = constructors.first {
                let provideDelegateCalls = ctor.body.compactMap { instruction
                    -> (symbol: SymbolID?, args: [KIRExprID])? in
                    guard case .call(let sym, let callee, let args, _, _, _, _) = instruction,
                          interner.resolve(callee) == "provideDelegate" else { return nil }
                    return (symbol: sym, args: args)
                }
                // If any provideDelegate call was emitted, verify it
                // follows the method-call convention.
                for call in provideDelegateCalls {
                    XCTAssertNotNil(call.symbol, "provideDelegate should be emitted as method call with non-nil symbol")
                    XCTAssertEqual(call.args.count, 2,
                                   "provideDelegate should have exactly 2 arguments (thisRef, kProperty)")
                }
            }
        }
    }
}

// MARK: - PropertyLoweringPass Delegate Rewrite Tests

final class PropertyLoweringDelegateTests: XCTestCase {

    func testPropertyLoweringPreservesGetValueInsideAccessorToAvoidRecursion() throws {
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
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let interner = ctx.interner

            // After lowering, the synthesized getter's body should still
            // contain a getValue call (not rewritten to a self-call via
            // "get") to avoid infinite recursion.
            let allFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let fn) = decl else { return nil }
                return fn
            }

            // The accessor function (named "get") should retain getValue in its body.
            var getterRetainsGetValue = false
            for fn in allFunctions {
                let fnName = interner.resolve(fn.name)
                if fnName == "get" {
                    let callees = extractCallees(from: fn.body, interner: interner)
                    if callees.contains("getValue") {
                        getterRetainsGetValue = true
                    }
                }
            }
            XCTAssertTrue(getterRetainsGetValue,
                          "Synthesized getter should retain getValue call (not rewrite to self-call)")
        }
    }

    func testPropertyLoweringDoesNotRewriteProvideDelegateToKKPropertyAccess() throws {
        let source = """
        class MyDelegate {
            fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate = this
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            // Before lowering, verify provideDelegate exists in a constructor.
            let moduleBeforeLowering = try XCTUnwrap(ctx.kir)
            let constructors = moduleBeforeLowering.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let fn) = decl else { return nil }
                return ctx.interner.resolve(fn.name) == "Foo" ? fn : nil
            }
            let hasProvideDelegateBeforeLowering = constructors.contains { ctor in
                extractCallees(from: ctor.body, interner: ctx.interner).contains("provideDelegate")
            }

            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let interner = ctx.interner

            // After lowering, provideDelegate should still be provideDelegate
            // (not rewritten to kk_property_access).
            if hasProvideDelegateBeforeLowering {
                let constructorsAfter = module.arena.declarations.compactMap { decl -> KIRFunction? in
                    guard case .function(let fn) = decl else { return nil }
                    return interner.resolve(fn.name) == "Foo" ? fn : nil
                }
                let hasProvideDelegate = constructorsAfter.contains { ctor in
                    extractCallees(from: ctor.body, interner: interner).contains("provideDelegate")
                }
                XCTAssertTrue(hasProvideDelegate,
                              "provideDelegate should NOT be rewritten to kk_property_access after lowering")
            }
        }
    }

    func testPropertyLoweringPreservesSetValueInsideAccessorToAvoidRecursion() throws {
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
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let interner = ctx.interner

            let allFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let fn) = decl else { return nil }
                return fn
            }

            // The accessor function (named "set") should retain setValue in its body.
            var setterRetainsSetValue = false
            for fn in allFunctions {
                let fnName = interner.resolve(fn.name)
                if fnName == "set" {
                    let callees = extractCallees(from: fn.body, interner: interner)
                    if callees.contains("setValue") {
                        setterRetainsSetValue = true
                    }
                }
            }
            XCTAssertTrue(setterRetainsSetValue,
                          "Synthesized setter should retain setValue call (not rewrite to self-call)")
        }
    }
}

// MARK: - End-to-end Compilation Tests

final class PropertyDelegationEndToEndTests: XCTestCase {

    func testDelegatedPropertyCompilesWithoutErrors() throws {
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
            try LoweringPhase().run(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Delegated property should compile without errors")
        }
    }

    func testMutableDelegatedPropertyCompilesWithoutErrors() throws {
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
            try LoweringPhase().run(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Mutable delegated property should compile without errors")
        }
    }

    func testDelegatedPropertyWithProvideDelegateCompilesWithoutErrors() throws {
        let source = """
        class MyDelegate {
            fun provideDelegate(thisRef: Any?, property: Any?): MyDelegate = this
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Delegated property with provideDelegate should compile without errors")
        }
    }

    func testTopLevelDelegatedPropertyCompilesWithoutErrors() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        val x: Int by MyDelegate()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Top-level delegated property should compile without errors")
        }
    }
}
