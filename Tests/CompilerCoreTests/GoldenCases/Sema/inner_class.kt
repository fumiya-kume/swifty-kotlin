package golden.sema

class Outer(val x: Int) {
    val y: Int = x

    inner class Inner {
        fun getY(): Int = this@Outer.y
    }

    class Nested {
        fun tryAccess(): Int = this@Outer.y
    }
}

fun main() {
    val outer = Outer(42)
    val inner = outer.Inner()
    val result = inner.getY()
}
