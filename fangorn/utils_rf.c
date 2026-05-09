/**
 * utils_rf.c - Random forest utility functions implementation
 */

#include "utils_rf.h"
#include <string.h>

/* ============================================================================
 * LCG Random Number Generator
 * Park-Miller multiplier=1664525, increment=1013904223
 * ============================================================================ */

void lcg_seed(lcg_state_t *state, unsigned int seed)
{
    *state = seed ? seed : 1u;
}

unsigned int lcg_next(lcg_state_t *state)
{
    *state = (lcg_state_t)(1664525u * (unsigned int)(*state) + 1013904223u);
    return *state;
}

double lcg_uniform(lcg_state_t *state)
{
    return (double)lcg_next(state) / 4294967296.0;
}

/* ============================================================================
 * Bootstrap Sampling
 * ============================================================================ */

int bootstrap_sample(int n_total, unsigned int seed, BootstrapSample *bs)
{
    int i;
    int *count;
    lcg_state_t rng;

    bs->indices = (int *)malloc((size_t)n_total * sizeof(int));
    bs->oob_mask = (int *)calloc((size_t)n_total, sizeof(int));
    if (!bs->indices || !bs->oob_mask) {
        free(bs->indices);
        free(bs->oob_mask);
        return -1;
    }

    lcg_seed(&rng, seed);

    count = (int *)calloc((size_t)n_total, sizeof(int));
    if (!count) {
        free(bs->indices);
        free(bs->oob_mask);
        return -1;
    }

    for (i = 0; i < n_total; i++) {
        int idx = (int)(lcg_uniform(&rng) * n_total);
        bs->indices[i] = idx;
        count[idx]++;
    }

    bs->n_oob = 0;
    for (i = 0; i < n_total; i++) {
        if (count[i] == 0) {
            bs->oob_mask[i] = 1;
            bs->n_oob++;
        }
    }

    bs->n_samples = n_total;
    free(count);
    return 0;
}

void free_bootstrap(BootstrapSample *bs)
{
    if (!bs) return;
    free(bs->indices);
    free(bs->oob_mask);
    bs->indices = NULL;
    bs->oob_mask = NULL;
    bs->n_samples = 0;
    bs->n_oob = 0;
}

void sample_features(int n_features, int mtry, int *out_features, lcg_state_t *rng)
{
    int i, j, tmp;
    int *pool;

    if (mtry >= n_features) {
        for (i = 0; i < n_features; i++) out_features[i] = i;
        return;
    }

    pool = (int *)malloc((size_t)n_features * sizeof(int));
    if (!pool) {
        for (i = 0; i < mtry; i++) out_features[i] = i % n_features;
        return;
    }

    for (i = 0; i < n_features; i++) pool[i] = i;

    for (i = 0; i < mtry; i++) {
        j = i + (int)(lcg_uniform(rng) * (n_features - i));
        tmp = pool[i];
        pool[i] = pool[j];
        pool[j] = tmp;
        out_features[i] = pool[i];
    }

    free(pool);
}

/* ============================================================================
 * Argsort: sort indices by double values using (value, index) pairs + qsort
 * ============================================================================ */

typedef struct {
    double val;
    int    idx;
} indexed_double_t;

static int cmp_indexed_double(const void *a, const void *b)
{
    const indexed_double_t *da = (const indexed_double_t *)a;
    const indexed_double_t *db = (const indexed_double_t *)b;
    if (da->val < db->val) return -1;
    if (da->val > db->val) return  1;
    return 0;
}

void argsort_double(double *values, int *indices, int n)
{
    indexed_double_t *pairs;
    int i;

    pairs = (indexed_double_t *)malloc((size_t)n * sizeof(indexed_double_t));
    if (!pairs) {
        for (i = 0; i < n; i++) indices[i] = i;
        return;
    }

    for (i = 0; i < n; i++) {
        pairs[i].val = values[i];
        pairs[i].idx = i;
    }
    qsort(pairs, (size_t)n, sizeof(indexed_double_t), cmp_indexed_double);
    for (i = 0; i < n; i++) indices[i] = pairs[i].idx;

    free(pairs);
}
