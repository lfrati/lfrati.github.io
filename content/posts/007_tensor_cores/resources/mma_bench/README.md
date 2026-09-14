# Tensor-core microbenchmarks for the RTX 5070 Ti (sm_120a)

Measures what a single `mma.sync` instruction actually computes on consumer Blackwell,
how many cycles it takes, and what the whole GPU sustains. Everything here was verified
against the PTX ISA 9.3 shape tables and the RTX Blackwell whitepaper (CUDA 12.9, driver
reporting compute capability 12.0).

## Files

| File | Purpose |
|---|---|
| `mma_bench.cuh` | Shared harness: kernel generator macros + runner (latency, issue interval, TFLOPS) |
| `mma_dense.cu` | Every dense `mma.sync` shape/type (f16, bf16, tf32, s8, s4, fp8, f6, f4, block-scaled, f64) |
| `mma_sparse_b1.cu` | 2:4 sparse `mma.sp` / `mma.sp::ordered_metadata` shapes and single-bit `b1` shapes |
| `sass_probe.cu` + `sass_count.sh` | Compile-only: what each PTX primitive becomes in SASS (wmma splitting, emulation) |
| `isa_probe.sh` | Shows ptxas rejecting `wgmma` / `tcgen05` / block-scale per target |
| `ptx_shapes.py` | Pulls the Matrix Shape and Target ISA tables out of the live PTX ISA docs (`uv run`) |
| `mma_precision.cu` | `make verify`: bit-exact check that every f32-accumulate path (incl. the full-rate block-scaled kinds) really accumulates in f32 |
| `mma_sustained.cu` | `make sustained`: whole-GPU TFLOPS over ~2.5 s per instruction with changing operand data, i.e. at the clock the card actually holds |
| `Makefile` | `make run`, `make verify`, `make sustained`, `make sass`, `make isa` |

Build needs `-gencode arch=compute_120a,code=sm_120a`. Plain `sm_120` rejects every
`kind::`, `block_scale` and `e2m1/e3m2/e2m3` instruction.

## How the numbers are measured

* **latency**: one warp per SM, one dependent accumulator chain, `clock64()` around 2048 instructions.
* **issue interval**: one warp per SM, 8 independent accumulator chains, so only one of the
  four tensor cores in the SM is busy. This is the true per-instruction cost of the pipe.
* **MAC/clk/TC**: `M*N*K / issue interval`, i.e. multiply-accumulates per clock per tensor core.
* **GPU TFLOPS**: all SMs, 8 warps per block, 8 blocks per SM, event-timed, `2*MACs/time`.
  The card ran at 2.55-2.87 GHz across rows and runs (power/boost dependent); the whitepaper quotes
  2.45 GHz boost, so measured TFLOPS land 5-17% above spec and vary up to 13% run to run. The cycle
  numbers do not vary. See "How much to trust each column" below before using the TFLOPS column.
* Sparse MAC counts are **dense-equivalent** (`M*N*K`); real multiplies are half.
* b1 "MAC" means one AND/XOR plus popcount.

## Key facts about this card (measured)

* The hardware unit is one tensor core per SM sub-partition (4 per SM, 280 total).
  Every `mma.sync` is exactly one SASS instruction (HMMA / IMMA / QMMA / OMMA / DMMA) and the
  largest thing a single instruction computes is `m16n8k64` (fp4) = 8192 MACs dense,
  `m16n8k128` (sparse fp4) = 16384 dense-equivalent MACs.
* A operand is always 4 registers/thread, B is 2 (4 for sparse): M and N are pinned to 16x8;
  only K grows as element width shrinks.
* The pipe issues one instruction every **16 cycles**, or **32 cycles when the accumulator is f32**
  (the GeForce half-rate on FP32 accumulate). Block-scaled kinds (`mxf8f6f4`, `mxf4`, `mxf4nvf4`)
  are the exception: full 16-cycle rate with f32 accumulators.
