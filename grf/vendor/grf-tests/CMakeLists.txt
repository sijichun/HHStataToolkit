cmake_minimum_required(VERSION 3.10)
project(grf_tests CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_compile_options(-std=c++17)

find_package(Threads REQUIRED)

file(GLOB_RECURSE GRF_CORE_SOURCES ../grf-core/src/*.cpp)
add_library(grf-core STATIC ${GRF_CORE_SOURCES})
target_include_directories(grf-core PUBLIC ../grf-core/src ../eigen ../grf-core/third_party)

add_executable(grf_tests
  setup.cpp
  ForestSmokeTest.cpp
  CausalForestTest.cpp
  RegressionPredictionStrategyTest.cpp
  utilities/FileTestUtilities.cpp
  utilities/ForestTestUtilities.cpp
)
target_link_libraries(grf_tests grf-core Threads::Threads)

enable_testing()
add_test(NAME grf_tests COMMAND grf_tests)
