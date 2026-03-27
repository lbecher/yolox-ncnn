#include "yolox.hpp"
#include <iostream>
#include <chrono>
#include <unistd.h>
#include <opencv2/highgui/highgui.hpp>

void print_usage() {
    std::cout << "Usage: ./yolox_ncnn -i <image_path> -p <param_path> -b <bin_path> [-s <target_size>] [-t <threads>] [-o <output_path>] [-v]\n"
              << "Options:\n"
              << "  -i  Path to the input image (required)\n"
              << "  -p  Path to the ncnn .param file (required)\n"
              << "  -b  Path to the ncnn .bin file (required)\n"
              << "  -s  Target size for resize (default: 640)\n"
              << "  -t  Number of threads for ncnn (default: 4)\n"
              << "  -o  Path to save the output image (default: output.jpg)\n"
              << "  -v  Enable Vulkan GPU compute (default: false)\n";
}

int main(int argc, char** argv) {
    std::string image_path;
    std::string param_path;
    std::string bin_path;
    std::string output_path = "output.jpg";
    int target_size = 640;
    int num_threads = 4;
    bool use_vulkan = false;

    int opt;
    while ((opt = getopt(argc, argv, "i:p:b:s:t:o:vh")) != -1) {
        switch (opt) {
            case 'i': image_path = optarg; break;
            case 'p': param_path = optarg; break;
            case 'b': bin_path = optarg; break;
            case 's': target_size = std::stoi(optarg); break;
            case 't': num_threads = std::stoi(optarg); break;
            case 'o': output_path = optarg; break;
            case 'v': use_vulkan = true; break;
            case 'h': 
            default:
                print_usage();
                return -1;
        }
    }

    if (image_path.empty() || param_path.empty() || bin_path.empty()) {
        std::cerr << "Error: Missing required arguments.\n";
        print_usage();
        return -1;
    }

    cv::Mat m = cv::imread(image_path, 1);
    if (m.empty()) {
        std::cerr << "Error: cv::imread " << image_path << " failed\n";
        return -1;
    }

    YoloX detector;
    if (!detector.init(param_path, bin_path, target_size, num_threads, use_vulkan)) {
        std::cerr << "Error: Failed to initialize YoloX detector.\n";
        return -1;
    }

    std::vector<Object> objects;
    
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
