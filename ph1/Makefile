# Cross-platform build for Linux/macOS.
# Windows users: use src/build.ps1 instead.

CC      ?= gcc
MPICC   ?= mpicc
CFLAGS  ?= -O2 -Wall

BIN_DIR := bin
SEQ     := $(BIN_DIR)/sequential
PAR     := $(BIN_DIR)/parallel_mpi

.PHONY: all clean test bench

all: $(SEQ) $(PAR)

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

$(SEQ): src/sequential.c | $(BIN_DIR)
	$(CC) $(CFLAGS) $< -o $@

$(PAR): src/parallel_mpi.c | $(BIN_DIR)
	$(MPICC) $(CFLAGS) $< -o $@

test: all
	./$(SEQ) data/data.bin
	mpiexec -n 1 ./$(PAR) data/data.bin
	mpiexec -n 2 ./$(PAR) data/data.bin
	mpiexec -n 4 ./$(PAR) data/data.bin

bench: all
	./bench/benchmark.sh

clean:
	rm -rf $(BIN_DIR)
