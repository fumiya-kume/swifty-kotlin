package golden.sema

class Outer(val x: Int) {
    inner class Inner {
        fun getX(): Int = this@Outer.x
    }

    class Nested {
        fun tryAccess(): Int = this@Outer.x
    }
}

fun main() {
    val outer = Outer(42)
    val inner = outer.Inner()
    val result = inner.getX()
}
