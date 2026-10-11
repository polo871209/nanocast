cask "nanocast" do
  version "0.12.3-1"
  sha256 "2b4489886c3fa9ad84fa7c4284c1495e8ef84b43138b4a48c096c5767fc64644"

  url "https://github.com/polo871209/nanocast/releases/download/v#{version}/Nanocast-#{version}.dmg"
  name "Nanocast"
  desc "Menu bar launcher with clipboard history and window management"
  homepage "https://github.com/polo871209/nanocast"

  livecheck do
    url :url
    regex(/^v?(\d+(?:\.\d+)+-\d+)$/i)
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :golden_gate

  app "Nanocast.app"

  # Self-signed, not notarized: Gatekeeper refuses a quarantined copy.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Nanocast.app"]
  end

  uninstall quit: "com.nanocast.app"

  zap trash: [
    "~/.config/nanocast",
    "~/Library/Application Support/com.nanocast.app",
    "~/Library/Caches/com.nanocast.app",
    "~/Library/Preferences/com.nanocast.app.plist",
  ]
end
