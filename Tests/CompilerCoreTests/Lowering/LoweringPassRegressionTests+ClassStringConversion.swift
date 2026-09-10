#if canImport(Testing)
@testable import CompilerCore
import Testing

// A class value stringified through the Any-erased `+`/string-template funnel
// (CallLowerer.emitAnyToStringWithNullGuard) must call its own overridden
// toString(), not fall through to the generic kk_any_to_string conversion --
// which has no notion of a user-defined override and renders the raw object
// handle ("<object 0x...>"). BUG-204 taught this funnel about enum classes
// only (their bare-ordinal KIR representation); a class's override needs the
// same treatment, and additionally must dispatch virtually when the static
// receiver type is an open class with subtypes, mirroring what direct
// `.toString()` calls and ConsolePrintLoweringPass's println/print rewrite
// already do for a polymorphic receiver.
extension LoweringPassRegressionTests {
    @Test
    func testClassInterpolationCallsOverriddenToString() throws {
        let source = """
        class Foo(val x: Int) {
            override fun toString(): String = "Foo(" + x + ")"
        }
        fun render(f: Foo): String {
            return "value=$f"
        }
        fun main() {
            println(render(Foo(1)))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ClassInterpolation", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("toString"),
                    "the interpolated class value must call its own toString() override; callees: \(callees)")
            #expect(!callees.contains("kk_any_to_string"),
                    "the class value must not reach the generic Any conversion; callees: \(callees)")
        }
    }

    @Test
    func testClassConcatenationCallsOverriddenToString() throws {
        let source = """
        class Foo(val x: Int) {
            override fun toString(): String = "Foo(" + x + ")"
        }
        fun render(f: Foo): String {
            return "value=" + f
        }
        fun main() {
            println(render(Foo(1)))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ClassConcatenation", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("toString"),
                    "the `+`-concatenated class value must call its own toString() override; callees: \(callees)")
            #expect(!callees.contains("kk_any_to_string"),
                    "the class value must not reach the generic Any conversion; callees: \(callees)")
        }
    }

    // A nullable class-typed value must still print "null" for an actual null
    // (kk_any_to_string's runtime sentinel check, which the direct-call rewrite
    // above bypasses entirely) -- so the rewrite must guard the call behind an
    // explicit null check rather than calling toString() unconditionally on
    // the raw static type. See BundledStdlibExecutionTests+ClassToStringOverride
    // (CompilerBackendTests) for the compiled-and-run counterpart of this case.
    @Test
    func testNullableClassConcatenationGuardsNullBeforeCallingToString() throws {
        let source = """
        class Foo(val x: Int) {
            override fun toString(): String = "Foo(" + x + ")"
        }
        fun render(f: Foo?): String {
            return "value=" + f
        }
        fun main() {
            println(render(Foo(1)))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NullableClassConcatenation", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("toString"),
                    "a nullable class value must still call its own toString() override on the non-null path; callees: \(callees)")
            #expect(body.contains(where: { if case .jumpIfNotNull = $0 { true } else { false } }),
                    "the non-null path must be guarded by an explicit null check, not an unconditional call")
        }
    }

    // A base-typed receiver holding a derived instance must call the runtime
    // type's override (virtual dispatch), not the statically-declared class's
    // own toString -- the same requirement `.toString()` calls already meet.
    @Test
    func testPolymorphicClassConcatenationUsesVirtualDispatch() throws {
        let source = """
        open class Animal {
            override fun toString(): String = "Animal"
        }
        class Dog : Animal() {
            override fun toString(): String = "Dog"
        }
        fun render(a: Animal): String {
            return "poly=" + a
        }
        fun main() {
            println(render(Dog()))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ClassPolyConcatenation", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)

            #expect(virtualCallees.contains("toString"),
                    "an open-class receiver must dispatch toString() virtually; virtualCallees: \(virtualCallees)")
            #expect(!callees.contains("toString"),
                    "toString() must not also be emitted as a direct call; callees: \(callees)")
            #expect(!callees.contains("kk_any_to_string"),
                    "the class value must not reach the generic Any conversion; callees: \(callees)")
        }
    }

    // A derived class that does not redeclare toString() must resolve the
    // inherited implementation before selecting the virtual dispatch path.
    @Test
    func testInheritedClassConcatenationResolvesSuperclassToString() throws {
        let source = """
        open class Base {
            override fun toString(): String = "Base!"
        }
        class Derived : Base()
        fun render(d: Derived): String {
            return "derived=" + d
        }
        fun main() {
            println(render(Derived()))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "InheritedClassConcatenation", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)

            #expect(virtualCallees.contains("toString"),
                    "an inherited open-class toString() must use virtual dispatch; virtualCallees: \(virtualCallees)")
            #expect(!callees.contains("kk_any_to_string"),
                    "an inherited class value must not reach the generic Any conversion; callees: \(callees)")
        }
    }

    // A data class's toString() is synthesized (by DataEnumSealedSynthesisPass,
    // a later lowering pass) rather than source-declared, but Sema registers
    // its signature at header-collection time -- well before this BuildKIR-time
    // funnel runs -- and DataEnumSealedSynthesisPass reliably gives it a body
    // before codegen ever needs one, the same guarantee `println`/`print`
    // (ConsolePrintLoweringPass) already rely on for a data class argument.
    // classToStringCallee's synthetic-symbol filter must accept it, not just a
    // source-declared override.
    @Test
    func testDataClassInterpolationCallsSynthesizedToString() throws {
        let source = """
        data class Point(val x: Int, val y: Int)
        fun render(p: Point): String {
            return "p=$p"
        }
        fun main() {
            println(render(Point(1, 2)))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "DataClassInterpolation", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("toString"),
                    "the interpolated data class value must call its synthesized toString(); callees: \(callees)")
            #expect(!callees.contains("kk_any_to_string"),
                    "the data class value must not reach the generic Any conversion; callees: \(callees)")
        }
    }
}
#endif
