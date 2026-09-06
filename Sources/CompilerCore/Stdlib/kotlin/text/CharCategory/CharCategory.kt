package kotlin.text

// KSP-1417: CharCategory's public enum API is backed by bundled Kotlin source.

public enum class CharCategory {
    UNASSIGNED,
    UPPERCASE_LETTER,
    LOWERCASE_LETTER,
    TITLECASE_LETTER,
    MODIFIER_LETTER,
    OTHER_LETTER,
    NON_SPACING_MARK,
    ENCLOSING_MARK,
    COMBINING_SPACING_MARK,
    DECIMAL_DIGIT_NUMBER,
    LETTER_NUMBER,
    OTHER_NUMBER,
    SPACE_SEPARATOR,
    LINE_SEPARATOR,
    PARAGRAPH_SEPARATOR,
    CONTROL,
    FORMAT,
    PRIVATE_USE,
    SURROGATE,
    DASH_PUNCTUATION,
    START_PUNCTUATION,
    END_PUNCTUATION,
    CONNECTOR_PUNCTUATION,
    OTHER_PUNCTUATION,
    MATH_SYMBOL,
    CURRENCY_SYMBOL,
    MODIFIER_SYMBOL,
    OTHER_SYMBOL,
    INITIAL_QUOTE_PUNCTUATION,
    FINAL_QUOTE_PUNCTUATION;

    public val code: String
        get() {
            if (this.ordinal == 0) return "Cn"
            if (this.ordinal == 1) return "Lu"
            if (this.ordinal == 2) return "Ll"
            if (this.ordinal == 3) return "Lt"
            if (this.ordinal == 4) return "Lm"
            if (this.ordinal == 5) return "Lo"
            if (this.ordinal == 6) return "Mn"
            if (this.ordinal == 7) return "Me"
            if (this.ordinal == 8) return "Mc"
            if (this.ordinal == 9) return "Nd"
            if (this.ordinal == 10) return "Nl"
            if (this.ordinal == 11) return "No"
            if (this.ordinal == 12) return "Zs"
            if (this.ordinal == 13) return "Zl"
            if (this.ordinal == 14) return "Zp"
            if (this.ordinal == 15) return "Cc"
            if (this.ordinal == 16) return "Cf"
            if (this.ordinal == 17) return "Co"
            if (this.ordinal == 18) return "Cs"
            if (this.ordinal == 19) return "Pd"
            if (this.ordinal == 20) return "Ps"
            if (this.ordinal == 21) return "Pe"
            if (this.ordinal == 22) return "Pc"
            if (this.ordinal == 23) return "Po"
            if (this.ordinal == 24) return "Sm"
            if (this.ordinal == 25) return "Sc"
            if (this.ordinal == 26) return "Sk"
            if (this.ordinal == 27) return "So"
            if (this.ordinal == 28) return "Pi"
            return "Pf"
        }

    public operator fun contains(char: Char): Boolean = char.category == this
}
