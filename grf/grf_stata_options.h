#ifndef GRF_STATA_OPTIONS_H
#define GRF_STATA_OPTIONS_H

#include <string>
#include <vector>
#include "stplugin.h"
#include "forest/ForestOptions.h"
#include "tree/TreeOptions.h"

struct GrfOptions {
    int num_trees;
    int seed;
    int num_threads;
    int mtry;
    int min_node_size;
    double sample_fraction;
    bool honesty;
    double honesty_fraction;
    bool honesty_prune_leaves;
    double alpha;
    double imbalance_penalty;
    bool stabilize_splits;
    int ci_group_size;
    bool compute_oob_predictions;
    bool estimate_variance;
    bool legacy_seed;
    int nfeatures;
    int ntarget;
    int ngroup;
};

bool parse_options(int argc, char* argv[], GrfOptions& opts, char* error_message);
const char* extract_option(const char* key, int argc, char* argv[]);
grf::ForestOptions build_forest_options(const GrfOptions& opts, const std::vector<size_t>& clusters, int nfeatures = 0);

#endif
