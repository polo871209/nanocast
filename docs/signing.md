# Signing

Nanocast is signed with a **stable self-signed identity** called `Nanocast Self-Signed`. Keeping the
_same_ identity on every build is what makes macOS remember the Accessibility permission across
rebuilds and updates — ad-hoc signing changes every build and macOS forgets the grant.

You create this identity **once**. The same identity is used for:

- **local dev builds** — so Accessibility persists while you develop (the Xcode project signs with it), and
- **CI releases** — exported into two GitHub secrets the release workflow imports.

## 1. Create the `Nanocast Self-Signed` identity (once)

Run these in a terminal. They generate a self-signed code-signing certificate and import it into your
login keychain:

```sh
# Generate a self-signed code-signing cert (10-year, codeSigning use).
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/tc-key.pem -out /tmp/tc-cert.pem \
  -subj "/CN=Nanocast Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle it as a .p12. `security import` reads only the legacy format, and `-legacy` needs OpenSSL 3+.
openssl pkcs12 -export -legacy -inkey /tmp/tc-key.pem -in /tmp/tc-cert.pem \
  -name "Nanocast Self-Signed" -out /tmp/tc.p12 -passout pass:nanocast

# Import into the login keychain so codesign can use it without prompting.
security import /tmp/tc.p12 -k ~/Library/Keychains/login.keychain-db \
  -P nanocast -A -T /usr/bin/codesign

rm -f /tmp/tc-key.pem /tmp/tc-cert.pem /tmp/tc.p12
```

Verify it's there:

```sh
security find-identity -p codesigning | grep "Nanocast Self-Signed"
```

Now local builds (Xcode, VS Code F5, `xcodebuild`) sign with it, and you grant Accessibility once.

## 2. Generate the CI secrets

The release workflow needs the same identity as two repo secrets. Export it, base64-encode it, and
pick a password:

```sh
# Pick a random password for the exported bundle.
P12_PASSWORD="$(openssl rand -base64 24)"; echo "password: $P12_PASSWORD"

# Export the identity (approve the keychain dialog if asked) and base64-encode it.
security export -t identities -f pkcs12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$P12_PASSWORD" -o /tmp/signing.p12
base64 -i /tmp/signing.p12 | tr -d '\n' > /tmp/signing.p12.base64
rm -f /tmp/signing.p12
```

Then set the two secrets on the repo (via `gh`, authed as the repo owner, or paste them in the GitHub
UI under **Settings → Secrets and variables → Actions**):

```sh
gh secret set SIGNING_P12_BASE64   --repo polo871209/nanocast < /tmp/signing.p12.base64
gh secret set SIGNING_P12_PASSWORD --repo polo871209/nanocast --body "$P12_PASSWORD"
rm -f /tmp/signing.p12.base64   # holds your private key — delete it
```

If you ever lose the secrets, just re-run this section — as long as the `Nanocast Self-Signed`
identity is still in your keychain, the exported identity is the same, so users are unaffected. If you
lose the identity entirely, recreate it (step 1) and re-do this; existing users will re-grant
Accessibility once on their next update, then it's stable again.

## Hardened runtime

**Release only**, on both targets: `ENABLE_HARDENED_RUNTIME: YES`, which notarization requires. Debug
must stay without it — hardened runtime turns on library validation, and Xcode's
`Nanocast Dev.debug.dylib` is refused at launch because a self-signed identity carries no Team ID for
the loader to match. The flag is not part of the designated requirement, so turning it on costs no
Accessibility grant. Each entitlement in `Nanocast/Nanocast.entitlements` earns its place:

| Entitlement | Without it |
| --- | --- |
| `com.apple.security.automation.apple-events` | Every Apple event is refused with `-1743` and no prompt — Get Info and the System Events–driven system actions all die silently |
| `com.apple.security.device.camera` | The camera prompt never appears and access resolves as denied |

**A usage string is not enough under the hardened runtime.** `tccd` checks the matching entitlement
*before* it prompts, and without it logs "requires entitlement … but it is missing" and denies on the
spot — no dialog, no error, status still `.notDetermined`. A grant saved before the hardened runtime
arrived keeps working, since `tccd` does not re-check it, which is why this surfaces only on fresh
installs. Adding a protected resource therefore means adding its usage string *and* its entitlement.

`RESOURCE_ENTITLEMENTS` in `Scripts/verify-signature.sh` maps every protected resource's usage string
to its entitlement, including resources Nanocast does not use. That grants nothing — only
`Nanocast.entitlements` does, and a row whose usage string `Info.plist` doesn't declare is skipped. It
is there so a future feature that adds the usage string but forgets the entitlement fails the release
instead of shipping a prompt that can never appear.

Nothing else is needed: the only `dlopen` is Apple's own IOBluetooth, so library validation is left
on, and `node`, `ray` and shell commands are separate processes it never reaches. Bluetooth has no
hardened-runtime entitlement.

`./Scripts/verify-signature.sh <path-to-.app>` asserts all of this — the runtime flag on the app *and*
on `Contents/Helpers/ClipboardTextHelper` and `FileIndexHelper`, an intact nested seal, no `get-task-allow`, and an
entitlement for every usage string `Info.plist` declares. Both release jobs run it before packaging:
a nested binary missing the runtime flag is the most common notarization rejection, and a usage string
missing its entitlement ships a permission that can never be granted.

## Update trust

The updater installs a downloaded bundle only when it satisfies the running copy's own designated
requirement. For a `Nanocast Self-Signed` build, that requirement pins the bundle id and the
certificate, so every release must be signed with the same identity. A release signed with any other
identity can never be installed by the updater, and every existing copy has to be replaced by hand.

## Quarantine (separate from signing)

macOS quarantines anything downloaded from the internet, and Gatekeeper blocks even a correctly
self-signed app with an "unverified developer" warning. The Homebrew cask runs
`xattr -dr com.apple.quarantine` in `postflight_steps`, so **brew users never touch it**. People who
download the DMG directly clear it once by hand.
