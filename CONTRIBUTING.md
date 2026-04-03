# Contributing to Bjorn 3B+

Thanks for your interest in contributing! This project customises a
[Bjorn](https://github.com/infinition/Bjorn) deployment for the Raspberry Pi
3B+ with GPS, headless LCD support, and hash-lookup utilities.

## Getting Started

1. **Fork & clone** the repository.
2. Create a feature branch: `git checkout -b feature/my-change`
3. Make your changes and test on a Raspberry Pi (or in a Pi-compatible
   environment).
4. Commit with a clear message: `git commit -m "Add feature X"`
5. Push and open a Pull Request.

## Guidelines

- **Shell scripts** must pass [ShellCheck](https://www.shellcheck.net/) with no
  warnings. The CI pipeline enforces this automatically.
- Use `set -euo pipefail` at the top of every Bash script.
- Follow the existing colour-logging conventions (`log_info`, `log_warn`,
  `log_step`, `log_error`).
- Python code should be formatted with [Black](https://github.com/psf/black)
  and pass [Flake8](https://flake8.pycqa.org/) linting.
- Keep commits focused -- one logical change per commit.

## Reporting Issues

Open a GitHub Issue with:

- A clear title describing the problem.
- Steps to reproduce (include your Pi model and OS version).
- Expected vs. actual behaviour.
- Relevant log output.

## Code of Conduct

Be respectful and constructive. We follow the
[Contributor Covenant](https://www.contributor-covenant.org/) code of conduct.
