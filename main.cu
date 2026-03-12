#include <iostream>
#include <vector>
#include <algorithm>
#include <numeric>
#include <cuda_runtime.h>

// 宏：检查 CUDA 错误
#define CHECK_CUDA(call) { \
    cudaError_t err = call; \
    if (err != cudaSuccess) { \
        std::cerr << "CUDA Error: " << cudaGetErrorString(err) << " at line " << __LINE__ << std::endl; \
        exit(1); \
    } \
}


long long calculateDynamicP(long long n) {
    // 1. 使用黄金比例系数
    const double golden_ratio = 0.618033988749895;
    long long p = static_cast<long long>(n * golden_ratio);

    // 2. 确保 p 至少大于 16，以跨越缓存行
    if (p < 17) p = 17;

    // 3. 寻找与 n 互质的 p
    // 如果 n 是 2 的幂，只要 p 为奇数即可
    while (std::gcd(p, n) != 1) {
        p++;
    }
    return p;
}

// random access
__global__ void random_read_kernel(double*  data, 
                                   const int* __restrict__ indices, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    // if (i < n) {
        int idx = indices[i];
        // double val = data[idx]; // 关键：随机读取
        double val = *(const volatile double*)&data[idx]; // 关键：随机读取
        // printf("the thread idx is %d\n", idx);
        // 防止编译器优化掉读取操作
        // data[idx] = val + 1; 
        // asm volatile("" : : "d"(val));
        // val = val + 1;
        // if(val > 1.0e30) data[idx] = val + 1;
        // asm volatile("" : "+d"(val));
    // }
}

__global__ void continue_read_kernel(double*  data, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    double val = *(const volatile double*)&data[i]; // 关键：随机读取
}

__global__ void continue_write_kernel(double* data, int n, double val)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    data[i] = val;
}


/**
 * generate indices
 */
__global__ void setup_indices(int* indices, int n, long long p) {
    long long i = blockIdx.x * (long long)blockDim.x + threadIdx.x;
    if (i < n) {
        // 使用 long long 防止乘法过程中溢出
        // (i * P) % n 保证了在 n 是 2 的幂且 P 是奇数时，生成的是 0 到 n-1 的全排列
        indices[i] = (int)((i * p) % n);
    }
}




