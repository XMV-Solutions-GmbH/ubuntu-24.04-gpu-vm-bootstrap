<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# How-to: Open Source Repository Setup

This document describes the standard setup for open source repositories at
XMV Solutions GmbH.

## Repository Structure

```text
project/
├── .github/
│   ├── CODEOWNERS
│   ├── copilot-instructions.md
│   ├── dependabot.yml
│   ├── gh-scripts/
│   │   ├── assign-repo-to-team.sh
│   │   ├── check-pr.sh
│   │   ├── create-pr.sh
│   │   ├── merge-pr.sh
│   │   ├── new-feature.sh
│   │   └── setup-branch-protection.sh
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/
│       ├── release.yml
│       └── test.yml
├── docs/
│   ├── app-concept.md
│   ├── howto-oss.md
│   ├── testconcept.md
│   └── todo.md
├── tests/
│   ├── unit/
│   ├── harness/
│   ├── e2e/
│   ├── fixtures/
│   ├── test_helper.bash
│   └── run_tests.sh
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── LICENSE
├── LICENSE-APACHE
├── LICENSE-MIT
├── Makefile
├── README.md
└── SECURITY.md
```

## Required Documents

| File | Purpose |
| ---- | ------- |
| `README.md` | Project overview, installation, usage, badges |
| `CONTRIBUTING.md` | Contribution guidelines, code style, PR process |
| `CODE_OF_CONDUCT.md` | Community standards (Contributor Covenant) |
| `LICENSE` | Primary licence file |
| `LICENSE-APACHE` | Apache 2.0 licence text |
| `LICENSE-MIT` | MIT licence text |
| `SECURITY.md` | Security policy and vulnerability reporting |
| `CHANGELOG.md` | Keep-a-changelog format version history |

## Licensing — Dual Licence (MIT / Apache-2.0)

Every source file must include an SPDX header:

```bash
# SPDX-License-Identifier: MIT OR Apache-2.0
```

```markdown
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
```

## GitHub Configuration

### Branch Protection

Use `.github/gh-scripts/setup-branch-protection.sh` to configure:

- Require PR reviews before merging
- Require status checks to pass
- No force pushes to `main`
- No branch deletions on `main`

### Dependabot

Configure in `.github/dependabot.yml` for:

- GitHub Actions updates (weekly)
- Docker dependency updates (if applicable)

### CI/CD

- **test.yml** — Runs on push/PR: lint, unit tests
- **release.yml** — Runs on tag push: creates GitHub release with artefacts

## Checklist for New Repositories

- [ ] Create repository on GitHub
- [ ] Add all required documents
- [ ] Configure branch protection
- [ ] Set up CI/CD workflows
- [ ] Configure Dependabot
- [ ] Assign repository to team
- [ ] Add badges to README
- [ ] Create initial release
