#!/bin/bash
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=/opt/homebrew
cmake --build build
./build/yolox_ncnn -w nano -i dog_bike_man.jpg -o output.jpg -t 4 -g --test-runs 20 --test-csv results_macos_gpu_half.csv
