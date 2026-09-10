import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

suspend fun probe(): Any? =
    suspendCoroutineUninterceptedOrReturn { COROUTINE_SUSPENDED }

fun main() {
    println(COROUTINE_SUSPENDED === COROUTINE_SUSPENDED)
}
