# Releasing StatusArc

The source repository deliberately contains no signing identity or notarization
credentials.

## Before a public binary release

1. Set a unique reverse-DNS bundle identifier for your distribution.
2. Choose your Apple Developer team in Xcode.
3. Confirm version and build numbers.
4. Run the manual test plan in `docs/TESTING.md`.
5. Review `CHANGELOG.md`.
6. Archive the app in Xcode.
7. Sign with the appropriate Developer ID identity if distributing outside the
   Mac App Store.
8. Notarize the exported app using Apple's current notarization workflow.
9. Staple the notarization ticket when applicable.
10. Test the exact downloadable artifact on another Mac if possible.

Because Apple's signing and notarization tooling evolves, use current Apple
documentation when producing a release binary rather than copying old command
examples blindly.

## GitHub release

Suggested first tag:

```bash
git tag -a v1.0.0 -m "StatusArc 1.0.0"
git push origin v1.0.0
```

Attach only artifacts you have actually built, signed, and tested. Never commit
developer certificates, private keys, notarization credentials, or App Store
Connect API secrets.
