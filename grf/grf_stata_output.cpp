#include <cstdio>
#include "grf_stata_output.h"
#include <cstring>

bool write_predictions_to_stata(
    const std::vector<grf::Prediction>& predictions,
    const std::vector<size_t>& row_map,
    int output_col_idx,
    int n_obs,
    char* error_message)
{
    // Initialize output column to missing for all observations
    for (ST_int row = 1; row <= n_obs; row++) {
        ST_retcode rc = SF_vstore(output_col_idx, row, SV_missval);
        if (rc != 0) {
            snprintf(error_message, 256, "SF_vstore failed at row=%d", row);
            return false;
        }
    }

    // Write predictions for touse observations
    for (size_t i = 0; i < row_map.size() && i < predictions.size(); i++) {
        ST_int row = static_cast<ST_int>(row_map[i]);
        double pred_val = predictions[i].get_predictions()[0];
        ST_retcode rc = SF_vstore(output_col_idx, row, static_cast<ST_double>(pred_val));
        if (rc != 0) {
            snprintf(error_message, 256, "SF_vstore failed at mapped row=%d", row);
            return false;
        }
    }
    return true;
}
