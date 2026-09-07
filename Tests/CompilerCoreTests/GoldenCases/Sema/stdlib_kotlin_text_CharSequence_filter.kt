package golden.sema

fun charSequenceFilter(source: CharSequence): CharSequence =
    source.filter { it == 'a' }

fun charSequenceFilterIndexed(source: CharSequence): CharSequence =
    source.filterIndexed { index, _ -> index % 2 == 0 }

fun charSequenceFilterNot(source: CharSequence): CharSequence =
    source.filterNot { it == 'x' }

fun charSequenceFilterTo(source: CharSequence, destination: Appendable): Appendable =
    source.filterTo(destination) { it != '-' }

fun charSequenceFilterNotTo(source: CharSequence, destination: Appendable): Appendable =
    source.filterNotTo(destination) { it != '-' }

fun charSequenceFilterIndexedTo(source: CharSequence, destination: Appendable): Appendable =
    source.filterIndexedTo(destination) { index, _ -> index % 2 == 0 }
