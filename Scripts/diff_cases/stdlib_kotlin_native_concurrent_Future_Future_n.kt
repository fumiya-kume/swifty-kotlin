// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

import kotlin.native.concurrent.Future
import kotlin.native.concurrent.FutureState

fun futureId(future: Future<Int>): Int = future.id
fun futureResult(future: Future<Int>): Int = future.result
fun futureState(future: Future<Int>): FutureState = future.state
fun futureEquals(future: Future<Int>, other: Any?): Boolean = future.equals(other)
fun futureHashCode(future: Future<Int>): Int = future.hashCode()
fun futureToString(future: Future<Int>): String = future.toString()
fun futureConsume(future: Future<Int>): Int = future.consume { value -> value }
