set shell := ["zsh", "-cu", "-o", "pipefail"]

# Build the Cursor agent container image
build-cursor:
	docker build -t ubuntu-docker-mise-direnv:local -f cursor/Dockerfile cursor

# Re-run install.sh in the image against mounted fixtures (no justfile / no
# setup recipe / setup without just via mise / setup with just already via mise /
# setup that advertises --skip-services / setup outside the /workspace direnv
# whitelist, with an .envrc). Then re-run start.sh --skip-docker: full
# `just setup` on container start, including a recipe that advertises
# --skip-services (the flag must not be passed) outside the /workspace
# direnv whitelist.
# Markers record OP_INTEGRATION_DISABLED, which both scripts set before just.
# Image build itself has no project justfile. install.sh does not install just.
[script]
test-just-setup: build-cursor
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT

	# One directory per install.sh outcome. Each is mounted as a project root.
	mkdir -p \
		"$tmp/none" \
		"$tmp/nosetup" \
		"$tmp/setup" \
		"$tmp/setup-with-just" \
		"$tmp/setup-skip-services" \
		"$tmp/setup-with-envrc" \
		"$tmp/start-full-setup"

	# No justfile. install.sh should not create a marker.
	# (directory stays empty)

	# Justfile, but no `setup` recipe. install.sh should skip it.
	printf 'default:\n\techo hello\n' > "$tmp/nosetup/Justfile"

	# `setup` recipe, and just is not a mise tool. install.sh should skip it.
	printf 'setup:\n\techo ran-setup > marker\n' > "$tmp/setup/Justfile"

	# `setup` recipe, and just is already declared in mise. install.sh should run it
	# with OP_INTEGRATION_DISABLED already set. This recipe has no --skip-services
	# flag, so install.sh must not pass one.
	printf 'setup:\n\tprintf "%%s\\n" "$OP_INTEGRATION_DISABLED" > marker\n' > "$tmp/setup-with-just/Justfile"
	printf '[tools]\njust = "1.38.0"\n' > "$tmp/setup-with-just/mise.toml"

	# `setup` advertises --skip-services. just 1.46 added [arg] long/value flags.
	# install.sh should pass the flag; the marker records that it did.
	# The quoted interpolation below writes a skip_services parameter
	# reference into the fixture justfile; it is not a variable of this recipe.
	printf '[arg("skip_services", long="skip-services", value="true")]\nsetup skip_services="false":\n\tprintf "%%s %%s\\n" "$OP_INTEGRATION_DISABLED" "{{ "{{skip_services}}" }}" > marker\n' > "$tmp/setup-skip-services/Justfile"
	printf '[tools]\njust = "1.46.0"\n' > "$tmp/setup-skip-services/mise.toml"

	# Same as setup-with-just, plus an .envrc. This directory is mounted at /opt/app,
	# outside the /workspace direnv whitelist, so the recipe only sees
	# FROM_DIRENV when install.sh allows that file and runs the recipe under `direnv exec`.
	printf 'setup:\n\tprintf "%%s %%s\\n" "$FROM_DIRENV" "$OP_INTEGRATION_DISABLED" > marker\n' > "$tmp/setup-with-envrc/Justfile"
	printf '[tools]\njust = "1.38.0"\n' > "$tmp/setup-with-envrc/mise.toml"
	printf 'export FROM_DIRENV=from-direnv\n' > "$tmp/setup-with-envrc/.envrc"

	# Container start runs full `just setup` after dockerd. This recipe advertises
	# --skip-services; start.sh must not pass it. Mounted at /opt/start-app, outside
	# the /workspace direnv whitelist, so the marker only sees FROM_DIRENV when
	# start.sh allows .envrc and runs the recipe under `direnv exec`.
	# The quoted interpolation below writes a skip_services parameter
	# reference into the fixture justfile; it is not a variable of this recipe.
	printf '[arg("skip_services", long="skip-services", value="true")]\nsetup skip_services="false":\n\tprintf "%%s %%s %%s\\n" "$FROM_DIRENV" "$OP_INTEGRATION_DISABLED" "{{ "{{skip_services}}" }}" > marker\n' > "$tmp/start-full-setup/Justfile"
	printf '[tools]\njust = "1.46.0"\n' > "$tmp/start-full-setup/mise.toml"
	printf 'export FROM_DIRENV=from-direnv\n' > "$tmp/start-full-setup/.envrc"

	# Base image has the Cursor-like CLIs and locale.
	docker run --rm ubuntu-docker-mise-direnv:local bash -lc '
	  set -euo pipefail
	  command -v tmux
	  command -v xz
	  command -v python3
	  command -v jq
	  command -v rg
	  command -v unzip
	  locale -a | grep -qiE "en_US\\.(utf8|UTF-8)"
	  grep -qxF "export OP_INTEGRATION_DISABLED=1" /home/ubuntu/.zshenv
	  grep -qxF "OP_INTEGRATION_DISABLED=1" /etc/environment
	'

	# No justfile: no marker.
	docker run --rm \
	  -v "$PWD/cursor/install.sh:/tmp/install.sh:ro" \
	  -v "$tmp/none:/workspace" \
	  -w /workspace \
	  ubuntu-docker-mise-direnv:local bash /tmp/install.sh
	[ ! -e "$tmp/none/marker" ]

	# Justfile without a setup recipe: no marker.
	docker run --rm \
	  -v "$PWD/cursor/install.sh:/tmp/install.sh:ro" \
	  -v "$tmp/nosetup:/workspace" \
	  -w /workspace \
	  ubuntu-docker-mise-direnv:local bash /tmp/install.sh
	[ ! -e "$tmp/nosetup/marker" ]

	# Setup recipe, but just is not installed via mise: no marker.
	docker run --rm \
	  -v "$PWD/cursor/install.sh:/tmp/install.sh:ro" \
	  -v "$tmp/setup:/workspace" \
	  -w /workspace \
	  ubuntu-docker-mise-direnv:local bash /tmp/install.sh
	[ ! -e "$tmp/setup/marker" ]

	# Setup recipe with just installed, and an .envrc outside /workspace.
	docker run --rm \
	  -v "$PWD/cursor/install.sh:/tmp/install.sh:ro" \
	  -v "$tmp/setup-with-just:/workspace" \
	  -v "$tmp/setup-with-envrc:/opt/app" \
	  -w /workspace \
	  ubuntu-docker-mise-direnv:local bash -c '
	    set -euo pipefail
	    chown -R ubuntu:ubuntu /workspace /opt/app
	    sudo -n -u ubuntu -H mise install
	    bash /tmp/install.sh
	    cd /opt/app
	    sudo -n -u ubuntu -H mise install
	    bash /tmp/install.sh
	  '
	# /workspace ran `just setup` with desktop 1Password integration disabled.
	grep -qx 1 "$tmp/setup-with-just/marker"
	# /opt/app saw the value exported by .envrc, and the same op flag through direnv exec.
	grep -qx 'from-direnv 1' "$tmp/setup-with-envrc/marker"

	# Setup recipe that lists --skip-services: install.sh must pass that flag.
	docker run --rm \
	  -v "$PWD/cursor/install.sh:/tmp/install.sh:ro" \
	  -v "$tmp/setup-skip-services:/workspace" \
	  -w /workspace \
	  ubuntu-docker-mise-direnv:local bash -c '
	    set -euo pipefail
	    chown -R ubuntu:ubuntu /workspace
	    sudo -n -u ubuntu -H mise install
	    bash /tmp/install.sh
	  '
	grep -qx '1 true' "$tmp/setup-skip-services/marker"

	# No justfile: start.sh --skip-docker exits without a marker.
	docker run --rm \
	  -v "$PWD/cursor/start.sh:/tmp/start.sh:ro" \
	  -v "$tmp/none:/workspace" \
	  -w /workspace \
	  ubuntu-docker-mise-direnv:local bash /tmp/start.sh --skip-docker
	[ ! -e "$tmp/none/marker" ]

	# Container start runs `just setup` with the service steps included.
	# --skip-docker stands in for the daemon this fixture does not need.
	docker run --rm \
	  -v "$PWD/cursor/start.sh:/tmp/start.sh:ro" \
	  -v "$tmp/start-full-setup:/opt/start-app" \
	  -w /opt/start-app \
	  ubuntu-docker-mise-direnv:local bash -c '
	    set -euo pipefail
	    chown -R ubuntu:ubuntu /opt/start-app
	    sudo -n -u ubuntu -H mise install
	    bash /tmp/start.sh --skip-docker
	  '
	grep -qx 'from-direnv 1 false' "$tmp/start-full-setup/marker"

