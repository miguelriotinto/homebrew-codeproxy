class Codeproxy < Formula
  desc "Local Bedrock access proxy for Claude Code"
  homepage "https://github.com/miguelriotinto/homebrew-codeproxy"
  # Prebuilt universal macOS binary. The source repository is private and
  # Homebrew fetches anonymously, so the formula installs a compiled artifact
  # published to this public tap rather than building from source.
  url "https://github.com/miguelriotinto/homebrew-codeproxy/releases/download/v0.2.0/codeproxy-0.2.0.tar.gz"
  # Homebrew infers the version from the `v0.2.0` segment of the URL, so an
  # explicit `version` would only be a second place for it to go stale.
  sha256 "e0d624ef79aa8d19ca6388f8964376b41a173236db1d7aaac77752b3fba8982a"
  license "MIT"

  depends_on :macos

  def install
    bin.install "codeproxy"
    # launchd does not inherit a shell environment and CodeProxy is configured
    # entirely by environment variables. This wrapper sources the 0600 env file
    # and execs the binary, keeping the credential out of the world-readable
    # launchd plist.
    bin.install "codeproxy-launch"
  end

  service do
    run [opt_bin/"codeproxy-launch"]
    keep_alive successful_exit: false
    log_path var/"log/codeproxy.log"
    error_log_path var/"log/codeproxy.err.log"
  end

  def caveats
    <<~EOS
      CodeProxy needs a configuration file before it will start:

        codeproxy init                    # prints a token and the lines to add
        mkdir -p ~/.config/codeproxy && chmod 700 ~/.config/codeproxy
        # create ~/.config/codeproxy/env with the printed values, then:
        chmod 600 ~/.config/codeproxy/env
        codeproxy check                   # verifies config and Bedrock access

      Then start it:

        brew services start codeproxy

      Configure Claude Code. Use the literal IP, not localhost: localhost
      resolves to both ::1 and 127.0.0.1 and which wins is resolver-dependent,
      which shows up as intermittent connection refusals.

        export CLAUDE_CODE_USE_BEDROCK=1
        export ANTHROPIC_BEDROCK_BASE_URL=http://127.0.0.1:8787/us-east-1
        export AWS_BEARER_TOKEN_BEDROCK=<the token from codeproxy init>
    EOS
  end

  test do
    output = shell_output("#{bin}/codeproxy init")
    assert_match "cp_live_", output
    assert_match "CODEPROXY_TOKEN_SHA256=", output

    # Must fail fast without configuration: under launchd's keep_alive, a
    # process that starts broken becomes a silent restart loop.
    output = shell_output("#{bin}/codeproxy env 2>&1", 1)
    assert_match "CODEPROXY_BEDROCK_KEY is not set", output

    # The wrapper must refuse to run when the env file is missing.
    (testpath/"empty").mkpath
    output = shell_output(
      "XDG_CONFIG_HOME=#{testpath}/empty #{bin}/codeproxy-launch 2>&1", 78
    )
    assert_match "not found", output

    # The wrapper must find its binary without help from PATH: launchd supplies
    # PATH=/usr/bin:/bin:/usr/sbin:/sbin, which excludes Homebrew's bin, so a
    # wrapper trusting PATH dies with "exec: codeproxy: not found".
    #
    # This needs a valid-looking env file — the checks above return at the config
    # gate, which is before the exec, so they cannot detect a resolution failure.
    # A deliberately malformed key gets past the wrapper and makes the binary
    # itself object, so seeing the binary's own error proves exec resolved it.
    (testpath/"cfg/codeproxy").mkpath
    env_file = testpath/"cfg/codeproxy/env"
    env_file.write "CODEPROXY_BEDROCK_KEY=not-a-bedrock-key\n" \
                   "CODEPROXY_TOKEN_SHA256=#{"0" * 64}\n"
    env_file.chmod 0600
    output = shell_output(
      "env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=#{testpath} " \
      "XDG_CONFIG_HOME=#{testpath}/cfg #{bin}/codeproxy-launch 2>&1", 1
    )
    refute_match "not found", output
    assert_match "does not look like a Bedrock API key", output
  end
end
