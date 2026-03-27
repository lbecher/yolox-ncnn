#!/bin/bash

# Auto-detect the connected device's ABI
DEVICE_ABI=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
if [ -z "$DEVICE_ABI" ]; then
    echo "Device not found via ADB. Using armeabi-v7a as default."
    DEVICE_ABI="armeabi-v7a"
else
    echo "Device detected: $DEVICE_ABI"
fi

ANDROID_NDK=$HOME/Android/Sdk/ndk/30.0.14904198

# Remove previous build folder to prevent caching the old architecture
rm -rf build/

cmake -B build \
    -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=$DEVICE_ABI \
    -DANDROID_PLATFORM=android-24 \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build

adb push build/yolox_ncnn /data/local/tmp/
adb push yoloxT.param /data/local/tmp/
adb push yoloxT.bin /data/local/tmp/
adb push dog_bike_man.jpg /data/local/tmp/

adb shell chmod +x /data/local/tmp/yolox_ncnn
adb shell "cd /data/local/tmp && ./yolox_ncnn -i dog_bike_man.jpg -p yoloxT.param -b yoloxT.bin -s 416 -t 4 -o output.jpg"

adb pull /data/local/tmp/output.jpg ./output.jpg