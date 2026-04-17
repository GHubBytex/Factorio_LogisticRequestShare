# Logistic Request Share

Minimal Factorio 2.0 mod that exports and imports the player's personal logistic request setup through a copy/paste code.
https://mods.factorio.com/mod/logistic-request-share

## Current scope

- Player only
- Copy/paste transfer only
- Saves and restores personal logistic sections plus `enabled` and `trash_not_requested`
- Skips missing items instead of failing the whole import

## Usage

1. Click the `LRS` shortcut in the shortcut bar on the right side of the screen.
2. Click `Capture Current` to generate a share code from your current personal logistics.
3. Copy the code from the text box.
4. Paste the code in another save and click `Apply Code`.

## Notes

- This MVP clears the player's existing manual logistic sections before applying the imported profile.
- Unsupported non-item logistic filter types are skipped and reported in chat.
- Two helper commands exist:
  - `/lrs-export`
  - `/lrs-clear-manual`