* Dependent latency is ~29 cycles (f16 acc) / ~34 cycles (f32 acc): two independent accumulator
  chains per warp saturate a sub-partition.
* Smaller-K shapes (`m16n8k8` f16, `m16n8k4` tf32, `m16n8k16` s8/fp8) cost the same cycles as the
  full-K shape and do half the work.
* `wmma` 16x16x16 and 32x8x16 compile to 2x `HMMA.16816`. `wgmma` (Hopper) and `tcgen05`
  (datacenter Blackwell) do not exist on sm_120a: ptxas rejects them.
* **Emulated, avoid**: s4/u4 (dense and sparse) -> CALL + IMMA.S8; all `b1` shapes -> CALL + IMMA.U8;
  f16 `m8n8k4` -> CALL. f64 `m8n8k4` is real DMMA but 0.6 TFLOPS.
* **Plain `.sp` is slow for f16 and s8** on Blackwell: the HMMA.SP/IMMA.SP instruction is preceded
  by a metadata-conversion subroutine (200+ cycles). Always use `.sp::ordered_metadata`.
  Plain `.sp` for bf16, tf32 and fp8 happened to be fast, but ptxas warns it will degrade.

## How much to trust each column

* **lat / issue / MAC/clk/TC are exact.** Three fresh runs reproduce them to 0.1 cycle. The SASS of every
  timed loop is nothing but back-to-back HMMA/QMMA/OMMA with the loop counter in uniform registers (no
  spills, no conversion code). MAC/clk/TC x 280 tensor cores x 2 x 2.452 GHz reproduces every peak in the
  whitepaper's RTX 5070 Ti table exactly (87.9 / 175.8 / 351.5 / 703, sparse 2x). The pipe rate is
  data-independent: distinct random operands on every instruction change the cycle count by 0%.
* **GPU TFLOPS is NOT a planning number.** It is the cycle rate times whatever clock the card happened to be
  at during a 1-3 ms window. Within one run different rows implied 2.55 and 2.87 GHz, and the same row swung
  13% between runs (mxf4: 822 vs 731). Plan from MAC/clk/TC x a clock you pick. Under a sustained synthetic
  tensor load (`make sustained`) this card held 2.80-2.86 GHz at 200-290 W, and fp4 with changing data
  reached 288 W of the 300 W limit; a real kernel adds memory/smem traffic, so budget ~2.4-2.6 GHz.
* **f32 accumulation is real f32** for every f32-accumulate path, including the full-rate block-scaled ones:
  `make verify` adds 2^-22 to 1.0 through mxf8f6f4/mxf4/nvf4 and gets it back bit-exact.
* These are pipe-only upper bounds: no ldmatrix, no shared or global memory in the loop.
* e2m1 in the k32 kinds (`f8f6f4`, `mxf8f6f4`) lives at bits 5:2 of its 8-bit container (PTX ISA fig. 199);
  in `kind::mxf4`/`mxf4nvf4` two e2m1 share a byte with no padding.
* Emulated shapes (s4, b1, f16 m8n8k4) are ptxas 12.9 subroutines; their cycles can change with CUDA.
* Only 2-3 of the 8 launched blocks per SM are resident at a time (register-limited). Irrelevant for the
  results, since 2 warps per sub-partition already saturate the pipe.

## Speed of light: the 16-cycle instructions

Everything below issues every 16 cycles, is one real SASS instruction, and is the fastest way to use its
input format on this card. TFLOPS = MAC/clk/TC x 280 x 2 x clock; the last column is what `make sustained`
measured (2.5 s per instruction, distinct operands, ~2.8 GHz).

