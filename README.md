# homebrew-codeproxy

Homebrew tap for [CodeProxy](https://github.com/miguelriotinto/CodeProxy) — a
local macOS proxy that gives Claude Code access to AWS Bedrock while holding the
Bedrock credential server-side.

```sh
brew install miguelriotinto/codeproxy/codeproxy
codeproxy init      # prints a token and the config lines to add
```

The CodeProxy source repository is private, so the formula here installs a
prebuilt universal (arm64 + x86_64) macOS binary published as a release asset on
this repository. Both the release asset and the formula are written by CodeProxy's
release workflow — do not edit `Formula/codeproxy.rb` by hand, it is regenerated
on every release.
