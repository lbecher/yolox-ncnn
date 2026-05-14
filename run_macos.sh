#!/bin/bash
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=/opt/homebrew
cmake --build build
./build/yolox_ncnn -w nano -i dog_bike_man.jpg -o output.jpg -t 8 --test-runs 20 --test-csv results_macos_cpu_t8.csv
