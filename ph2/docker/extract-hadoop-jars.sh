#!/usr/bin/env bash
# One-time copy of Hadoop's jars out of the running container into a host
# cache, so the JAR can be built on the host (which has a working JDK).
# Hadoop's runtime classpath at job-submit time still comes from the
# container — these jars are only for compile-time.

set -euo pipefail

CONTAINER=${CONTAINER:-hadoop-pseudo}
DEST="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/.hadoop-jars"

if [[ -d "$DEST" ]] && find "$DEST" -name '*.jar' -print -quit | grep -q .; then
    echo "[extract] $DEST already populated; remove it to re-extract"
    exit 0
fi

mkdir -p "$DEST"
for d in common hdfs mapreduce yarn; do
    docker cp "$CONTAINER:/opt/hadoop/share/hadoop/$d" "$DEST/$d"
done
du -sh "$DEST"
echo "[extract] done"
