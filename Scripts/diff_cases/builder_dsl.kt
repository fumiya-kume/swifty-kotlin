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
    println(list)

    val map = buildMap {
        put("a", 1)
        put("b", 2)
    }
    println(map)
}
