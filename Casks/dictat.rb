cask "dictat" do
  version "0.1.0"
  sha256 "adf14c9f35c481e2f2b3033082cbb93eb67babeaca0772062dea2f0a15e06991"

  url "https://github.com/marcfranquesa/dictat/releases/download/v#{version}/Dictat.zip"
  name "Dictat"
  desc "Tiny fully on-device dictation"
  homepage "https://github.com/marcfranquesa/dictat"

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "Dictat.app"

  zap trash: [
    "~/Library/Application Support/FluidAudio/Models/parakeet-unified-en-0.6b",
    "~/Library/Preferences/dev.local.dictat.plist",
  ]

  caveats <<~EOS
    On first launch, dictat downloads the Parakeet model (~500 MB) to:
      ~/Library/Application Support/FluidAudio/Models

    macOS will ask for Microphone and Accessibility permission. Accessibility
    is needed to paste the transcription at the cursor.

    This build is ad-hoc signed, not notarized. If Gatekeeper blocks first
    launch, use Finder's Open action or System Settings > Privacy & Security.
  EOS
end
