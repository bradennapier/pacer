# Homebrew formula for pacer
# To install from local tap: brew install bradennapier/tap/pacer

class Pacer < Formula
  desc "Single-flight debounce/throttle for shell scripts"
  homepage "https://github.com/bradennapier/pacer"
  url "https://github.com/bradennapier/pacer/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"
  head "https://github.com/bradennapier/pacer.git", branch: "main"

  depends_on "bash"
  depends_on "flock"

  def install
    bin.install "pacer"
  end

  test do
    # Basic help test
    assert_match "single-flight debounce/throttle", shell_output("#{bin}/pacer --help")

    # Test debounce execution
    output = shell_output("#{bin}/pacer test-formula 50 echo 'brew-test-ok'")
    assert_match "brew-test-ok", output
  end
end
