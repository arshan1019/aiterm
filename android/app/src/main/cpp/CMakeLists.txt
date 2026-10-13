cmake_minimum_required(VERSION 3.22.1)
project(aiterm_pty C)

add_library(aiterm-pty SHARED pty_native.c)
