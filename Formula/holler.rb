# Canonical copy of this formula lives in github.com/NicholasDominici/homebrew-tap.
# Users install with:
#   brew install nicholasdominici/tap/holler
class Holler < Formula
  desc "Ping coworkers on the same Wi-Fi, straight from the menu bar"
  homepage "https://github.com/NicholasDominici/holler"
  url "https://github.com/NicholasDominici/holler/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "8eccb83b03127c9a83bc8e7b0207f57d861c02312575a33d6a1df72b8f873052"
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
