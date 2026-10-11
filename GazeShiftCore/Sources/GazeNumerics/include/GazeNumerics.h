#ifndef GAZE_NUMERICS_H
#define GAZE_NUMERICS_H
#include <stdint.h>

// Column-major matrix rows x 3, and two RHS columns with the same row stride.
// Inputs are overwritten; each solution occupies its RHS column's first 3 rows.
int32_t gaze_solve_affine(int32_t rows, double *matrix, double *targets,
                          double rank_tolerance, int32_t *rank);
#endif
