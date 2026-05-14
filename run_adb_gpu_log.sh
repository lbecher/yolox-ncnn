#!/bin/bash
set -euo pipefail

ANDROID_SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}
if [ ! -d "$ANDROID_SDK" ] && [ -d "$HOME/Android/Sdk" ]; then
    ANDROID_SDK="$HOME/Android/Sdk"
fi

ADB="$ANDROID_SDK/platform-tools/adb"
if [ ! -x "$ADB" ]; then
    echo "adb not found at $ADB"
    echo "Set ANDROID_SDK_ROOT to your Android SDK path or install Android platform-tools."
    exit 1
fi

MODEL=${MODEL:-nano}
TEST_RUNS=${TEST_RUNS:-20}
REMOTE_CSV=${REMOTE_CSV:-results_android_gpu.csv}
LOCAL_CSV=${LOCAL_CSV:-results_android_gpu.csv}
MODEL_CACHE=${YOLOX_MODEL_CACHE:-$HOME/.cache/yolox-ncnn}

case "$MODEL" in
    nano|n|yolox-n|yolox-nano)
        MODEL_PARAM=yoloxN.param
        MODEL_BIN=yoloxN.bin
        MODEL_PARAM_URL=https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxN.param
        MODEL_BIN_URL=https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxN.bin
        ;;
    tiny|t|yolox-t|yolox-tiny)
        MODEL_PARAM=yoloxT.param
        MODEL_BIN=yoloxT.bin
        MODEL_PARAM_URL=https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxT.param
        MODEL_BIN_URL=https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxT.bin
        ;;
    small|s|yolox-s|yolox-small)
        MODEL_PARAM=yoloxS.param
        MODEL_BIN=yoloxS.bin
        MODEL_PARAM_URL=https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxS.param
        MODEL_BIN_URL=https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxS.bin
        ;;
    *)
        echo "Unknown MODEL '$MODEL'. Use nano, tiny, or small."
        exit 1
        ;;
esac

ensure_model_file() {
    local path="$1"
    local url="$2"

    if [ -s "$path" ]; then
        return
    fi

    mkdir -p "$(dirname "$path")"
    echo "Downloading $(basename "$path") to $path"
    curl -fL --retry 3 -o "$path.download" "$url"
    mv "$path.download" "$path"
}

ANDROID_NDK=${ANDROID_NDK_HOME:-}
if [ -z "$ANDROID_NDK" ]; then
    ANDROID_NDK=$(find "$ANDROID_SDK/ndk" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -r | head -n 1 || true)
fi

if [ -z "$ANDROID_NDK" ] || [ ! -f "$ANDROID_NDK/build/cmake/android.toolchain.cmake" ]; then
    echo "Android NDK not found under $ANDROID_SDK/ndk"
    echo "Install an Android NDK or set ANDROID_NDK_HOME to the NDK path."
    exit 1
fi

# Auto-detect the connected device's ABI
DEVICE_ABI=$("$ADB" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r' || true)
if [ -z "$DEVICE_ABI" ]; then
    echo "Device not found via ADB. Using armeabi-v7a as default."
    DEVICE_ABI="armeabi-v7a"
else
    echo "Device detected: $DEVICE_ABI"
fi

echo "Using Android SDK: $ANDROID_SDK"
echo "Using Android NDK: $ANDROID_NDK"

# Remove previous build folder to prevent caching the old architecture
rm -rf build/

cmake -B build \
    -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=$DEVICE_ABI \
    -DANDROID_PLATFORM=android-24 \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build

ensure_model_file "$MODEL_CACHE/$MODEL_PARAM" "$MODEL_PARAM_URL"
ensure_model_file "$MODEL_CACHE/$MODEL_BIN" "$MODEL_BIN_URL"

#"$ADB" push build/yolox_ncnn /data/local/tmp/
"$ADB" push "$MODEL_CACHE/$MODEL_PARAM" "/data/local/tmp/$MODEL_PARAM"
"$ADB" push "$MODEL_CACHE/$MODEL_BIN" "/data/local/tmp/$MODEL_BIN"
#"$ADB" push dog_bike_man.jpg /data/local/tmp/

"$ADB" shell chmod +x /data/local/tmp/yolox_ncnn
"$ADB" shell 'cd /data/local/tmp &&
    rm -f gpu.log
    rm -f '"$REMOTE_CSV"'
    GPU_METRIC_DIR=
    GPU_METRICS=

    if [ -d /sys/class/mpgpu ]; then
        GPU_METRIC_DIR=/sys/class/mpgpu
        GPU_METRICS="cur_freq utilization util_cl util_gl domain_stat"
    else
        GPU_METRIC_DIR=$(find /sys/class/devfreq -maxdepth 1 \( -iname "*mali*" -o -iname "*gpu*" \) 2>/dev/null | head -n 1 || true)
        GPU_METRICS="cur_freq load utilisation busy_time total_time gpu_busy"
    fi

    if [ -n "$GPU_METRIC_DIR" ]; then
        echo "Sampling GPU metrics from $GPU_METRIC_DIR to /data/local/tmp/gpu.log"
        touch gpu_monitor.running
        (
            while [ -f gpu_monitor.running ]; do
                LINE=$(date +%s%3N)
                for metric in $GPU_METRICS; do
                    if [ -r "$GPU_METRIC_DIR/$metric" ]; then
                        VALUE=$(cat "$GPU_METRIC_DIR/$metric" | tr "\n" " ")
                        LINE="$LINE $metric=$VALUE"
                    fi
                done
                echo "$LINE"
                sleep 0.05
            done
        ) > gpu.log &
        GPU_MONITOR_PID=$!
    else
        echo "No readable Mali/GPU metrics node found; GPU metrics will not be sampled." | tee gpu.log
        GPU_MONITOR_PID=
    fi

    ./yolox_ncnn -w '"$MODEL"' -i dog_bike_man.jpg -t 4 -g --test-runs '"$TEST_RUNS"' --test-csv '"$REMOTE_CSV"'
    STATUS=$?

    if [ -n "$GPU_MONITOR_PID" ]; then
        rm -f gpu_monitor.running
        wait "$GPU_MONITOR_PID" 2>/dev/null
    fi

    exit "$STATUS"'

"$ADB" pull "/data/local/tmp/$REMOTE_CSV" "./$LOCAL_CSV"
"$ADB" pull /data/local/tmp/gpu.log ./gpu.log
