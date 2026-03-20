fun main() {
    val hm: HashMap<String, Int> = HashMap()
    hm["x"] = 10
    hm["y"] = 20
    val mm: MutableMap<String, Int> = hm
    mm["w"] = 40
    println(mm.size)
    val copy = HashMap(hm)
    println(copy.size)
    println(hm.containsKey("x"))
    println(hm.containsValue(99))
    hm.remove("y")
    println(hm.size)
    println(hm.getOrDefault("missing", -1))
    val empty: HashMap<Int, Int> = HashMap()
    println(empty.isEmpty())
}
