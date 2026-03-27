# YoloX - Android NDK Inference (C++)

This project presents a highly-optimized C++ implementation for running the **YoloX** target detection model directly on Android devices via native binary execution (using Android NDK, Shell or ADB).

This codebase is heavily inspired by and based on the work from [Qengineering/YoloX-ncnn-Raspberry-Pi-4](https://github.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4) but has been entirely refactored, modernized, and geared towards **Android compilation (`armeabi-v7a`, `arm64-v8a`)** using CMake and the **Tencent ncnn** framework, featuring:
- Seamless C++ structure splitting context gracefully (headers and implementation decoupling).
- POSIX-style Command Line Interface (CLI) parameters using `getopt` (no need to hardcode paths or configs anymore).
- Auto-download and setup of NCNN & OpenCV dependencies.
- Hardware-specific compiling tailored for ARM architecture (with explicit pipeline and instruction set targeting for `cortex-a55`).
- Fast math and Link Time Optimization (LTO) via GCC/Clang flags for max inference speed.
- Support for optional **Vulkan** GPU acceleration.

------------

## Original Paper & Reference
Paper: [YOLOX: Exceeding YOLO Series in 2021](https://arxiv.org/pdf/2107.08430.pdf)  
Original Repository (Raspberry Pi Focus): [YoloX-ncnn-Raspberry-Pi-4](https://github.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4)

------------

## How to Build

1. Ensure the paths to your local Android NDK are correctly set inside the `run.sh` script (default is `$HOME/Android/Sdk/ndk/...`).
2. Run the build script in your terminal. It will automatically detect the architecture of any connected ADB device to use the matching ABI, download OpenCV and NCNN, and compile an optimized release binary.

```bash
chmod +x run.sh
./run.sh
```

------------

## How to Run (Inside Android Shell via ADB)

Once built, the script outputs the executable file under `build/yolox_ncnn`. You should push it to the Android device, usually to a folder with execution permissions (like `/data/local/tmp/`), along with your target image and the pre-converted NCNN YoloX parameter (`.param`) and binary weight (`.bin`) models.

```bash
# Push executable and give permissions
adb push build/yolox_ncnn /data/local/tmp/
adb shell chmod +x /data/local/tmp/yolox_ncnn

# Push your network models and inference image
adb push yoloxS.param /data/local/tmp/
adb push yoloxS.bin /data/local/tmp/
adb push image_to_test.jpg /data/local/tmp/
```

### CLI Execution Example:

Run the inference by sshing into the machine or via `adb shell` dynamically mapping the parameters:

```bash
adb shell "cd /data/local/tmp && ./yolox_ncnn -i image_to_test.jpg -p yoloxS.param -b yoloxS.bin -s 640 -t 4 -o output.jpg"
```

To enable **Vulkan Acceleration**, just append the `-v` flag:
```bash
adb shell "cd /data/local/tmp && ./yolox_ncnn -i image_to_test.jpg -p yoloxS.param -b yoloxS.bin -s 640 -t 4 -v -o output.jpg"
```

Then fetch back the drawn outcome image:
```bash
adb pull /data/local/tmp/output.jpg ./output.jpg
```

### Command Line Options

| Flag | Meaning | Required | Default |
|:---:|---|:---:|:---:|
| `-i` | Path to the input image file | Yes | - |
| `-p` | Path to the `.param` NCNN file | Yes | - |
| `-b` | Path to the `.bin` NCNN file | Yes | - |
| `-s` | Target scale/size of inference | No | 640 |
| `-t` | Number of threads to use on NCNN | No | 4 |
| `-o` | Output file name for drawn bounding boxes | No | `output.jpg` |
| `-v` | Uses Vulcan GPU Hardware acceleration | No | `false` (CPU) |

------------

### Acknowledgments
This repository maintains the BSD 3-Clause permissive license for code sharing. Huge thanks to the [ncnn](https://github.com/Tencent/ncnn) open-source framework and to [Q-engineering](https://qengineering.eu) for providing a stellar foundation algorithm for C++ anchor-bound manipulation.
