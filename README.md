# YoloX - Android NDK Inference (C++)

This project presents a highly-optimized C++ implementation for running the **YoloX** target detection model directly on Android devices via native binary execution (using Android NDK, Shell or ADB), with host builds for macOS Apple Silicon, Linux ARM, and Linux amd64.

This codebase is heavily inspired by and based on the work from [Qengineering/YoloX-ncnn-Raspberry-Pi-4](https://github.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4) but has been entirely refactored, modernized, and geared towards **Android compilation (`armeabi-v7a`, `arm64-v8a`)**, **macOS Apple Silicon**, **Linux ARM**, and **Linux amd64** using CMake and the **Tencent ncnn** framework, featuring:
- Seamless C++ structure splitting context gracefully (headers and implementation decoupling).
- POSIX-style Command Line Interface (CLI) parameters using `getopt` (no need to hardcode paths or configs anymore).
- Auto-download and setup of NCNN for Android/macOS and OpenCV for Android builds.
- Hardware-specific compiling for Android/Linux ARM (`cortex-a55`), macOS Apple Silicon (`apple-m1`), and Linux amd64 (`x86-64-v3` when supported).
- Fast math and Link Time Optimization (LTO) via GCC/Clang flags for max inference speed.
- Support for optional **Vulkan** GPU acceleration.

------------

## Original Paper & Reference
Paper: [YOLOX: Exceeding YOLO Series in 2021](https://arxiv.org/pdf/2107.08430.pdf)  
Original Repository (Raspberry Pi Focus): [YoloX-ncnn-Raspberry-Pi-4](https://github.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4)

------------

## How to Build

### Android

The Android path automatically downloads the Android OpenCV SDK and the Vulkan-enabled ncnn Android release into `lib/`.

1. Ensure the paths to your local Android NDK are correctly set by `ANDROID_NDK_HOME` or available under your Android SDK.
2. Run the ADB build script. It will automatically detect the architecture of any connected ADB device to use the matching ABI, download OpenCV and NCNN, and compile an optimized release binary.

```bash
chmod +x run_adb.sh
./run_adb.sh
```

You can also configure Android directly:

```bash
cmake -B build-android \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build-android
```

### macOS Apple Silicon

The macOS path automatically downloads the Vulkan-enabled ncnn macOS release into `lib/`. Install OpenCV for the host system, then point CMake at its package config files if they are not already discoverable.

```bash
cmake -B build-macos -DCMAKE_BUILD_TYPE=Release
cmake --build build-macos
```

### Linux ARM / Linux amd64

Install OpenCV and ncnn for the host system, then build normally:

```bash
cmake -B build-linux -DCMAKE_BUILD_TYPE=Release
cmake --build build-linux
```

For non-standard dependency locations, pass `-DCMAKE_PREFIX_PATH=/path/to/opencv;/path/to/ncnn` or set `OpenCV_DIR` and `ncnn_DIR` explicitly. On macOS, `ncnn_DIR` is set automatically to the downloaded package unless you override it before configure.

------------

## How to Run (Inside Android Shell via ADB)

Once built, the script outputs the executable file under `build/yolox_ncnn`. You should push it to the Android device, usually to a folder with execution permissions (like `/data/local/tmp/`), along with your target image. COCO-pretrained NCNN YoloX models can be selected with `-w` and are cached automatically when `curl` or `wget` is available on the device.

```bash
# Push executable and give permissions
adb push build/yolox_ncnn /data/local/tmp/
adb shell chmod +x /data/local/tmp/yolox_ncnn

# Push your inference image
adb push image_to_test.jpg /data/local/tmp/
```

### CLI Execution Example:

Run the inference by sshing into the machine or via `adb shell` dynamically mapping the parameters:

```bash
adb shell "cd /data/local/tmp && ./yolox_ncnn -w tiny -i image_to_test.jpg -t 4 -o output.jpg"
```

To enable **Vulkan Acceleration**, just append the `-v` flag:
```bash
adb shell "cd /data/local/tmp && ./yolox_ncnn -w tiny -i image_to_test.jpg -t 4 -v -o output.jpg"
```

Then fetch back the drawn outcome image:
```bash
adb pull /data/local/tmp/output.jpg ./output.jpg
```

### Command Line Options

| Flag | Meaning | Required | Default |
|:---:|---|:---:|:---:|
| `-i` | Path to the input image file | Yes | - |
| `-w` | COCO-pretrained model preset: `nano`, `tiny`, `small` (`n`, `t`, `s` aliases) | No | - |
| `-p` | Path to the `.param` NCNN file | Required without `-w` | - |
| `-b` | Path to the `.bin` NCNN file | Required without `-w` | - |
| `-s` | Target scale/size override | No | Preset default, or 640 for manual models |
| `-t` | Number of threads to use on NCNN | No | 4 |
| `-o` | Output file name for drawn bounding boxes | No | `output.jpg` |
| `-v` | Uses Vulcan GPU Hardware acceleration | No | `false` (CPU) |

Preset defaults:

| Preset | Files | Target size |
|---|---|---:|
| `nano` / `n` | `yoloxN.param`, `yoloxN.bin` | 416 |
| `tiny` / `t` | `yoloxT.param`, `yoloxT.bin` | 416 |
| `small` / `s` | `yoloxS.param`, `yoloxS.bin` | 640 |

The model cache lookup order is `YOLOX_MODEL_CACHE`, `$HOME/.cache/yolox-ncnn`, then the current directory. If a preset is missing from every cache directory, the binary downloads it from the Qengineering YoloX NCNN model repository.

------------

### Acknowledgments
This repository maintains the BSD 3-Clause permissive license for code sharing. Huge thanks to the [ncnn](https://github.com/Tencent/ncnn) open-source framework and to [Q-engineering](https://qengineering.eu) for providing a stellar foundation algorithm for C++ anchor-bound manipulation.
