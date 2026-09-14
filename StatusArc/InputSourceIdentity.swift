import AppKit
import Carbon

struct InputSourceIdentity {
    let localizedName: String
    let compactLabel: String
}

enum InputSourceIdentityResolver {
    static func resolve(_ source: TISInputSource) -> InputSourceIdentity {
        let localizedName = stringProperty(source, key: kTISPropertyLocalizedName)
            ?? "Input Source"

        return InputSourceIdentity(
            localizedName: localizedName,
            compactLabel: compactLabel(
                for: source,
                localizedName: localizedName
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

    private static func compactLabel(
        for source: TISInputSource,
        localizedName: String
    ) -> String {
        if boolProperty(source, key: kTISPropertyInputSourceIsASCIICapable),
           let firstLetter = localizedName.first(where: \.isLetter) {
            return String(firstLetter).uppercased()
        }

        if let language = arrayProperty(
            source,
            key: kTISPropertyInputSourceLanguages
        )?.first {
            let languageCode = language
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first
                .map(String.init) ?? language
            let languageLocale = Locale(identifier: languageCode)
            let nativeName = languageLocale.localizedString(
                forLanguageCode: languageCode
            ) ?? localizedName
            let letters = nativeName.filter(\.isLetter)
            if !letters.isEmpty {
                return String(letters.prefix(2)).uppercased(with: languageLocale)
            }
        }

        let letters = localizedName.filter(\.isLetter)
        return letters.first.map { String($0).uppercased() } ?? "⌨"
    }
}
