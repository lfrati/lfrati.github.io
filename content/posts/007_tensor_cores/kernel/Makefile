NVCC  := nvcc
ARCH  := -arch=sm_120
FLAGS := -O2

all: gemm_tc gemm_tc_v2

gemm_tc: gemm_tc.cu
	$(NVCC) $(ARCH) $(FLAGS) -o $@ $<

gemm_tc_v2: gemm_tc_v2.cu
	$(NVCC) $(ARCH) $(FLAGS) -o $@ $<

run: gemm_tc
	./gemm_tc

run2: gemm_tc_v2
	./gemm_tc_v2

clean:
	rm -f gemm_tc gemm_tc_v2

.PHONY: all run clean
