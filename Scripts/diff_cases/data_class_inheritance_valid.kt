// Test cases for valid data class inheritance (STDLIB-DATA-014)

// Case 1: Data class inheriting from regular open class - should be allowed
open class BaseEntity(val id: String) {
    override fun toString(): String = "BaseEntity($id)"
    
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is BaseEntity) return false
        return this.id == other.id
    }
    
    override fun hashCode(): Int = id.hashCode()
}

data class Entity(val name: String, id: String) : BaseEntity(id) {
    // This should be allowed
}

// Case 2: Data class implementing interface - should be allowed
interface Serializable {
    fun serialize(): String
}

data class SerializablePerson(val name: String, val age: Int) : Serializable {
    override fun serialize(): String = "$name,$age"
}

// Case 3: Data class inheriting from sealed class - should be allowed
sealed class Result {
    abstract val code: Int
}

data class Success(val data: String, override val code: Int = 200) : Result()

data class Error(val message: String, override val code: Int = 400) : Result()

// Case 4: Data class inheriting from abstract class - should be allowed
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
    println(entity.hashCode())
    
    val entity2 = Entity("Test", "123")
    println(entity == entity2)
    
    val person = SerializablePerson("Alice", 30)
    println(person.serialize())
    
    val success = Success("data")
    println(success.toString())
    
    val error = Error("Something went wrong")
    println(error.toString())
    
    val concrete = ConcreteData("test", 1)
    println(concrete.getInfo())
    println(concrete.toString())
}
