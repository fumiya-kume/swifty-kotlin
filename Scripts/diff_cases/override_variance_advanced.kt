// Advanced test cases for override variance

// Test generic return type covariance
abstract class AbstractContainer<T> {
    abstract fun getItems(): List<T>
    protected abstract fun getSize(): Int
}

class StringContainer : AbstractContainer<String>() {
    // Valid: return type covariance with generics
    override fun getItems(): List<String> = listOf("a", "b", "c")
    
    // Valid: visibility expansion
    public override fun getSize(): Int = 3
}

// Test nullable type covariance
open class NullableProvider {
    open fun getValue(): String? = null
}

open class NonNullProvider : NullableProvider() {
    // Valid: return type covariance (String is subtype of String?)
    override fun getValue(): String = "non-null value"
}

// Test union type scenarios (if supported)
open class BaseClass {
    open fun process(): Any = "base result"
}

open class DerivedClass : BaseClass() {
    // Valid: return type covariance (String is subtype of Any)
    override fun process(): String = "derived result"
}

// Test interface inheritance with variance
interface Reader<out T> {
    fun read(): T
    protected fun getStatus(): String
}

class FileReader : Reader<String> {
    override fun read(): String = "file content"
    
    // Valid: visibility expansion
    public override fun getStatus(): String = "file ready"
}

class AdvancedFileReader : FileReader() {
    // Valid: return type covariance (String -> String, same type)
    override fun read(): String = "advanced file content"
    
    // Valid: visibility expansion (public -> public, same type)
    public override fun getStatus(): String = "advanced file ready"
}

// Test multiple inheritance levels with variance
open class Level1 {
    open fun getData(): Number = 1
    protected open fun validate(): Boolean = true
}

open class Level2 : Level1() {
    override fun getData(): Int = 42  // Valid: Number -> Int
    public override fun validate(): Boolean = true  // Valid: protected -> public
}

open class Level3 : Level2() {
    override fun getData(): Int = 100  // Valid: Int -> Int
    public override fun validate(): Boolean = false  // Valid: public -> public
}

// Test abstract class implementation
abstract class AbstractProcessor {
    abstract fun process(input: Any): String
    protected abstract fun log(message: String): Unit
}

class ConcreteProcessor : AbstractProcessor() {
    override fun process(input: Any): String = "processed: $input"
    
    // Valid: visibility expansion
    public override fun log(message: String) {
        println("LOG: $message")
    }
}

// Test edge cases
open class EdgeCaseBase {
    open fun getUnit(): Unit = Unit
    open fun getNothing(): Nothing = throw RuntimeException()
}

open class EdgeCaseDerived : EdgeCaseBase() {
    // Valid: Unit -> Unit
    override fun getUnit(): Unit = Unit
    
    // Valid: Nothing -> Nothing (bottom type)
    override fun getNothing(): Nothing = throw RuntimeException("derived")
}

fun main() {
    val container = StringContainer()
    println(container.getItems().joinToString())
    println(container.getSize())
    
    val provider = NonNullProvider()
    println(provider.getValue())
    
    val processor = ConcreteProcessor()
    println(processor.process("test"))
    processor.log("test message")
    
    val reader = AdvancedFileReader()
    println(reader.read())
    println(reader.getStatus())
}
