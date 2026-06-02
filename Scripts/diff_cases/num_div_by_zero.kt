// SKIP-DIFF: SPEC-NUM-0002 — integer division/remainder by zero must throw a
// catchable kotlin.ArithmeticException ("/ by zero"). kswiftk instead raises a
// hardware SIGFPE and aborts the process (uncatchable), so the try/catch below
// never runs. Floating-point division by zero is already correct (Infinity/NaN).
// Remove the SKIP-DIFF marker once codegen emits a divisor zero-check.
fun main() {
    val n = 1
    val zero = 0
    try {
        println(n / zero)
    } catch (e: ArithmeticException) {
        println("int div: ArithmeticException")
    }
    try {
        println(n % zero)
    } catch (e: ArithmeticException) {
        println("int rem: ArithmeticException")
    }
    val d = 1.0
    val dz = 0.0
    println(d / dz)
    println((-d) / dz)
    println(dz / dz)
}
