// Test cases for valid data class inheritance (STDLIB-DATA-014)

// Case 1: Data class inheriting from regular open class - should be allowed
open class BaseEntity(val id: String)

data class Entity(val name: String, id: String) : BaseEntity(id)

// Case 2: Data class implementing interface - should be allowed
interface Serializable {
    fun serialize(): String
}

data class SerializablePerson(val name: String, val age: Int) : Serializable {
    override fun serialize(): String = "$name,$age"
}

// Case 3: Data class inheriting from abstract class - should be allowed
abstract class AbstractBase(val version: Int) {
    abstract fun getInfo(): String
}

data class ConcreteData(val value: String, version: Int) : AbstractBase(version) {
    override fun getInfo(): String = "ConcreteData($value, v$version)"
}

fun main() {
    // Test allowed cases
    val entity = Entity("Test", "123")
    println(entity.toString())
    
    val person = SerializablePerson("Alice", 30)
    println(person.serialize())
    
    val concrete = ConcreteData("test", 1)
    println(concrete.getInfo())
    println(concrete.toString())
}
