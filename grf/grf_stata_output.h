#ifndef GRF_STATA_OUTPUT_H
#define GRF_STATA_OUTPUT_H

#include <vector>
#include <cstddef>
#include "stplugin.h"
#include "prediction/Prediction.h"

bool write_predictions_to_stata(
    const std::vector<grf::Prediction>& predictions,
    const std::vector<size_t>& row_map,
    int output_col_idx,
    int n_obs,
    char* error_message
);

#endif
