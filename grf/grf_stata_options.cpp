#include "grf_stata_options.h"
#include <cstring>
#include <cstdlib>
#include <algorithm>
#include <cmath>

const char* extract_option(const char* key, int argc, char* argv[])
{
    size_t key_len = std::strlen(key);
    for (int i = 0; i < argc; i++) {
        if (std::strncmp(argv[i], key, key_len) == 0) {
            const char* p = argv[i] + key_len;
            while (*p && *p != '(') p++;
            if (*p == '(') {
                const char* start = p + 1;
                const char* end = start;
                while (*end && *end != ')') end++;
                if (*end == ')') {
                    static char buf[256];
                    size_t len = std::min(static_cast<size_t>(end - start), sizeof(buf) - 1);
                    std::strncpy(buf, start, len);
                    buf[len] = '\0';
                    return buf;
                }
            }
        }
    }
    return NULL;
}

bool parse_options(int argc, char* argv[], GrfOptions& opts, char* error_message)
{
    opts.num_trees = 2000;
    opts.seed = 12345;
    opts.num_threads = 16;
    opts.mtry = 0;       // 0 = use R default formula: min(ceil(sqrt(p)+20), p)
    opts.min_node_size = 5;
    opts.sample_fraction = 0.5;
    opts.honesty = true;
    opts.honesty_fraction = 0.5;
    opts.honesty_prune_leaves = true;
    opts.alpha = 0.05;
    opts.imbalance_penalty = 0.0;
    opts.stabilize_splits = true;
    opts.ci_group_size = 2;
    opts.compute_oob_predictions = false;
    opts.estimate_variance = false;
    opts.legacy_seed = false;
    opts.nfeatures = 0;
    opts.ntarget = 0;
    opts.ngroup = 0;

    const char* val = NULL;
    #define PARSE_INT(field, key) do { val = extract_option(key, argc, argv); if (val) opts.field = std::atoi(val); } while(0)
    #define PARSE_DBL(field, key) do { val = extract_option(key, argc, argv); if (val) opts.field = std::atof(val); } while(0)

    PARSE_INT(num_trees, "ntree");
    PARSE_INT(seed, "seed");
    PARSE_INT(num_threads, "nproc");
    PARSE_INT(mtry, "mtry");
    PARSE_INT(min_node_size, "minnodesize");
    PARSE_DBL(sample_fraction, "samplefraction");
    PARSE_DBL(honesty_fraction, "honestyfraction");
    PARSE_DBL(alpha, "alpha");
    PARSE_DBL(imbalance_penalty, "imbalancepenalty");
    PARSE_INT(ci_group_size, "cigroupsize");
    PARSE_INT(nfeatures, "nfeatures");
    PARSE_INT(ntarget, "ntarget");
    PARSE_INT(ngroup, "ngroup");

    val = extract_option("honesty", argc, argv);
    if (val) opts.honesty = (std::atoi(val) != 0);

    val = extract_option("nostabilizesplits", argc, argv);
    if (val) opts.stabilize_splits = false;

    val = extract_option("nohonestyprune", argc, argv);
    if (val) opts.honesty_prune_leaves = false;

    val = extract_option("computeoob", argc, argv);
    if (val) opts.compute_oob_predictions = (std::atoi(val) != 0);

    val = extract_option("estimatevariance", argc, argv);
    if (val) opts.estimate_variance = (std::atoi(val) != 0);

    #undef PARSE_INT
    #undef PARSE_DBL
    return true;
}

grf::ForestOptions build_forest_options(const GrfOptions& opts, const std::vector<size_t>& clusters, int nfeatures)
{
    // Apply R default mtry formula when mtry=0:
    //   mtry = min(ceil(sqrt(p) + 20), p)  where p = number of features
    grf::uint mtry = static_cast<grf::uint>(opts.mtry);
    if (mtry == 0 && nfeatures > 0) {
        mtry = static_cast<grf::uint>(std::min(
            static_cast<int>(std::ceil(std::sqrt(static_cast<double>(nfeatures)) + 20.0)),
            nfeatures));
    }

    return grf::ForestOptions(
        static_cast<grf::uint>(opts.num_trees),
        static_cast<size_t>(opts.ci_group_size),
        opts.sample_fraction,
        mtry,
        static_cast<grf::uint>(opts.min_node_size),
        opts.honesty, opts.honesty_fraction, opts.honesty_prune_leaves,
        opts.alpha, opts.imbalance_penalty,
        static_cast<grf::uint>(opts.num_threads),
        static_cast<grf::uint>(opts.seed),
        opts.legacy_seed, clusters, 0);
}
