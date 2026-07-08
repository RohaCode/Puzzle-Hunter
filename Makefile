# GPU-only PuzzleHunter build
CXX ?= g++

COMMON_FLAGS = -m64 -std=c++17 -Ofast -mssse3 -Wall -Wextra \
               -Wno-write-strings -Wno-unused-variable -Wno-deprecated-copy \
               -Wno-unused-parameter -Wno-sign-compare -Wno-strict-aliasing \
               -Wno-unused-but-set-variable -funroll-loops -ftree-vectorize \
               -fstrict-aliasing -fno-semantic-interposition -fvect-cost-model=unlimited \
               -fno-trapping-math -fipa-ra -fassociative-math -fopenmp \
               -mavx2 -mbmi2 -madx -fwrapv -I"."

ifeq ($(OS),Windows_NT)
    OPENCL_PATH ?= ./OpenCL
    TARGET = hunter.exe
    CXXFLAGS = $(COMMON_FLAGS) -static -I"$(OPENCL_PATH)/include"
    LDFLAGS = -L"$(OPENCL_PATH)/lib/x86_64" -lOpenCL -static -Wl,--stack,8388608
    CLEAN = powershell -NoProfile -Command "Remove-Item -Force -ErrorAction SilentlyContinue *.o, '$(TARGET)'"
else
    TARGET = hunter
    CXXFLAGS = $(COMMON_FLAGS)
    LDFLAGS = -lOpenCL
    CLEAN = rm -f *.o $(TARGET)
endif

SRCS = main_gpu.cpp SECP256K1.cpp Int.cpp IntMod.cpp Point.cpp
OBJS = $(SRCS:.cpp=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(OBJS) $(LDFLAGS)

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	$(CLEAN)
