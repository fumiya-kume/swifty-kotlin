fun main() {
    // HashMap is a typealias for MutableMap
    val hm: HashMap<String, Int> = HashMap()
    hm["x"] = 10
    hm["y"] = 20
    hm["z"] = 30

    // Assignable to MutableMap
    val mm: MutableMap<String, Int> = hm
    mm["w"] = 40
    println(mm.size)

    // HashMap constructed from another map
    val copy = HashMap(hm)
    println(copy.size)

    // containsKey / containsValue
    println(hm.containsKey("x"))
    println(hm.containsValue(99))

    // remove
    hm.remove("z")
    println(hm.size)

    // getOrDefault
    println(hm.getOrDefault("missing", -1))

    // isEmpty
    val empty: HashMap<Int, Int> = HashMap()
    println(empty.isEmpty())

    // putAll
    empty[1] = 100
    empty[2] = 200
    println(empty.size)
}
// SKIP-DIFF: HashMap alias parity pending
