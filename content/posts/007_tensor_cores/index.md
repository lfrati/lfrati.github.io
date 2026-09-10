+++
title = 'Tensor Cores, Elevensor Cores, Twelvesor Cores'
slug = 'tensor-cores'
date = 2026-09-03
draft = true
tags = ["gpu", "cuda"]
summary = " AI goes brrr using GPU. But tensor cores make gpu go brrr. What is a tensor core tho? Shall we find out?"
+++

Let's start googling a tensor core. To get a visual intuition of what the hell we are talking about. 

<div style="text-align: center;">
  <video muted autoplay loop playsinline style="width: 200px; max-width: 100%;">
    <source src="images/tensor_core_pascal.mp4" type="video/mp4">
  </video>
</div>

Here we go. Pretty clear? It's... a cube of sorts? That multiplies matrices.

It's something that does 

{{< img src="images/Blackwell_SM.png" alt="Blackwell SM" width="400">}}

My pc has a 5070Ti, which has 70SM and each SM has 4 5th generation tensor cores, for a total of 280 tensor cores.

How powerful are these 280 TCores? The Blackwell whitepaper says all together they are capable of

| Type | Accumulate  | Peak TFLOPS | Sparse[^sparse] |
|:----:|:-----------:|------------:|:-------|
| FP4  | FP32        |         703 |   1406 |
| FP8  | FP16        |       351.5 |    703 |
| FP8  | FP32        |       175.8 |  351.5 |
| FP16 | FP16        |       175.8 |  351.5 |
| FP16 | FP32        |        87.9 |  175.8 |
| BF16 | FP32        |        87.9 |  175.8 |
| TF32 | -           |        43.9 |   87.9 |
| INT8 | -           |       351.5 |    703 |

Peak tensor core throughput of the 5070Ti, from the Blackwell whitepaper.<br>
{.table-caption}

[^sparse]:  2:4 sparsity, meaning for each 4 contiguous values at least 2 must be zeros. Stored as half the size + small index.

Using them tho, like everything else in a gpu is tricky.
- accessed with warp level operations
- there are 4 TCores per SM, 32 threads per SM = 8 threads per TCore?
- load them from shared memory with ldmatrix

The key functions are going to be `mma.sync` the tensor core op and `ldmatrix` the op we use to feed data to the core.

Let's start with `mma.sync`, it computes `D = AB + C` and comes in multiple flavors e.g. `m16n8k16`, `m16n8k32`, `m16n8k64`.
M,N,K are conventional names from BLAS and if we consider `m16n8k32`:
- `m16` means that there are 16 rows in A (and therefore in D)
- `n8`  means that there are 8 columns in B (and therefore in D)
- `k32` means the inner dimension is 32 elements
So together we get D[16x8] = A[16x32] B[32x8] + C[16x8] 

On NVIDIA GPUs threads are scheduled in groups of 32 called warps. All 32 threads in a warp execute the same instruction at the same time, each on its own data. The position of a thread within its warp, 0 through 31, is its lane.
`mma.sync` is a warp-level instruction that computes D = AB+C. `A` takes 4 registers in each of the 32 lanes, for a total of 32 threads x 4 registers x 32 bits/register = 4096 bits. 

These 4096 bits are arranged in 16xK elements based on the element type. Since 4096 = 16 x 256 we have 256 bits to use for numbers.
For example if the type is fp16 bits then K = 16, if we use fp32 then K = 8

A[16x16]
16 * 16  = 256
4 * (8 * 8) = 256
16 * 8  = 128

Speed of light on this card: only five dense instructions issue every 16 cycles. Everything else is half rate or worse. Peak TFLOPS = MAC/clk/TC x 280 x 2 x clock.

| format | instruction | MAC/clk/TC | @2.452 spec | @2.6 | measured sustained ~2.8 GHz |
|:-------|:------------|-----------:|------------:|-----:|----------------------------:|
| fp16         | `m16n8k16 f16.f16.f16.f16` (f16 accumulate)     | 128 | 176 | 186 | 205 |
| int8         | `m16n8k32 s32.s8.s8.s32`                        | 256 | 352 | 373 | 410 |
| fp8          | `m16n8k32 f16.e4m3.e4m3.f16` (f16 accumulate)   | 256 | 352 | 373 | 410 |
| fp8, f32 acc | `m16n8k32 kind::mxf8f6f4.block_scale ... ue8m0` | 256 | 352 | 373 | 409 |
| fp4          | `m16n8k64 kind::mxf4.block_scale` (or mxf4nvf4) | 512 | 703 | 745 | 817 |

Dense `mma.sync` throughput per tensor core, and resulting TFLOPS at various clocks.<br>
{.table-caption}


