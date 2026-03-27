#pragma once

#include <vector>
#include <string>
#include <opencv2/core/core.hpp>
#include "net.h"

struct Object
{
    cv::Rect_<float> rect;
    int label;
    float prob;
};

class YoloX
{
public:
    YoloX();
    ~YoloX();

    bool init(const std::string& param_path, const std::string& bin_path, int target_size = 640, int num_threads = 4, bool use_vulkan = false);
    int detect(const cv::Mat& bgr, std::vector<Object>& objects);
    void draw(cv::Mat& bgr, const std::vector<Object>& objects);

private:
    ncnn::Net yolox_net;
    int target_size_;
    int num_threads_;
    const float prob_threshold_ = 0.25f;
    const float nms_threshold_ = 0.45f;
};
