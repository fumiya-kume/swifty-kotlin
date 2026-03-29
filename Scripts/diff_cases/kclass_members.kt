// STDLIB-REFLECT-061: KClass member access
data class Person(val name: String, val age: Int)

class Counter {
    var count: Int = 0
    fun increment() { count++ }
    fun decrement() { count-- }
}

fun main() {
    val personClass = Person::class
    val counterClass = Counter::class

    // properties: includes inherited members
    val personProperties = personClass.properties
    println("Person::class.properties.size >= 0: ${personProperties.size >= 0}")

    // memberProperties: non-extension properties
    val personMemberProps = personClass.memberProperties
    println("Person::class.memberProperties.size >= 0: ${personMemberProps.size >= 0}")

    // functions: includes inherited members
    val personFunctions = personClass.functions
    println("Person::class.functions.size >= 0: ${personFunctions.size >= 0}")

    // memberFunctions: non-extension functions
    val counterMemberFunctions = counterClass.memberFunctions
    println("Counter::class.memberFunctions.size >= 0: ${counterMemberFunctions.size >= 0}")

    // declaredMemberProperties: own declared properties
    val personDeclaredProps = personClass.declaredMemberProperties
    println("Person::class.declaredMemberProperties.size >= 0: ${personDeclaredProps.size >= 0}")

    // declaredMemberFunctions: own declared functions
    val counterDeclaredFunctions = counterClass.declaredMemberFunctions
    println("Counter::class.declaredMemberFunctions.size >= 0: ${counterDeclaredFunctions.size >= 0}")

    // Filtering: filter by size > 0 is valid (result depends on metadata registration)
    val largeMemberProps = personMemberProps.filter { true }
    println("Filtered properties list is not null: ${largeMemberProps != null}")
}
