# Phase 2 build. Everything compiles and runs INSIDE the hadoop-pseudo
# container — the host only needs docker.
#
# The cluster must be up first:
#   ./docker/run-cluster.sh
# then:
#   make            # build the jar inside the container
#   make put        # upload data/data.txt into HDFS (one-time per session)
#   make test       # single end-to-end run at --reduces 4
#   make bench      # full sweep (15 runs x 4 reducer counts)
#   make clean      # wipe ph2/bin

CONTAINER ?= hadoop-pseudo
WORKDIR   ?= /work/ph2
JAR       := bin/phase2-mr.jar
INPUT_HDFS ?= /input/data.txt

SRC_FILES := $(shell find src/main/java -name '*.java' 2>/dev/null)

.PHONY: all clean put put-force test bench run shell logs

all: $(JAR)

HADOOP_JARS_DIR := .hadoop-jars
HADOOP_CP := $(shell find $(HADOOP_JARS_DIR) -name '*.jar' 2>/dev/null | tr '\n' ':')

$(JAR): $(SRC_FILES)
	@mkdir -p bin/classes
	@if [ -z "$(HADOOP_CP)" ]; then \
		echo "no hadoop jars in $(HADOOP_JARS_DIR)/ -- run docker/extract-hadoop-jars.sh"; \
		exit 1; \
	fi
	@echo "  [javac] $(words $(SRC_FILES)) sources"
	@javac --release 8 -Xlint:-options -cp "$(HADOOP_CP)" -d bin/classes $(SRC_FILES)
	@echo "  [jar]   $(JAR)"
	@jar cf $(JAR) -C bin/classes .

put: ../data/data.txt
	@docker exec -u hadoop $(CONTAINER) bash -c '\
		if hdfs dfs -test -e $(INPUT_HDFS); then \
			echo "[put] $(INPUT_HDFS) already in HDFS; use make put-force to replace"; \
		else \
			hdfs dfs -put /work/data/data.txt $(INPUT_HDFS); \
			echo "[put] uploaded $(INPUT_HDFS)"; \
		fi'

put-force:
	@docker exec -u hadoop $(CONTAINER) bash -c '\
		hdfs dfs -rm -f $(INPUT_HDFS) >/dev/null 2>&1; \
		hdfs dfs -put /work/data/data.txt $(INPUT_HDFS); \
		echo "[put] re-uploaded $(INPUT_HDFS)"'

test: all put
	docker exec -u hadoop -w $(WORKDIR) $(CONTAINER) \
		hadoop jar $(JAR) com.pdc.Driver \
		  --input $(INPUT_HDFS) --output /output/run --reduces 4 2>&1 \
		| grep -E '\[mr\]|^map|^reduce|Map-Reduce|completed successfully' \
		| tail -15

run: all put
	docker exec -u hadoop -w $(WORKDIR) $(CONTAINER) \
		hadoop jar $(JAR) com.pdc.Driver --input $(INPUT_HDFS) --output /output/run --reduces $(N)

bench: all put
	./bench/benchmark.sh

shell:
	docker exec -it -u hadoop $(CONTAINER) bash

logs:
	docker exec -u hadoop $(CONTAINER) ls /opt/hadoop/logs/

clean:
	rm -rf bin
