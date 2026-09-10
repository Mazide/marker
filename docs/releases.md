# Publishing a GitHub Release

Only pushing a stable version tag (`vMAJOR.MINOR.PATCH`) publishes a release.
Normal branch pushes and manual workflow runs produce Actions artifacts only.
Tags must point to a commit containing `.github/workflows/signed-build.yml`.
The CI configuration currently lives on `ci/macos-build-test`; merge it into
`main` before tagging releases from `main`.

When a release is explicitly requested:

1. Choose and commit the release changes. Set `CFBundleShortVersionString` in
   `Resources/Info.plist` to the intended version and increment `CFBundleVersion`.
2. Run tests and push the release commit. Confirm that this is the commit to ship.
3. Create and push **only the intended tag**. For example, for version 0.13.2:

   ```sh
   git tag -a v0.13.2 -m "Marker 0.13.2" <release-commit-sha>
   git push origin refs/tags/v0.13.2
   ```

The tag version must exactly match `CFBundleShortVersionString`; malformed,
prerelease, or mismatched tags fail before signing. A tag push is the explicit
publication action: no additional approval or release button is required.

After tests, Developer ID signing, notarization and Gatekeeper validation succeed,
a separate job downloads that run's verified artifact, checks its SHA-256 and
creates a GitHub Release with the DMG, checksum and generated release notes.
Only the publication job gets repository write permission. A failed build cannot
publish. Existing releases are not overwritten; investigate a failed publication
before retrying or making any manual release changes. Never move a published tag.

This publishes GitHub download assets only. The website and Sparkle appcast are
not updated by this workflow.
