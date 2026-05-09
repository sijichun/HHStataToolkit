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
 * Bootstrap Sampling
 * ============================================================================ */

typedef struct {
    int *indices;      /* bootstrap sample indices (length = n_samples) */
    int n_samples;     /* = n_total (same size as original) */
    int *oob_mask;     /* 1 if observation is OOB, length = n_total */
    int n_oob;         /* count of OOB observations */
} BootstrapSample;

/*
 * Generate a bootstrap sample of size n_total with replacement.
 * seed: per-tree seed (will use seed + tree_index in caller)
 * bs: output structure (caller must call free_bootstrap afterwards)
 * Returns 0 on success, -1 on allocation failure.
 */
int bootstrap_sample(int n_total, unsigned int seed, BootstrapSample *bs);

/* Free memory allocated by bootstrap_sample */
void free_bootstrap(BootstrapSample *bs);

/*
 * Sample mtry unique features from [0, n_features-1] without replacement.
 * out_features must be pre-allocated with length >= mtry.
 * rng: LCG state (will be modified)
 */
void sample_features(int n_features, int mtry, int *out_features, lcg_state_t *rng);

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
