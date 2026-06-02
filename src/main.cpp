#include "yolox.hpp"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <getopt.h>
#include <iostream>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <vector>
#include <opencv2/highgui/highgui.hpp>

struct ModelPreset {
    const char* name;
    const char* param_file;
    const char* bin_file;
    const char* param_url;
    const char* bin_url;
    int target_size;
};

const std::vector<ModelPreset>& model_presets() {
    static const std::vector<ModelPreset> presets = {
        {
            "nano",
            "yoloxN.param",
            "yoloxN.bin",
            "https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxN.param",
            "https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxN.bin",
            416,
        },
        {
            "tiny",
            "yoloxT.param",
            "yoloxT.bin",
            "https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxT.param",
            "https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxT.bin",
            416,
        },
        {
            "small",
            "yoloxS.param",
            "yoloxS.bin",
            "https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxS.param",
            "https://raw.githubusercontent.com/Qengineering/YoloX-ncnn-Raspberry-Pi-4/main/yoloxS.bin",
            640,
        },
    };
    return presets;
}

const ModelPreset* find_model_preset(const std::string& name) {
    for (const auto& preset : model_presets()) {
        if (name == preset.name || name == std::string("yolox-") + preset.name) {
            return &preset;
        }
    }
    if (name == "n") return find_model_preset("nano");
    if (name == "t") return find_model_preset("tiny");
    if (name == "s") return find_model_preset("small");
    if (name == "yolox-n") return find_model_preset("nano");
    if (name == "yolox-t") return find_model_preset("tiny");
    if (name == "yolox-s") return find_model_preset("small");
    return nullptr;
}