| format | instruction | SASS | MAC/clk/TC | @2.452 (spec) | @2.6 | sustained meas. |
|---|---|---|---|---|---|---|
| fp16 | `m16n8k16 f16.f16.f16.f16` | HMMA.16816.F16 | 128 | 175.8 | 186 | 205 |
| int8 | `m16n8k32 s32.s8.s8.s32` | IMMA.16832 | 256 | 351.5 | 373 | 410 |
| fp8 | `m16n8k32 f16.e4m3.e4m3.f16` | QMMA.16832.F16 | 256 | 351.5 | 373 | 410 |
| fp8, f32 acc | `m16n8k32 kind::mxf8f6f4.block_scale f32.e4m3.e4m3.f32.ue8m0` | QMMA.SF.16832.F32 | 256 | 351.5 | 373 | 409 |
| fp4 | `m16n8k64 kind::mxf4.block_scale f32.e2m1.e2m1.f32.ue8m0` (or `mxf4nvf4` + ue4m3 4X) | OMMA.SF.16864.F32 | 512 | 703 | 745 | 817 |
| 2:4 fp16 | `sp::ordered_metadata m16n8k32 f16 acc` | HMMA.SP.16832.F16 | 256 | 351.5 | 373 | 409* |
| 2:4 int8 | `sp::ordered_metadata m16n8k64 s8` | IMMA.SP.16864 | 512 | 703 | 745 | 808* |
| 2:4 fp8 | `sp::ordered_metadata m16n8k64 f16 acc`, or `mxf8f6f4` SF f32 acc | QMMA.SP.16864.F16 / QMMA.SF.SP.16864.F32 | 512 | 703 | 745 | 727-818* |
| 2:4 fp4 | `sp::ordered_metadata m16n8k128 kind::mxf4` SF | OMMA.SF.SP.168128.F32 | 1024 | 1406 | 1490 | 1616* |

\* sparse rows are dense-equivalent MACs; `*` = measured with the original 1-3 ms harness or the first
sustained run, not the distinct-operand one.

Everything else is half rate (32 cycles) or worse and buys nothing:
* **f32-accumulate without block scaling**: f16/bf16/tf32 -> f32 and plain `e4m3 -> f32` are 32 cycles.
  bf16 and tf32 have no 16-bit-accumulate variant, so bf16 tops out at 64 MAC/clk/TC and tf32 at 32.
  For fp8 with a true f32 accumulator use the block-scaled `mxf8f6f4` kind (scale = ue8m0 127 for 1.0).
* **fp6 (e3m2 / e2m3)** is 32 cycles in every kind: no faster than fp8, worse than fp8 -> f16.
* **fp4 through the k32 kinds** (`f8f6f4`/`mxf8f6f4` e2m1) is 32 cycles for 4096 MACs: 4x slower than
  `kind::mxf4` m16n8k64. Only the k64 OMMA path gives fp4 its full rate.
* **f16 acc in the f8f6f4 kind** (`f8f6f4 e2m1 -> f16`) stays at 32 cycles; the f16-accumulate speedup only
  exists for the plain `e4m3 -> f16` instruction.
* **Smaller-K shapes** cost the same 16/32 cycles for half the MACs.
* **Plain `.sp` (no `::ordered_metadata`)** for f16 and s8 costs 200-300 cycles per instruction.
* s4/u4, all b1, f16 m8n8k4 are emulated; f64 is 584 cycles.

## Results: dense (`./build/mma_dense`)

