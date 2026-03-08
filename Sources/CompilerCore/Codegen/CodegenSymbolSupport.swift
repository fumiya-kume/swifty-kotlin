import Foundation

enum CodegenSymbolSupport {
    static func cFunctionSymbol(
        for function: KIRFunction,
        interner: StringInterner,
        fileFacadeNamesByFileID: [Int32: String] = [:]
    ) -> String {
        let rawName = interner.resolve(function.name)
        let facadePrefix = if let fileID = function.sourceRange?.start.file.rawValue,
                              let facadeName = fileFacadeNamesByFileID[fileID],
                              !facadeName.isEmpty
        {
            "\(sanitizeForCSymbol(facadeName))_"
        } else {
            ""
        }
        let safeName = sanitizeForCSymbol(rawName)
        let suffix = abs(function.symbol.rawValue)
        return "kk_fn_\(facadePrefix)\(safeName)_\(suffix)"
    }

    private static func sanitizeForCSymbol(_ text: String) -> String {
        if text.isEmpty {
            return "_"
        }
        var result = ""
        for (index, scalar) in text.unicodeScalars.enumerated() {
            let isAlphaNum = CharacterSet.alphanumerics.contains(scalar)
            if index == 0 {
                if CharacterSet.letters.contains(scalar) || scalar == "_" {
                    result.append(Character(scalar))
                } else if isAlphaNum {
                    result.append("_")
                    result.append(Character(scalar))
                } else {
                    result.append("_")
                }
            } else if isAlphaNum || scalar == "_" {
                result.append(Character(scalar))
            } else {
                result.append("_")
            }
        }
        if result.isEmpty {
            return "_"
        }
        return result
    }
}
