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
TEST_RUNS=${TEST_RUNS:-5}
THREADS=${THREADS:-"1 2 4"}
IMAGE=${IMAGE:-dog_bike_man.jpg}
REMOTE_DIR=${REMOTE_DIR:-/data/local/tmp}
REMOTE_OUT_DIR=${REMOTE_OUT_DIR:-$REMOTE_DIR/yolox_cpu_profile}
LOCAL_OUT_DIR=${LOCAL_OUT_DIR:-cpu_profile_android}
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

find_android_ndk() {
    if [ -n "${ANDROID_NDK_HOME:-}" ]; then
        echo "$ANDROID_NDK_HOME"
        return
    fi

    find "$ANDROID_SDK/ndk" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -r | head -n 1 || true
}

find_simpleperf_for_abi() {
    local ndk="$1"
    local abi="$2"
    local arch_dir

    case "$abi" in
        arm64-v8a) arch_dir=arm64 ;;
        armeabi-v7a) arch_dir=arm ;;
        x86_64) arch_dir=x86_64 ;;
        x86) arch_dir=x86 ;;
        *) arch_dir= ;;
    esac

    if [ -n "$arch_dir" ]; then
        local candidate="$ndk/simpleperf/bin/android/$arch_dir/simpleperf"
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return
        fi
    fi

    find "$ndk/simpleperf/bin/android" -path "*/simpleperf" -type f -perm -111 2>/dev/null | head -n 1 || true
}

ANDROID_NDK=$(find_android_ndk)
if [ -z "$ANDROID_NDK" ] || [ ! -f "$ANDROID_NDK/build/cmake/android.toolchain.cmake" ]; then
    echo "Android NDK not found under $ANDROID_SDK/ndk"
    echo "Install an Android NDK or set ANDROID_NDK_HOME to the NDK path."
    exit 1
fi

