fun main() {
    val list = buildList {
        add(1)
        add(2)
        add(3)
        addAll(listOf(4, 5))
    }
    println(list.size)
    println(list.get(0))
    println(list.get(4))

    val set = buildSet {
        add("a")
        add("b")
        add("a")
        addAll(listOf("c", "d"))
    }
    println(set.size)

    val map = buildMap {
        put("x", 10)
        put("y", 20)
    }
    println(map.size)
    println(map.get("x"))
}
