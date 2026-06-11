# Canonical copy of this formula lives in github.com/NicholasDominici/homebrew-tap.
# Users install with:
#   brew install nicholasdominici/tap/holler
class Holler < Formula
  desc "Ping coworkers on the same Wi-Fi, straight from the menu bar"
  homepage "https://github.com/NicholasDominici/holler"
  url "https://github.com/NicholasDominici/holler/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "9c9325d44f8d29b49ce7df235d1180fb5717c5edfec7fbbc9431c432d45f087c"
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
