# cuda path
CUDA_PATH = /usr/local/cuda-13.1

# compiler
NVCC := $(CUDA_PATH)/bin/nvcc

# target
TARGET := cudaBandwidthTest

SRC := main.cu

# options
NVCC_FLAGS := -O3 -std=c++17 -Xcompiler -Wall

GENCODE_FLAGS := -gencode arch=compute_120,code=sm_120 \
                 -gencode arch=compute_120,code=compute_120


all: $(TARGET)

$(TARGET): $(SRC)
	$(NVCC) $(NVCC_FLAGS) $(GENCODE_FLAGS) $(SRC) -o $(TARGET)

clean:
	rm -f $(TARGET)

run: all
	./$(TARGET)

.PHONY: all clean run