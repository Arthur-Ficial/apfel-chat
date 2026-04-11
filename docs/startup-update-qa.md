# Startup And Update QA

This feature now has two testing modes:

- Real release/manual QA: works on installed app bundles and released builds.
- Debug smoke QA: uses the local control API plus the debug-only fake update hook.

## What To Verify

- First launch shows the welcome screen once.
- `Check for updates on launch` defaults to `on`.
- If the machine is offline on launch, no error banner or update message appears.
- `Show welcome on next start` reopens the welcome screen exactly once, then resets to `false` after dismissal.
- Manual `Check for Update` still surfaces update results and errors.
- Homebrew installs still offer in-app `Install`; direct installs open the release download page.

## Fast Smoke Test

Build a local app bundle and run the smoke script:

```bash
./scripts/build-app.sh
zsh ./scripts/qa-startup-update.sh
```

Optional app override:

```bash
APP_PATH=/Applications/apfel-chat.app zsh ./scripts/qa-startup-update.sh
```

The script always verifies:

- first-run welcome visibility
- saved `check_updates_on_launch`
- one-shot `show_welcome_on_next_start`

On debug builds it also verifies:

- fake update available on dismiss
- silent launch behavior vs manual error surfacing

The script uses isolated defaults suites, so it does not pollute normal app settings.

## Install Matrix

### Source install

```bash
make install APP_DIR="$PWD/.qa/Applications"
APP_PATH="$PWD/.qa/Applications/apfel-chat.app" zsh ./scripts/qa-startup-update.sh
```

### ZIP install

```bash
./scripts/build-dist.sh
mkdir -p .qa/zip-apps
ditto -x -k dist/apfel-chat-macos-arm64.zip .qa/zip-apps
APP_PATH="$PWD/.qa/zip-apps/apfel-chat.app" zsh ./scripts/qa-startup-update.sh
```

### Curl installer

```bash
./scripts/build-dist.sh
APP_DIR="$PWD/.qa/curl-install/Applications" \
BIN_DIR="$PWD/.qa/curl-install/bin" \
ASSET_URL_OVERRIDE="file://$PWD/dist/apfel-chat-macos-arm64.zip" \
zsh ./scripts/install.sh

APP_PATH="$PWD/.qa/curl-install/Applications/apfel-chat.app" zsh ./scripts/qa-startup-update.sh
```

### Homebrew install

Current machine state already contains:

- `/opt/homebrew/Caskroom/apfel-chat`
- `/Applications/apfel-chat.app` at version `1.1.8`

Smoke-check the installed app:

```bash
APP_PATH=/Applications/apfel-chat.app zsh ./scripts/qa-startup-update.sh
```

To test the real Homebrew update path, publish a release newer than the installed cask, then run:

```bash
brew upgrade apfel-chat
APP_PATH=/Applications/apfel-chat.app zsh ./scripts/qa-startup-update.sh
```

## Old-To-New Upgrade Check

This machine also has an older direct-install app at:

- `/Users/arthurficial/Downloads/apfel-chat.app` at version `1.0.5`

Use that to verify an actual upgrade replacement path:

1. Copy the old app into a temp Applications folder.
2. Launch it once and quit.
3. Replace it with the new app bundle or install over it with the curl installer / ZIP copy / `make install`.
4. Launch the new app.
5. Confirm the welcome screen appears once because the new build introduces the feature and the previous install had no seen-flag yet.
6. Dismiss the welcome screen.
7. Relaunch and confirm it stays hidden unless `Show welcome on next start` is armed.
