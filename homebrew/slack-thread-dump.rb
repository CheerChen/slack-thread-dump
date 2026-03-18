class SlackThreadDump < Formula
  desc "Export Slack threads to text or Markdown"
  homepage "https://github.com/cheerchen/slack-thread-dump"
  url "https://github.com/cheerchen/slack-thread-dump.git", branch: "main"
  version "0.1.0"
  license "MIT"

  depends_on "jq"

  def install
    bin.install "slack-thread-dump.sh" => "slack-thread-dump"
  end

  test do
    system "#{bin}/slack-thread-dump", "--version"
  end
end
