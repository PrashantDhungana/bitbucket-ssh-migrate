# Security

This project only rewrites local Git remote URLs and optionally appends public Bitbucket host keys to `~/.ssh/known_hosts`.

- It never sends credentials, tokens, or private keys anywhere.
- It does not disable SSH host-key verification.
- Host keys are fetched from Atlassian’s published endpoint: https://bitbucket.org/site/ssh

If you discover a security issue, open a private GitHub security advisory on this repository (or an issue without sensitive detail).
