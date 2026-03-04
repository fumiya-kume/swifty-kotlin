fun main() {
    val len = "hello".let { it.length }
    println(len)

    val runLen = "hello".run { length }
    println(runLen)

    "test".also { println(it) }

    val alsoResult = "hello".also { println(it) }
    println(alsoResult)

    val withLen = with("hello") { length }
    println(withLen)
}
