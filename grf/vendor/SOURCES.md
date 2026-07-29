# 导入来源清单

上游：https://github.com/grf-labs/grf
版本：R package v2.6.1
导入方式：从 grf/grf/ 目录拷贝，2026-07-29 snapshot

## vendor/grf-core/src/

来源前缀：`grf/grf/core/src/`（GRF 仓库 C++ 核心目录）。

| 文件 | 来源 | 本地改动 |
|------|------|---------|
| analysis/SplitFrequencyComputer.cpp | grf/grf/core/src/analysis/SplitFrequencyComputer.cpp | 无 |
| analysis/SplitFrequencyComputer.h | grf/grf/core/src/analysis/SplitFrequencyComputer.h | 无 |
| commons/Data.cpp | grf/grf/core/src/commons/Data.cpp | 无 |
| commons/Data.h | grf/grf/core/src/commons/Data.h | 无 |
| commons/globals.h | grf/grf/core/src/commons/globals.h | 无 |
| commons/ProgressBar.cpp | grf/grf/core/src/commons/ProgressBar.cpp | 无 |
| commons/ProgressBar.h | grf/grf/core/src/commons/ProgressBar.h | 无 |
| commons/utility.cpp | grf/grf/core/src/commons/utility.cpp | 无 |
| commons/utility.h | grf/grf/core/src/commons/utility.h | 无 |
| forest/Forest.cpp | grf/grf/core/src/forest/Forest.cpp | 无 |
| forest/Forest.h | grf/grf/core/src/forest/Forest.h | 无 |
| forest/ForestOptions.cpp | grf/grf/core/src/forest/ForestOptions.cpp | 无 |
| forest/ForestOptions.h | grf/grf/core/src/forest/ForestOptions.h | 无 |
| forest/ForestPredictor.cpp | grf/grf/core/src/forest/ForestPredictor.cpp | 无 |
| forest/ForestPredictor.h | grf/grf/core/src/forest/ForestPredictor.h | 无 |
| forest/ForestPredictors.cpp | grf/grf/core/src/forest/ForestPredictors.cpp | 无 |
| forest/ForestPredictors.h | grf/grf/core/src/forest/ForestPredictors.h | 无 |
| forest/ForestTrainer.cpp | grf/grf/core/src/forest/ForestTrainer.cpp | 无 |
| forest/ForestTrainer.h | grf/grf/core/src/forest/ForestTrainer.h | 无 |
| forest/ForestTrainers.cpp | grf/grf/core/src/forest/ForestTrainers.cpp | 无 |
| forest/ForestTrainers.h | grf/grf/core/src/forest/ForestTrainers.h | 无 |
| prediction/CausalSurvivalPredictionStrategy.cpp | grf/grf/core/src/prediction/CausalSurvivalPredictionStrategy.cpp | 无 |
| prediction/CausalSurvivalPredictionStrategy.h | grf/grf/core/src/prediction/CausalSurvivalPredictionStrategy.h | 无 |
| prediction/collector/DefaultPredictionCollector.cpp | grf/grf/core/src/prediction/collector/DefaultPredictionCollector.cpp | 无 |
| prediction/collector/DefaultPredictionCollector.h | grf/grf/core/src/prediction/collector/DefaultPredictionCollector.h | 无 |
| prediction/collector/OptimizedPredictionCollector.cpp | grf/grf/core/src/prediction/collector/OptimizedPredictionCollector.cpp | 无 |
| prediction/collector/OptimizedPredictionCollector.h | grf/grf/core/src/prediction/collector/OptimizedPredictionCollector.h | 无 |
| prediction/collector/PredictionCollector.h | grf/grf/core/src/prediction/collector/PredictionCollector.h | 无 |
| prediction/collector/SampleWeightComputer.cpp | grf/grf/core/src/prediction/collector/SampleWeightComputer.cpp | 无 |
| prediction/collector/SampleWeightComputer.h | grf/grf/core/src/prediction/collector/SampleWeightComputer.h | 无 |
| prediction/collector/TreeTraverser.cpp | grf/grf/core/src/prediction/collector/TreeTraverser.cpp | 无 |
| prediction/collector/TreeTraverser.h | grf/grf/core/src/prediction/collector/TreeTraverser.h | 无 |
| prediction/DefaultPredictionStrategy.h | grf/grf/core/src/prediction/DefaultPredictionStrategy.h | 无 |
| prediction/InstrumentalPredictionStrategy.cpp | grf/grf/core/src/prediction/InstrumentalPredictionStrategy.cpp | 无 |
| prediction/InstrumentalPredictionStrategy.h | grf/grf/core/src/prediction/InstrumentalPredictionStrategy.h | 无 |
| prediction/LLCausalPredictionStrategy.cpp | grf/grf/core/src/prediction/LLCausalPredictionStrategy.cpp | 无 |
| prediction/LLCausalPredictionStrategy.h | grf/grf/core/src/prediction/LLCausalPredictionStrategy.h | 无 |
| prediction/LocalLinearPredictionStrategy.cpp | grf/grf/core/src/prediction/LocalLinearPredictionStrategy.cpp | 无 |
| prediction/LocalLinearPredictionStrategy.h | grf/grf/core/src/prediction/LocalLinearPredictionStrategy.h | 无 |
| prediction/MultiCausalPredictionStrategy.cpp | grf/grf/core/src/prediction/MultiCausalPredictionStrategy.cpp | 无 |
| prediction/MultiCausalPredictionStrategy.h | grf/grf/core/src/prediction/MultiCausalPredictionStrategy.h | 无 |
| prediction/MultiRegressionPredictionStrategy.cpp | grf/grf/core/src/prediction/MultiRegressionPredictionStrategy.cpp | 无 |
| prediction/MultiRegressionPredictionStrategy.h | grf/grf/core/src/prediction/MultiRegressionPredictionStrategy.h | 无 |
| prediction/ObjectiveBayesDebiaser.cpp | grf/grf/core/src/prediction/ObjectiveBayesDebiaser.cpp | 无 |
| prediction/ObjectiveBayesDebiaser.h | grf/grf/core/src/prediction/ObjectiveBayesDebiaser.h | 无 |
| prediction/OptimizedPredictionStrategy.h | grf/grf/core/src/prediction/OptimizedPredictionStrategy.h | 无 |
| prediction/Prediction.cpp | grf/grf/core/src/prediction/Prediction.cpp | 无 |
| prediction/Prediction.h | grf/grf/core/src/prediction/Prediction.h | 无 |
| prediction/PredictionValues.cpp | grf/grf/core/src/prediction/PredictionValues.cpp | 无 |
| prediction/PredictionValues.h | grf/grf/core/src/prediction/PredictionValues.h | 无 |
| prediction/ProbabilityPredictionStrategy.cpp | grf/grf/core/src/prediction/ProbabilityPredictionStrategy.cpp | 无 |
| prediction/ProbabilityPredictionStrategy.h | grf/grf/core/src/prediction/ProbabilityPredictionStrategy.h | 无 |
| prediction/QuantilePredictionStrategy.cpp | grf/grf/core/src/prediction/QuantilePredictionStrategy.cpp | 无 |
| prediction/QuantilePredictionStrategy.h | grf/grf/core/src/prediction/QuantilePredictionStrategy.h | 无 |
| prediction/RegressionPredictionStrategy.cpp | grf/grf/core/src/prediction/RegressionPredictionStrategy.cpp | 无 |
| prediction/RegressionPredictionStrategy.h | grf/grf/core/src/prediction/RegressionPredictionStrategy.h | 无 |
| prediction/SurvivalPredictionStrategy.cpp | grf/grf/core/src/prediction/SurvivalPredictionStrategy.cpp | 无 |
| prediction/SurvivalPredictionStrategy.h | grf/grf/core/src/prediction/SurvivalPredictionStrategy.h | 无 |
| relabeling/CausalSurvivalRelabelingStrategy.cpp | grf/grf/core/src/relabeling/CausalSurvivalRelabelingStrategy.cpp | 无 |
| relabeling/CausalSurvivalRelabelingStrategy.h | grf/grf/core/src/relabeling/CausalSurvivalRelabelingStrategy.h | 无 |
| relabeling/InstrumentalRelabelingStrategy.cpp | grf/grf/core/src/relabeling/InstrumentalRelabelingStrategy.cpp | 无 |
| relabeling/InstrumentalRelabelingStrategy.h | grf/grf/core/src/relabeling/InstrumentalRelabelingStrategy.h | 无 |
| relabeling/LLRegressionRelabelingStrategy.cpp | grf/grf/core/src/relabeling/LLRegressionRelabelingStrategy.cpp | 无 |
| relabeling/LLRegressionRelabelingStrategy.h | grf/grf/core/src/relabeling/LLRegressionRelabelingStrategy.h | 无 |
| relabeling/MultiCausalRelabelingStrategy.cpp | grf/grf/core/src/relabeling/MultiCausalRelabelingStrategy.cpp | 无 |
| relabeling/MultiCausalRelabelingStrategy.h | grf/grf/core/src/relabeling/MultiCausalRelabelingStrategy.h | 无 |
| relabeling/MultiNoopRelabelingStrategy.cpp | grf/grf/core/src/relabeling/MultiNoopRelabelingStrategy.cpp | 无 |
| relabeling/MultiNoopRelabelingStrategy.h | grf/grf/core/src/relabeling/MultiNoopRelabelingStrategy.h | 无 |
| relabeling/NoopRelabelingStrategy.cpp | grf/grf/core/src/relabeling/NoopRelabelingStrategy.cpp | 无 |
| relabeling/NoopRelabelingStrategy.h | grf/grf/core/src/relabeling/NoopRelabelingStrategy.h | 无 |
| relabeling/QuantileRelabelingStrategy.cpp | grf/grf/core/src/relabeling/QuantileRelabelingStrategy.cpp | 无 |
| relabeling/QuantileRelabelingStrategy.h | grf/grf/core/src/relabeling/QuantileRelabelingStrategy.h | 无 |
| relabeling/RelabelingStrategy.h | grf/grf/core/src/relabeling/RelabelingStrategy.h | 无 |
| RuntimeContext.cpp | grf/grf/core/src/RuntimeContext.cpp | 无 |
| RuntimeContext.h | grf/grf/core/src/RuntimeContext.h | 无 |
| sampling/RandomSampler.cpp | grf/grf/core/src/sampling/RandomSampler.cpp | 无 |
| sampling/RandomSampler.h | grf/grf/core/src/sampling/RandomSampler.h | 无 |
| sampling/SamplingOptions.cpp | grf/grf/core/src/sampling/SamplingOptions.cpp | 无 |
| sampling/SamplingOptions.h | grf/grf/core/src/sampling/SamplingOptions.h | 无 |
| splitting/AcceleratedSurvivalSplittingRule.cpp | grf/grf/core/src/splitting/AcceleratedSurvivalSplittingRule.cpp | 无 |
| splitting/AcceleratedSurvivalSplittingRule.h | grf/grf/core/src/splitting/AcceleratedSurvivalSplittingRule.h | 无 |
| splitting/CausalSurvivalSplittingRule.cpp | grf/grf/core/src/splitting/CausalSurvivalSplittingRule.cpp | 无 |
| splitting/CausalSurvivalSplittingRule.h | grf/grf/core/src/splitting/CausalSurvivalSplittingRule.h | 无 |
| splitting/factory/CausalSurvivalSplittingRuleFactory.cpp | grf/grf/core/src/splitting/factory/CausalSurvivalSplittingRuleFactory.cpp | 无 |
| splitting/factory/CausalSurvivalSplittingRuleFactory.h | grf/grf/core/src/splitting/factory/CausalSurvivalSplittingRuleFactory.h | 无 |
| splitting/factory/InstrumentalSplittingRuleFactory.cpp | grf/grf/core/src/splitting/factory/InstrumentalSplittingRuleFactory.cpp | 无 |
| splitting/factory/InstrumentalSplittingRuleFactory.h | grf/grf/core/src/splitting/factory/InstrumentalSplittingRuleFactory.h | 无 |
| splitting/factory/MultiCausalSplittingRuleFactory.cpp | grf/grf/core/src/splitting/factory/MultiCausalSplittingRuleFactory.cpp | 无 |
| splitting/factory/MultiCausalSplittingRuleFactory.h | grf/grf/core/src/splitting/factory/MultiCausalSplittingRuleFactory.h | 无 |
| splitting/factory/MultiRegressionSplittingRuleFactory.cpp | grf/grf/core/src/splitting/factory/MultiRegressionSplittingRuleFactory.cpp | 无 |
| splitting/factory/MultiRegressionSplittingRuleFactory.h | grf/grf/core/src/splitting/factory/MultiRegressionSplittingRuleFactory.h | 无 |
| splitting/factory/ProbabilitySplittingRuleFactory.cpp | grf/grf/core/src/splitting/factory/ProbabilitySplittingRuleFactory.cpp | 无 |
| splitting/factory/ProbabilitySplittingRuleFactory.h | grf/grf/core/src/splitting/factory/ProbabilitySplittingRuleFactory.h | 无 |
| splitting/factory/RegressionSplittingRuleFactory.cpp | grf/grf/core/src/splitting/factory/RegressionSplittingRuleFactory.cpp | 无 |
| splitting/factory/RegressionSplittingRuleFactory.h | grf/grf/core/src/splitting/factory/RegressionSplittingRuleFactory.h | 无 |
| splitting/factory/SplittingRuleFactory.h | grf/grf/core/src/splitting/factory/SplittingRuleFactory.h | 无 |
| splitting/factory/SurvivalSplittingRuleFactory.cpp | grf/grf/core/src/splitting/factory/SurvivalSplittingRuleFactory.cpp | 无 |
| splitting/factory/SurvivalSplittingRuleFactory.h | grf/grf/core/src/splitting/factory/SurvivalSplittingRuleFactory.h | 无 |
| splitting/InstrumentalSplittingRule.cpp | grf/grf/core/src/splitting/InstrumentalSplittingRule.cpp | 无 |
| splitting/InstrumentalSplittingRule.h | grf/grf/core/src/splitting/InstrumentalSplittingRule.h | 无 |
| splitting/MultiCausalSplittingRule.cpp | grf/grf/core/src/splitting/MultiCausalSplittingRule.cpp | 无 |
| splitting/MultiCausalSplittingRule.h | grf/grf/core/src/splitting/MultiCausalSplittingRule.h | 无 |
| splitting/MultiRegressionSplittingRule.cpp | grf/grf/core/src/splitting/MultiRegressionSplittingRule.cpp | 无 |
| splitting/MultiRegressionSplittingRule.h | grf/grf/core/src/splitting/MultiRegressionSplittingRule.h | 无 |
| splitting/ProbabilitySplittingRule.cpp | grf/grf/core/src/splitting/ProbabilitySplittingRule.cpp | 无 |
| splitting/ProbabilitySplittingRule.h | grf/grf/core/src/splitting/ProbabilitySplittingRule.h | 无 |
| splitting/RegressionSplittingRule.cpp | grf/grf/core/src/splitting/RegressionSplittingRule.cpp | 无 |
| splitting/RegressionSplittingRule.h | grf/grf/core/src/splitting/RegressionSplittingRule.h | 无 |
| splitting/SplittingRule.h | grf/grf/core/src/splitting/SplittingRule.h | 无 |
| splitting/SurvivalSplittingRule.cpp | grf/grf/core/src/splitting/SurvivalSplittingRule.cpp | 无 |
| splitting/SurvivalSplittingRule.h | grf/grf/core/src/splitting/SurvivalSplittingRule.h | 无 |
| tree/Tree.cpp | grf/grf/core/src/tree/Tree.cpp | 无 |
| tree/Tree.h | grf/grf/core/src/tree/Tree.h | 无 |
| tree/TreeOptions.cpp | grf/grf/core/src/tree/TreeOptions.cpp | 无 |
| tree/TreeOptions.h | grf/grf/core/src/tree/TreeOptions.h | 无 |
| tree/TreeTrainer.cpp | grf/grf/core/src/tree/TreeTrainer.cpp | 无 |
| tree/TreeTrainer.h | grf/grf/core/src/tree/TreeTrainer.h | 无 |

