package golden.sema

interface LeftBound
interface RightBound

class BothBound : LeftBound, RightBound
class LeftOnly : LeftBound

fun <T> pickFirst(a: T, b: T): T where T : LeftBound, T : RightBound = a

fun usePick() {
    val ok = pickFirst(BothBound(), BothBound())
    val ng = pickFirst(LeftOnly(), LeftOnly())
}