int main() {
    // 1. 设置数据量：256M个double ≈ 2GB (远大于 L2 缓存)
    // const int n = 256 * 1024 * 1024; 
    // size_t data_size = n * sizeof(double);
    // size_t idx_size = n * sizeof(int);

    int deviceId = 0;
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, deviceId);
    float msec = 0;
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);

    std::cout << "Device Name: " << prop.name << std::endl;
    // L2 缓存大小
    std::cout << "L2 Cache Size: " << prop.l2CacheSize / (1024 * 1024) << " MB" << std::endl;
    // 每个 SM 的共享内存
    std::cout << "Shared Memory per SM: " << prop.sharedMemPerMultiprocessor / 1024 << " KB" << std::endl;
    // 显存位宽
    std::cout << "Memory Bus Width: " << prop.memoryBusWidth << " bit" << std::endl;

    int blocksize = 1024;
    int repeat = 200;
    int data_size = 48 * prop.l2CacheSize / (sizeof(double));
    data_size = (data_size + blocksize -1) / blocksize * blocksize;
    double total_bytes = (double)data_size * (sizeof(double) + sizeof(int));
    double total_MB = total_bytes / 1024 / 1024;

    printf("the total bytes is %.2f B (%.2f MB)\n", total_bytes, total_MB);
    std::cout.flush();

    // 2. 分配内存
    double *d_input;
    CHECK_CUDA(cudaMalloc(&d_input, data_size * sizeof(double)));

    int *d_indices;
    CHECK_CUDA(cudaMalloc(&d_indices, data_size * sizeof(int)));

    
    int gridsize = (data_size + blocksize - 1) / blocksize ;
    long long p = calculateDynamicP(data_size);

    CHECK_CUDA(cudaDeviceSynchronize());
    setup_indices<<<gridsize, blocksize>>>(d_indices, data_size, p);

    CHECK_CUDA(cudaDeviceSynchronize());
    cudaEventRecord(start);
    for(int i=0; i< repeat; i++)
    {
        random_read_kernel<<<gridsize, blocksize>>>(d_input, d_indices, data_size);
        // printf("the repeat is %d\n", i);
    }
    cudaEventRecord(stop);
    CHECK_CUDA(cudaEventSynchronize(stop));
    cudaEventElapsedTime(&msec, start, stop);

    CHECK_CUDA(cudaGetLastError());

    double average_msec = msec / repeat;

    // double data_volume_MB = total_bytes / 1.0e6;

    double randomAcessBandwidth = total_MB / (average_msec);
    
    printf("\n");
    printf("==================== Benchmark  Results ====================\n");
    printf("%-25s : %d\n",       "Iterations",      repeat);
    printf("%-25s : %.2f MB\n",  "Data Volume",     total_MB);
    printf("%-25s : %.4f ms\n",  "Avg Execution Time", average_msec);
    printf("%-25s : %.2f GB/s\n", "Avg Bandwidth",    randomAcessBandwidth);
    printf("-----------------------------------------------------------\n");
    printf("Hardware Device           : RTX 5060 Ti\n"); // 手动标注硬件
    printf("Access Pattern            : Random (L2 Cold Miss)\n");
    printf("===========================================================\n");
    printf("\n");


    /** ***************************** continume read ****************************************/
    CHECK_CUDA(cudaDeviceSynchronize());
    cudaEventRecord(start);
    for(int i=0; i< repeat; i++)
    {
        continue_read_kernel<<<gridsize, blocksize>>>(d_input, data_size);
        // printf("the repeat is %d\n", i);
    }
    cudaEventRecord(stop);
    CHECK_CUDA(cudaEventSynchronize(stop));
    cudaEventElapsedTime(&msec, start, stop);

    CHECK_CUDA(cudaGetLastError());

    double average_msec_read = msec / repeat;

    double readBandwidth = total_MB / (average_msec_read);
    
    // double data_volume_sequential_MB = data_size *  (sizeof(double) + sizeof(int)) / 1.0e6;

    printf("\n");
    printf("====================  Benchmark Results ====================\n");
    printf("%-25s : %d\n",       "Iterations",       repeat);
    printf("%-25s : %.2f MB\n",  "Data Volume",     total_MB);
    printf("%-25s : %.4f ms\n",  "Avg Execution Time", average_msec_read);
    printf("%-25s : %.2f GB/s\n", "Avg Read Bandwidth",     readBandwidth); 
    printf("-----------------------------------------------------------\n");
    printf("Hardware Device           : RTX 5060 Ti\n"); 
    printf("Access Pattern            : Sequential Read (Coalesced)\n"); // 强调合并访问
    printf("===========================================================\n");
    printf("\n");


    /** ***************************** continume write ****************************************/
    CHECK_CUDA(cudaDeviceSynchronize());
    cudaEventRecord(start);
    for(int i=0; i< repeat; i++)
    {
        continue_write_kernel<<<gridsize, blocksize>>>(d_input, data_size, i * 1.0);
        // printf("the repeat is %d\n", i);
    }
    cudaEventRecord(stop);
    CHECK_CUDA(cudaEventSynchronize(stop));
    cudaEventElapsedTime(&msec, start, stop);

    CHECK_CUDA(cudaGetLastError());

    double average_msec_write = msec / repeat;

    double writeBandwidth = total_MB / (average_msec_write);
    
    // double data_volume_write_MB = data_size *  (sizeof(double) + sizeof(int)) / 1.0e6;

    printf("\n");
    printf("====================  Benchmark Results ====================\n");
    printf("%-25s : %d\n",       "Iterations",       repeat);
    printf("%-25s : %.2f MB\n",  "Data Volume",     total_MB);
    printf("%-25s : %.4f ms\n",  "Avg Execution Time", average_msec_write);
    printf("%-25s : %.2f GB/s\n", "Avg Bandwidth",     writeBandwidth); 
    printf("-----------------------------------------------------------\n");
    printf("Hardware Device           : RTX 5060 Ti\n"); 
    printf("Access Pattern            : Sequential Write (Coalesced)\n"); // 强调合并访问
    printf("===========================================================\n");
    printf("\n");




    // double *d_data, *d_out;
    // int *d_indices;
    // CHECK_CUDA(cudaMalloc(&d_data, data_size));
    // CHECK_CUDA(cudaMalloc(&d_indices, idx_size));
    // CHECK_CUDA(cudaMalloc(&d_out, sizeof(double)));

    // // 3. 在 CPU 上生成完全随机的索引 (Fisher-Yates Shuffle)
    // std::vector<int> h_indices(n);
    // std::iota(h_indices.begin(), h_indices.end(), 0);
    // std::random_shuffle(h_indices.begin(), h_indices.end());

    // CHECK_CUDA(cudaMemcpy(d_indices, h_indices.data(), idx_size, cudaMemcpyHostToDevice));

    // // 4. 执行预热循环 (确保显存频率进入最高状态)
    // random_read_kernel<<<n/1024, 1024>>>(d_data, d_indices, d_out, n);
    // cudaDeviceSynchronize();

    // // 5. 计时开始
    // cudaEvent_t start, stop;
    // CHECK_CUDA(cudaEventCreate(&start));
    // CHECK_CUDA(cudaEventCreate(&stop));
    // CHECK_CUDA(cudaEventRecord(start));

    // const int iterations = 10;
    // for(int i = 0; i < iterations; i++) {
    //     random_read_kernel<<<n/1024, 1024>>>(d_data, d_indices, d_out, n);
    // }

    // CHECK_CUDA(cudaEventRecord(stop));
    // CHECK_CUDA(cudaEventSynchronize(stop));

    // float milliseconds = 0;
    // CHECK_CUDA(cudaEventElapsedTime(&milliseconds, start, stop));

    // // 6. 计算带宽
    // // 每个操作读取了: 8字节的double + 4字节的int索引
    // double total_bytes = (double)n * (sizeof(double) + sizeof(int)) * iterations;
    // double bandwidth_gb_s = (total_bytes / (milliseconds / 1000.0)) / 1e9;

    // // 计算“有效”有效带宽（仅计算目标数据 double 的搬运）
    // double useful_bytes = (double)n * sizeof(double) * iterations;
    // double effective_bw = (useful_bytes / (milliseconds / 1000.0)) / 1e9;

    // std::cout << "---------------------------------------" << std::endl;
    // std::cout << "Total Memory Throughput: " << bandwidth_gb_s << " GB/s" << std::endl;
    // std::cout << "Effective Data Bandwidth (8B): " << effective_bw << " GB/s" << std::endl;
    // std::cout << "---------------------------------------" << std::endl;

    // // 清理
    // cudaFree(d_data); cudaFree(d_indices); cudaFree(d_out);
    cudaFree(d_input);
    cudaFree(d_indices);

    return 0;
}