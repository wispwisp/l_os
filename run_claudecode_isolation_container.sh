#!/usr/bin/env bash

IMAGE_NAME="los-claude-agent"
CONTAINER_NAME="los-claude-agent-dev"

local_claude=$(pwd -P)/.claude
if [ ! -d "$local_claude" ]; then
    mkdir "$local_claude"
    echo "Created: $local_claude"
else
    echo "Already exists: $local_claude Use it."
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        echo "Container is already running — opening a NEW shell via exec"
        docker exec -it "$CONTAINER_NAME" bash
    else
        echo "Container is stopped — starting it and attaching"
        docker start -ai "$CONTAINER_NAME"
    fi
else
    docker run -it \
           --name "$CONTAINER_NAME" \
           -u $(id -u):$(id -g) \
           --network host \
           -e https_proxy="http://127.0.0.1:8080" \
           -e http_proxy="http://127.0.0.1:8080" \
           -v $(pwd -P):/home/claudeuser/workspace \
           -v $local_claude:/home/claudeuser/.claude \
           "$IMAGE_NAME"
fi
