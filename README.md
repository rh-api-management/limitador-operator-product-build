# Limitador Operator Product Build
Konflux configuration for the Limitador Operator & Operator Bundle components
## Renovate Configuration

This repository uses [Renovate](https://docs.renovatebot.com/) to automatically manage dependency updates.

### Enabled Managers

The `renovate.json` configuration uses the `enabledManagers` option to explicitly control which package managers are active. This is important because `enabledManagers` is **not additive** - it completely overrides the default manager list.

Currently enabled managers:
- **tekton** - Updates Tekton bundle references in `.tekton/*.yaml` files (e.g., `quay.io/konflux-ci/tekton-catalog/task-*@sha256:...`)
- **dockerfile** - Updates container image references in Dockerfiles and similar files
- **regex** - Custom pattern matching for specialized dependency updates
- **rpm** - Updates RPM package versions in `rpms.in.yaml` and `rpms.lock.yaml` lockfiles
- **github-actions** - Updates GitHub Actions versions in workflow files (`.github/workflows/*.yaml`)

### Excluding Managers

The git-submodules manager is explicitly excluded by omitting it from the `enabledManagers` array. This is intentional because **git submodule updates are managed by our custom GitHub Action** (`.github/workflows/submodule-version-bump.yaml`) rather than by Renovate. This prevents conflicts between the two automation systems.

If you need to add or remove managers, update the `enabledManagers` list in `renovate.json`:

```json
{
  "enabledManagers": ["tekton", "dockerfile", "regex", "rpm", "github-actions"]
}
```

**Note:** When modifying `enabledManagers`, you must list ALL desired managers. Adding one manager without listing the others will disable those others.