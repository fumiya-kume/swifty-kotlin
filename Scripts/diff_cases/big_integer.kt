import java.math.BigInteger

fun main() {
    // BigInteger(String) constructor
    val a = BigInteger("100")
    val b = BigInteger("200")
    println("ctorSmall: ${a.toString()}")

    val c = BigInteger("12345678901234567890")
    println("fromString: ${c.toString()}")

    // add()
    val sum = a.add(b)
    println("add: ${sum.toString()}")

    // subtract()
    val diff = b.subtract(a)
    println("subtract: ${diff.toString()}")

    // multiply()
    val product = a.multiply(b)
    println("multiply: ${product.toString()}")

    // divide()
    val quotient = b.divide(a)
    println("divide: ${quotient.toString()}")

    // gcd()
    val x = BigInteger("12")
    val y = BigInteger("8")
    val g = x.gcd(y)
    println("gcd: ${g.toString()}")

    // abs()
    val neg = BigInteger("-42")
    println("abs: ${neg.abs().toString()}")

    // pow()
    val base = BigInteger("2")
    val powered = base.pow(10)
    println("pow: ${powered.toString()}")

    // toInt()
    val small = BigInteger("42")
    println("toInt: ${small.toInt()}")

    // toLong()
    println("toLong: ${small.toLong()}")

    // toString()
    println("toString: ${small.toString()}")

    println("OK")
}
