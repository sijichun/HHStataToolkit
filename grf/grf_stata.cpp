#include "stplugin.h"
#include "grf_stata_data.h"
#include "grf_stata_options.h"
#include "grf_stata_output.h"

#include "forest/ForestTrainers.h"
#include "forest/ForestPredictors.h"
#include "forest/ForestOptions.h"

#include <cstring>
#include <string>
#include <vector>
#include <set>
#include <stdexcept>
#include <cstdio>

static bool run_regression(int, char**, const GrfOptions&, int*, int, ST_int, char*);
static bool run_causal(int, char**, const GrfOptions&, int*, int, ST_int, char*);

// Build minimal training data with only features + outcome + treatment
// (matching R's create_train_matrices behavior)
static bool build_minimal_training_data(
    int n_total_vars,
    int touse_col_idx,
    int outcome_idx,
    int treatment_idx,
    int n_features,
    char* error_msg,
    grf::Data*& out_data,
    std::vector<size_t>& out_row_map)
{
    ST_int n_obs = SF_nobs();
    if (n_obs < 1) { snprintf(error_msg, 256, "No observations"); return false; }

    // Read all columns into full buffer
    std::vector<double> full(n_total_vars * n_obs, 0.0);
    for (int c = 1; c <= n_total_vars; c++) {
        if (SF_var_is_string(c)) { snprintf(error_msg, 256, "String var at col %d", c); return false; }
        for (ST_int r = 1; r <= n_obs; r++) {
            ST_double v;
            if (SF_vdata(c, r, &v) != 0) { snprintf(error_msg, 256, "SF_vdata fail at %d,%d", c, r); return false; }
            // Only check missing on input cols (1..n_features+2 + yhat/what)
            if (c <= n_features + 4 && SF_is_missing(v)) {
                snprintf(error_msg, 256, "Missing at col=%d row=%d", c, r); return false;
            }
            full[(c-1)*n_obs + (r-1)] = v;
        }
    }

    // Count training obs
    size_t n_tr = 0;
    for (ST_int r = 1; r <= n_obs; r++)
        if (full[(touse_col_idx-1)*n_obs + (r-1)] == 1.0) n_tr++;
    if (n_tr < 2) { snprintf(error_msg, 256, "Need >=2 training obs"); return false; }

    // Build compact matrix: only features + outcome + treatment (n_features + 2 columns)
    int n_cols_compact = n_features + 2;
    auto* buf = new std::vector<double>(n_cols_compact * n_tr, 0.0);
    out_row_map.clear(); out_row_map.reserve(n_tr);

    // Which columns from full buffer to keep (1-based): 1..n_features, outcome_idx, treatment_idx
    int keep_cols[3];
    keep_cols[0] = n_features;                    // features go to cols 0..n_features-1
    keep_cols[1] = outcome_idx;                   // goes to compact col n_features
    keep_cols[2] = treatment_idx;                  // goes to compact col n_features+1

    size_t tr = 0;
    for (ST_int r = 1; r <= n_obs; r++) {
        if (full[(touse_col_idx-1)*n_obs + (r-1)] != 1.0) continue;
        out_row_map.push_back(static_cast<size_t>(r));

        // Copy features (1..n_features)
        for (int f = 0; f < n_features; f++)
            (*buf)[f * n_tr + tr] = full[f * n_obs + (r-1)];

        // Copy outcome (y_centered) at compact col = n_features
        (*buf)[n_features * n_tr + tr] = full[(outcome_idx-1) * n_obs + (r-1)];

        // Copy treatment (w_centered) at compact col = n_features+1
        (*buf)[(n_features+1) * n_tr + tr] = full[(treatment_idx-1) * n_obs + (r-1)];

        tr++;
    }

    out_data = new grf::Data(*buf, n_tr, n_cols_compact);
    out_data->set_outcome_index(static_cast<size_t>(n_features));
    out_data->set_treatment_index(static_cast<size_t>(n_features + 1));
    return true;
}

STDLL stata_call(int argc, char *argv[])
{
    char err[256] = {0};
    try {
        GrfOptions opts;
        if (!parse_options(argc, argv, opts, err)) { SF_error((char*)err); return 1; }
        if (opts.nfeatures < 1) { SF_error((char*)"nfeatures must be > 0"); return 1; }

        int n_total = opts.nfeatures + 10;
        int m[12];
        for (int i = 0; i < 12; i++) m[i] = opts.nfeatures + i;
        m[10] = opts.nfeatures + 10; // touse

        ST_int nobs = SF_nobs();
        const char* v = extract_option("ntotalvars", argc, argv);
        if (v) n_total = std::atoi(v);

        bool has_yhat = (extract_option("yhatidx", argc, argv) != NULL);
        if (has_yhat) return run_causal(argc, argv, opts, m, n_total, nobs, err) ? 0 : 1;
        else return run_regression(argc, argv, opts, m, n_total, nobs, err) ? 0 : 1;
    } catch (const std::exception& e) {
        snprintf(err, 256, "GRF error: %s", e.what()); SF_error((char*)err); return 1;
    } catch (...) { SF_error((char*)"Unknown error"); return 1; }
}

static bool run_regression(int, char**, const GrfOptions& opts, int* m,
    int n_total, ST_int n_obs, char* err)
{
    std::vector<size_t> rm, ec; grf::Data* d = nullptr;
    if (!build_training_data(n_total, opts.nfeatures+6, m[10], m[1], m[2], -1, -1, err, d, rm)) return false;
    auto fo = build_forest_options(opts, ec, opts.nfeatures);
    auto f = grf::regression_trainer().train(*d, fo);
    auto p = grf::regression_predictor(static_cast<uint>(opts.num_threads));
    auto preds = p.predict(f, *d, *d, false);
    if (!write_predictions_to_stata(preds, rm, m[7], n_obs, err)) { free_training_data(d); return false; }
    SF_scal_save((char*)"N", static_cast<ST_double>(n_obs));
    SF_scal_save((char*)"N_train", static_cast<ST_double>(rm.size()));
    free_training_data(d); return true;
}

static bool run_causal(int, char**, const GrfOptions& opts, int* m,
    int n_total, ST_int n_obs, char* err)
{
    std::vector<size_t> rm, ec; grf::Data* d = nullptr;

    // Build minimal data: only features + y_centered + w_centered
    // This matches R's create_train_matrices exactly:
    // train.matrix = [X, Y.centered, W.centered]
    if (!build_minimal_training_data(n_total, m[10], m[1], m[2],
                                      opts.nfeatures, err, d, rm))
        return false;

    d->set_instrument_index(static_cast<size_t>(opts.nfeatures + 1)); // same as treatment

    auto fo = build_forest_options(opts, ec, opts.nfeatures);
    auto f = grf::instrumental_trainer(0, opts.stabilize_splits).train(*d, fo);
    auto preds = grf::instrumental_predictor(static_cast<uint>(opts.num_threads))
                     .predict(f, *d, *d, opts.estimate_variance);

    if (!write_predictions_to_stata(preds, rm, m[7], n_obs, err)) { free_training_data(d); return false; }
    SF_scal_save((char*)"N", static_cast<ST_double>(n_obs));
    SF_scal_save((char*)"N_train", static_cast<ST_double>(rm.size()));
    free_training_data(d); return true;
}