## vendor/grf-core/third_party/

GRF 核心自带的第三方单头文件库，随 GRF 一同拷贝。

| 文件 | 来源 | 本地改动 |
|------|------|---------|
| random/algorithm.hpp | grf/grf/core/third_party/random/algorithm.hpp（上游：effolkronium/random） | 无 |
| random/random.hpp | grf/grf/core/third_party/random/random.hpp（上游：effolkronium/random） | 无 |
| tqdm/tqdm.hpp | grf/grf/core/third_party/tqdm/tqdm.hpp（上游：tqdm-cpp） | 无 |

## vendor/eigen/

Eigen 线性代数头文件库（header-only），版本 3.4.0，MPL2 许可。
不逐文件列出源码，整体引用如下：

| 条目 | 来源 | 本地改动 |
|------|------|---------|
| Eigen/（全部 Eigen headers） | https://gitlab.com/libeigen/eigen（v3.4.0） | 无 |
| LICENSE | Eigen 3.4.0 发行包随附许可证文件（MPL2 及相关说明） | 无 |

## vendor/grf-tests/

GRF 上游 C++ 单元测试（来源前缀：`grf/grf/core/test/`）及本地测试基建。

| 文件 | 来源 | 本地改动 |
|------|------|---------|
| catch.hpp | grf/grf/core/test/third_party/catch/catch.hpp（Catch v2.13.10 单头文件） | 无 |
| CausalForestTest.cpp | grf/grf/core/test/forest/CausalForestTest.cpp | 无 |
| ForestSmokeTest.cpp | grf/grf/core/test/forest/ForestSmokeTest.cpp | 无 |
| RegressionPredictionStrategyTest.cpp | grf/grf/core/test/prediction/RegressionPredictionStrategyTest.cpp | 无 |
| utilities/FileTestUtilities.cpp | grf/grf/core/test/utilities/FileTestUtilities.cpp | 无 |
| utilities/FileTestUtilities.h | grf/grf/core/test/utilities/FileTestUtilities.h | 无 |
| utilities/ForestTestUtilities.cpp | grf/grf/core/test/utilities/ForestTestUtilities.cpp | 无 |
| utilities/ForestTestUtilities.h | grf/grf/core/test/utilities/ForestTestUtilities.h | 无 |
| test/forest/resources/*.csv（54 个数据文件） | grf/grf/core/test/forest/resources/ | 无 |
| setup.cpp | 本地新增（Catch 测试入口，替代上游 main.cpp 结构） | 本地文件 |
| CMakeLists.txt | 本地新增（测试构建脚本） | 本地文件 |

注：`grf-tests/build/` 为 CMake 构建产物目录，`grf-tests/test_results.log` 为测试运行输出，均非导入源码，不在本清单追踪范围内。
