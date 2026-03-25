fun interface Transformer { fun transform(s: String): String }
fun apply(t: Transformer, s: String) = t.transform(s)
fun main() {
    val upper = Transformer { it.uppercase() }
    println(upper.transform("hello"))
    println(apply({ it.reversed() }, "world"))
    println(apply(Transformer { it + "!" }, "hi"))
}
// SKIP-DIFF: SAM conversion parity pending
