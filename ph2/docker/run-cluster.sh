#!/usr/bin/env bash
# Host-side helper: pull image, start container, run in-container init.
# Mounts ../data (shared dataset) and ../ (ph2 work tree) into /work.

set -euo pipefail

IMAGE=apache/hadoop:3
NAME=hadoop-pseudo
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[run] pulling $IMAGE"
    docker pull "$IMAGE"
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
    if docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
        echo "[run] container $NAME already running"
    else
        echo "[run] starting existing container $NAME"
        docker start "$NAME"
    fi
else
    echo "[run] creating new container $NAME"
    docker run -d --name "$NAME" \
        -p 9870:9870 -p 8088:8088 -p 9000:9000 \
        -v "$PROJECT_ROOT/data:/work/data:ro" \
        -v "$PROJECT_ROOT/ph2:/work/ph2" \
        "$IMAGE" tail -f /dev/null
fi

echo "[run] running init-hadoop.sh inside container"
docker exec -u hadoop "$NAME" bash /work/ph2/docker/init-hadoop.sh

echo "[run] done. UIs: HDFS http://localhost:9870  YARN http://localhost:8088"
