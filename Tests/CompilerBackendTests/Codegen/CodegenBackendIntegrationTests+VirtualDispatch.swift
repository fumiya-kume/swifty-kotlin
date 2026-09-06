#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendVirtualDispatchTests {

    @Test
    func testOpenClassVirtualDispatchChoosesConcreteOverride() throws {
        let source = """
        open class Animal {
            open fun speak(): String = "base"
        }
        class Dog : Animal() {
            override fun speak(): String = "dog"
        }
        class Cat : Animal() {
            override fun speak(): String = "cat"
        }
        fun callSpeak(animal: Animal): String = animal.speak()
        fun main() {
            println(callSpeak(Dog()))
            println(callSpeak(Cat()))
            println(callSpeak(Animal()))
        }
        """
        try assertKotlinOutput(source, moduleName: "OpenClassVirtualDispatchRuntime", expected: "dog\ncat\nbase\n")
    }

    @Test
    func testOpenPropertyReadUsesDirectAccessWithoutSubtypeAndVirtualOverrideWithSubtype() throws {
        let source = """
        open class DirectRead {
            open val p: Int = 5
        }
        open class Base {
            open val p: Int = 5
        }
        class BaseChild : Base()
        open class Parent {
            open val p: Int = 6
        }
        class Child : Parent() {
            override val p: Int = 7
        }
        fun readCharSequenceLength(value: CharSequence): Int = value.length
        fun main() {
            println(DirectRead().p)
            val base: Base = BaseChild()
            println(base.p)
            val parent: Parent = Child()
            println(parent.p)
            println(readCharSequenceLength("hello"))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "OpenPropertyDispatchRuntime",
            expected: "5\n5\n7\n5\n"
        )
    }

    // BUG-156: the interface method implemented by the abstract base must be
    // reachable through the concrete subclass' itable, and the base's
    // unqualified `compute()` must reach the subclass override.
    @Test
    func testInterfaceMethodInheritedFromAbstractBaseDispatchesThroughItable() throws {
        let source = """
        interface Box<T> {
            fun get(): T
        }
        abstract class AbstractBox<T> : Box<T> {
            abstract fun compute(): T
            override fun get(): T = compute()
        }
        class IntBox(val v: Int) : AbstractBox<Int>() {
            override fun compute(): Int = v
        }
        fun accept(b: Box<Int>): Int = b.get()
        fun main() {
            val box = IntBox(7)
            println(box.get())
            println(accept(box))
        }
        """
        try assertKotlinOutput(source, moduleName: "InheritedInterfaceItableDispatchRuntime", expected: "7\n7\n")
    }

    @Test
    func testUnqualifiedSelfCallDispatchesToSubclassOverride() throws {
        let source = """
        abstract class Greeter {
            abstract fun name(): String
            fun greet(): String = "hello " + name()
        }
        class Named : Greeter() {
            override fun name(): String = "world"
        }
        fun main() {
            println(Named().greet())
        }
        """
        try assertKotlinOutput(source, moduleName: "UnqualifiedSelfCallDispatchRuntime", expected: "hello world\n")
    }

    @Test
    func testPropertyReferenceAccessorsDispatchForBoundUnboundAndUpcastValues() throws {
        let source = """
        import kotlin.reflect.KMutableProperty0
        import kotlin.reflect.KMutableProperty1
        import kotlin.reflect.KProperty
        import kotlin.reflect.KProperty0
        import kotlin.reflect.KProperty1

        class Person(val name: String, var age: Int, var label: String)

        fun main() {
            val person = Person("A", 1, "L")
            println(person.name)
            val boundName: KProperty0<String> = person::name
            println(boundName.name)
            println(boundName.get())
            println(boundName.invoke())
            val boundNameAsProperty: KProperty<String> = boundName
            println(boundNameAsProperty.name)
            val nullableName: KProperty0<String>? = boundName
            println(nullableName?.name)

            val boundAge: KMutableProperty0<Int> = person::age
            println(boundAge.name)
            println(boundAge.get())
            println(boundAge.invoke())
            val boundAgeAsProperty0: KProperty0<Int> = boundAge
            println(boundAgeAsProperty0.get())
            boundAge.set(2)
            println(person.age)

            val boundLabel: KMutableProperty0<String> = person::label
            println(boundLabel.name)
            println(boundLabel.get())
            println(boundLabel.invoke())
            boundLabel.set("M")
            println(person.label)

            val unboundName: KProperty1<Person, String> = Person::name
            println(unboundName.name)
            println(unboundName.get(person))
            println(unboundName.invoke(person))
            val unboundNameAsProperty: KProperty<String> = unboundName
            println(unboundNameAsProperty.name)

            val unboundAge: KMutableProperty1<Person, Int> = Person::age
            println(unboundAge.name)
            println(unboundAge.get(person))
            println(unboundAge.invoke(person))
            val unboundAgeAsProperty1: KProperty1<Person, Int> = unboundAge
            println(unboundAgeAsProperty1.get(person))
            unboundAge.set(person, 3)
            println(person.age)

            val unboundLabel: KMutableProperty1<Person, String> = Person::label
            println(unboundLabel.name)
            println(unboundLabel.get(person))
            println(unboundLabel.invoke(person))
            unboundLabel.set(person, "N")
            println(person.label)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "PropertyReferenceAccessorDispatchRuntime",
            expected: "A\nname\nA\nA\nname\nname\nage\n1\n1\n1\n2\nlabel\nL\nL\nM\nname\nA\nA\nname\nage\n2\n2\n2\n3\nlabel\nM\nM\nN\n"
        )
    }

    // KSP-496 byproduct bug: a bare (receiver-less) top-level `val` whose
    // initializer is a compile-time literal never gets a runtime store for
    // its backing global (see lowerPropertyInitializer's `needsInit` check —
    // ordinary reads are constant-folded and never touch the global at all).
    // The synthetic KProperty0 accessor generated for `::topLevel` used to
    // unconditionally `loadGlobal` that never-initialized slot, so `.name`
    // read correctly but `.get()` returned the zero value instead of the
    // literal. A top-level `var` (never constant-folded, per ConstantCollector
    // excluding `isVar`) and a non-literal `val` initializer are included as
    // contrast cases that must keep going through the real global.
    @Test
    func testBareTopLevelPropertyReferenceGetReturnsActualValue() throws {
        let source = """
        import kotlin.reflect.KMutableProperty0
        import kotlin.reflect.KProperty0

        val topLevelInt: Int = 7
        val topLevelString: String = "hi"
        var topLevelCounter: Int = 10
        fun compute(): Int = 3 + 4
        val topLevelComputed: Int = compute()

        fun main() {
            val intRef: KProperty0<Int> = ::topLevelInt
            println(intRef.name)
            println(intRef.get())

            val stringRef: KProperty0<String> = ::topLevelString
            println(stringRef.get())

            val counterRef: KMutableProperty0<Int> = ::topLevelCounter
            println(counterRef.get())
            counterRef.set(42)
            println(counterRef.get())
            println(topLevelCounter)

            val computedRef: KProperty0<Int> = ::topLevelComputed
            println(computedRef.get())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "BareTopLevelPropertyReferenceRuntime",
            expected: "topLevelInt\n7\nhi\n10\n42\n42\n7\n"
        )
    }
}
#endif
