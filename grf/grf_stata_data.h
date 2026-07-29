#ifndef GRF_STATA_DATA_H
#define GRF_STATA_DATA_H

#include <cstddef>
#include <vector>
#include "stplugin.h"
#include "commons/Data.h"

bool build_training_data(
    int n_total_vars,
    int n_input_cols,
    int touse_col_idx,
    int outcome_idx,
    int treatment_idx,
    int weight_idx,
    int cluster_idx,
    char* error_message,
    grf::Data*& out_data,
    std::vector<size_t>& out_row_map
);

void free_training_data(grf::Data* data);

#endif
