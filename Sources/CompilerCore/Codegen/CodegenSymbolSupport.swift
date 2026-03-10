import Foundation

enum CodegenSymbolSupport {
    static func fileFacadeNames(from ast: ASTModule?) -> [Int32: String] {
        guard let ast else {
            return [:]
        }
        return ast.files.reduce(into: [:]) { partial, file in
            guard let name = fileFacadeName(for: file) else {
                return
            }
            partial[file.fileID.rawValue] = name
        }
    }

    static func fileFacadeName(for file: ASTFile) -> String? {
        for annotation in file.annotations where annotation.useSiteTarget == "file" {
            guard annotation.name == "JvmName" || annotation.name == "kotlin.jvm.JvmName",
                  let firstArgument = annotation.arguments.first
            else {
                continue
            }
            let trimmed = firstArgument.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

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
