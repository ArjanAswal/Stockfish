cmake_minimum_required(VERSION 3.4.1)

file(GLOB_RECURSE cppPaths "../ios/Stockfish/src/*.cpp")
add_library(
  stockfish
  SHARED
  ../ios/FlutterStockfish/ffi.cpp
  ${cppPaths}
)

file(DOWNLOAD https://tests.stockfishchess.org/api/nn/nn-ad9b42354671.nnue ${CMAKE_BINARY_DIR}/nn-ad9b42354671.nnue)
