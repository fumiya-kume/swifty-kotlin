fun main() {
    val dec = 42
    val decZero = 0
    val decLarge = 1234567890
    val decUnderscore = 1_000_000
    val decUnder2 = 1_2_3

    val hex = 0xFF
    val hexUpper = 0XAB
    val hexUnderscore = 0xFF_FF
    val hexMixed = 0xAB_cd_EF

    val bin = 0b1010
    val binUpper = 0B1100
    val binUnderscore = 0b1010_0101

    val longDec = 42L
    val longHex = 0xFFL
    val longBin = 0b1010L
    val longUnder = 1_000L

    val dbl = 1.0
    val dblFrac = 3.14
    val dblExp = 1e10
    val dblExpPlus = 1e+5
    val dblExpMinus = 1e-3
    val dblDotExp = 1.5e10
    val dblDotExpMinus = 2.0e-4

    val flt = 1.0f
    val fltUpper = 1.0F
    val fltInt = 42f
    val fltIntUpper = 42F
    val fltExp = 1e5f
    val fltExpUpper = 1e5F
}
