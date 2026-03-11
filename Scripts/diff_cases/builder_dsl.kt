fun main() {
    val s = buildString {
        append("hello ")
        append("world")
    }
    println(s)

    val list = buildList {
        add(1)
        add(2)
        add(3)
    }
    println(list.size)
    println(list.get(0))
    println(list.get(1))
    println(list.get(2))

    val map = buildMap {
        put("a", 1)
        put("b", 2)
    }
    println(map.size)
    println(map.get("a"))
    println(map.get("b"))
}
