// Test cases for STDLIB-INHERIT-019: Override variance and visibility expansion

// Exception hierarchy for testing exception covariance
open class IOException : Exception()
open class FileNotFoundException : IOException()
open class EOFException : IOException()

// Base classes for testing
open class Animal {
    open fun makeSound(): String = "animal sound"
    protected open fun feed(): String = "feeding animal"
    internal open fun care(): String = "caring for animal"
    open fun process(): Unit throws IOException = Unit
}

open class Dog : Animal() {
    // Valid: return type covariance (String is subtype of String - same type)
    override fun makeSound(): String = "woof"
    
    // Valid: visibility expansion (protected -> protected, same visibility)
    protected override fun feed(): String = "feeding dog"
    
    // Valid: visibility expansion (internal -> internal, same visibility)  
    internal override fun care(): String = "caring for dog"
    
    // Valid: exception covariance (FileNotFoundException is subtype of IOException)
    override fun process(): Unit throws FileNotFoundException = Unit
}

// Test visibility expansion to public
open class Cat : Animal() {
    override fun makeSound(): String = "meow"
    
    // Valid: visibility expansion (protected -> public)
    public override fun feed(): String = "feeding cat"
    
    // Valid: visibility expansion (internal -> public)
    public override fun care(): String = "caring for cat"
    
    // Valid: exception covariance (same exception type)
    override fun process(): Unit throws IOException = Unit
}

// Test return type covariance with inheritance hierarchy
open class NumberContainer {
    open fun getValue(): Number = 42
}

open class IntContainer : NumberContainer() {
    // Valid: return type covariance (Int is subtype of Number)
    override fun getValue(): Int = 123
}

// Test invalid visibility restriction (should cause errors)
open class InvalidVisibility : Animal() {
    override fun makeSound(): String = "invalid sound"
    
    // ERROR: Cannot reduce visibility from protected to private
    // private override fun feed(): String = "invalid feeding"
    
    // ERROR: Cannot reduce visibility from internal to private  
    // private override fun care(): String = "invalid caring"
}

// Test interface implementation with variance
interface Producer<out T> {
    fun produce(): T
}

class StringProducer : Producer<String> {
    // Valid: return type covariance
    override fun produce(): String = "hello"
}

// Test more complex inheritance chain
abstract class Shape {
    abstract fun area(): Double
    protected abstract fun description(): String
}

open class Circle : Shape() {
    override fun area(): Double = 3.14159 * 2.0 * 2.0
    
    // Valid: visibility expansion (protected abstract -> protected)
    protected override fun description(): String = "circle with radius 2"
}

open class SmallCircle : Circle() {
    // Valid: return type covariance (Double -> Double, same type)
    override fun area(): Double = 3.14159 * 1.0 * 1.0
    
    // Valid: visibility expansion (protected -> public)
    public override fun description(): String = "small circle with radius 1"
}

fun main() {
    val animal = Animal()
    val dog = Dog()
    val cat = Cat()
    
    println(animal.makeSound())
    println(dog.makeSound())
    println(cat.makeSound())
    
    val container = IntContainer()
    println(container.getValue())
    
    val shape = SmallCircle()
    println(shape.area())
    println(shape.description())
}

// Test exception covariance scenarios
class ExceptionTest {
    open class BaseProcessor {
        open fun processData(): String throws IOException = "base processed"
    }
    
    open class SpecificProcessor : BaseProcessor() {
        // Valid: exception covariance (FileNotFoundException is subtype of IOException)
        override fun processData(): String throws FileNotFoundException = "specific processed"
    }
    
    // Invalid: exception contravariance (should cause error when uncommented)
    // open class InvalidProcessor : BaseProcessor() {
    //     override fun processData(): String throws Exception = "invalid" // Exception is supertype of IOException
    // }
    
    // Valid: same exception type
    open class SameExceptionProcessor : BaseProcessor() {
        override fun processData(): String throws IOException = "same exception"
    }
}
