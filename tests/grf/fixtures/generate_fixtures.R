# generate_fixtures.R — Generate GRF parity reference CSV files
# Run with: Rscript tests/grf/fixtures/generate_fixtures.R
# Requires R >= 3.5 with grf package installed

library(grf)
set.seed(42)
options(grf.legacy.seed = FALSE)
output_dir <- "tests/grf/fixtures"

# Fixture 1: README example (n=2000, p=10)
message("Generating parity_readme1...")
n <- 2000; p <- 10
X <- matrix(rnorm(n * p), n, p)
W <- rbinom(n, 1, 0.4 + 0.2 * (X[, 1] > 0))
Y <- pmax(X[, 1], 0) * W + X[, 2] + pmin(X[, 3], 0) + rnorm(n)
X.test <- matrix(0, 101, p)
X.test[, 1] <- seq(-2, 2, length.out = 101)

cf <- causal_forest(X, Y, W, tune.parameters = "none",
                    num.threads = 1, seed = 12345)
tau_oob <- predict(cf)$predictions
tau_test <- predict(cf, X.test)$predictions

write.csv(data.frame(id = 1:length(tau_oob),
                     tau_oob = tau_oob,
                     tau_test = tau_test),
          file = file.path(output_dir, "parity_readme1.csv"),
          row.names = FALSE)

# Save the training data for Stata to import
train_data <- data.frame(id = 1:n, X, Y, W)
write.csv(train_data,
          file = file.path(output_dir, "parity_readme1_data.csv"),
          row.names = FALSE)

message("Fixtures generated successfully.")
message("Output directory: ", normalizePath(output_dir))
