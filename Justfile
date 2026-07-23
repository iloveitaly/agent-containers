set shell := ["zsh", "-cu", "-o", "pipefail"]

# Build the Cursor agent container image
build-cursor:
	docker build -t agent-container-cursor:local -f cursor/Dockerfile cursor
