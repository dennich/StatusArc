import AppKit

struct HiddenWiFiCredentials {
    let networkName: String
    let password: String?
}

enum WiFiDialogs {
    static func requestHiddenNetwork() -> HiddenWiFiCredentials? {
        HiddenNetworkDialogController().runModal()
    }

    static func requestPassword(networkName: String) -> String? {
        PasswordDialogController(networkName: networkName).runModal()
    }
}

private final class HiddenNetworkDialogController: NSObject, NSTextFieldDelegate {
    private let alert = NSAlert()
    private let nameField = NSTextField()
    private let securityPopup = NSPopUpButton()
    private let securePasswordField = NSSecureTextField()
    private let visiblePasswordField = NSTextField()
    private let showPasswordButton = NSButton(
        checkboxWithTitle: "Show password",
        target: nil,
        action: nil
    )
    private var joinButton: NSButton!

    override init() {
        super.init()

        alert.messageText = "Join Other Network"
        alert.informativeText = "Enter the name and security used by the Wi-Fi network."
        joinButton = alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Cancel")

        nameField.placeholderString = "Network name"
        nameField.delegate = self
        nameField.setAccessibilityLabel("Network name")

        securityPopup.addItems(withTitles: [
            "WPA/WPA2 Personal",
            "WPA3 Personal",
            "None"
        ])
        securityPopup.target = self
        securityPopup.action = #selector(securityChanged)
        securityPopup.setAccessibilityLabel("Security")

        configurePasswordFields()

        let passwordContainer = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        for field in [securePasswordField, visiblePasswordField] {
            field.frame = passwordContainer.bounds
            field.autoresizingMask = [.width, .height]
            passwordContainer.addSubview(field)
        }

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Network Name:"), nameField],
            [NSTextField(labelWithString: "Security:"), securityPopup],
            [NSTextField(labelWithString: "Password:"), passwordContainer],
            [NSView(), showPasswordButton]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 280
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 380, height: 112)
        alert.accessoryView = grid

        updateValidation()
    }

    func runModal() -> HiddenWiFiCredentials? {
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let password = isOpenNetwork ? "" : currentPassword
        return HiddenWiFiCredentials(
            networkName: name,
            password: password.isEmpty ? nil : password
        )
    }

    func controlTextDidChange(_ obj: Notification) {
        syncPasswordFields(changed: obj.object as? NSTextField)
        updateValidation()
    }

    private func configurePasswordFields() {
        securePasswordField.placeholderString = "Password"
        visiblePasswordField.placeholderString = "Password"
        visiblePasswordField.isHidden = true

        for field in [securePasswordField, visiblePasswordField] {
            field.delegate = self
            field.setAccessibilityLabel("Password")
        }

        showPasswordButton.target = self
        showPasswordButton.action = #selector(showPasswordChanged)
    }

    private var isOpenNetwork: Bool {
        securityPopup.indexOfSelectedItem == 2
    }

    private var currentPassword: String {
        visiblePasswordField.isHidden
            ? securePasswordField.stringValue
            : visiblePasswordField.stringValue
    }

    private func syncPasswordFields(changed field: NSTextField?) {
        guard let field else { return }
        if field === securePasswordField {
            visiblePasswordField.stringValue = field.stringValue
        } else if field === visiblePasswordField {
            securePasswordField.stringValue = field.stringValue
        }
    }

    @objc private func securityChanged() {
        let enabled = !isOpenNetwork
        securePasswordField.isEnabled = enabled
        visiblePasswordField.isEnabled = enabled
        showPasswordButton.isEnabled = enabled
        updateValidation()
    }

    @objc private func showPasswordChanged() {
        let show = showPasswordButton.state == .on
        visiblePasswordField.stringValue = securePasswordField.stringValue
        securePasswordField.isHidden = show
        visiblePasswordField.isHidden = !show
        alert.window.makeFirstResponder(show ? visiblePasswordField : securePasswordField)
    }

    private func updateValidation() {
        joinButton.isEnabled = !nameField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}

private final class PasswordDialogController: NSObject, NSTextFieldDelegate {
    private let alert = NSAlert()
    private let secureField = NSSecureTextField()
    private let visibleField = NSTextField()
    private let showPasswordButton = NSButton(
        checkboxWithTitle: "Show password",
        target: nil,
        action: nil
    )
    private var joinButton: NSButton!

    init(networkName: String) {
        super.init()

        alert.messageText = "Password for “\(networkName)”"
        alert.informativeText = "Enter the Wi-Fi password."
        joinButton = alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Cancel")

        for field in [secureField, visibleField] {
            field.frame = NSRect(x: 0, y: 30, width: 280, height: 24)
            field.placeholderString = "Password"
            field.delegate = self
            field.setAccessibilityLabel("Password")
        }
        visibleField.isHidden = true

        showPasswordButton.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        showPasswordButton.target = self
        showPasswordButton.action = #selector(showPasswordChanged)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 54))
        container.addSubview(secureField)
        container.addSubview(visibleField)
        container.addSubview(showPasswordButton)
        alert.accessoryView = container
        joinButton.isEnabled = false
    }

    func runModal() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = secureField
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return currentPassword
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === secureField {
            visibleField.stringValue = field.stringValue
        } else if field === visibleField {
            secureField.stringValue = field.stringValue
        }
        joinButton.isEnabled = !currentPassword.isEmpty
    }

    private var currentPassword: String {
        visibleField.isHidden ? secureField.stringValue : visibleField.stringValue
    }

    @objc private func showPasswordChanged() {
        let show = showPasswordButton.state == .on
        visibleField.stringValue = secureField.stringValue
        secureField.isHidden = show
        visibleField.isHidden = !show
        alert.window.makeFirstResponder(show ? visibleField : secureField)
    }
}
