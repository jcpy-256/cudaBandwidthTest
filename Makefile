# 指定 CUDA 安装路径 (通常为 /usr/local/cuda)
CUDA_PATH = /usr/local/cuda-13.1

# 编译器
NVCC := $(CUDA_PATH)/bin/nvcc

# 目标文件名
TARGET := cudaBandwidthTest

# 源文件
SRC := main.cu

# 编译选项
# -O3: 最高等级优化
# -std=c++14: 使用 C++14 标准
# -Xcompiler -Wall: 向主机编译器传递警告选项
NVCC_FLAGS := -O3 -std=c++17 -Xcompiler -Wall

# 架构选项 (针对 RTX 4090 / 40 系列使用 sm_89)
# 如果是 RTX 30 系列，请改为 sm_86
# 如果是 RTX 50 系列，请改为 sm_90 (如果已支持)
# GENCODE_FLAGS := -gencode arch=compute_100,code=sm_100
GENCODE_FLAGS := -gencode arch=compute_120,code=sm_120 \
                 -gencode arch=compute_120,code=compute_120

# 默认规则
all: $(TARGET)

$(TARGET): $(SRC)
	$(NVCC) $(NVCC_FLAGS) $(GENCODE_FLAGS) $(SRC) -o $(TARGET)

# 清理规则
clean:
	rm -f $(TARGET)

# 运行规则
run: all
	./$(TARGET)

.PHONY: all clean run