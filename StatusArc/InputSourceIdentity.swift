import Carbon

struct InputSourceIdentity {
    let identifier: String
    let localizedName: String
    let code: String
}

enum InputSourceIdentityResolver {
    static func resolve(_ source: TISInputSource) -> InputSourceIdentity {
        let identifier = stringProperty(source, key: kTISPropertyInputSourceID)
            ?? "unknown"
        let localizedName = stringProperty(source, key: kTISPropertyLocalizedName)
            ?? "Input Source"
        let language = arrayProperty(source, key: kTISPropertyInputSourceLanguages)?.first

        return InputSourceIdentity(
            identifier: identifier,
            localizedName: localizedName,
            code: sourceSpecificCode(
                identifier: identifier,
                localizedName: localizedName,
                language: language
            )
        )
    }

    static func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<CFString>
            .fromOpaque(pointer)
            .takeUnretainedValue() as String
    }

    static func boolProperty(_ source: TISInputSource, key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return false
        }

        let value = Unmanaged<CFBoolean>
            .fromOpaque(pointer)
            .takeUnretainedValue()
        return CFBooleanGetValue(value)
    }

    private static func arrayProperty(
        _ source: TISInputSource,
        key: CFString
    ) -> [String]? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<CFArray>
            .fromOpaque(pointer)
            .takeUnretainedValue() as? [String]
    }

    private static func sourceSpecificCode(
        identifier: String,
        localizedName: String,
        language: String?
    ) -> String {
        let sourceText = "\(identifier) \(localizedName)".lowercased()
        let namedLayouts: [(tokens: [String], code: String)] = [
            (["u.s. international", "usinternational"], "UI"),
            (["dvorak"], "DV"),
            (["colemak"], "CM"),
            (["british"], "GB"),
            (["australian"], "AU"),
            (["canadian"], "CA"),
            (["u.s.", "keylayout.us"], "US"),
            (["abc"], "AB"),
            (["ukrain"], "UA")
        ]

        for layout in namedLayouts where layout.tokens.contains(where: sourceText.contains) {
            return layout.code
        }

        if let language {
            let components = language
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .map(String.init)

            if let region = components.dropFirst().first(where: {
                $0.count == 2 && $0.allSatisfy(\.isLetter)
            }) {
                return region.uppercased()
            }

            if let base = components.first {
                let languageCodes = [
                    "uk": "UA",
                    "de": "DE",
                    "fr": "FR",
                    "es": "ES",
                    "it": "IT",
                    "pt": "PT",
                    "pl": "PL",
                    "ja": "JA",
                    "ko": "KO",
                    "zh": "ZH"
                ]
                if let code = languageCodes[base.lowercased()] {
                    return code
                }

                let letters = base.filter(\.isLetter)
                if letters.count >= 2 {
                    return String(letters.prefix(2)).uppercased()
                }
            }
        }

        let letters = localizedName.filter(\.isLetter)
        if letters.count >= 2 {
            return String(letters.prefix(2)).uppercased()
        }

        return "--"
    }
}
