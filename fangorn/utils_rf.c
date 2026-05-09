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
