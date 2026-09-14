# Tensor-core mma.sync microbenchmarks for consumer Blackwell (sm_120a).
# The 'a' suffix is REQUIRED: plain sm_120 rejects every kind:: / block_scale instruction.
ARCH   ?= -gencode arch=compute_120a,code=sm_120a
NVCC   ?= nvcc
FLAGS  ?= -O3 $(ARCH)
BUILD  := build

all: $(BUILD)/mma_dense $(BUILD)/mma_sparse_b1 $(BUILD)/sass_probe.cubin $(BUILD)/mma_precision $(BUILD)/mma_sustained

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/mma_dense: mma_dense.cu mma_bench.cuh | $(BUILD)
	$(NVCC) $(FLAGS) -o $@ $<

$(BUILD)/mma_sparse_b1: mma_sparse_b1.cu mma_bench.cuh | $(BUILD)
	$(NVCC) $(FLAGS) -o $@ $<

$(BUILD)/sass_probe.cubin: sass_probe.cu | $(BUILD)
	$(NVCC) $(FLAGS) -cubin -o $@ $<

run: all
	./$(BUILD)/mma_dense
	./$(BUILD)/mma_sparse_b1

# Count tensor-core SASS ops per kernel: shows wmma splitting into 2x HMMA, s4 emulation, etc.
sass: $(BUILD)/sass_probe.cubin $(BUILD)/mma_dense
	./sass_count.sh $(BUILD)/sass_probe.cubin
	./sass_count.sh $(BUILD)/mma_dense _Z8k_s4_k64ILi8EEvPiPxj

# Prove wgmma / tcgen05 are not available on sm_120a
isa:
	./isa_probe.sh

clean:
	rm -rf $(BUILD)

.PHONY: all run sass isa clean

# ---- verification of the numbers above ----
$(BUILD)/mma_precision: mma_precision.cu | $(BUILD)
	$(NVCC) $(FLAGS) -o $@ $<

$(BUILD)/mma_sustained: mma_sustained.cu | $(BUILD)
	$(NVCC) $(FLAGS) -o $@ $<

# Bit-exact check that the f32-accumulate paths (incl. full-rate block-scaled kinds) really accumulate in f32
verify: $(BUILD)/mma_precision
	./$(BUILD)/mma_precision

# Whole-GPU TFLOPS over ~2.5 s per instruction, with changing operand data; shows what clock the card sustains
sustained: $(BUILD)/mma_sustained
	./$(BUILD)/mma_sustained 2.5

.PHONY: verify sustained