| instruction | MAC/ins | lat | issue | MAC/clk/TC | GPU TFLOPS |
|---|---|---|---|---|---|
| f16->f32 m16n8k16 | 2048 | 34 | 32 | 64 | 103 |
| f16->f16 m16n8k16 | 2048 | 29 | 16 | 128 | 203 |
| bf16->f32 m16n8k16 | 2048 | 34 | 32 | 64 | 103 |
| f16->f32 m16n8k8 | 1024 | 34 | 32 | 32 | 51 |
| tf32->f32 m16n8k8 | 1024 | 34 | 32 | 32 | 51 |
| s8->s32 m16n8k32 | 4096 | 27 | 16 | 256 | 408 |
| s4->s32 m16n8k64 (emulated) | 8192 | 377 | 322 | 25 | 41-56 |
| e4m3->f32 m16n8k32 | 4096 | 34 | 32 | 128 | 205 |
| e4m3->f16 m16n8k32 | 4096 | 29 | 16 | 256 | ~410 |
| kind::f8f6f4 e2m1/e3m2->f32 k32 | 4096 | 34 | 32 | 128 | 205 |
| kind::mxf8f6f4 e4m3 SF k32 | 4096 | 29 | 16 | 256 | 402 |
| kind::mxf8f6f4 e3m2 / e2m1 SF k32 | 4096 | 34 | 32 | 128 | 206 |
| kind::f8f6f4 e2m1->f16 k32 | 4096 | 34 | 32 | 128 | 206 |
| kind::mxf4 / mxf4nvf4 e2m1 SF k64 | 8192 | 29 | 16 | 512 | 804 |
| f64 m8n8k4 | 256 | 584 | 584 | 0.4 | 0.7 |

## Results: sparse and b1 (`./build/mma_sparse_b1`)

| instruction | dense-eq MAC/ins | lat | issue | MAC/clk/TC | GPU TFLOPS |
|---|---|---|---|---|---|
| sp f16->f32 m16n8k32 (plain .sp) | 4096 | 242 | 294 | 14 | 80 |
| sp::om f16->f32 m16n8k32 | 4096 | 34 | 32 | 128 | 205 |
| sp::om f16->f16 m16n8k32 | 4096 | 29 | 16 | 256 | 409 |
| sp bf16->f32 m16n8k32 | 4096 | 34 | 32 | 128 | 205 |
| sp tf32->f32 m16n8k16 | 2048 | 34 | 32 | 64 | 102 |
| sp s8->s32 m16n8k64 (plain .sp) | 8192 | 291 | 294 | 28 | 114 |
| sp::om s8->s32 m16n8k64 | 8192 | 27 | 16 | 512 | 728 |
| sp s4->s32 m16n8k128 (emulated) | 16384 | 976 | 1046 | 16 | 48 |
| sp::om e4m3->f32 m16n8k64 | 8192 | 34 | 32 | 256 | 410 |
| sp::om e4m3->f16 m16n8k64 | 8192 | 29 | 16 | 512 | 818 |
| sp::om f8f6f4 e2m1 k64 (f32 or f16 acc) | 8192 | 34 | 32 | 256 | 410 |
| sp::om mxf8f6f4 e4m3 SF k64 | 8192 | 29 | 16 | 512 | 727 |
| sp::om mxf4 / nvf4 e2m1 SF k128 | 16384 | 29 | 16 | 1024 | 1455 |
| b1 xor.popc m16n8k256 (emulated) | 32768 | 842 | 1326 | 25 | 125 |
| b1 and.popc m16n8k256 (emulated) | 32768 | 378 | 506 | 65 | 264 |
| b1 xor.popc m16n8k128 (emulated) | 16384 | 547 | 678 | 24 | 125 |
| b1 xor.popc m8n8k128 (emulated) | 8192 | 544 | 588 | 14 | 74 |

Whitepaper (RTX 5070 Ti, 2.45 GHz) for comparison: FP16->FP32 87.9, FP16->FP16 175.8,
FP8->FP32 175.8, FP8->FP16 351.5, INT8 351.5, FP4 703 dense; sparse doubles each; FP4 sparse 1406.

## Sources

* PTX ISA 9.3: https://docs.nvidia.com/cuda/parallel-thread-execution/index.html
* RTX Blackwell whitepaper v1.1: https://images.nvidia.com/aem-dam/Solutions/geforce/blackwell/nvidia-rtx-blackwell-gpu-architecture.pdf
* CUTLASS SM120 notes: https://github.com/NVIDIA/cutlass/blob/main/media/docs/cpp/blackwell_functionality.md
