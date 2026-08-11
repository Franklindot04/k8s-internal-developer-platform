# Contributing

Thank you for contributing to the Kubernetes Internal Developer Platform.

The project is currently being rebuilt from an audited recovery baseline. Documentation and implementation should always describe what the repository can actually do today, while keeping future architecture clearly marked as planned work.

This project uses a branch-based workflow. Contributors should not push directly to `main`. All changes should be made in a separate branch and submitted through a pull request.

## Branch Workflow

Create a new branch from `main` for each focused change.

Recommended branch naming:

* `feature/<short-description>`
* `fix/<short-description>`
* `docs/<short-description>`
* `chore/<short-description>`

Examples:

* `feature/variable-rendering`
* `fix/helm-values-overlay`
* `docs/add-runbook`
* `chore/update-ci-checks`

## Pull Requests

All changes should be submitted through a pull request into `main`.

Each pull request should include:

* A clear summary of what changed
* Why the change is needed
* Any testing or validation performed
* Screenshots, logs, or command output if useful
* Documentation updates if project behavior changed

## Reviews

Meaningful changes should be reviewed before they are merged. High-impact architecture, Kubernetes, GitOps, security, CI/CD, and generator changes should include validation evidence and should not be bundled with unrelated work.

Reviewers should check:

* Scope of the change
* Code quality
* Security impact
* Kubernetes, Helm, or GitOps correctness
* Documentation accuracy
* Whether the change fits the project roadmap

## Validation

Before opening a pull request, run the baseline checks:

```bash
make verify-tools
make validate
```

Also run relevant checks for the area being changed.

For Kubernetes, Helm, GitOps, and platform changes, validate:

* YAML formatting
* Kubernetes manifest correctness
* Helm chart rendering
* Environment overlay correctness
* CI workflow syntax
* Service generator output
* Documentation accuracy

Where applicable, include the commands or checks you ran in the pull request description.

## Documentation

Update documentation when changes affect:

* Deployment behavior
* Service template generation
* GitOps workflows
* CI scaffolding
* Environment overlays
* Observability
* Self-service developer workflows
* Platform runbooks or operational processes

## Commit Messages

Use clear commit messages.

Examples:

* `docs: add contributing guide`
* `feat: add service template variable rendering`
* `fix: correct dev overlay values`
* `chore: update ci checks`

## Main Branch Protection

The `main` branch should represent the stable project state.

Do not commit directly to `main`. Use branches and pull requests.

## Historical Branches

The historical branches `develop`, `feature/base-helm-structure`, and `feature/service-template-generator` are preserved for attribution and recovery evidence. Do not base new implementation work on them, merge them wholesale, rewrite them, or delete them without explicit approval.
