class Codeproxy < Formula
  desc "Local Bedrock access proxy for Claude Code"
  homepage "https://github.com/miguelriotinto/homebrew-codeproxy"
  # Prebuilt universal macOS binary. The source repository is private and
  # Homebrew fetches anonymously, so the formula installs a compiled artifact
  # published to this public tap rather than building from source.
  url "https://github.com/miguelriotinto/homebrew-codeproxy/releases/download/v0.2.1/codeproxy-0.2.1.tar.gz"
  # Homebrew infers the version from the `v0.2.1` segment of the URL, so an
  # explicit `version` would only be a second place for it to go stale.
  sha256 "3177356c15accc203cda1b58f0a7189214bf1449c8fe455c820e80aa242cbed7"
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
    # CodeProxy writes its own daily-rotated codeproxy.log in this directory and
    # prunes old files itself. Deliberately NOT log_path: that makes launchd hold
    # an open fd to the file, and anything that renames it (newsyslog, a manual
    # mv) leaves the daemon writing to an unlinked inode while the visible log
    # stays empty. error_log_path is still launchd's, because a process that dies
    # before configuring its logger can only report through stderr.
    environment_variables CODEPROXY_LOG_DIR: var/"log/codeproxy"
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

    # A rotation setting that silently fell back to unbounded growth would look
    # exactly like a working one until the disk filled, so assert the binary
    # reports the directory and retention it will actually use.
    (testpath/"cfg2/codeproxy").mkpath
    env2 = testpath/"cfg2/codeproxy/env"
    env2.write "CODEPROXY_BEDROCK_KEY=ABSKfake\n" \
               "CODEPROXY_TOKEN_SHA256=#{"0" * 64}\n" \
               "CODEPROXY_LOG_DIR=#{testpath}/logs\n" \
               "CODEPROXY_LOG_KEEP_DAYS=3\n"
    env2.chmod 0600
    output = shell_output(
      "env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=#{testpath} " \
      "XDG_CONFIG_HOME=#{testpath}/cfg2 #{bin}/codeproxy env",
    )
    assert_match "#{testpath}/logs (keep 3 days)", output

    # And that a retention of 0 is rejected: it would mean "keep no files at all",
    # deleting the log this feature exists to preserve.
    env2.write env2.read.sub("KEEP_DAYS=3", "KEEP_DAYS=0")
    output = shell_output(
      "env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=#{testpath} " \
      "XDG_CONFIG_HOME=#{testpath}/cfg2 #{bin}/codeproxy env 2>&1", 1
    )
    assert_match "must be at least 1", output
  end
end
