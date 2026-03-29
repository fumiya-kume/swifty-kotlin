package golden.sema

class Container<T>(val item: T)

// Read-only access via star projection
fun readContainer(c: Container<*>): Any? = c.item

// Star projection in function parameter (type erasure)
fun eraseType(list: List<*>): Int = list.size

// Star projection: accepting any Container
fun acceptAny(c: Container<*>) {
    val v = c.item
}
