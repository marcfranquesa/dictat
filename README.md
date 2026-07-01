# dictat

tiny, fully on-device macOS dictation. press Ctrl+Opt+Space, speak, then press again, and the text is pasted at your cursor and copied to the clipboard. build it with `./build.sh`, or install the prebuilt app with Homebrew:

```sh
brew tap marcfranquesa/dictat https://github.com/marcfranquesa/dictat
brew trust --cask marcfranquesa/dictat/dictat
brew install --cask marcfranquesa/dictat/dictat
```

if macOS says `"Dictat" Not Opened` because Apple cannot verify it is free of malware, remove the download quarantine and open it again:

```sh
xattr -dr com.apple.quarantine /Applications/Dictat.app
open /Applications/Dictat.app
```

uninstall with:

```sh
brew uninstall --zap --cask marcfranquesa/dictat/dictat
```

the v1 cask build is Apple Silicon only and ad-hoc signed, not notarized, so Gatekeeper may block first launch. Developer ID signing and notarization are the proper fix; until then, use the quarantine command above. licensed Apache-2.0, with the Parakeet STT engine vendored from [FluidAudio](https://github.com/FluidInference/FluidAudio).

the feature is no features.

| | lines | deps |
|---|--:|--:|
| app code (`Sources/dictat`) | 668 | 0 |
| vendored FluidAudio (Parakeet engine) | 3,894 | 0 |
| C shim (`MachTaskSelfWrapper`) | 21 | 0 |
| **total** | **4,579** | **0** |

there are zero external dependencies, so nothing is fetched at build time. the only network use is a one-time model download of about 500 MB on first launch, after which it runs fully offline.

this project was vibe-coded, you may ask your agent to review the code before you run it.

<p align="center">
  <img src="mascot.png" alt="dictat mascot" width="220">
</p>
