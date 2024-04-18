cmake_minimum_required(VERSION 3.4.1)

file(GLOB_RECURSE cppPaths "../ios/Stockfish/src/*.cpp")
add_library(
  stockfish
  SHARED
  ../ios/FlutterStockfish/ffi.cpp
  ${cppPaths}
)

if(ANDROID_ABI STREQUAL arm64-v8a)
  target_compile_options(stockfish PRIVATE -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8)
else()
  target_compile_options(stockfish PRIVATE -DUSE_PTHREADS -DNDEBUG -O3)
endif()

file(DOWNLOAD https://tests.stockfishchess.org/api/nn/nn-5af11540bbfe.nnue ${CMAKE_BINARY_DIR}/nn-5af11540bbfe.nnue)
