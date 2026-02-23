import Foundation

extension DataFlowSemaPassPhase {
    func discoverLibraryDirectories(searchPaths: [String]) -> [String] {
        let fm = FileManager.default
        var found: Set<String> = []
        for rawPath in searchPaths {
            let path = URL(fileURLWithPath: rawPath).path
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if path.hasSuffix(".kklib") {
                found.insert(path)
                continue
            }
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".kklib") {
                found.insert(URL(fileURLWithPath: path).appendingPathComponent(entry).path)
            }
        }
        return found.sorted()
    }

    func resolveLibraryManifestInfo(
        libraryDir: String,
        currentTarget: TargetTriple,
        diagnostics: DiagnosticEngine
    ) -> LibraryManifestInfo {
        let manifestPath = URL(fileURLWithPath: libraryDir).appendingPathComponent("manifest.json").path
        if let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
           let object = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] {
            var isValid = true

            isValid = validateManifestSchema(
                object: object,
                libraryDir: libraryDir,
                currentTarget: currentTarget,
                diagnostics: diagnostics
            ) && isValid

            let metadataPath: String
            if let metadataRelativePath = object["metadata"] as? String, !metadataRelativePath.isEmpty {
                metadataPath = URL(fileURLWithPath: libraryDir).appendingPathComponent(metadataRelativePath).path
            } else {
                metadataPath = URL(fileURLWithPath: libraryDir).appendingPathComponent("metadata.bin").path
            }
            let inlineKIRDir: String?
            if let inlineRelativePath = object["inlineKIRDir"] as? String, !inlineRelativePath.isEmpty {
                inlineKIRDir = URL(fileURLWithPath: libraryDir).appendingPathComponent(inlineRelativePath).path
            } else {
                inlineKIRDir = nil
            }

            isValid = validateManifestPaths(
                object: object,
                libraryDir: libraryDir,
                metadataPath: metadataPath,
                inlineKIRDir: inlineKIRDir,
                diagnostics: diagnostics
            ) && isValid

            return LibraryManifestInfo(metadataPath: metadataPath, inlineKIRDir: inlineKIRDir, isValid: isValid)
        }
        return LibraryManifestInfo(
            metadataPath: URL(fileURLWithPath: libraryDir).appendingPathComponent("metadata.bin").path,
            inlineKIRDir: URL(fileURLWithPath: libraryDir).appendingPathComponent("inline-kir").path,
            isValid: true
        )
    }

    private func validateManifestSchema(
        object: [String: Any],
        libraryDir: String,
        currentTarget: TargetTriple,
        diagnostics: DiagnosticEngine
    ) -> Bool {
        let libName = URL(fileURLWithPath: libraryDir).lastPathComponent
        var isValid = true

        if let formatVersion = object["formatVersion"] as? Int {
            if formatVersion != 1 {
                diagnostics.error(
                    "KSWIFTK-LIB-0010",
                    "Unsupported formatVersion \(formatVersion) in \(libName)/manifest.json (expected 1)",
                    range: nil
                )
                isValid = false
            }
        } else {
            diagnostics.error(
                "KSWIFTK-LIB-0010",
                "Missing or invalid 'formatVersion' in \(libName)/manifest.json",
                range: nil
            )
            isValid = false
        }

        if let moduleName = object["moduleName"] as? String {
            if moduleName.isEmpty {
                diagnostics.error(
                    "KSWIFTK-LIB-0011",
                    "Empty 'moduleName' in \(libName)/manifest.json",
                    range: nil
                )
                isValid = false
            }
        } else {
            diagnostics.error(
                "KSWIFTK-LIB-0011",
                "Missing 'moduleName' in \(libName)/manifest.json",
                range: nil
            )
            isValid = false
        }

        let supportedLanguageVersions: Set<String> = ["2.3.10"]
        if let langVersion = object["kotlinLanguageVersion"] as? String {
            if !supportedLanguageVersions.contains(langVersion) {
                diagnostics.error(
                    "KSWIFTK-LIB-0012",
                    "Unsupported kotlinLanguageVersion '\(langVersion)' in \(libName)/manifest.json (expected one of: \(supportedLanguageVersions.sorted().joined(separator: ", ")))",
                    range: nil
                )
                isValid = false
            }
        } else {
            diagnostics.warning(
                "KSWIFTK-LIB-0012",
                "Missing 'kotlinLanguageVersion' in \(libName)/manifest.json",
                range: nil
            )
        }

        if let targetString = object["target"] as? String, !targetString.isEmpty {
            let currentTargetString = "\(currentTarget.arch)-\(currentTarget.vendor)-\(currentTarget.os)"
            if targetString != currentTargetString {
                diagnostics.error(
                    "KSWIFTK-LIB-0013",
                    "Library \(libName) targets '\(targetString)' but current compilation targets '\(currentTargetString)'",
                    range: nil
                )
                isValid = false
            }
        } else {
            diagnostics.warning(
                "KSWIFTK-LIB-0013",
                "Missing 'target' in \(libName)/manifest.json; skipping compatibility check",
                range: nil
            )
        }

        return isValid
    }

    private func validateManifestPaths(
        object: [String: Any],
        libraryDir: String,
        metadataPath: String,
        inlineKIRDir: String?,
        diagnostics: DiagnosticEngine
    ) -> Bool {
        let fm = FileManager.default
        let libName = URL(fileURLWithPath: libraryDir).lastPathComponent
        var isValid = true

        if !fm.fileExists(atPath: metadataPath) {
            diagnostics.error(
                "KSWIFTK-LIB-0014",
                "Metadata file not found at '\(metadataPath)' referenced by \(libName)/manifest.json",
                range: nil
            )
            isValid = false
        }

        if let objectPaths = object["objects"] as? [String] {
            for relativePath in objectPaths {
                let fullPath = URL(fileURLWithPath: libraryDir).appendingPathComponent(relativePath).path
                if !fm.fileExists(atPath: fullPath) {
                    diagnostics.warning(
                        "KSWIFTK-LIB-0014",
                        "Object file not found at '\(relativePath)' referenced by \(libName)/manifest.json",
                        range: nil
                    )
                }
            }
        }

        if let inlineDir = inlineKIRDir {
            var isDirectory: ObjCBool = false
            if !fm.fileExists(atPath: inlineDir, isDirectory: &isDirectory) {
                diagnostics.warning(
                    "KSWIFTK-LIB-0014",
                    "Inline KIR directory not found at '\(inlineDir)' referenced by \(libName)/manifest.json",
                    range: nil
                )
            } else if !isDirectory.boolValue {
                diagnostics.warning(
                    "KSWIFTK-LIB-0014",
                    "Inline KIR path '\(inlineDir)' is not a directory in \(libName)/manifest.json",
                    range: nil
                )
            }
        }

        return isValid
    }
}
