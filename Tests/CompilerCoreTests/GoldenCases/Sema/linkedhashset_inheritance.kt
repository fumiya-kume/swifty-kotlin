// RF-FIXTURE-008: LinkedHashSet is an open class — a subclass inherits the
// MutableSet surface and stays assignable to LinkedHashSet positions.

class MySet : LinkedHashSet<String>() {
    fun customOp(): String {
        return "custom"
    }
}

fun acceptLinked(set: LinkedHashSet<String>) {}

fun inheritanceChecks() {
    val mySet = MySet()

    // Subclass instances satisfy the superclass, MutableSet, and Set types.
    val asLinked: LinkedHashSet<String> = mySet
    val asMutable: MutableSet<String> = mySet
    val asReadOnly: Set<String> = mySet
    acceptLinked(mySet)

    // The subclass' own member stays resolvable.
    val op: String = mySet.customOp()
}
