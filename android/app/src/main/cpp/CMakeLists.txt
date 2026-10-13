cmake_minimum_required(VERSION 3.22.1)
project(aiterm_native C CXX)

add_library(aiterm-pty SHARED pty_native.c)

set(NEEDLE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/needle)
add_library(needle STATIC IMPORTED)
set_target_properties(needle PROPERTIES IMPORTED_LOCATION ${NEEDLE_DIR}/libneedle.a)

add_library(aiterm-needle SHARED needle_jni.cpp)
target_include_directories(aiterm-needle PRIVATE ${NEEDLE_DIR})
target_compile_features(aiterm-needle PRIVATE cxx_std_17)
target_link_libraries(aiterm-needle needle m)
