package golden.sema

abstract class CustomList : List<String>

fun listProbe(values: List<Int>): List<Number> = values

fun listFactoryProbe(): List<Int> = List(3) { it }

fun listTypeProbe(value: Any): Boolean = value is List<*>

fun listResidualProbe(values: List<Int>): Int = values[0]
