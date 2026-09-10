package golden.sema

fun charSequenceHasSurrogatePairAt(cs: CharSequence, index: Int): Boolean =
    cs.hasSurrogatePairAt(index)

fun stringHasSurrogatePairAt(): Boolean = "\uD83D\uDE00".hasSurrogatePairAt(0)

fun emptyHasSurrogatePairAt(): Boolean = "".hasSurrogatePairAt(0)
