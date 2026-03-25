// Function parameter type
fun processList(list: ArrayList<String>) {
    println(list.size)
}

// Return type
fun createList(): ArrayList<Int> {
    return ArrayList<Int>()
}

// Property type
class Container {
    val items: ArrayList<String> = ArrayList()
    val numbers: ArrayList<Int> = ArrayList<Int>()
}

// Generic type argument
fun nestedLists() {
    val nested: ArrayList<ArrayList<String>> = ArrayList()
    val inner = ArrayList<String>()
    inner.add("nested")
    nested.add(inner)
    println(nested.size)
}

// Inheritance
class MyList : ArrayList<String>() {
    fun customOp() = "custom"
}

// Type constraint
fun <T : ArrayList<String>> constrain(list: T): T {
    return list
}

// Extension function on ArrayList
fun ArrayList<String>.customExtension(): String {
    return "extended: ${this.size}"
}

fun main() {
    val list: ArrayList<String> = ArrayList()
    list.add("hello")
    list.add("world")
    println(list.size)
    println(list[0])

    val ml: MutableList<String> = list
    ml.add("!")
    println(ml.size)

    val nums = ArrayList<Int>()
    nums.add(1)
    nums.add(2)
    nums.add(3)
    nums.removeAt(0)
    println(nums)

    val items: List<String> = ArrayList()
    println(items.size)

    // Test function parameter
    processList(list)

    // Test return type
    val created = createList()
    created.add(42)
    println(created.size)

    // Test property type
    val container = Container()
    container.items.add("property")
    println(container.items.size)

    // Test nested generic
    nestedLists()

    // Test inheritance
    val myList = MyList()
    myList.add("inherited")
    println(myList.customOp())

    // Test type constraint
    val constrained = constrain(list)
    println(constrained.size)

    // Test extension function
    println(list.customExtension())
}
