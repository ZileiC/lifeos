# Security Policy

## Supported versions

Only the latest release built from `main` is supported. The project is pre-1.0; fixes land on `main`.

## Reporting a vulnerability

Please do not open a public issue for security problems.

Report privately through GitHub's [Security Advisories](https://github.com/ZileiC/lifeos/security/advisories/new) for this repository. Include:

- a description of the issue and its impact;
- steps to reproduce;
- the app version / commit, platform and version;
- any relevant logs with secrets removed.

You can expect an acknowledgement within a few days. There is no paid bug bounty.

## Scope notes

- AI provider API keys are entered by the user at runtime and stored per provider in the platform keystore. A report that leaks a key into logs, the database, or the repository is in scope.
- The app sends task text to the selected provider only when the user invokes an AI action. Sending more context than documented is in scope.
- Third-party provider outages or pricing are not security issues.
