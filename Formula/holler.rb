# Canonical copy of this formula lives in github.com/NicholasDominici/homebrew-tap.
# Users install with:
#   brew install nicholasdominici/tap/holler
class Holler < Formula
  desc "Ping coworkers on the same Wi-Fi, straight from the menu bar"
  homepage "https://github.com/NicholasDominici/holler"
  url "https://github.com/NicholasDominici/holler/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "8e0b99a8b80e887fa38a61652c247323302017fd87a2c45febefd40d184c9b01"
  license "MIT"
  head "https://github.com/NicholasDominici/holler.git", branch: "main"

  depends_on :macos

  def install
    system "make", "app", "SWIFT_FLAGS=--disable-sandbox"
    prefix.install "build/Holler.app"
  end

  def caveats
    <<~EOS
      Copy Holler.app into /Applications so macOS treats it as a normal app:
        cp -R "#{opt_prefix}/Holler.app" /Applications/
        open /Applications/Holler.app
    EOS
  end

  test do
    assert_predicate prefix/"Holler.app/Contents/MacOS/Holler", :exist?
  end
end
