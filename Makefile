# cuda path
CUDA_PATH = /usr/local/cuda/

# compiler
NVCC := $(CUDA_PATH)/bin/nvcc

# target
TARGET := cudaBandwidthTest

SRC := main.cu

# options
NVCC_FLAGS := -O2 -std=c++17 -Xcompiler -Wall

GENCODE_FLAGS := -gencode arch=compute_89,code=sm_89 \
                 -gencode arch=compute_89,code=compute_89


all: $(TARGET)

$(TARGET): $(SRC)
	$(NVCC) $(NVCC_FLAGS) $(GENCODE_FLAGS) $(SRC) -o $(TARGET)

clean:
	rm -f $(TARGET)

run: all
	./$(TARGET)

.PHONY: all clean run