bool file_exists(const std::string& path) {
    struct stat st {};
    return stat(path.c_str(), &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0;
}

bool ensure_dir(const std::string& path) {
    struct stat st {};
    if (stat(path.c_str(), &st) == 0) {
        return S_ISDIR(st.st_mode);
    }

    const size_t slash = path.find_last_of('/');
    if (slash != std::string::npos && slash > 0) {
        const std::string parent = path.substr(0, slash);
        if (!ensure_dir(parent)) {
            return false;
        }
    }

    return mkdir(path.c_str(), 0755) == 0;
}

bool can_write_dir(const std::string& path) {
    if (!ensure_dir(path)) {
        return false;
    }

    const std::string probe = path + "/.write-test";
    FILE* fp = std::fopen(probe.c_str(), "w");
    if (!fp) {
        return false;
    }
    std::fclose(fp);
    std::remove(probe.c_str());
    return true;
}

std::string join_path(const std::string& dir, const std::string& file) {
    if (dir.empty() || dir == ".") {
        return file;
    }
    if (dir.back() == '/') {
        return dir + file;
    }
    return dir + "/" + file;
}

std::string shell_quote(const std::string& value) {
    std::string quoted = "'";
    for (char c : value) {
        if (c == '\'') {
            quoted += "'\\''";
        } else {
            quoted += c;
        }
    }
    quoted += "'";
    return quoted;
}

bool run_download_command(const std::string& command) {
    int result = std::system(command.c_str());
    return result == 0;
}

bool download_file(const std::string& url, const std::string& output_path) {
    const std::string tmp_path = output_path + ".download";
    std::remove(tmp_path.c_str());

    const std::string quoted_url = shell_quote(url);
    const std::string quoted_tmp = shell_quote(tmp_path);
    const std::string curl_cmd = "curl -fL --retry 3 -o " + quoted_tmp + " " + quoted_url;
    const std::string wget_cmd = "wget -O " + quoted_tmp + " " + quoted_url;

    if (!run_download_command(curl_cmd) && !run_download_command(wget_cmd)) {
        std::remove(tmp_path.c_str());
        return false;
    }

    if (!file_exists(tmp_path) || std::rename(tmp_path.c_str(), output_path.c_str()) != 0) {
        std::remove(tmp_path.c_str());
        return false;
    }

    return true;
}

std::vector<std::string> cache_dirs() {
    std::vector<std::string> dirs;
    const char* model_cache = std::getenv("YOLOX_MODEL_CACHE");
    if (model_cache && model_cache[0] != '\0') {
        dirs.emplace_back(model_cache);
    }

    const char* home = std::getenv("HOME");
    if (home && home[0] != '\0') {
        dirs.emplace_back(std::string(home) + "/.cache/yolox-ncnn");
    }

    dirs.emplace_back(".");
    return dirs;
}

bool resolve_model_files(const ModelPreset& preset, std::string& param_path, std::string& bin_path) {
    for (const auto& dir : cache_dirs()) {
        const std::string candidate_param = join_path(dir, preset.param_file);
        const std::string candidate_bin = join_path(dir, preset.bin_file);
        if (file_exists(candidate_param) && file_exists(candidate_bin)) {
            param_path = candidate_param;
            bin_path = candidate_bin;
            return true;
        }
    }

    for (const auto& dir : cache_dirs()) {
        if (!can_write_dir(dir)) {
            continue;
        }

        const std::string candidate_param = join_path(dir, preset.param_file);
        const std::string candidate_bin = join_path(dir, preset.bin_file);
        std::cout << "Model '" << preset.name << "' not found. Downloading to " << dir << "\n";

        if (!file_exists(candidate_param) && !download_file(preset.param_url, candidate_param)) {
            std::cerr << "Error: Failed to download " << preset.param_file << "\n";
            return false;
        }
        if (!file_exists(candidate_bin) && !download_file(preset.bin_url, candidate_bin)) {
            std::cerr << "Error: Failed to download " << preset.bin_file << "\n";
            return false;
        }

        param_path = candidate_param;
        bin_path = candidate_bin;
        return true;
    }

    std::cerr << "Error: No writable model cache directory found.\n";
    return false;
}

static int cpu_core_count() {
    int n = 0;
    while (true) {
        std::string path = "/sys/devices/system/cpu/cpu" + std::to_string(n) + "/cpufreq/scaling_cur_freq";
        FILE* f = std::fopen(path.c_str(), "r");
        if (!f) break;
        std::fclose(f);
        ++n;
    }
    return n;
}

static long read_cpu_freq_khz(int cpu) {
    std::string path = "/sys/devices/system/cpu/cpu" + std::to_string(cpu) + "/cpufreq/scaling_cur_freq";
    FILE* f = std::fopen(path.c_str(), "r");
    if (!f) return -1;
    long freq = -1;
    std::fscanf(f, "%ld", &freq);
    std::fclose(f);
    return freq;
}

std::string csv_escape(const std::string& value) {
    std::string escaped = "\"";
    for (char c : value) {
        if (c == '"') {
            escaped += "\"\"";
        } else {
            escaped += c;
        }
    }
    escaped += "\"";
    return escaped;
}

void print_usage() {
    std::cout << "Usage: ./yolox_ncnn -i <image_path> [-w <model>] [-p <param_path> -b <bin_path>] [-s <target_size>] [-t <threads>] [-o <output_path>] [-g|--gpu] [--test-runs <n> --test-csv <path>] [--clock-csv <path>]\n"
              << "Options:\n"
              << "  -i  Path to the input image (required)\n"
              << "  -w  COCO pretrained model preset: nano, tiny, small (aliases: n, t, s)\n"
              << "  -p  Path to the ncnn .param file (required if -w is not used)\n"
              << "  -b  Path to the ncnn .bin file (required if -w is not used)\n"
              << "  -s  Target size override (defaults: nano/tiny=416, small/manual=640)\n"
              << "  -t  Number of threads for ncnn (default: 4)\n"
              << "  -o  Path to save the output image (default: output.jpg)\n"
              << "  -g, --gpu  Enable Vulkan GPU compute (default: false)\n"
              << "  --test-runs  Run benchmark/test mode with N repeated inferences\n"
              << "  --test-csv   Path to save per-run benchmark results as CSV\n"
              << "  --clock-csv  Path to save CPU core clock samples (sampled every 50 ms during test-runs)\n"
              << "               CSV columns: timestamp_ms, run, cpu0_khz, cpu1_khz, ...\n"
              << "               Requires --test-runs.\n"
              << "Environment:\n"
              << "  YOLOX_MODEL_CACHE  Directory used to cache preset model files\n";
}

int main(int argc, char** argv) {
    std::string image_path;
    std::string model_name;
    std::string param_path;
    std::string bin_path;
    std::string output_path = "output.jpg";
    int target_size = 640;
    bool target_size_overridden = false;
    int num_threads = 4;
    bool use_vulkan = false;
    int test_runs = 0;
    std::string test_csv_path;
    std::string clock_csv_path;
    bool test_runs_set = false;
    bool test_csv_set = false;
    bool clock_csv_set = false;

    static const option long_options[] = {
        {"gpu", no_argument, nullptr, 'g'},
        {"test-runs", required_argument, nullptr, 1000},
        {"test-csv", required_argument, nullptr, 1001},
        {"clock-csv", required_argument, nullptr, 1002},
        {"help", no_argument, nullptr, 'h'},
        {nullptr, 0, nullptr, 0},
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "i:w:p:b:s:t:o:gvh", long_options, nullptr)) != -1) {
        switch (opt) {
            case 'i': image_path = optarg; break;
            case 'w': model_name = optarg; break;
            case 'p': param_path = optarg; break;
            case 'b': bin_path = optarg; break;
            case 's':
                target_size = std::stoi(optarg);
                target_size_overridden = true;
                break;
            case 't': num_threads = std::stoi(optarg); break;
            case 'o': output_path = optarg; break;
            case 'g': use_vulkan = true; break;
            case 'v': use_vulkan = true; break;
            case 1000:
                test_runs = std::stoi(optarg);
                test_runs_set = true;
                break;
            case 1001:
                test_csv_path = optarg;
                test_csv_set = true;
                break;
            case 1002:
                clock_csv_path = optarg;
                clock_csv_set = true;
                break;
            case 'h':
            default:
                print_usage();
                return -1;
        }
    }

    if (image_path.empty()) {
        std::cerr << "Error: Missing required arguments.\n";
        print_usage();
        return -1;
    }

    if (!model_name.empty()) {
        const ModelPreset* preset = find_model_preset(model_name);
        if (!preset) {
            std::cerr << "Error: Unknown model preset '" << model_name << "'.\n";
            print_usage();
            return -1;
        }

        if (!target_size_overridden) {
            target_size = preset->target_size;
        }

        if (param_path.empty() && bin_path.empty() && !resolve_model_files(*preset, param_path, bin_path)) {
            return -1;
        }
    }

    if (param_path.empty() || bin_path.empty()) {
        std::cerr << "Error: Use -w <model> or provide both -p <param_path> and -b <bin_path>.\n";
        print_usage();
        return -1;
    }

    if (test_runs_set != test_csv_set) {
        std::cerr << "Error: Test mode requires both --test-runs <n> and --test-csv <path>.\n";
        print_usage();
        return -1;
    }

    if (clock_csv_set && !test_runs_set) {
        std::cerr << "Error: --clock-csv requires --test-runs.\n";
        print_usage();
        return -1;
    }

    if (test_runs_set && test_runs <= 0) {
        std::cerr << "Error: --test-runs must be greater than zero.\n";
        return -1;
    }

    cv::Mat m = cv::imread(image_path, 1);
    if (m.empty()) {
        std::cerr << "Error: cv::imread " << image_path << " failed\n";
        return -1;
    }

    YoloX detector;
    std::cout << "Using model: " << param_path << " + " << bin_path << " (" << target_size << "x" << target_size << ")\n";
    if (!detector.init(param_path, bin_path, target_size, num_threads, use_vulkan)) {
        std::cerr << "Error: Failed to initialize YoloX detector.\n";
        return -1;
    }

    std::vector<Object> objects;

    if (test_runs_set) {
        std::ofstream csv(test_csv_path);
        if (!csv.is_open()) {
            std::cerr << "Error: Failed to open CSV output " << test_csv_path << "\n";
            return -1;
        }

        csv << "run,elapsed_ms,objects_detected,image_path,param_path,bin_path,target_size,threads,gpu\n";
        std::cout << "Running test mode with " << test_runs << " repetitions. CSV: " << test_csv_path << "\n";

        std::atomic<int> current_run{0};
        std::atomic<bool> sampling_active{false};
        std::thread clock_thread;

        if (clock_csv_set) {
            std::ofstream clock_csv(clock_csv_path);
            if (!clock_csv.is_open()) {
                std::cerr << "Error: Failed to open clock CSV output " << clock_csv_path << "\n";
                return -1;
            }

            const int cpu_count = cpu_core_count();
            clock_csv << "timestamp_ms,run";
            for (int c = 0; c < cpu_count; ++c) {
                clock_csv << ",cpu" << c << "_khz";
            }
            clock_csv << '\n';

            std::cout << "Sampling " << cpu_count << " CPU core(s) clock to " << clock_csv_path << "\n";

            sampling_active.store(true);
            auto epoch = std::chrono::steady_clock::now();

            clock_thread = std::thread([&, cpu_count, epoch]() mutable {
                while (sampling_active.load(std::memory_order_relaxed)) {
                    auto now = std::chrono::steady_clock::now();
                    long long ts_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - epoch).count();
                    int run = current_run.load(std::memory_order_relaxed);

                    clock_csv << ts_ms << ',' << run;
                    for (int c = 0; c < cpu_count; ++c) {
                        clock_csv << ',' << read_cpu_freq_khz(c);
                    }
                    clock_csv << '\n';
                    std::this_thread::sleep_for(std::chrono::milliseconds(50));
                }
            });
        }

        for (int run = 1; run <= test_runs; run++) {
            current_run.store(run, std::memory_order_relaxed);
            objects.clear();

            auto start = std::chrono::steady_clock::now();
            if (detector.detect(m, objects) != 0) {
                sampling_active.store(false);
                if (clock_thread.joinable()) clock_thread.join();
                std::cerr << "Error: Detection failed on test run " << run << ".\n";
                return -1;
            }
            auto end = std::chrono::steady_clock::now();
            double elapsed_ms = std::chrono::duration<double, std::milli>(end - start).count();

            csv << run << ','
                << elapsed_ms << ','
                << objects.size() << ','
                << csv_escape(image_path) << ','
                << csv_escape(param_path) << ','
                << csv_escape(bin_path) << ','
                << target_size << ','
                << num_threads << ','
                << (use_vulkan ? 1 : 0) << '\n';
        }

        sampling_active.store(false);
        if (clock_thread.joinable()) clock_thread.join();

        std::cout << "Test results saved to " << test_csv_path << "\n";
        if (clock_csv_set) {
            std::cout << "Clock samples saved to " << clock_csv_path << "\n";
        }
        return 0;
    }

    // Start measuring time
    auto start = std::chrono::steady_clock::now();

    if (detector.detect(m, objects) != 0) {
        std::cerr << "Error: Detection failed.\n";
        return -1;
    }

    // Stop measuring time
    auto end = std::chrono::steady_clock::now();
    double elapsed_ms = std::chrono::duration<double, std::milli>(end - start).count();

    std::cout << "Inference completed in " << elapsed_ms << " ms\n";
    std::cout << "Objects detected: " << objects.size() << "\n";

    detector.draw(m, objects);

    cv::imwrite(output_path, m);
    std::cout << "Result saved to " << output_path << "\n";

    return 0;
}