# Smoke-test the image: just-setup hook, then clone railpack, mise install, and build
[script]
test: test-just-setup
	docker run --rm ubuntu-docker-mise-direnv:local bash -lc '
	  set -euo pipefail
	  export HOME=/home/ubuntu
	  eval "$(mise activate bash)"
	  command -v gh
	  command -v uv
	  mise which gh | grep -F '.local/share/mise/installs/gh'
	  mise which uv | grep -F '.local/share/mise/installs/uv'
	  test -x /home/ubuntu/.local/share/gh/extensions/gh-ai-pr/gh-ai-pr
	  git clone --depth 1 https://github.com/iloveitaly/railpack.git /tmp/railpack
	  cd /tmp/railpack
	  mise trust && mise install && mise run build
	'

# set publish permissions, update metadata, and protect master; all in one command
github_setup: github_repo_permissions_create github_repo_set_metadata github_ruleset_protect_master_create

GITHUB_PROTECT_MASTER_RULESET := """
{
  "name": "Protect master from force pushes",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/master"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "non_fast_forward"
    }
  ]
}
"""

_github_repo:
	gh repo view --json nameWithOwner -q .nameWithOwner

# TODO this only supports deleting the single ruleset specified above
github_ruleset_protect_master_delete:
	repo=$(just _github_repo) && \
		ruleset_name=$(echo '{{GITHUB_PROTECT_MASTER_RULESET}}' | jq -r .name) && \
		ruleset_id=$(gh api repos/$repo/rulesets --jq ".[] | select(.name == \"$ruleset_name\") | .id") && \
		(([ -n "${ruleset_id}" ] || (echo "No ruleset found" && exit 0)) || gh api --method DELETE repos/$repo/rulesets/$ruleset_id)

# adds github ruleset to prevent --force and other destructive actions on the github main branch
github_ruleset_protect_master_create: github_ruleset_protect_master_delete
	gh api --method POST repos/$(just _github_repo)/rulesets --input - <<< '{{GITHUB_PROTECT_MASTER_RULESET}}'

# Set GitHub Actions permissions for the repository to allow workflows to write and approve PR reviews
github_repo_permissions_create:
	repo_path=$(gh repo view --json nameWithOwner --jq '.nameWithOwner') && \
		gh api --method PUT "/repos/${repo_path}/actions/permissions/workflow" \
			-f default_workflow_permissions=write \
			-F can_approve_pull_request_reviews=true && \
		gh api "/repos/${repo_path}/actions/permissions/workflow"

github_repo_set_metadata:
	gh repo edit \
		--description "$(jq -r '.description' metadata.json)" \
		--homepage "$(jq -r '.homepage' metadata.json)" \
		--add-topic "$(jq -r '.keywords | join(",")' metadata.json)"
