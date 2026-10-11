#include "GazeNumerics.h"
#include <Accelerate/Accelerate.h>
#include <limits.h>
#include <math.h>
#include <stdlib.h>

enum { GAZE_COLUMNS = 3, GAZE_OUTPUTS = 2, GAZE_INVALID_INPUT = -1000,
       GAZE_WORKSPACE_FAILURE = -1001 };

int32_t gaze_solve_affine(int32_t rows, double *matrix, double *targets,
                          double rank_tolerance, int32_t *rank) {
    if (rows < GAZE_COLUMNS || !matrix || !targets || !rank ||
        !isfinite(rank_tolerance) || rank_tolerance <= 0 || rank_tolerance >= 1) {
        return GAZE_INVALID_INPUT;
    }
    __LAPACK_int m = rows, n = GAZE_COLUMNS, rhs = GAZE_OUTPUTS;
    __LAPACK_int pivots[GAZE_COLUMNS] = {0}, result_rank = 0, info = 0, work_count = -1;
    double query = 0;
    // LAPACK's pivoted QR exposes rank before ridge can hide degenerate inputs.
    dgelsy_(&m, &n, &rhs, matrix, &m, targets, &m, pivots, &rank_tolerance,
            &result_rank, &query, &work_count, &info);
    if (info != 0) { return info; }
    if (!isfinite(query) || query < 1 || query > INT_MAX) { return GAZE_WORKSPACE_FAILURE; }
    work_count = (__LAPACK_int)ceil(query);
    double *work = malloc((size_t)work_count * sizeof(double));
    if (!work) { return GAZE_WORKSPACE_FAILURE; }
    dgelsy_(&m, &n, &rhs, matrix, &m, targets, &m, pivots, &rank_tolerance,
            &result_rank, work, &work_count, &info);
    free(work);
    *rank = result_rank;
    return info;
}