With 2:4 sparsity via sp::ordered_metadata each row doubles its dense-equivalent rate (fp4 reaches 1024 MAC/clk/TC, 1406 at spec, 1616 measured).

Ranking by raw MACs: fp4 is 4x fp16, and int8 and fp8 are 2x fp16. Within a format the choices that matter:

- fp16: you must accumulate in f16 to get 16 cycles. f16->f32 is 32 cycles. bf16 has no 16-bit accumulate, so bf16 is stuck at half rate, 64 MAC/clk/TC. tf32 is 32 MAC/clk/TC.
- int8: plain s8.s8.s32 is already full rate with a 32-bie five.
- fp8: either accumulate in f16 with the plain instruction, or use the block-scaled mxf8f6f4 kind to get a true f32 accumulator at the same cycles. Plain e4m3 -> f32 is 32 cycles. Set the ue8m0 s0 if you don't need scaling.
- fp4: only the k64 kind::mxf4 / mxf4nvf4 path (OMMA) is full rate, with e2m1 nibble-packed. fp4 fed through the k32 f8f6f4 or mxf8f6f4 kind32 cycles for half the MACs, 4x slower.
- Skip: fp6 (32 cycles everywhere, no faster than fp8), s4 and b1 (emulated), f64, smaller-K shapes (same cycles, half the work), plain .sp without ordered_metadata for f16 and s8 (200 to 300 cyc

Clock to plan with. These rates are exact and data-indepe is the clock. Under a pure tensor load this card held2.80 to 2.86 GHz at up to 288 W of the 300 W limit, so a real kernel with memory and shared-memory traffic will be power-limited. I'd plan around 2.5 to 2.6 GHz and treat the sustained column as t

# why is ldmatrix used to load data?

ldmatrix is not magic and it is not faster than shared memory can go. It exists because the fragment layout mma.sync wants is awkward to fill with ordinary loads, and it does the whole fill in one instruction, with an optional transpose.

Recall the A layout from earlier: lane (g, t) holds row g columns 2t and 2t+1 in a0, row g+8 in a1, and the same rows 8 columns over in a2 and a3. With plain CUDA that is four separate 32-bit loads per thread, each with its own address arithmetic, and B needs two more. It works, and it is what "raw CUDA" tensor-core code did before Ampere. But it costs six load instructions plus the index math per mma, and you have to lay shared memory out so those scattered 4-byte reads do not bank-conflict.

ldmatrix replaces that with a single warp-wide instruction. Its unit of work is an 8×8 tile of 16-bit elements. Each of 8 lanes supplies the address of one 16-byte row, the hardware reads the 8 rows, and shuffles the data across lanes so each thread ends up holding exactly the 32-bit piece the mma layout expects. The .x4 form does four such tiles at once, which is precisely the 16×16 A fragment of m16n8k16: four registers filled by one instruction, with lanes 0 to 7, 8 to 15, 16 to 23 and 24 to 31 each providing the row addresses for one tile.

{{< embed "viz/ldmatrix.html" >}}

Step through the load with the arrows, then hover a cell of D to see which row of A and column of B produced it, and which lanes hold them.

The second reason is transposition. mma.sync uses .row.col, meaning B must arrive as if column-major. If B sits in shared memory row-major, as it usually does after a straight copy from global memory, plain loads would need to gather one element from each of 16 rows to build a register. ldmatrix.trans performs that transpose during the load for free. That is the case where it is a real win rather than a convenience.

What it does not do: it only reads shared memory, not global, so the global to shared copy is still plain loads or cp.async. It only understands 16-bit element rows, so for fp8 or int8 you treat pairs of bytes as one 16-bit element and the layouts happen to line up. And bank conflicts are still your problem. Each 8×8 tile reads 8 rows of 16 bytes, and if the row stride puts those 8 rows on overlapping banks you get conflicts exactly as you would with plain loads, which is why real kernels pad or XOR-swizzle the shared memory layout.

Idea: gpu programming is hard because people are not used to think about registers. When coding for the CPU you rarely gother thinking about it and just let the compiler handle it. When coding for the GPU register pressure is quite important to take into consideration

<-TODO: what's register pressure?->


Resources: 
- [Nvidia tensor core evolution from volta to blackwell](https://newsletter.semianalysis.com/p/nvidia-tensor-core-evolution-from-volta-to-blackwell)
- [Tensor Core MMA Instruction, Lei Mao](https://leimao.github.io/blog/NVIDIA-Tensor-Core-MMA-Instruction-TN-Layout/)
- [Dissecting Tensor Cores](https://arxiv.org/abs/2206.02874)
- [GEMM using Tensor Cores](https://am17an.bearblog.dev/a-gentle-introduction-to-gemm-using-mma-tensor-cores/)
