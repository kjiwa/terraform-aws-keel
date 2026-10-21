# Contributing

- Write the `terraform test` contract test first and confirm it fails, then change the module.
- Run `pre-commit run --all-files` and check its exit status before opening a pull request.
- Run `sh scripts/docs.sh` after changing a module's variables, outputs, or providers.
- Shell scripts are POSIX `sh`: `set -eu`, a `main()` function, no `local`, no `eval`.
- Keep examples and tests free of account IDs, AWS profile names, personal emails, and home paths; `scripts/hygiene.sh` enforces this.
- A change to a variable, output, or resource address is a breaking change; say so in the pull request.
