// Test cases for abstract property error conditions

// ERROR: Abstract property with initializer
abstract class BadClass1 {
    abstract val name: String = "error"  // Should error: cannot have initializer
}

// ERROR: Abstract property with explicit backing field  
abstract class BadClass2 {
    abstract val count: Int
        field = 0  // Should error: cannot have explicit backing field
}

// ERROR: Abstract property with delegate expression
abstract class BadClass3 {
    abstract val data: String by lazy { "error" }  // Should error: cannot have delegate
}

// ERROR: Abstract property with getter body
abstract class BadClass4 {
    abstract val value: String
        get() = "error"  // Should error: cannot have getter body
}

// ERROR: Abstract property with setter body
abstract class BadClass5 {
    abstract var mutable: String
        set(value) {}  // Should error: cannot have setter body
}

// ERROR: Class not implementing abstract property
abstract class Base {
    abstract val required: String
}

class Derived : Base() {
    // Missing override for abstract property 'required'
}

// ERROR: Class with incomplete abstract property implementation
abstract class Parent {
    abstract val parentProp: String
    abstract fun parentFunc()
}

class Child : Parent() {
    override fun parentFunc() {}
    // Missing override for abstract property 'parentProp'
}