DEVICE_ABI=$("$ADB" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r' || true)
if [ -z "$DEVICE_ABI" ]; then
    echo "Device not found via ADB. Using armeabi-v7a as default."
    DEVICE_ABI="armeabi-v7a"
else
    echo "Device detected: $DEVICE_ABI"
fi

echo "Using Android SDK: $ANDROID_SDK"
echo "Using Android NDK: $ANDROID_NDK"
echo "Profiling model '$MODEL' with $TEST_RUNS run(s) for thread counts: $THREADS"

rm -rf build/
cmake -B build \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$DEVICE_ABI" \
    -DANDROID_PLATFORM=android-24 \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build

ensure_model_file "$MODEL_CACHE/$MODEL_PARAM" "$MODEL_PARAM_URL"
ensure_model_file "$MODEL_CACHE/$MODEL_BIN" "$MODEL_BIN_URL"

mkdir -p "$LOCAL_OUT_DIR"

"$ADB" shell "mkdir -p '$REMOTE_OUT_DIR'"
"$ADB" shell "rm -f '$REMOTE_OUT_DIR'/*"
"$ADB" push build/yolox_ncnn "$REMOTE_DIR/"
"$ADB" push "$MODEL_CACHE/$MODEL_PARAM" "$REMOTE_DIR/$MODEL_PARAM"
"$ADB" push "$MODEL_CACHE/$MODEL_BIN" "$REMOTE_DIR/$MODEL_BIN"
"$ADB" push "$IMAGE" "$REMOTE_DIR/$(basename "$IMAGE")"
"$ADB" shell chmod +x "$REMOTE_DIR/yolox_ncnn"

DEVICE_SIMPLEPERF=$("$ADB" shell 'command -v simpleperf 2>/dev/null' | tr -d '\r' || true)
if [ -z "$DEVICE_SIMPLEPERF" ]; then
    SIMPLEPERF_HOST=$(find_simpleperf_for_abi "$ANDROID_NDK" "$DEVICE_ABI")
    if [ -n "$SIMPLEPERF_HOST" ]; then
        echo "Pushing NDK simpleperf: $SIMPLEPERF_HOST"
        "$ADB" push "$SIMPLEPERF_HOST" "$REMOTE_DIR/simpleperf"
        "$ADB" shell chmod +x "$REMOTE_DIR/simpleperf"
        DEVICE_SIMPLEPERF="$REMOTE_DIR/simpleperf"
    fi
fi

if [ -z "$DEVICE_SIMPLEPERF" ]; then
    echo "simpleperf not found; continuing with timing CSV, CPU clocks, top -H, and /proc snapshots."
else
    echo "Using simpleperf: $DEVICE_SIMPLEPERF"
fi

for thread_count in $THREADS; do
    remote_csv="$REMOTE_OUT_DIR/results_t${thread_count}.csv"
    remote_clock_csv="$REMOTE_OUT_DIR/clocks_t${thread_count}.csv"
    remote_simpleperf="$REMOTE_OUT_DIR/simpleperf_t${thread_count}.txt"
    remote_top_log="$REMOTE_OUT_DIR/top_t${thread_count}.log"
    remote_proc_log="$REMOTE_OUT_DIR/proc_t${thread_count}.log"

    echo "Running $TEST_RUNS iteration(s) with -t $thread_count"

    "$ADB" shell "cd '$REMOTE_DIR' &&
        rm -f '$remote_csv' '$remote_clock_csv' '$remote_simpleperf' '$remote_top_log' '$remote_proc_log'
        touch '$REMOTE_OUT_DIR/profile_t${thread_count}.running'

        (
            while [ -f '$REMOTE_OUT_DIR/profile_t${thread_count}.running' ]; do
                pid=\$(pidof yolox_ncnn 2>/dev/null | awk '{print \$1}')
                if [ -n \"\$pid\" ]; then
                    {
                        echo \"--- \$(date +%s%3N) pid=\$pid ---\"
                        top -H -b -n 1 -p \"\$pid\" 2>/dev/null | head -n 40
                    } >> '$remote_top_log'
                    {
                        echo \"--- \$(date +%s%3N) pid=\$pid ---\"
                        cat \"/proc/\$pid/stat\" 2>/dev/null
                        for task in /proc/\$pid/task/*; do
                            tid=\$(basename \"\$task\")
                            printf 'tid=%s stat=' \"\$tid\"
                            cat \"\$task/stat\" 2>/dev/null
                        done
                    } >> '$remote_proc_log'
                fi
                sleep 0.05
            done
        ) &
        monitor_pid=\$!

        if [ -n '$DEVICE_SIMPLEPERF' ]; then
            '$DEVICE_SIMPLEPERF' stat \
                -e task-clock,cpu-cycles,instructions,cache-references,cache-misses,branch-misses,context-switches,cpu-migrations,page-faults \
                ./yolox_ncnn -w '$MODEL' -i '$(basename "$IMAGE")' -t '$thread_count' --test-runs '$TEST_RUNS' --test-csv '$remote_csv' --clock-csv '$remote_clock_csv' \
                > '$remote_simpleperf' 2>&1
            status=\$?
            if [ \"\$status\" -ne 0 ]; then
                {
                    echo
                    echo 'Custom simpleperf event set failed; retrying with simpleperf defaults.'
                } >> '$remote_simpleperf'
                '$DEVICE_SIMPLEPERF' stat \
                    ./yolox_ncnn -w '$MODEL' -i '$(basename "$IMAGE")' -t '$thread_count' --test-runs '$TEST_RUNS' --test-csv '$remote_csv' --clock-csv '$remote_clock_csv' \
                    >> '$remote_simpleperf' 2>&1
                status=\$?
            fi
            if [ \"\$status\" -ne 0 ]; then
                {
                    echo
                    echo 'simpleperf failed again; running benchmark without simpleperf.'
                } >> '$remote_simpleperf'
                ./yolox_ncnn -w '$MODEL' -i '$(basename "$IMAGE")' -t '$thread_count' --test-runs '$TEST_RUNS' --test-csv '$remote_csv' --clock-csv '$remote_clock_csv' \
                    >> '$remote_simpleperf' 2>&1
                status=\$?
            fi
        else
            ./yolox_ncnn -w '$MODEL' -i '$(basename "$IMAGE")' -t '$thread_count' --test-runs '$TEST_RUNS' --test-csv '$remote_csv' --clock-csv '$remote_clock_csv' \
                > '$remote_simpleperf' 2>&1
            status=\$?
        fi

        rm -f '$REMOTE_OUT_DIR/profile_t${thread_count}.running'
        wait \"\$monitor_pid\" 2>/dev/null
        exit \"\$status\""
done

"$ADB" pull "$REMOTE_OUT_DIR" "$LOCAL_OUT_DIR"

echo "Pulled profiling outputs to $LOCAL_OUT_DIR/$(basename "$REMOTE_OUT_DIR")"
echo "Compare results_t*.csv, clocks_t*.csv, simpleperf_t*.txt, top_t*.log, and proc_t*.log for 1/2/4 threads."
