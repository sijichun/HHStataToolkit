#ifndef SPLIT_H
#define SPLIT_H

#include "ent.h"

typedef double (*ImpurityFunc)(const double *y, const int *idx, int n, int n_classes);

typedef struct {
    int    feature;
    double threshold;
    double impurity_decrease;
    int    left_n;
    int    right_n;
    int    found;
} SplitResult;

double gini_impurity(const double *y, const int *idx, int n, int n_classes);
double entropy_impurity(const double *y, const int *idx, int n, int n_classes);
double mse_impurity(const double *y, const int *idx, int n, int n_classes);

ImpurityFunc get_impurity_func(int criterion);

void find_best_split(Dataset *data, const int *sample_idx, int n_samples,
                     double parent_impurity, const TreeParams *params,
                     SplitResult *result);

#endif /* SPLIT_H */
