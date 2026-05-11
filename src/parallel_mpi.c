// parallel_mpi.c -- MPI version of avg / min / max
// rank 0 reads the file, scatters chunks, every rank does its bit, then we reduce.
//
// build: gcc parallel_mpi.c -O2 -I"%MSMPI_INC%" -L"%MSMPI_LIB64%" -lmsmpi -o parallel_mpi.exe
// run:   mpiexec -n 4 parallel_mpi.exe data\data.bin

#include <stdio.h>
#include <stdlib.h>
#include <float.h>
#include <sys/stat.h>
#include <mpi.h>

int main(int argc, char **argv)
{
    MPI_Init(&argc, &argv);

    int rank, np;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &np);

    if (argc != 2) {
        if (rank == 0) fprintf(stderr, "usage: %s <data.bin>\n", argv[0]);
        MPI_Finalize();
        return 1;
    }

    long long N = 0;
    double *full = NULL;

    if (rank == 0) {
        struct stat st;
        if (stat(argv[1], &st) != 0) {
            perror(argv[1]);
            MPI_Abort(MPI_COMM_WORLD, 1);
        }
        N = st.st_size / (long long)sizeof(double);
        full = malloc((size_t)N * sizeof(double));
        FILE *f = fopen(argv[1], "rb");
        if (!f || fread(full, sizeof(double), (size_t)N, f) != (size_t)N) {
            fprintf(stderr, "read failed\n");
            MPI_Abort(MPI_COMM_WORLD, 1);
        }
        fclose(f);
        printf("[mpi] rank0 loaded %lld doubles from %s\n", N, argv[1]);
    }

    MPI_Bcast(&N, 1, MPI_LONG_LONG, 0, MPI_COMM_WORLD);

    // figure out chunk sizes -- last few ranks get one extra if N isn't divisible
    int *cnts = malloc(np * sizeof(int));
    int *disp = malloc(np * sizeof(int));
    long long base = N / np;
    long long rem  = N % np;
    int off = 0;
    for (int r = 0; r < np; r++) {
        cnts[r] = (int)(base + (r < rem ? 1 : 0));
        disp[r] = off;
        off += cnts[r];
    }

    int my_n = cnts[rank];
    double *buf = malloc(my_n * sizeof(double));

    MPI_Scatterv(full, cnts, disp, MPI_DOUBLE,
                 buf,  my_n,       MPI_DOUBLE,
                 0, MPI_COMM_WORLD);

    // warm cache (mirrors what sequential.c does so timing is fair)
    double warm = 0.0;
    for (int i = 0; i < my_n; i++) warm += buf[i];
    if (warm == 0.0) { /* don't let the compiler delete this */ }

    MPI_Barrier(MPI_COMM_WORLD);
    double t0 = MPI_Wtime();

    double s = 0.0, mx = -DBL_MAX, mn = DBL_MAX;
    for (int i = 0; i < my_n; i++) {
        double v = buf[i];
        s += v;
        if (v > mx) mx = v;
        if (v < mn) mn = v;
    }

    double gsum, gmx, gmn;
    MPI_Reduce(&s,  &gsum, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);
    MPI_Reduce(&mx, &gmx,  1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(&mn, &gmn,  1, MPI_DOUBLE, MPI_MIN, 0, MPI_COMM_WORLD);

    double t1 = MPI_Wtime();

    if (rank == 0) {
        double avg = gsum / (double)N;
        printf("[mpi] size=%d  n=%lld  avg=%.9f  min=%.9f  max=%.9f\n",
               np, N, avg, gmn, gmx);
        printf("[mpi] elapsed_ms=%.3f\n", (t1 - t0) * 1000.0);
    }

    free(buf);
    free(cnts);
    free(disp);
    if (rank == 0) free(full);

    MPI_Finalize();
    return 0;
}
