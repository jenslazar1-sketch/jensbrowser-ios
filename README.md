# J3NSONTOP Browser — iOS

A native **SwiftUI + WKWebView** port of the Android J3NSONTOP Browser
(neon-red-on-black). This is a **rewrite**, not an APK repackage — Android and
iOS share no binaries, so the app is rebuilt on iOS's own web engine.

Built entirely on **Windows** via GitHub Actions' macOS runners — no Mac needed.

## What's ported (v0.1)

| Feature | Status |
|---|---|
| Tabs (each its own WKWebView, only the active one attached) | ✅ |
| Omnibox: URL / search / **DuckDuckGo-style bangs** (`!yt`, `!w`, …) | ✅ (faithful port of `BangShortcuts`) |
| Bookmarks + home **speed dial** | ✅ |
| Neon-red-on-black theme (`#FF003C` / `#000000`) | ✅ |
| Desktop mode + custom **User-Agent** | ✅ |
| Search-engine picker, user-editable bangs | ✅ |
| Back/forward gestures, new-tab from `target=_blank` | ✅ |

## On the roadmap (clean iOS mappings, coming next)

- **User mods** → `WKUserScript` (CSS/JS by host glob — actually cleaner than Android)
- **Console + JS runner** → `WKScriptMessageHandler` + `evaluateJavaScript`
- **AI bot** (Ollama / Claude / OpenAI) → `URLSession` streaming
- **Content/tracker blocking** → `WKContentRuleList` (declarative — iOS has no
  per-request `shouldInterceptRequest`, so the *network dev-console* and
  per-subresource header rules can't be reproduced 1:1)
- Backup/restore, PIN gate, private tabs

## Build

CI builds an **unsigned** IPA on every push (Actions → artifact) and publishes a
release on a `v*` tag. Locally on a Mac:

```sh
brew install xcodegen
xcodegen generate
open J3nsBrowser.xcodeproj
```

## Installing the IPA on a device

The release IPA is **unsigned**. Sign it with your own Apple certificate and
sideload it (AltStore / Sideloadly, or the companion **ipatool**), or install on
a jailbroken device. Building an unsigned app is legal; running it on an iPhone
requires your own signing identity.

## License

MIT.
