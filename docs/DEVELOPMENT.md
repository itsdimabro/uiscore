# Development

## Signing local builds

`scripts/make-app.sh` signs `dist/UIScore.app` in one of two ways:

1. If a dedicated keychain at `~/Library/Application Support/UIScoreDev/signing.keychain-db` holds a valid code-signing identity named "UIScore Local Signing", it signs with that identity.
2. Otherwise it signs ad-hoc with a fixed designated requirement (`identifier "com.screencheck.app"`), so every build has the same requirement and anyone can build from source with no setup.

The identity is never stored in the repo or the login keychain. macOS only accepts a self-signed certificate for signing once it is marked trusted, and doing that asks for the user's password, so the script falls back to option 2 when the identity is not valid.

When developing, set `SCREENCHECK_ENV_KEYS=1` with `ANTHROPIC_API_KEY` and `JEV_API_KEY` in the shell so test runs never read the Keychain.
