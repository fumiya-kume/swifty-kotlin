// SKIP-DIFF
import kotlinx.coroutines.*

// TEST-CORO-003: SupervisorJob — child failure does not cancel siblings;
// supervisorScope provides the same semantics for a block.

fun main() = runBlocking {
    // 1. SupervisorJob: one child fails, other continues
    val supervisor = SupervisorJob()
    val scope = CoroutineScope(coroutineContext + supervisor)

    val child1 = scope.launch {
        delay(1)
        println("child1 done")
    }
    val child2 = scope.launch {
        delay(1)
        throw RuntimeException("child2 failed")
    }

    // wait for both
    child1.join()
    child2.join()
    println("child1 active: ${child1.isCompleted}")
    println("child2 failed: ${child2.isCancelled || child2.isCompleted}")
    supervisor.cancel()

    // 2. supervisorScope block
    supervisorScope {
        val a = launch {
            println("a ok")
        }
        val b = launch {
            throw IllegalStateException("b failed")
        }
        a.join()
        b.join()
    }

    // 3. Parent job is not cancelled when supervisorScope child fails
    println("parent still running")

    println("done")
}
