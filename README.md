# OpenCode v2 kit for Docker Sandboxes

**DISCLAIMER: this is an experimental kit, mainly devised as a proof of concept.**
**You should consider using Docker Sandboxes' builtin `opencode` agent, as soon as it [supports OpenCode v2](https://github.com/docker/sbx-releases/issues/670).**

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) kit that runs
[OpenCode](https://github.com/anomalyco/opencode) v2 (npm package
`@opencode/cli`) in a sandbox. It is a `kind: workload` kit written against
the [Sandbox Kit Specification v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md),
derived from the spec's `examples/opencode` kit, which still ships OpenCode 1.x.

What the kit provides:

- OpenCode v2 pinned to one release per build, on the
  `dhi.io/sbx-templates:opencode-docker` base (bash, git, CA store, the
  `agent` user with sudo, node and npm, Docker engine).
- Seven optional, proxy-managed provider API keys: Anthropic, OpenAI,
  Google, Groq, OpenRouter, xAI and GitHub (Copilot).
- Scoped egress for those providers, opencode.ai, npm and GitHub assets.
- Registration of the sandbox MCP gateway in `opencode.json` when MCP is
  enabled, headless (`opencode run`), interactive and ACP session verbs,
  shared skills and an `AGENTS.md` agent context.

## Requirements

- `sbx` 0.45 or later (v3 kits).
- Every kit composed into the sandbox must also be v3: built-in agent names
  such as `claude` select v2 kits and cannot be mixed with this one.

## Quick start

From the directory that contains `opencode2-sbx-kit/`:

```console
sbx run ./opencode2-sbx-kit --name oc2 .
```

`sbx` builds the kit when it creates the sandbox and reuses the cached
build while the kit source and its arguments are unchanged.

Bind the provider keys you use as sandbox secrets on the host, for example:

```console
sbx secret set anthropic --sandbox oc2 -t "<your key>"
```

The service names are `anthropic`, `openai`, `google`, `groq`,
`openrouter`, `xai` and `github`. Inside the sandbox, the matching variables
(`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_GENERATIVE_AI_API_KEY`,
`GROQ_API_KEY`, `OPENROUTER_API_KEY`, `XAI_API_KEY`, `GITHUB_TOKEN`) hold
sentinels; the proxy substitutes the real values on the provider hosts, so
the keys never enter the sandbox.

## Version policy

The kit follows the model of Docker's official v3 kits
(`docker/sbx-kit-opencode`, `docker/sbx-kit-claude`, ...): **one OpenCode
release per kit build**.

- The `version` kit argument (default `2.1.2`, 2.x only) selects the release.
  It is a build argument: the build fails unless `opencode --version` prints
  exactly that version, and the kit's `provides` entry records it.
- OpenCode's self-update is disabled in the image
  (`OPENCODE_DISABLE_AUTOUPDATE=1`), so a sandbox does not drift away from
  the version its kit declares. The variable takes precedence over the
  `autoupdate` setting in `opencode.json`.
- Once the kit is published, each OpenCode release gets its own image tag
  (for example `<namespace>/sbx-kit-opencode2:2.1.2`).

What that means in practice:

| Situation | OpenCode version | To change it |
|---|---|---|
| New sandbox from the local or Git kit | `--kit-arg version=…`, else the default | Pass another `--kit-arg version=…` (sbx rebuilds) |
| New sandbox from a published kit | The tag's version | Use another tag |
| Existing sandbox | The one it was created with: a sandbox keeps the kit configuration recorded at creation | Create a new sandbox, or upgrade manually (below) |
| Template saved with `sbx template save` | Fixed: a template is a snapshot | Save a new template |

Pick a version at creation:

```console
sbx run ./opencode2-sbx-kit --name oc2-211 --kit-arg version=2.1.1 .
```

Use a new sandbox name: reusing a name reuses the recorded kit
configuration.

### Manual upgrade inside an existing sandbox

OpenCode is installed as the `agent` user in an agent-writable npm prefix,
so no sudo is needed. Either:

```console
opencode upgrade 2.1.3 --method npm
```

or, equivalently:

```console
npm install -g @opencode/cli@2.1.3 --allow-scripts=@opencode/cli
```

After a manual upgrade the sandbox no longer matches the version its kit
declares. Prefer a new sandbox when reproducibility matters.

## ChatGPT subscriptions

The 1.x example kit rendered a proxy-managed ChatGPT OAuth token into
`~/.local/share/opencode/auth.json`. OpenCode v2 stores credentials in its
database (`~/.local/share/opencode/opencode.db`) and reads `auth.json` only
when migrating an existing 1.x database, so this kit does not carry that
OAuth block.

You can still log in from inside the sandbox with `opencode auth login`;
the OpenAI OAuth and Codex backend hosts stay allowed for that. Unlike the
API keys, those tokens are stored in the sandbox itself.

## MCP gateway

When the sandbox has an MCP gateway, a startup hook merges this entry into
`~/.config/opencode/opencode.json`, leaving the rest of the file untouched:

```json
{ "mcp": { "servers": { "mcp-gateway": { "type": "remote", "url": "…", "headers": { "Authorization": "Bearer …" } } } } }
```

This is OpenCode v2's canonical shape, the one `opencode mcp add` writes.

## Build and validate without sbx

```console
docker buildx build . -f opencode2.yaml --build-arg version=2.1.2 -t opencode2-kit:2.1.2 --load
```

The `# syntax=docker/sandbox-kit:3` frontend validates the descriptor during
the build. To run the spec's conformance checks on the result, export an OCI
layout and use `kit-tck` from a clone of
[docker/sandbox-kit-spec](https://github.com/docker/sandbox-kit-spec):

```console
docker buildx build . -f opencode2.yaml --build-arg version=2.1.2 --output type=oci,dest=kit.tar
mkdir kit-oci && tar -xf kit.tar -C kit-oci
go run ./cmd/kit-tck validate --layout kit-oci "$(jq -r '.manifests[0].digest' kit-oci/index.json)"
```

## Smoke tests

`tests/smoke.sh` runs on the host (bash: Git Bash or WSL on Windows) and
checks a sandbox through `sbx exec`:

```console
tests/smoke.sh oc2 2.1.2
```

It checks the version, the `agent` user, that auto-update is disabled, that
the install is agent-writable, the config directory, the agent context, the
MCP gateway entry (when MCP is enabled) and the detected providers. To also
send one headless prompt, which spends tokens:

```console
SMOKE_PROMPT=1 SMOKE_MODEL=anthropic/claude-haiku-4-5 tests/smoke.sh oc2 2.1.2
```

With `SMOKE_RUNNER=docker`, the same checks run against a container started
from the kit image, minus the ones only a sandbox runtime can satisfy:

```console
docker run -d --name oc2 --entrypoint sleep opencode2-kit:2.1.2 infinity
SMOKE_RUNNER=docker tests/smoke.sh oc2 2.1.2
```

## Files

| File | Role |
|---|---|
| `opencode2.yaml` | Kit descriptor (v3) |
| `opencode2.dockerfile` | Image recipe, paired with the descriptor by name |
| `tests/smoke.sh` | Post-creation smoke tests |
| `PLAN.md` | Implementation plan (in French) |
