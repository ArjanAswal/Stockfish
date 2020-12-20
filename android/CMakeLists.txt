cmake_minimum_required(VERSION 3.4.1)

file(GLOB_RECURSE cppPaths "../ios/Stockfish/src/*.cpp")
add_library(
  stockfish
  SHARED
  ../ios/FlutterStockfish/ffi.cpp
  ${cppPaths}
)

file(GLOB nnuePaths "../ios/Stockfish/src/*.nnue")
foreach(nnuePath ${nnuePaths})
  get_filename_component(nnueName ${nnuePath} NAME)
  configure_file(${nnuePath} ${nnueName} COPYONLY)
endforeach()
