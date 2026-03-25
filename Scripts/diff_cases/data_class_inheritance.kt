// Test cases for data class inheritance constraints (STDLIB-DATA-014)

// Case 1: Attempting to inherit from data class - should be error
data class Person(val name: String, val age: Int)

class Employee(name: String, age: Int, val salary: Double) : Person(name, age) {
    // This should cause KSWIFTK-SEMA-DATA-INHERIT error
}

// Case 2: Data class inheriting from regular open class - should be allowed
open class BaseEntity(val id: String) {
    override fun toString(): String = "BaseEntity($id)"
}

data class Entity(val name: String, val id: String) : BaseEntity(id) {
    // This should be allowed
}

// Case 3: Data class implementing interface - should be allowed
interface Serializable {
    fun serialize(): String
}

data class SerializablePerson(val name: String, val age: Int) : Serializable {
    override fun serialize(): String = "$name,$age"
}

// Case 4: Data class inheriting from sealed class - should be allowed
sealed class Result {
    abstract val code: Int
}

data class Success(val data: String, override val code: Int = 200) : Result() {
    // This should be allowed
}

data class Error(val message: String, override val code: Int = 400) : Result() {
    // This should be allowed
}

// Case 5: Nested data class inheritance attempt
class Container {
    data class Inner(val value: String)
    
    class Outer(val value: String) : Inner(value) {
        // This should cause KSWIFTK-SEMA-DATA-INHERIT error
    }
}

fun main() {
    // Test allowed cases
    val entity = Entity("Test", "123")
    println(entity.toString())
    
    val person = SerializablePerson("Alice", 30)
    println(person.serialize())
    
    val success = Success("data")
    println(success.toString())
    
    val error = Error("Something went wrong")
    println(error.toString())
}
