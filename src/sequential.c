// sequential.c -- baseline: avg / min / max over data.bin
// build (Linux/macOS): gcc sequential.c -O2 -o sequential
// build (Windows):     gcc sequential.c -O2 -o sequential.exe
// run:                 ./sequential data/data.bin

#define _POSIX_C_SOURCE 199309L  // expose clock_gettime / CLOCK_MONOTONIC

#include <stdio.h>
#include <stdlib.h>
#include <float.h>
#include <sys/stat.h>

#ifdef _WIN32
  #include <windows.h>
  static double now_ms(void)
  {
      static LARGE_INTEGER f;
      static int init = 0;
      if (!init) { QueryPerformanceFrequency(&f); init = 1; }
      LARGE_INTEGER t;
      QueryPerformanceCounter(&t);
      return (double)t.QuadPart * 1000.0 / (double)f.QuadPart;
  }
#else
  #include <time.h>
  static double now_ms(void)
  {
      struct timespec ts;
      clock_gettime(CLOCK_MONOTONIC, &ts);
      return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
  }
#endif

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s <data.bin>\n", argv[0]);
        return 1;
    }

    struct stat st;
    if (stat(argv[1], &st) != 0) {
        perror(argv[1]);
        return 1;
    }
    size_t n = (size_t)(st.st_size / sizeof(double));

    double *a = malloc(n * sizeof(double));
    if (!a) { fprintf(stderr, "out of memory\n"); return 1; }

    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); free(a); return 1; }
    if (fread(a, sizeof(double), n, f) != n) {
        fprintf(stderr, "short read\n");
        fclose(f); free(a); return 1;
    }
    fclose(f);

    // warm the cache so the timed loop isn't measuring DRAM cold-start.
    // sink to a volatile so the compiler can't elide the read.
    double warm = 0.0;
    for (size_t i = 0; i < n; i++) warm += a[i];
    static volatile double sink;
    sink = warm;
    (void)sink;

    double t0 = now_ms();

    double sum = 0.0, mx = -DBL_MAX, mn = DBL_MAX;
    for (size_t i = 0; i < n; i++) {
        double v = a[i];
        sum += v;
        if (v > mx) mx = v;
        if (v < mn) mn = v;
    }

    double t1 = now_ms();
    double avg = sum / (double)n;

    printf("[seq] loaded %zu doubles from %s\n", n, argv[1]);
    printf("[seq] n=%zu  avg=%.9f  min=%.9f  max=%.9f\n", n, avg, mn, mx);
    printf("[seq] elapsed_ms=%.3f\n", t1 - t0);

    free(a);
    return 0;
}
