# cudaBandwidthTest
This is a benchmark tool for evaluating GPU memory bandwidth performance. Unlike traditional bandwidth testing tools, this project not only measures simple sequential read/write bandwidth but also specifically focuses on bandwidth performance under non-contiguous memory access patterns. It generates memory access indices through a Linear Congruential Generator (LCG).

## Preliminaries
*  CUDA >= 12.4.0
* NVIDA GPU (default: RTX 4090)
* GCC >= 11.3

## Getting Started 
For different GPU device, please modify the `Makefile` before `make`. 
```shell 
make clean 
make CUDA_PATH=XXX   # default: /usr/local/cuda/

timestamp=$(date "+%Y-%m-%d %H:%M:%S")

./cudaBandwidthTest > "./result_${timestamp}.log" 2>&1
```
The result will be written in a `result_XX-XX-XX XX:XX:XX.log` file.
