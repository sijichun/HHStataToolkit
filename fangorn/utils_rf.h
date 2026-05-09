/**
 * utils_rf.h - Utility functions for fangorn plugin
 *
 * Provides:
 *   - LCG random number generator (for future bootstrap sampling)
 *   - Argsort (sort indices by double values)
 */

#ifndef UTILS_RF_H
#define UTILS_RF_H

#include <stdlib.h>

/* ============================================================================
 * LCG Random Number Generator
 * ============================================================================ */

typedef unsigned int lcg_state_t;

/* Seed the LCG state */
void lcg_seed(lcg_state_t *state, unsigned int seed);

/* Advance state and return next pseudo-random unsigned int */
unsigned int lcg_next(lcg_state_t *state);

/* Return uniform double in [0, 1) */
double lcg_uniform(lcg_state_t *state);

/* ============================================================================
 * Argsort
 * ============================================================================ */

/*
 * argsort_double:
 *   On entry,  indices[] is ignored.
 *   On return, indices[0..n-1] are the positions (0-based) in values[]
 *   such that values[indices[0]] <= values[indices[1]] <= ...
 *   i.e. indices[0] is the position of the smallest element.
 */
void argsort_double(double *values, int *indices, int n);

#endif /* UTILS_RF_H */
