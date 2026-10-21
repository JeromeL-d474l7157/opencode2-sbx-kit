# OpenCode v2 on the sandbox-templates opencode base. The template carries
# the platform floor (bash, git, CA store, the agent user, node and npm with
# an agent-owned global prefix); this recipe swaps its opencode 1.x for the
# v2 release the kit publishes, so the provide cannot claim a version the
# image does not ship.
FROM dhi.io/sbx-templates:opencode-docker
ARG OPENCODE_VERSION
# As agent, not root: NPM_CONFIG_PREFIX (/usr/local/share/npm-global) is
# agent-owned, and keeping the install there writable is what lets a manual
# `opencode upgrade --method npm` work inside an existing sandbox.
#   - v1 ships as `opencode-ai` and v2 as `@opencode/cli`; both install an
#     `opencode` bin, so v1 goes first.
#   - The v2 package's postinstall is what swaps its bin stub for the
#     platform binary, and newer npm only runs scripts named in
#     allow-scripts. (The base's npm is the real npm-cli.js, not a corepack
#     shim, so lifecycle scripts do run.)
#   - The version check is fatal and exact: npm's exit code only says npm
#     ran, while a stub left in place cannot print the version.
USER agent
RUN set -eux \
 && npm rm -g opencode-ai \
 && npm install -g "@opencode/cli@${OPENCODE_VERSION}" --include=optional --allow-scripts=@opencode/cli \
 && test "$(opencode --version)" = "opencode v${OPENCODE_VERSION}" \
 && npm cache clean --force \
 && rm -rf /home/agent/.npm /home/agent/.cache/opencode /home/agent/.local/share/opencode /home/agent/.local/state/opencode
# Pinned per kit tag: a self-update would make the published provide lie.
ENV OPENCODE_DISABLE_AUTOUPDATE=1
WORKDIR /home/agent/workspace
ENTRYPOINT ["opencode"]
