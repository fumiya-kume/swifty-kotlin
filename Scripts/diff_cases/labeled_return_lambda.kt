fun main() {
    listOf(1, 2, 3, 4, 5).forEach {
        if (it == 3) return@forEach
        println(it)
    }
    println("after forEach")
    val result = run {
        if (true) return@run "early"
        "late"
    }
    println(result)
}
