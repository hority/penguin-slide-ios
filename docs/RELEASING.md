# Release setup

The game source repository is public.
Signing material must remain in a separate **private** repository. Never copy
its signing branch or commit history into this repository.

The manual **Upload to TestFlight** workflow runs only from `master`, uses the
`testflight` environment, and imports existing profiles with Fastlane match
`readonly: true`. It does not create certificates, renew profiles, register an
app, change tester groups, or submit an external beta/App Store review.

Configure the `testflight` GitHub environment with deployment restricted to
`master`; require a trusted reviewer before release where the GitHub plan supports
it. Do not give contributors who should not publish releases write access.

Environment variables:
- `APPLE_TEAM_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `MATCH_GIT_URL`: HTTPS URL of the existing private signing repository, ending in `.git`

Environment secrets (entered by the owner; never committed or pasted into chat):
- `APP_STORE_CONNECT_PRIVATE_KEY`: existing Apple API private key
- `MATCH_PASSWORD`: existing signing encryption password; do not generate a replacement
- `SIGNING_GIT_TOKEN`: credential scoped to read repository contents in the private signing repository only

The source repository's `GITHUB_TOKEN` cannot read a different private repository.
Establishing cross-repository access and entering credentials requires the owner's
approval and secure setup. Nothing in this source snapshot provisions that access.
Keep the old release process available until the new pipeline is verified.

Build numbers continue after the latest TestFlight build, rather than restarting
from this repository's GitHub Actions run counter. Avoid concurrent uploads from
the original repository. Renew expired signing assets through the private process.

No signed IPA is uploaded as a public Actions artifact. Build success is not an
iPhone gameplay test; verify the changed flow on the device after delivery.
