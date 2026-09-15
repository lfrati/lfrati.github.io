# Minimal mma.sync examples for the RTX 5070 Ti (sm_120).
# One warp computes D[16x8] = A[16x16] * B[16x8] with fp16 inputs and an fp32 accumulator,
# then checks the result against a CPU loop.
#   mma_manual.cu   : fragments filled by hand with plain loads from global memory
#   mma_ldmatrix.cu : fragments filled with ldmatrix from shared memory
ARCH ?= -arch=sm_120
NVCC ?= nvcc

all: mma_manual mma_ldmatrix

mma_manual: mma_manual.cu
	$(NVCC) -O2 $(ARCH) -o $@ $<

mma_ldmatrix: mma_ldmatrix.cu
	$(NVCC) -O2 $(ARCH) -o $@ $<

run: all
	./mma_manual
	./mma_ldmatrix

# Show that the manual version has no LDSM and the ldmatrix version has two
sass: all
	cuobjdump -sass mma_manual   | grep -E "HMMA|LDG|LDSM"
	@echo ---
	cuobjdump -sass mma_ldmatrix | grep -E "HMMA|LDG|LDSM|STS"

clean:
	rm -f mma_manual mma_ldmatrix

.PHONY: all run sass clean
