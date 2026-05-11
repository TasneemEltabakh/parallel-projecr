# Project Phase 1

The goal of this project is to implement a parallel program using MPI to process a dataset efficiently by distributing the workload across multiple processes, and to compare performance with sequential execution. :contentReference[oaicite:0]{index=0}

## 1. Data Selection
- Each team must select a dataset.
- The dataset must contain at least one numeric column.
- The dataset size should be at least 100,000 rows. :contentReference[oaicite:1]{index=1}

## 2. Data Preparation
- Read the dataset.
- Extract the numeric column.
- Store the values in an array. :contentReference[oaicite:2]{index=2}

## 3. Sequential Implementation
Students must implement a sequential C program that performs one basic operation on the numeric data:
- Average
- Maximum
- Minimum :contentReference[oaicite:3]{index=3}

## 4. MPI Parallel Implementation
- Implement the same operation using MPI.
- Distribute data among processes. :contentReference[oaicite:4]{index=4}

## 5. Performance Measurement
- Compare sequential vs parallel performance. :contentReference[oaicite:5]{index=5}