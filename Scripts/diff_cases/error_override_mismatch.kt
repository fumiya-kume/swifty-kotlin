// Error cases for override mismatches (KSWIFTK-SEMA-*)

open class Base {
    open fun method(): Int = 0
    open val prop: Number = 0
    fun finalMethod(): String = "final"
}

class Child : Base() {
    // ERROR: Return type mismatch in override
    override fun method(): String = "wrong"  // KSWIFTK-SEMA-0030: return type of override is incompatible with base type

    // ERROR: Overriding val with incompatible type
    override val prop: String = "wrong"  // KSWIFTK-SEMA-0031: type of 'prop' is not a subtype of the overridden property type

    // ERROR: Overriding non-open (final) function
    override fun finalMethod(): String = "overriding final"  // KSWIFTK-SEMA-0032: 'finalMethod' hides member but cannot be overridden

    // This method is not declared in Base, so it is not an override and needs no keyword.
    fun anotherMethod(): Int = 1  // OK: new method, no override required
}

interface IBase {
    fun interfaceMethod(): Int
}

class BadImpl : IBase {
    // ERROR: Missing override for interface method
    fun interfaceMethod(): String = "wrong return type"  // KSWIFTK-SEMA-0033: 'interfaceMethod' clashes with method in IBase
}

// Overriding val with var is explicitly allowed in Kotlin (widening is permitted).
// This is NOT an error:
open class PropBase {
    open val readOnly: Int = 0
}

class PropChild : PropBase() {
    override var readOnly: Int = 0  // OK: widening val -> var is valid in Kotlin
}

// ERROR: Override changes property type to an incompatible (non-subtype) type
open class TypeBase {
    open val count: Number = 0
}

class TypeChild : TypeBase() {
    override val count: String = "wrong"  // KSWIFTK-SEMA-0031: type of 'count' is not a subtype of the overridden property type
}

fun main() {}
