#include <iostream>
#include <vector>
#include <algorithm>
#include <numeric>
#include <cuda_runtime.h>


#define CHECK_CUDA(call) { \
    cudaError_t err = call; \
    if (err != cudaSuccess) { \
        std::cerr << "CUDA Error: " << cudaGetErrorString(err) << " at line " << __LINE__ << std::endl; \
        exit(1); \
    } \
}


long long calculateDynamicP(long long n) {
    const double golden_ratio = 0.618033988749895;
    long long p = static_cast<long long>(n * golden_ratio);
    if (p < 17) p = 17;

    while (std::gcd(p, n) != 1) {
        p++;
    }
    return p;
}

// random access
__global__ void random_read_kernel(double*  data, 
                                   const int* __restrict__ indices, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;

    int idx = indices[i];
    double val = *(const volatile double*)&data[idx]; 
}

__global__ void continue_read_kernel(double*  data, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    double val = *(const volatile double*)&data[i]; 
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
        indices[i] = (int)((i * p) % n);
    }
}




int main() {

    int deviceId = 0;
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, deviceId);
    float msec = 0;
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);

    std::cout << "Device Name: " << prop.name << std::endl;

    std::cout << "L2 Cache Size: " << prop.l2CacheSize / (1024 * 1024) << " MB" << std::endl;

    std::cout << "Shared Memory per SM: " << prop.sharedMemPerMultiprocessor / 1024 << " KB" << std::endl;

    std::cout << "Memory Bus Width: " << prop.memoryBusWidth << " bit" << std::endl;

    int blocksize = 1024;
    int repeat = 100;
    uint64_t data_size = (uint64_t) 194 * prop.l2CacheSize / (sizeof(double));
    data_size = (data_size + blocksize -1) / blocksize * blocksize;
    double total_bytes = (double)data_size * (sizeof(double) + sizeof(int));
    double total_MB = (double)data_size * (sizeof(double) + sizeof(int)) / 1e6;
    double totalData_MB = (double)data_size * sizeof(double) / 1e6;

    printf("the total bytes is %.2f B (%.2f MB)\n", total_bytes, total_MB);
    std::cout.flush();

   
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



    double randomAcessBandwidth = total_MB / (average_msec);
    
    printf("\n");
    printf("==================== Benchmark  Results ====================\n");
    printf("%-25s : %d\n",       "Iterations",      repeat);
    printf("%-25s : %.2f MB\n",  "Data Volume",     total_MB);
    printf("%-25s : %.4f ms\n",  "Avg Execution Time", average_msec);
    printf("%-25s : %.2f GB/s\n", "Avg Bandwidth",    randomAcessBandwidth);
    printf("-----------------------------------------------------------\n");
    printf("Hardware Device           : %s\n", prop.name); 
    printf("Access Pattern            : Worst Indirect Access\n");
    printf("===========================================================\n");
    printf("\n");


    /** ***************************** continume read ****************************************/
    CHECK_CUDA(cudaDeviceSynchronize());
    cudaEventRecord(start);
    for(int i=0; i< repeat; i++)
    {
        continue_read_kernel<<<gridsize, blocksize>>>(d_input, data_size);

    }
    cudaEventRecord(stop);
    CHECK_CUDA(cudaEventSynchronize(stop));
    cudaEventElapsedTime(&msec, start, stop);

    CHECK_CUDA(cudaGetLastError());

    double average_msec_read = msec / repeat;

    double readBandwidth = totalData_MB / (average_msec_read);
    

    printf("\n");
    printf("====================  Benchmark Results ====================\n");
    printf("%-25s : %d\n",       "Iterations",       repeat);
    printf("%-25s : %.2f MB\n",  "Data Volume",     totalData_MB);
    printf("%-25s : %.4f ms\n",  "Avg Execution Time", average_msec_read);
    printf("%-25s : %.2f GB/s\n", "Avg Read Bandwidth",     readBandwidth); 
    printf("-----------------------------------------------------------\n");
     printf("Hardware Device           : %s\n", prop.name); 
    printf("Access Pattern            : Sequential Read (Coalesced)\n"); 
    printf("===========================================================\n");
    printf("\n");


    /** ***************************** continume write ****************************************/
    CHECK_CUDA(cudaDeviceSynchronize());
    cudaEventRecord(start);
    for(int i=0; i< repeat; i++)
    {
        continue_write_kernel<<<gridsize, blocksize>>>(d_input, data_size, i * 1.0);
    }
    cudaEventRecord(stop);
    CHECK_CUDA(cudaEventSynchronize(stop));
    cudaEventElapsedTime(&msec, start, stop);

    CHECK_CUDA(cudaGetLastError());

    double average_msec_write = msec / repeat;

    double writeBandwidth = totalData_MB / (average_msec_write);
    

    printf("\n");
    printf("====================  Benchmark Results ====================\n");
    printf("%-25s : %d\n",       "Iterations",       repeat);
    printf("%-25s : %.2f MB\n",  "Data Volume",     totalData_MB);
    printf("%-25s : %.4f ms\n",  "Avg Execution Time", average_msec_write);
    printf("%-25s : %.2f GB/s\n", "Avg Bandwidth",     writeBandwidth); 
    printf("-----------------------------------------------------------\n");
     printf("Hardware Device           : %s\n", prop.name); 
    printf("Access Pattern            : Sequential Write (Coalesced)\n"); 
    printf("===========================================================\n");
    printf("\n");

    cudaFree(d_input);
    cudaFree(d_indices);

    return 0;
}