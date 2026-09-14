import AppKit
import Carbon

struct InputSourceIdentity {
    let localizedName: String
    let icon: NSImage?
}

enum InputSourceIdentityResolver {
    static func resolve(_ source: TISInputSource) -> InputSourceIdentity {
        let localizedName = stringProperty(source, key: kTISPropertyLocalizedName)
            ?? "Input Source"

        return InputSourceIdentity(
            localizedName: localizedName,
            icon: icon(for: source)
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

    private static func icon(for source: TISInputSource) -> NSImage? {
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyIconImageURL) {
            let iconURL = Unmanaged<CFURL>
                .fromOpaque(pointer)
                .takeUnretainedValue() as URL
            if let image = NSImage(contentsOf: iconURL) {
                return image
            }
        }

        // Some built-in keyboard layouts expose their public legacy IconRef but
        // no image URL. This documented fallback preserves the same identity
        // artwork macOS associates with that input source.
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyIconRef) {
            let iconRef = unsafeBitCast(pointer, to: IconRef.self)
            return NSImage(iconRef: iconRef)
        }

        return nil
    }
}
