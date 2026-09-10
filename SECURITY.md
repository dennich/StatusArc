# Security Policy

## Supported version

Security fixes are expected to target the latest release on the `main` branch.

## Reporting a vulnerability

Please do not publish credentials, private network information, exploit details,
or other sensitive material in a public issue.

If the repository has GitHub Private Vulnerability Reporting enabled, use that
channel. Otherwise, open a minimal public issue stating that you have a
security report and ask the maintainer for a private contact channel.

Useful information includes:

- affected StatusArc version or commit;
- macOS version and architecture;
- reproduction conditions;
- security impact;
- whether Wi-Fi, keychain access, or permissions are involved.

Please give maintainers a reasonable opportunity to investigate before public
disclosure.

## Security design notes

StatusArc should not log Wi-Fi passwords or other secrets. Changes involving
CoreWLAN, Keychain APIs, Location permission, process execution, private APIs,
or Accessibility permissions deserve extra review.
