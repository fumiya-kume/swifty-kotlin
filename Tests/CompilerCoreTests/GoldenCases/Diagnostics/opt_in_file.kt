@file:OptIn(ExperimentalFileApi::class)

package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalFileApi

@ExperimentalFileApi
fun unstableFile(): Int = 1

fun callerFile(): Int = unstableFile()
