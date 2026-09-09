package golden.sema

fun charSequenceSumDouble(source: CharSequence): Double =
    source.sumOf { it.code.toDouble() }

fun charSequenceSumInt(source: CharSequence): Int =
    source.sumOf { it.code }

fun charSequenceSumLong(source: CharSequence): Long =
    source.sumOf { it.code.toLong() }

fun charSequenceSumUInt(source: CharSequence): UInt =
    source.sumOf { it.code.toUInt() }

fun charSequenceSumULong(source: CharSequence): ULong =
    source.sumOf { it.code.toULong() }

fun stringSum(source: String): Int = source.sumOf { it.code }

fun stringBuilderSum(source: StringBuilder): Long =
    source.sumOf { it.code.toLong() }
