import java.io.Closeable

// Basic Closeable.use {} usage
class MyResource(val name: String) : Closeable {
    override fun close() {
        println("$name closed")
    }
}

// use {} returns the lambda result and calls close
fun testBasicUse() {
    val result = MyResource("r1").use {
        println("using r1")
        42
    }
    println("result=$result")
}

// use {} calls close even on normal return
fun testCloseCalledOnNormalReturn() {
    val r = MyResource("r2")
    r.use {
        println("using r2")
    }
    println("after use r2")
}

// use {} with null receiver via safe call
fun testNullableUse() {
    val r: MyResource? = null
    val result = r?.use {
        println("should not print")
        99
    }
    println("null result=$result")
}

// use {} returning value from lambda
fun testReturnValue() {
    val s = MyResource("r5").use {
        "hello from use"
    }
    println(s)
}

// Nested use {}
fun testNestedUse() {
    MyResource("outer").use {
        println("in outer")
        MyResource("inner").use {
            println("in inner")
        }
        println("after inner")
    }
    println("after outer")
}

fun main() {
    testBasicUse()
    println("---")
    testCloseCalledOnNormalReturn()
    println("---")
    testNullableUse()
    println("---")
    testReturnValue()
    println("---")
    testNestedUse()
}
