fun main() {
    val a = try { "123".toInt() } catch (e: NumberFormatException) { -1 }
    println(a)
    val b = try { "abc".toInt() } catch (e: NumberFormatException) { -1 }
    println(b)
    val c = try { 10 / 2 } catch (e: ArithmeticException) { 0 } finally { println("finally") }
    println(c)
}
