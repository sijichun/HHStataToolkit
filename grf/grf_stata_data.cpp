#include "grf_stata_data.h"
#include <cstring>
#include <cmath>

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
    std::vector<size_t>& out_row_map)
{
    ST_int n_obs = SF_nobs();
    if (n_obs < 1) {
        snprintf(error_message, 256, "No observations");
        return false;
    }

    std::vector<double> full_buffer(n_total_vars * n_obs, 0.0);

    for (int col = 1; col <= n_total_vars; col++) {
        if (SF_var_is_string(col)) {
            snprintf(error_message, 256, "String variable not allowed in column %d", col);
            return false;
        }
        for (ST_int row = 1; row <= n_obs; row++) {
            ST_double val;
            ST_retcode rc = SF_vdata(col, row, &val);
            if (rc != 0) {
                snprintf(error_message, 256, "SF_vdata failed at col=%d, row=%d", col, row);
                return false;
            }
            // Only check missing for input columns (not output variables)
            if (col <= n_input_cols && SF_is_missing(val)) {
                snprintf(error_message, 256, "Missing value at col=%d, row=%d", col, row);
                return false;
            }
            full_buffer[(col - 1) * n_obs + (row - 1)] = val;
        }
    }

    size_t n_train = 0;
    for (ST_int row = 1; row <= n_obs; row++) {
        if (full_buffer[(touse_col_idx - 1) * n_obs + (row - 1)] == 1.0)
            n_train++;
    }

    if (n_train < 2) {
        snprintf(error_message, 256, "Need >=2 training obs, found %zu", n_train);
        return false;
    }

    int n_train_cols = n_total_vars - 1;
    std::vector<double>* train_buffer = new std::vector<double>(n_train_cols * n_train, 0.0);
    out_row_map.clear();
    out_row_map.reserve(n_train);

    size_t train_row = 0;
    for (ST_int row = 1; row <= n_obs; row++) {
        if (full_buffer[(touse_col_idx - 1) * n_obs + (row - 1)] != 1.0)
            continue;
        out_row_map.push_back(static_cast<size_t>(row));
        for (int col = 0; col < n_train_cols; col++) {
            int full_col = (col >= touse_col_idx - 1) ? col + 1 : col;
            (*train_buffer)[col * n_train + train_row] =
                full_buffer[full_col * n_obs + (row - 1)];
        }
        train_row++;
    }

    int train_outcome_idx = outcome_idx - 1;
    int train_treatment_idx = treatment_idx - 1;
    if (outcome_idx > touse_col_idx) train_outcome_idx--;
    if (treatment_idx > touse_col_idx) train_treatment_idx--;

    int train_weight_idx = -1;
    if (weight_idx > 0) {
        train_weight_idx = weight_idx - 1;
        if (weight_idx > touse_col_idx) train_weight_idx--;
    }

    out_data = new grf::Data(*train_buffer, n_train, n_train_cols);
    out_data->set_outcome_index(static_cast<size_t>(train_outcome_idx));
    out_data->set_treatment_index(static_cast<size_t>(train_treatment_idx));
    if (train_weight_idx >= 0)
        out_data->set_weight_index(static_cast<size_t>(train_weight_idx));

    return true;
}

void free_training_data(grf::Data* data)
{
    if (data) delete data;
}
