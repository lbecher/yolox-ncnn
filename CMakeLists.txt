cmake_minimum_required(VERSION 3.11)
project(yolox_ncnn C CXX)

include(CheckCXXCompilerFlag)
include(CheckIPOSupported)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(YOLOX_ENABLE_FAST_MATH "Enable aggressive floating-point optimizations" ON)
option(YOLOX_ENABLE_LTO "Enable link-time optimization when supported" ON)
option(YOLOX_FETCH_NCNN "Download and build ncnn from source when it is not installed on Linux hosts" ON)
option(YOLOX_FETCH_NCNN_VULKAN "Enable Vulkan for the fetched Linux ncnn build" OFF)
set(YOLOX_FETCH_NCNN_TAG "20260113" CACHE STRING "ncnn Git tag to fetch for Linux host builds")

set(LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib")
file(MAKE_DIRECTORY "${LIB_DIR}")

function(yolox_add_supported_compile_option target option var_name)
    check_cxx_compiler_flag("${option}" "${var_name}")
    if(${var_name})
        target_compile_options(${target} PRIVATE "${option}")
    endif()
endfunction()

function(yolox_apply_platform_optimizations target)
    if(MSVC)
        target_compile_options(${target} PRIVATE
            $<$<CONFIG:Release>:/O2>
        )
        return()
    endif()

    target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:-O3>
    )

    if(YOLOX_ENABLE_FAST_MATH)
        yolox_add_supported_compile_option(${target} "-ffast-math" YOLOX_HAS_FFAST_MATH)
    endif()

    string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" YOLOX_SYSTEM_PROCESSOR)

    if(ANDROID)
        if(ANDROID_ABI MATCHES "arm64-v8a|armeabi-v7a")
            yolox_add_supported_compile_option(${target} "-mcpu=cortex-a55" YOLOX_HAS_ANDROID_A55)
        endif()
    elseif(APPLE AND YOLOX_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        yolox_add_supported_compile_option(${target} "-mcpu=apple-m1" YOLOX_HAS_APPLE_M1)
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND YOLOX_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|armv7|arm")
        yolox_add_supported_compile_option(${target} "-mcpu=cortex-a55" YOLOX_HAS_LINUX_A55)
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND YOLOX_SYSTEM_PROCESSOR MATCHES "x86_64|amd64")
        yolox_add_supported_compile_option(${target} "-march=x86-64-v3" YOLOX_HAS_X86_64_V3)
        yolox_add_supported_compile_option(${target} "-mtune=generic" YOLOX_HAS_MTUNE_GENERIC)
    endif()

    if(YOLOX_ENABLE_LTO)
        check_ipo_supported(RESULT YOLOX_IPO_SUPPORTED OUTPUT YOLOX_IPO_ERROR)
        if(YOLOX_IPO_SUPPORTED)
            set_property(TARGET ${target} PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)
        else()
            message(STATUS "IPO/LTO not enabled: ${YOLOX_IPO_ERROR}")
        endif()
    endif()
endfunction()

# ---------------------------------------------------------
# Dependencies
# ---------------------------------------------------------
if(ANDROID)
    set(NCNN_DIR "${LIB_DIR}/ncnn-20260113-android-vulkan")
    set(NCNN_URL "https://github.com/Tencent/ncnn/releases/download/20260113/ncnn-20260113-android-vulkan.zip")

    if(NOT EXISTS "${NCNN_DIR}")
        message(STATUS "NCNN Vulkan not found. Downloading from ${NCNN_URL}...")
        file(DOWNLOAD "${NCNN_URL}" "${LIB_DIR}/ncnn-vulkan.zip" SHOW_PROGRESS)

        message(STATUS "Extracting NCNN Vulkan to lib directory...")
        execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xzf "${LIB_DIR}/ncnn-vulkan.zip" WORKING_DIRECTORY "${LIB_DIR}")
        file(REMOVE "${LIB_DIR}/ncnn-vulkan.zip")
    endif()

    set(OPENCV_DIR "${LIB_DIR}/OpenCV-android-sdk")
    set(OPENCV_URL "https://github.com/opencv/opencv/releases/download/4.12.0/opencv-4.12.0-android-sdk.zip")

    if(NOT EXISTS "${OPENCV_DIR}")
        message(STATUS "OpenCV not found. Downloading from ${OPENCV_URL}...")
        file(DOWNLOAD "${OPENCV_URL}" "${LIB_DIR}/opencv.zip" SHOW_PROGRESS)

        message(STATUS "Extracting OpenCV to lib directory...")
        execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xzf "${LIB_DIR}/opencv.zip" WORKING_DIRECTORY "${LIB_DIR}")
        file(REMOVE "${LIB_DIR}/opencv.zip")
    endif()

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

    set(OpenCV_DIR "${OPENCV_DIR}/sdk/native/jni")
    set(ncnn_DIR "${NCNN_DIR}/${ANDROID_ABI}/lib/cmake/ncnn")
