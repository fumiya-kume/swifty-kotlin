// SKIP-DIFF: expect/actual cases require kotlinc multiplatform flags that the current diff harness does not pass.
package diff.kmp

expect fun <T> identity(value: T): T
actual fun <T> identity(value: T): T = value

expect val platformName: String
actual val platformName: String = "kswift"

fun main() {
    println(platformName)
    println(identity(42))
}
