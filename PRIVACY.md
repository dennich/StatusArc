# Privacy

StatusArc is designed as a local macOS utility.

## Data sent off the Mac

StatusArc does not contain analytics, telemetry, advertising, crash-reporting
SDKs, or an application backend. The app itself does not transmit usage data.

Normal macOS system components may of course communicate with Apple or network
services independently of StatusArc.

## Battery and power information

Battery state is read locally from IOKit power-source APIs.

## Network information

StatusArc reads the primary active interface from SystemConfiguration and reads
Wi-Fi state through CoreWLAN.

### Location permission

macOS restricts access to nearby Wi-Fi network names (SSIDs). StatusArc asks
for Location permission only when the user requests a nearby-network scan.

StatusArc does not request location coordinates and does not store a location
history.

If Location access is denied, the core status icon can still work, but nearby
Wi-Fi network names may not be available.

### Wi-Fi passwords

For a secured personal Wi-Fi network, StatusArc can ask CoreWLAN for an
existing saved password in the macOS keychain. This is used only to attempt the
requested association.

StatusArc does not log the password, save a separate copy, upload it, or expose
it in the menu.

macOS remains responsible for keychain access control and may show its own
authorization prompts.

## Keyboard input source

The current and enabled keyboard/input sources are read locally using macOS
Text Input Source Services. StatusArc does not inspect typed text or keystrokes.

## Contributions

A contribution that introduces telemetry, networking, new permissions,
credential handling, or persistent user data must document that behavior in
both this file and the README.
