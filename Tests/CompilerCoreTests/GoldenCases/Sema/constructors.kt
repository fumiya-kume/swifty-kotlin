class Point(val x: Int, val y: Int)

class Named(val name: String) {
    constructor() : this("default")
}

fun main() {
    val p = Point(1, 2)
    val n = Named("hello")
    val d = Named()
}