elseif(APPLE)
    set(NCNN_DIR "${LIB_DIR}/ncnn-20260113-macos-vulkan")
    set(NCNN_URL "https://github.com/Tencent/ncnn/releases/download/20260113/ncnn-20260113-macos-vulkan.zip")

    if(NOT EXISTS "${NCNN_DIR}/ncnn.framework")
        message(STATUS "NCNN macOS Vulkan not found. Downloading from ${NCNN_URL}...")
        file(DOWNLOAD "${NCNN_URL}" "${LIB_DIR}/ncnn-macos-vulkan.zip" SHOW_PROGRESS STATUS NCNN_DOWNLOAD_STATUS)
        list(GET NCNN_DOWNLOAD_STATUS 0 NCNN_DOWNLOAD_RESULT)
        if(NOT NCNN_DOWNLOAD_RESULT EQUAL 0)
            list(GET NCNN_DOWNLOAD_STATUS 1 NCNN_DOWNLOAD_ERROR)
            message(FATAL_ERROR "Failed to download ncnn macOS Vulkan: ${NCNN_DOWNLOAD_ERROR}")
        endif()

        message(STATUS "Extracting NCNN macOS Vulkan to lib directory...")
        file(MAKE_DIRECTORY "${NCNN_DIR}")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" -E tar xzf "${LIB_DIR}/ncnn-macos-vulkan.zip"
            WORKING_DIRECTORY "${NCNN_DIR}"
            RESULT_VARIABLE NCNN_EXTRACT_RESULT
        )
        file(REMOVE "${LIB_DIR}/ncnn-macos-vulkan.zip")
        if(NOT NCNN_EXTRACT_RESULT EQUAL 0)
            message(FATAL_ERROR "Failed to extract ncnn macOS Vulkan package.")
        endif()
    endif()

    if(NOT EXISTS "${NCNN_DIR}/ncnn.framework")
        message(FATAL_ERROR "ncnn macOS framework was not found at ${NCNN_DIR}/ncnn.framework")
    endif()

    set(YOLOX_NCNN_INCLUDE_DIRS "${NCNN_DIR}/ncnn.framework/Headers/ncnn")
    set(YOLOX_NCNN_LIBRARIES
        "${NCNN_DIR}/ncnn.framework"
        "${NCNN_DIR}/glslang.framework"
        "${NCNN_DIR}/openmp.framework"
    )

    find_library(YOLOX_VULKAN_FRAMEWORK Vulkan
        PATHS
            "$ENV{VULKAN_SDK}/Frameworks"
            "/opt/homebrew/opt/vulkan-loader/lib"
            "/usr/local/opt/vulkan-loader/lib"
            "/Library/Frameworks"
        NO_DEFAULT_PATH
    )
    if(NOT YOLOX_VULKAN_FRAMEWORK)
        find_library(YOLOX_VULKAN_FRAMEWORK Vulkan)
    endif()
    if(NOT YOLOX_VULKAN_FRAMEWORK)
        message(FATAL_ERROR "ncnn macOS Vulkan requires Vulkan.framework. Install the Vulkan SDK/MoltenVK or set VULKAN_SDK before configuring.")
    endif()
    list(APPEND YOLOX_NCNN_LIBRARIES "${YOLOX_VULKAN_FRAMEWORK}")

    message(STATUS "Configuring macOS host build for ${CMAKE_SYSTEM_PROCESSOR}")
    message(STATUS "Using bundled ncnn frameworks from ${NCNN_DIR}; OpenCV is resolved from the system or OpenCV_DIR.")
    message(STATUS "Using Vulkan framework from ${YOLOX_VULKAN_FRAMEWORK}")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(NCNN_DIR "${LIB_DIR}/ncnn-${YOLOX_FETCH_NCNN_TAG}-linux-source")

    message(STATUS "Configuring Linux host build for ${CMAKE_SYSTEM_PROCESSOR}")
    message(STATUS "Host builds use OpenCV from the system or OpenCV_DIR.")

    if(NOT YOLOX_FETCH_NCNN_VULKAN)
        find_package(ncnn QUIET)
    endif()

    if(ncnn_FOUND)
        message(STATUS "Using system ncnn package.")
    elseif(YOLOX_FETCH_NCNN)
        if(YOLOX_FETCH_NCNN_VULKAN)
            message(STATUS "Building fetched Linux ncnn with Vulkan enabled.")
        endif()
        message(STATUS "ncnn package not found. Downloading ncnn ${YOLOX_FETCH_NCNN_TAG} source to ${NCNN_DIR}...")
        include(FetchContent)

        set(NCNN_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
        set(NCNN_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
        set(NCNN_BUILD_TESTS OFF CACHE BOOL "" FORCE)
        set(NCNN_BUILD_BENCHMARK OFF CACHE BOOL "" FORCE)
        set(NCNN_BUILD_QUIRC OFF CACHE BOOL "" FORCE)
        set(NCNN_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
        set(NCNN_VULKAN ${YOLOX_FETCH_NCNN_VULKAN} CACHE BOOL "" FORCE)

        FetchContent_Declare(
            ncnn
            GIT_REPOSITORY https://github.com/Tencent/ncnn.git
            GIT_TAG ${YOLOX_FETCH_NCNN_TAG}
            GIT_SHALLOW TRUE
            SOURCE_DIR "${NCNN_DIR}"
            BINARY_DIR "${CMAKE_BINARY_DIR}/_deps/ncnn-build"
        )
        FetchContent_MakeAvailable(ncnn)
    else()
        message(FATAL_ERROR "ncnn package not found. Install ncnn, set ncnn_DIR/CMAKE_PREFIX_PATH, or enable YOLOX_FETCH_NCNN.")
    endif()

    set(YOLOX_NCNN_LIBRARIES ncnn)
else()
    message(STATUS "Configuring host build for ${CMAKE_SYSTEM_NAME}/${CMAKE_SYSTEM_PROCESSOR}")
    message(STATUS "Host builds use OpenCV and ncnn from the system or CMAKE_PREFIX_PATH.")
endif()

find_package(OpenCV REQUIRED)
if(ANDROID)
    find_package(ncnn REQUIRED)
    set(YOLOX_NCNN_LIBRARIES ncnn)
elseif(NOT APPLE AND NOT YOLOX_NCNN_LIBRARIES)
    find_package(ncnn REQUIRED)
    set(YOLOX_NCNN_LIBRARIES ncnn)
endif()

file(GLOB SRC_FILES "src/*.cpp")
add_executable(yolox_ncnn ${SRC_FILES})

if(YOLOX_NCNN_INCLUDE_DIRS)
    target_include_directories(yolox_ncnn PRIVATE ${YOLOX_NCNN_INCLUDE_DIRS})
endif()

target_link_libraries(yolox_ncnn PRIVATE ${YOLOX_NCNN_LIBRARIES} ${OpenCV_LIBS})
if(APPLE)
    set_property(TARGET yolox_ncnn APPEND PROPERTY BUILD_RPATH "${NCNN_DIR}")
endif()
yolox_apply_platform_optimizations(yolox_ncnn)
