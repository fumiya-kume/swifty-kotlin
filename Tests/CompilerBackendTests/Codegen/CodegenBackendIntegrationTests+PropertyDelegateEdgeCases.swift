#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendPropertyDelegateEdgeCasesTests {

    @Test
    func testCodegenTrailingLambdaDelegatesAcrossPropertyScopes() throws {
        let source = """
        import kotlin.reflect.KProperty
        class MyLazy<T>(private val initializer: () -> T) {
            private var cached: Any? = null
            private var done: Boolean = false
            operator fun getValue(thisRef: Any?, property: KProperty<*>): T {
                if (!done) { cached = initializer(); done = true }
                @Suppress("UNCHECKED_CAST")
                return cached as T
            }
        }
        fun <T> myLazy(initializer: () -> T): MyLazy<T> = MyLazy(initializer)
        var evaluations = 0
        val top: String by MyLazy { val value = "top"; value }
        val evaluated: Int by myLazy { evaluations = evaluations + 1; evaluations }
        val parenthesizedCtor: String by MyLazy({ "parenthesized-ctor" })
        val parenthesizedFactory: String by myLazy({ "parenthesized-factory" })
        class Box(val prefix: String) {
            val member: String by myLazy { val value = prefix; value + "-member" }
        }
        fun local(prefix: String): String {
            val value: String by myLazy { val localValue = prefix; localValue + "-local" }
            return value
        }
        fun main() {
            println(top)
            println(evaluated)
            println(evaluated)
            println(evaluations)
            println(Box("member").member)
            println(local("capture"))
            println(parenthesizedCtor)
            println(parenthesizedFactory)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TrailingLambdaDelegatesAcrossScopes",
            expected:
                """
                top
                1
                1
                1
                member-member
                capture-local
                parenthesized-ctor
                parenthesized-factory
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesLazyOfValueRead() throws {
        let source = """
        fun main() {
            val value = lazyOf(42)
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyOfValueRead",
            expected:
                """
                42
                """ + "\n"
        )
    }

    // KSP-CAP-013: `lazy { ... }` (the plain call form, not the `by lazy { }`
    // property delegate) lowers its initializer lambda through the general
    // closure-conversion path (a boxed Function0 value), unlike the delegate
    // form whose initializer is a standalone top-level thunk. Runtime used to
    // bitcast `RuntimeLazyBox`'s stored initializer straight to a raw thunk
    // pointer and call it directly, which crashed for this boxed-closure
    // shape. Also pins that an explicit `Lazy<Int>` expected type resolves
    // and type-checks correctly end to end (not just at the Sema layer).
    @Test
    func testCodegenCompilesLazyBlockValueRead() throws {
        let source = """
        fun main() {
            val value: Lazy<Int> = lazy { 42 }
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyBlockValueRead",
            expected:
                """
                42
                """ + "\n"
        )
    }

    // BUG-017: `lazy { ... }` called directly (not via `by`) lowers its
    // initializer lambda through the general closure-boxing path
    // (`kk_function_create_0`), unlike `by lazy` member/top-level accessors,
    // which pass a bare non-capturing function symbol. `RuntimeLazyBox`
    // previously bit-cast the stored handle straight to a context-free
    // `KKThunkEntryPoint` and called it, which for the boxed-closure case
    // jumped into heap data instead of code and crashed with a bad pointer
    // dereference. Fixed by invoking through `kk_function_invoke_0`, which
    // unwraps a boxed closure when present and falls back to a bare pointer
    // otherwise.
    @Test
    func testCodegenCompilesDirectLazyCallValueRead() throws {
        let source = """
        fun main() {
            val value = lazy { 42 }
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DirectLazyCallValueRead",
            expected:
                """
                42
                """ + "\n"
        )
    }

    // Exercises the boxed-closure initializer with an actual captured
    // variable, rather than a trivial literal, since a capture-free lambda
    // could conceivably take a different codegen shape.
    @Test
    func testCodegenCompilesLazyBlockCapturingOuterVariable() throws {
        let source = """
        fun main() {
            val base = 40
            val value = lazy { base + 2 }
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyBlockCapturingOuterVariable",
            expected:
                """
                42
                """ + "\n"
        )
    }

    // KSP-781: a local `by lazy` delegate can be captured by a nested lambda.
    // The delegate factory must be rewritten at declaration lowering time;
    // a later same-function consumer scan cannot see the nested read.
    @Test
    func testCodegenCompilesLazyDelegateCapturedByNestedLambda() throws {
        let source = """
        fun main() {
            val value by lazy { 42 }
            val read = { value }
            println(read())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyDelegateCapturedByNestedLambda",
            expected:
                """
                42
                """ + "\n",
            allowDefaultStdlibLibrary: false
        )
    }

    // BUG-017: an explicit `Lazy<T>` type annotation used to resolve to a
    // dead, non-standard `kotlin.properties.Lazy` interface stub (registered
    // but otherwise unused) instead of the real `kotlin.Lazy` that `lazy()`/
    // `lazyOf()` actually return, because unqualified short-name lookup
    // picked whichever symbol was registered first (registration order, not
    // import visibility -- `kotlin.properties` isn't even a default import).
    // This made any explicitly annotated `Lazy<T>` local fail type checking
    // against `lazyOf(...)`'s inferred type. Fixed by removing the dead
    // `kotlin.properties.Lazy` registration.
    @Test
    func testCodegenCompilesExplicitlyTypedLazyOfValueRead() throws {
        let source = """
        fun main() {
            val value: Lazy<Int> = lazyOf(99)
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ExplicitlyTypedLazyOfValueRead",
            expected:
                """
                99
                """ + "\n"
        )
    }

    // MARK: - KSP-CAP-007 / BUG-014: local custom-delegate getValue/setValue

    // `val x by Prop()` inside a function body used to bind `x` to the `Prop()`
    // instance's own raw handle instead of calling `Prop().getValue(...)` — see
    // ExprLowerer+ControlFlowAndBlocks.swift's `.localDecl` case. This was
    // observable for every return type (reference or primitive), since getValue
    // was never called at all; it was most visibly wrong for primitives, which
    // printed as a raw object address instead of their value. Member and
    // top-level delegated properties were unaffected — they already route
    // through a synthesized getter/setter accessor.

    @Test
    func testCodegenLocalCustomDelegateReturnsUnboxedInt() throws {
        let source = """
        class IntProp {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        fun main() {
            val x by IntProp()
            println(x)
            println(x + 1)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateInt",
            expected:
                """
                42
                43
                """ + "\n"
        )
    }

    @Test
    func testCodegenLocalCustomDelegateReturnsString() throws {
        let source = """
        class StringProp {
            operator fun getValue(thisRef: Any?, property: Any?): String = "hello"
        }
        fun main() {
            val x by StringProp()
            println(x)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateString",
            expected:
                """
                hello
                """ + "\n"
        )
    }

    @Test
    func testCodegenLocalCustomDelegateReturnsBoolean() throws {
        let source = """
        class BooleanProp {
            operator fun getValue(thisRef: Any?, property: Any?): Boolean = true
        }
        fun main() {
            val x by BooleanProp()
            println(x)
            println(!x)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateBoolean",
            expected:
                """
                true
                false
                """ + "\n"
        )
    }

    @Test
    func testCodegenLocalCustomDelegateVarSetValueRoundTrips() throws {
        let source = """
        class IntProp {
            var backing: Int = 0
            operator fun getValue(thisRef: Any?, property: Any?): Int = backing
            operator fun setValue(thisRef: Any?, property: Any?, value: Int) {
                backing = value
            }
        }
        fun main() {
            var x by IntProp()
            println(x)
            x = 100
            println(x)
            println(x + 1)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateVarSetValue",
            expected:
                """
                0
                100
                101
                """ + "\n"
        )
    }

    // A mutable delegated local must remain delegate storage when captured by
    // a lambda, so reads and writes continue to dispatch getValue/setValue.
    @Test
    func testCodegenLocalMutableDelegateCaptureInLambdaUsesAccessors() throws {
        let source = """
        class IntProp {
            var backing: Int = 1
            operator fun getValue(thisRef: Any?, property: Any?): Int = backing
            operator fun setValue(thisRef: Any?, property: Any?, value: Int) {
                backing = value
            }
        }
        fun main() {
            var value by IntProp()
            val update = {
                println(value)
                value = 7
                println(value)
            }
            update()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalMutableDelegateLambdaCapture",
            expected:
                """
                1
                7
                """ + "\n"
        )
    }

    // A delegated local captured by a nested local function must be restored
    // as delegate storage after the function scope is reset.
    @Test
    func testCodegenLocalDelegateCaptureInNestedFunctionUsesAccessor() throws {
        let source = """
        class IntProp {
            var backing: Int = 42
            operator fun getValue(thisRef: Any?, property: Any?): Int = backing
        }
        fun main() {
            val value by IntProp()
            fun readValue(): Int = value
            println(readValue())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalDelegateNestedFunctionCapture",
            expected:
                """
                42
                """ + "\n"
        )
    }

    // MARK: - DEBT-KIR-008: class-member `by lazy` per-instance storage/capture

    // A class member's `by lazy { ... }` body used to lower into a standalone
    // function with no way to reach the enclosing instance, so any reference
    // to an instance member inside the block (here, the primary-constructor
    // property `label`) silently resolved to nothing instead of the captured
    // value.
    @Test
    func testMemberLazyDelegateCapturesEnclosingInstanceProperty() throws {
        let source = """
        class Foo(val label: String) {
            val x by lazy { label }
        }
        fun main() {
            val a = Foo("a")
            println(a.x)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberLazyDelegateCapturesLabel",
            expected:
                """
                a
                """ + "\n"
        )
    }

    // KSP-781 regression: the body lowered for a member lazy delegate must
    // retain Sema bindings for both implicit member calls and field reads.
    @Test
    func testMemberLazyDelegateBodyUsesTypedInstanceState() throws {
        let source = """
        class Foo {
            var count = 0
            fun next(): Int {
                count += 1
                return count
            }
            val x: Int by lazy { next() + count }
        }
        fun main() {
            val foo = Foo()
            println(foo.x)
            println(foo.x)
            println(foo.count)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberLazyDelegateUsesTypedInstanceState",
            expected:
                """
                2
                2
                1
                """ + "\n"
        )
    }

    // The delegate handle (`$delegate_x`, holding the `Lazy` instance) used to
    // be stored in a single module-global slot shared by every instance of the
    // class, so constructing a second `Foo` clobbered the first instance's
    // delegate — both `a.x` and `b.x` observed whichever instance was
    // constructed last instead of their own captured `label`.
    @Test
    func testMemberLazyDelegateUsesPerInstanceStorage() throws {
        let source = """
        class Foo(val label: String) {
            val x by lazy { label }
        }
        fun main() {
            val a = Foo("a")
            val b = Foo("b")
            println(a.x)
            println(b.x)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberLazyDelegatePerInstanceStorage",
            expected:
                """
                a
                b
                """ + "\n"
        )
    }

    // MARK: - BUG-146: local delegate with a provideDelegate operator

    // `val x by Factory()` where `Factory` exposes `provideDelegate` used to
    // bind `x` to the `Factory()` instance itself: no provideDelegate call was
    // emitted and getValue resolved against the wrong receiver, so `println(x)`
    // printed the factory's raw object handle. The effective delegate is
    // provideDelegate's return value (same rule as member/top-level delegated
    // properties in KIRLoweringDriver+ProvideDelegate.swift).

    @Test
    func testCodegenLocalProvideDelegateReturnsString() throws {
        let source = """
        import kotlin.reflect.KProperty
        class StrDelegate(private val v: String) {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): String = v
        }
        class StrFactory(private val v: String) {
            operator fun provideDelegate(thisRef: Any?, prop: KProperty<*>): StrDelegate = StrDelegate(v.uppercase())
        }
        fun main() {
            val name by StrFactory("hello")
            println(name)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalProvideDelegateString",
            expected:
                """
                HELLO
                """ + "\n"
        )
    }

    @Test
    func testCodegenLocalProvideDelegateVarSetValueRoundTrips() throws {
        let source = """
        import kotlin.reflect.KProperty
        class IntBox(private var stored: Int) {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = stored
            operator fun setValue(thisRef: Any?, property: KProperty<*>, newValue: Int) { stored = newValue }
        }
        class IntBoxFactory(private val initial: Int) {
            operator fun provideDelegate(thisRef: Any?, prop: KProperty<*>): IntBox = IntBox(initial)
        }
        fun main() {
            var counter by IntBoxFactory(10)
            println(counter)
            counter = 42
            println(counter)
            counter = counter + 1
            println(counter)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LocalProvideDelegateVarSetValue",
            expected:
                """
                10
                42
                43
                """ + "\n"
        )
    }

    @Test
    func testCodegenTopLevelProvideDelegateStillWorks() throws {
        // Regression guard: top-level provideDelegate already worked through
        // KIRLoweringDriver+ProvideDelegate.swift and must be unaffected by the
        // new local-declaration path.
        let source = """
        import kotlin.reflect.KProperty
        class StrDelegate(private val v: String) {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): String = v
        }
        class StrFactory(private val v: String) {
            operator fun provideDelegate(thisRef: Any?, prop: KProperty<*>): StrDelegate = StrDelegate(v.uppercase())
        }
        val topName by StrFactory("hi")
        fun main() {
            println(topName)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TopLevelProvideDelegateStillWorks",
            expected:
                """
                HI
                """ + "\n"
        )
    }

    @Test
    func testCodegenMemberProvideDelegateUsesResolvedOperator() throws {
        let source = """
        import kotlin.reflect.KProperty
        class StrDelegate(private val value: String) {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): String = value
        }
        class StrFactory(private val value: String) {
            operator fun provideDelegate(thisRef: Any?, property: KProperty<*>): StrDelegate =
                StrDelegate(value.uppercase())
        }
        class Holder {
            val name by StrFactory("member")
        }
        fun main() {
            println(Holder().name)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberProvideDelegateResolvedOperator",
            expected:
                """
                MEMBER
                """ + "\n"
        )
    }

    @Test
    func testCodegenMemberCustomDelegatePrimitiveStillWorks() throws {
        // Regression guard: member-property custom delegates already worked
        // before this fix and share DeclTypeChecker+PropertyHelpers.swift's
        // typeCheckDelegate, whose signature this fix changed.
        let source = """
        class IntProp {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Holder {
            val x by IntProp()
        }
        fun main() {
            val h = Holder()
            println(h.x)
            println(h.x + 1)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberDelegateIntStillWorks",
            expected:
                """
                42
                43
                """ + "\n"
        )
    }

    // BUG-151: a stdlib delegate's callback lambda declared with a parameter
    // list (`{ property, old, new -> ... }`) lost its whole body, because the
    // parameter list and arrow form their own CST statement node that the
    // block-statement parser could not turn into an expression. The callback
    // also never observed a value change, because assignment through an
    // explicit receiver wrote the (unused) backing field slot directly instead
    // of dispatching to the property's setter accessor.
    @Test
    func testCodegenMemberObservableDelegateReportsChanges() throws {
        let source = """
        import kotlin.properties.Delegates

        class User {
            var name: String by Delegates.observable("initial") { _, old, new ->
                println("changed from $old to $new")
            }
        }

        fun main() {
            val u = User()
            u.name = "hello"
            println(u.name)
            u.name = "world"
            println(u.name)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberObservableDelegate",
            expected:
                """
                changed from initial to hello
                hello
                changed from hello to world
                world
                """ + "\n"
        )
    }

    // BUG-151: an `Int`-typed observable callback interpolating its value
    // parameters used to concatenate the raw values as if they were string
    // handles, because the synthetic callback parameters were all typed `Any`
    // and Sema never binds a type to the (unvisited) callback body.
    @Test
    func testCodegenMemberObservableDelegateFormatsIntValues() throws {
        let source = """
        import kotlin.properties.Delegates

        class Counter {
            var value: Int by Delegates.observable(1) { _, old, new ->
                println("obs:$old->$new")
            }
        }

        fun main() {
            val c = Counter()
            c.value = 2
            c.value = 5
            println(c.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberObservableDelegateIntValues",
            expected:
                """
                obs:1->2
                obs:2->5
                5
                """ + "\n"
        )
    }

    // BUG-151: the vetoable callback returns a Kotlin `Boolean`, which reaches
    // the runtime boxed; a boxed `false` is a non-zero handle, so every change
    // was accepted. Also covers compound assignment, which used to bypass the
    // delegate entirely by reading and writing the backing field slot.
    @Test
    func testCodegenMemberVetoableDelegateRejectsChanges() throws {
        let source = """
        import kotlin.properties.Delegates

        class Counter {
            var value: Int by Delegates.vetoable(0) { _, _, new -> new >= 0 }
        }

        fun main() {
            val c = Counter()
            c.value = 5
            println(c.value)
            c.value = -1
            println(c.value)
            c.value += 3
            println(c.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberVetoableDelegate",
            expected:
                """
                5
                5
                8
                """ + "\n"
        )
    }

    // BUG-169: member observable/vetoable callbacks need a boxed Function3
    // value so the enclosing instance can travel with the three callback
    // arguments. A raw top-level thunk has no way to resolve implicit member
    // reads or writes in the callback body.
    @Test
    func testCodegenMemberDelegateCallbacksCaptureEnclosingInstance() throws {
        let source = """
        import kotlin.properties.Delegates

        class Counter(val label: String, val minimum: Int) {
            var callbackCount: Int = 0
            var observed: Int by Delegates.observable(1) { _, old, new ->
                callbackCount += 1
                println("$label:$old->$new:$callbackCount")
            }
            var guarded: Int by Delegates.vetoable(0) { _, _, new ->
                println("$label:check:$new")
                new >= minimum
            }
        }

        fun main() {
            val a = Counter("a", 2)
            val b = Counter("b", 5)
            a.observed = 3
            b.observed = 4
            println(a.callbackCount)
            println(b.callbackCount)
            a.guarded = 1
            a.guarded = 2
            println(a.guarded)
            b.guarded = 4
            b.guarded = 5
            println(b.guarded)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberDelegateCallbackCapture",
            expected:
                """
                a:1->3:1
                b:1->4:1
                1
                1
                a:check:1
                a:check:2
                2
                b:check:4
                b:check:5
                5
                """ + "\n"
        )
    }

    // BUG-151: `Delegates.notNull()` reads crashed with
    // "Property delegate must be assigned before being accessed" even after a
    // write, because the write never reached `kk_notNull_set_value`.
    @Test
    func testCodegenMemberNotNullDelegateRoundTrips() throws {
        let source = """
        import kotlin.properties.Delegates

        class Box {
            var value: String by Delegates.notNull()
        }

        fun main() {
            val b = Box()
            b.value = "abc"
            println(b.value)
            b.value = "def"
            println(b.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MemberNotNullDelegate",
            expected:
                """
                abc
                def
                """ + "\n"
        )
    }

    // BUG-151: the same callback-body loss affected top-level delegated
    // properties, which lower through a separate initializer path.
    @Test
    func testCodegenTopLevelObservableAndVetoableDelegates() throws {
        let source = """
        import kotlin.properties.Delegates

        var topName: String by Delegates.observable("t0") { _, old, new -> println("top $old->$new") }
        var topCount: Int by Delegates.vetoable(1) { _, _, new -> new > 0 }
        var topLate: Int by Delegates.notNull()

        fun main() {
            topName = "t1"
            println(topName)
            topCount = 9
            println(topCount)
            topCount = -5
            println(topCount)
            topLate = 3
            println(topLate)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TopLevelStdlibDelegates",
            expected:
                """
                top t0->t1
                t1
                9
                9
                3
                """ + "\n"
        )
    }

    // KSP-681: observable/vetoable/notNull must be executed through their
    // Kotlin source implementations. In particular, the factory call keeps
    // its trailing callback as an ordinary call argument, and notNull keeps
    // its source-backed getValue/setValue behavior.
    @Test
    func testCodegenSourceBackedStdlibDelegatesUseNormalExpressionLowering() throws {
        let source = """
        import kotlin.properties.Delegates

        var observed: Int by Delegates.observable(1) { _, old, new -> println("observed:$old->$new") }
        var accepted: Int by Delegates.vetoable(0) { _, _, new -> new >= 0 }
        var late: Int by Delegates.notNull()

        fun main() {
            observed = 2
            accepted = -1
            println(accepted)
            late = 3
            println(late)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KSP681SourceBackedStdlibDelegates",
            expected:
                """
                observed:1->2
                0
                3
                """ + "\n"
        )
    }
}
#endif
