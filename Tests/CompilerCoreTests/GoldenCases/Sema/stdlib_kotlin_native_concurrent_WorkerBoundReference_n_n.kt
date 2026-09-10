@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.WorkerBoundReference

fun construct(value: String): WorkerBoundReference<String> = WorkerBoundReference(value)
