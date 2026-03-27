cmake_minimum_required(VERSION 3.10)
project(yolox_ncnn C CXX)

set(CMAKE_CXX_STANDARD 17)

# Adding heavy optimization flags
# -mcpu=cortex-a55 optimizes instructions and pipelines EXACTLY for Cortex-A55
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -Ofast -ffast-math -flto -mcpu=cortex-a55")

# Base directory for libraries
set(LIB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/lib)

# ---------------------------------------------------------
# 1. Automatic Download and Extraction of NCNN (Vulkan Version)
# ---------------------------------------------------------
set(NCNN_DIR "${LIB_DIR}/ncnn-20260113-android-vulkan")
set(NCNN_URL "https://github.com/Tencent/ncnn/releases/download/20260113/ncnn-20260113-android-vulkan.zip")

if(NOT EXISTS ${NCNN_DIR})
    message(STATUS "NCNN Vulkan not found. Downloading from ${NCNN_URL}...")
    file(DOWNLOAD ${NCNN_URL} "${LIB_DIR}/ncnn-vulkan.zip" SHOW_PROGRESS)
    
    message(STATUS "Extracting NCNN Vulkan to lib directory...")
    execute_process(COMMAND ${CMAKE_COMMAND} -E tar xzf "${LIB_DIR}/ncnn-vulkan.zip" WORKING_DIRECTORY ${LIB_DIR})
    
    # Clean up the zip file after extraction
    file(REMOVE "${LIB_DIR}/ncnn-vulkan.zip")
endif()

# ---------------------------------------------------------
# Automatically download and extract OpenCV
# ---------------------------------------------------------
set(OPENCV_DIR "${LIB_DIR}/OpenCV-android-sdk")
set(OPENCV_URL "https://github.com/opencv/opencv/releases/download/4.12.0/opencv-4.12.0-android-sdk.zip")

if(NOT EXISTS ${OPENCV_DIR})
    message(STATUS "OpenCV not found. Downloading from ${OPENCV_URL}...")
    file(DOWNLOAD ${OPENCV_URL} "${LIB_DIR}/opencv.zip" SHOW_PROGRESS)
    
    message(STATUS "Extracting OpenCV to lib directory...")
    execute_process(COMMAND ${CMAKE_COMMAND} -E tar xzf "${LIB_DIR}/opencv.zip" WORKING_DIRECTORY ${LIB_DIR})
    
    # Cleanup the zip file
    file(REMOVE "${LIB_DIR}/opencv.zip")
endif()

# ---------------------------------------------------------
# Android NDK Configuration
# ---------------------------------------------------------

# NOTE: NCNN for Android has several folders for ABIs (e.g. arm64-v8a, armeabi-v7a).
# Getting the ABI of the connected device via ADB if not explicitly set
if(NOT DEFINED ANDROID_ABI)
    execute_process(
        COMMAND adb shell getprop ro.product.cpu.abi
        OUTPUT_VARIABLE ADB_ABI
        RESULT_VARIABLE ADB_RESULT
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(ADB_RESULT EQUAL 0 AND NOT "${ADB_ABI}" STREQUAL "")
        set(ANDROID_ABI "${ADB_ABI}" CACHE STRING "Target Android ABI")
        message(STATUS "ANDROID_ABI detected via adb: ${ANDROID_ABI}")
    else()
        set(ANDROID_ABI "arm64-v8a" CACHE STRING "Target Android ABI")
        message(WARNING "ADB did not detect a device or failed. Using default: ${ANDROID_ABI}")
    endif()
endif()

# OpenCV Configuration (using cmake directory from Android native SDK)
set(OpenCV_DIR "${OPENCV_DIR}/sdk/native/jni")
find_package(OpenCV REQUIRED)

# NCNN Configuration
set(ncnn_DIR "${NCNN_DIR}/${ANDROID_ABI}/lib/cmake/ncnn")
find_package(ncnn REQUIRED)

# Add the executable
file(GLOB SRC_FILES "src/*.cpp")
add_executable(yolox_ncnn ${SRC_FILES})

# Link dependencies (ncnn handles OpenMP and Vulkan internally in targets exported by CMake)
target_link_libraries(yolox_ncnn ncnn ${OpenCV_LIBS})

