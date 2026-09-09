// KSP-627: the collection aliases (ArrayList / HashSet / HashMap / LinkedHashMap)
// and the concrete LinkedHashSet class are source-backed
// (Sources/CompilerCore/Stdlib/kotlin/collections/CollectionAliases.kt).
// This locks their observable behavior — construction (empty, capacity and copy
// forms), mutation and alias-typed declarations — against kotlinc.
// Two constructs are intentionally left out because they are broken independently
// of this migration (both reproduce on master): subclassing
// (`class Tags : LinkedHashSet<String>()`, BUG-185) and assigning a LinkedHashSet
// to a `MutableSet` binding under `--stdlib-library` (BUG-186).

fun fillList(target: ArrayList<Int>) {
    target.add(1)
    target.add(2)
}

fun main() {
    val list = ArrayList<Int>()
    fillList(list)
    println(list.size)
    println(list.joinToString(","))

    val sized = ArrayList<Int>(8)
    sized.add(3)
    println(sized)

    val copied = ArrayList(listOf(4, 5))
    println(copied.joinToString(","))

    val set = HashSet<String>()
    set.add("a")
    set.add("a")
    println(set.size)
    println(set.contains("a"))
    println(set.remove("a"))
    println(set.contains("a"))

    val linked = LinkedHashSet<Int>()
    linked.add(6)
    linked.add(7)
    println(linked.size)

    val linkedOf = linkedSetOf(1, 2, 3)
    println(linkedOf.size)
    println(linkedOf.remove(2))
    println(linkedOf.contains(2))

    val linkedCopy = LinkedHashSet(listOf(8, 8, 9))
    println(linkedCopy.size)

    val map = HashMap<String, Int>()
    map["one"] = 1
    println(map["one"])
    println(map.size)

    val linkedMap = LinkedHashMap<String, Int>()
    linkedMap["two"] = 2
    linkedMap["three"] = 3
    println(linkedMap.size)
    println(linkedMap.containsKey("two"))
}
