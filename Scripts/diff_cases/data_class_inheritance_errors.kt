// Test cases for data class inheritance errors (STDLIB-DATA-014)

// Case 1: Attempting to inherit from data class - should be error
data class Person(val name: String, val age: Int)

class Employee(name: String, age: Int, val salary: Double) : Person(name, age) {
    // This should cause KSWIFTK-SEMA-DATA-INHERIT error
}

// Case 2: Nested data class inheritance attempt
class Container {
    data class Inner(val value: String)
    
    class Outer(val value: String) : Inner(value) {
        // This should cause KSWIFTK-SEMA-DATA-INHERIT error
    }
}

// Case 3: Multiple inheritance with data class
interface Interface1
interface Interface2

data class Base(val value: String)

class Multi(val prop: Int) : Base("test"), Interface1, Interface2 {
    // This should cause KSWIFTK-SEMA-DATA-INHERIT error for Base
}

fun main() {
    // Regression case entry point for tracking tests.
}
