import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testNativeConcurrentTopLevelFunctionsExecuteThroughSourceWrappers() throws {
        try compileAndRunKotlin(
            """
            @file:Suppress("DEPRECATION_ERROR")
            @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

            import kotlin.native.concurrent.TransferMode
            import kotlin.native.concurrent.atomicLazy
            import kotlin.native.concurrent.freeze
            import kotlin.native.concurrent.waitForMultipleFutures
            import kotlin.native.concurrent.withWorker

            fun main() {
                println(atomicLazy { 40 + 2 }.value)
                println("stable".freeze())
                val result = withWorker("ksp-1216", true) {
                    val future = execute(TransferMode.SAFE, { 35 }) { input -> input + 7 }
                    println(waitForMultipleFutures(listOf(future), 1000).size)
                    future.result
                }
                println(result)
            }
            """,
            expectedOutput: "42\nstable\n1\n42\n"
        )
    }
}
