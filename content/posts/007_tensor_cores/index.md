+++
title = 'What are Tensor Cores? Part 1'
slug = 'tensor-cores'
date = 2026-09-03
draft = false
tags = ["gpu", "cuda"]
summary = "AI goes brrr using GPU. But tensor cores make gpu go brrr. What is a tensor core tho? Shall we find out?"
math = true
+++


> [!WARNING]
> This post assumes some familiarity with the cuda programming model. If you could use a refresher, [here is one](https://developer.nvidia.com/blog/cuda-refresher-cuda-programming-model/). Also I'm going to focus on the GPU my PC has: a 5070Ti with 5th generation tensor cores. Numbers may vary depending on the nvidia gpu model and tensor core generation.

# What is a Tensor Core (TC)?
Put simply: a gpu inside your gpu.
More specifically it's dedicated hardware that computes a dense[^well1] matrix multiply-accumulate in tens of cycles. How big of a matrix it's... complicated, we'll talk about it later.

[^well1]: or sparse with a fixed pattern, but that's just a dense with fewer steps.

# Why?
Well the most relatable benefit is: how many numbers you multiply per unit of time. You have many numbers to multiply? If you use this you will be done sooner. Easy.

Less relatable but also important: instruction count and registers. A single TC instruction multiplies many numbers, which means you need to dispatch fewer instructions.
This has 2 benefits: 
- The first one is the same as above, the GPU can only issue a few instructions per clock. So if those instructions do more you get more done. 
- The second one is: instructions are not just compute, but also data movement. Fewer compute instructions = more data movement to make sure when the next compute train arrives the data is ready to board it.
1 TC instruction also saves you registers' _access_. Without it you would need many more roundtrips through the register file.

Do you miss CS class where you usually just focus on the algorithm and the hardware implementation is abstracted away? Well, that's the price you pay for speed. With GPU programming the compiler will give you what you asked for, but if you asked for something bad, well that's on you.

# Ok but what IS a tensor core? 
What does it look like?
Let's start googling a tensor core. To get a visual intuition of what the hell we are talking about. 

<div style="text-align: center;">
  <video muted autoplay loop playsinline style="width: 200px; max-width: 100%;">
    <source src="images/tensor_core_volta.mp4" type="video/mp4">
  </video>
</div>

Here we go. Pretty clear? It's... a cube of sorts?

Remember that while it's convenient to think that GPUs run "a bunch of things in parallel" and it's true that they can run many threads of computation in parallel, there is structure to those threads.

Think about your processor, specs might say something like: 6 cores 12 threads.
That means it has 6 physically distinct components (the cores) that can virtually do 12 things at once.
But those 12 things use [hyper-threading](https://www.intel.com/content/www/us/en/gaming/resources/hyper-threading.html) (if it's intel or [SMT](https://www.amd.com/en/blogs/2025/simultaneous-multithreading-driving-performance-a.html) for AMD) which means that you not always can do 12 things at once, it depends on what those parallel tasks need. 

You might be tempted to ask how many cores your gpu has and you might see that a 5070Ti has 8,960 cuda cores. But don't compare them to cpu cores, they are very different things. 🤦‍♂️

Similarly to how a cpu is a collection of cores that can run threads, an nvidia gpu is a collection of [Streaming Multiprocessors](https://docs.nvidia.com/cuda/cuda-programming-guide/01-introduction/programming-model.html#gpu-hardware-model) (SMs) that run blocks of threads.
In this context a cuda "core" is a processing unit that can perform some numerical operations, with thirty-two of them running the same instruction in lockstep as a [warp](https://docs.nvidia.com/cuda/cuda-programming-guide/01-introduction/programming-model.html#warps-and-simt). Cuda cores are much more like Arithmetic Logic Units (ALUs), which you would check to see how many numbers a cpu core can crunch. An SM is more of a "gpu core" than a cuda core is. 🙄

But back to Tensor Cores[^core]. My 5070Ti has 70 SMs and each SM has 4 5th generation tensor cores, for a total of 280 tensor cores.
[^core]: “Listen carefully, Feyd,” the Baron said. “Observe the cores within cores within cores.” - Vladimir Harkonnen, cuda expert.


{{< img src="images/Blackwell_SM.png" alt="Blackwell SM" width="400">}}

How powerful are these 280 TCores? The [Blackwell whitepaper](resources/nvidia-rtx-blackwell-gpu-architecture.pdf) says all together they are capable of

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

<!-- Using them tho, like everything else in a gpu is tricky. -->
<!-- - accessed with warp level operations -->
<!-- - there are 4 TCores per SM, 32 threads per SM = 8 threads per TCore? -->
<!-- - load them from shared memory with ldmatrix -->

# How do you actually use them?

The key functions to unlock the TCore power are: `mma.sync` (the tensor core compute op) and `ldmatrix` (the op we use to feed data to the core).

Let's start with `mma.sync`, it computes `D = AB + C` and it has a fixed size in bits. This means that the effective size of the operands depends on the data type and that's why it comes in multiple flavors e.g. `m16n8k16`, `m16n8k32`, `m16n8k64`.

Here M,N,K are conventional names from BLAS. Consider `m16n8k32` for example:
- `m16` means that there are 16 rows in A (and therefore in D)
- `n8`  means that there are 8 columns in B (and therefore in D)
- `k32` means the inner dimension is 32 elements
So together it computes D[16x8] = A[16x32] B[32x8] + C[16x8].

Remember that on NVIDIA GPUs threads are scheduled in groups of 32 called warps. All 32 threads in a warp execute the same instruction at the same time, each on its own data. The position of a thread within its warp, 0 through 31, is its lane.
`mma.sync` is a warp-level instruction that computes D = AB+C. `A` takes 4 registers in each of the 32 lanes, for a total of 32 threads x 4 registers x 32 bits/register = 4096 bits. 

These 4096 bits are arranged in 16xK elements based on the element type. Since 4096 = 16 x 256 we have 256 bits to use for numbers.
For example if the type is fp16 then K = 16 (16 x 16bits = 256bits), if we use fp32 then K = 8 (8 x 32bits = 256bits).

What's the speed of light[^light] on this card?

[^light]: because nothing is faster than the speed of light and it sounds much cooler than "Mr. Max Speed".

To reach the speed of light we need to issue instructions as fast as possible, and only five dense instructions issue every 16 cycles (full rate). Everything else is half rate or worse. Peak TFLOPS = MAC/clk/TC x 280 x 2 x clock.

$$
\text{Peak FLOPS}
\;=\;
\underbrace{\frac{\text{MAC}}{\text{clk}\cdot\text{TC}}}_{\substack{\text{MACs per clock}\\\text{per tensor core}}}
\;\times\;
\underbrace{280\ \text{TC}}_{\substack{\text{tensor cores}\\\text{(70 SMs $\times$ 4)}}}
\;\times\;
\underbrace{\frac{2\ \text{FLOP}}{\text{MAC}}}_{\substack{\text{multiply + add}\\\text{= 2 FLOPs}}}
\;\times\;
\underbrace{\text{clk}/\text{s}}_{\substack{\text{clock}\\\text{frequency}}}
$$

| format | acc. | instruction | MAC/clk/TC | TFLOPS @ 2.85 GHz |
|:-------|:-----------|:------------|-----------:|---------:|
| fp16 | f16 | `m16n8k16` f16                                    | 128 | 205 |
| int8 | s32 | `m16n8k32` s8                                     | 256 | 410 |
| fp8  | f16 | `m16n8k32` e4m3                                   | 256 | 410 |
| fp8  | f32 [^throttle] | `m16n8k32 kind::mxf8f6f4.block_scale` e4m3, ue8m0 scale | 256 | 409 |
| fp4  | f32 | `m16n8k64 kind::mxf4nvf4.block_scale.scale_vec::4X` e2m1, ue4m3 scale | 512 | 817 |

Dense `mma.sync` throughput per tensor core, measured on my RTX 5070 Ti. Scripts to reproduce them are in [resources/mma_bench](https://github.com/lfrati/lfrati.github.io/tree/main/content/posts/007_tensor_cores/resources/mma_bench).<br>
{.table-caption}

[^throttle]: The whitepaper says fp8 with f32 accumulate is 175.8 TFLOPS at boost clock, but my card does 2x that. What gives? Turns out that GeForce cards run tensor instructions that accumulate in f32 at half the rate of the same instruction accumulating in f16, by design. The plain `e4m3 -> f32` instruction really does take 32 cycles on this card, however the block-scaled `kind::mxf8f6f4` instruction is a different opcode (`QMMA.SF` instead of `QMMA` in SASS), it only exists with an f32 accumulator, and it is not throttled. A [FlashInfer RFC](https://github.com/flashinfer-ai/flashinfer/issues/3628) measured the same thing on an RTX 5060 Ti.

How do you actually use these instructions?

Let's look at one.

```asm
asm volatile(
        "mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32 "
        "{%0,%1,%2,%3}, {%4,%5,%6,%7}, {%8,%9}, {%10,%11,%12,%13};"
        : "=f"(d[0]), "=f"(d[1]), "=f"(d[2]), "=f"(d[3])
        : "r"(a[0]), "r"(a[1]), "r"(a[2]), "r"(a[3]), "r"(b[0]), "r"(b[1]),
          "f"(c[0]), "f"(c[1]), "f"(c[2]), "f"(c[3])
);
```
Yuck. Let's parse it:
- `mma`: matrix multiply-accumulate, D = A×B + C
- `.sync`: every mma is warp-wide, so all threads need to be ready and sync when starting. Results will be available in registers
- `.aligned`: a promise that all 32 lanes execute this same instruction from the same point in the program. If a lane is masked off by a branch, the result is undefined. 🙏 
- `.m16n8k16`: the shape. A is 16×16, B is 16×8, C and D are 16×8. M and N are output rows and columns, K is the inner dimension
- `.row`: A is row-major, meaning within a lane's register pair the two elements are neighbours along K
- `.col`: B is column-major, meaning a lane's register pair holds two elements that are neighbours along K in one column
- `.f32`: type of D
- `.f16`: type of A
- `.f16`: type of B
- `.f32`: type of C

The newer instructions add a `.kind::` field, such as `.kind::mxf8f6f4`, and for block scaling a `.block_scale` and `.scale_vec::4X` modifier plus a fifth type for the scale factor, such as the trailing `.ue4m3` in the nvf4 row.

# How to feed the machine 

We can tell the tensor core which registers hold the operands, but it expects the data in a specific arrangement across the warp's registers, and that arrangement is awkward to build with ordinary loads: each thread needs pairs of adjacent elements pulled from several different rows, which means several narrow loads per thread.

`ldmatrix` reads an 8×8 tile from shared memory in one pass and routes the elements to lanes through a fixed, hardwired pattern that matches what `mma.sync` wants, it requires fewer instructions and no rearranging in registers. Also, the `.trans` variant uses a second hardwired pattern that delivers the transposed fragment at the same cost, something ordinary loads can't do at all without extra loads or shuffles.

Let's see what `ldmatrix` does (step through with the arrows, hover a cell of D to see where the data comes from)

{{< embed "viz/ldmatrix.html" >}}

While helpful `ldmatrix` is not magic. Bank conflicts can still happen. Each 8×8 tile reads 8 rows of 16 bytes, and if the row stride puts those 8 rows on overlapping banks you get conflicts exactly as you would with plain loads, which is why real kernels pad or XOR-swizzle the shared memory layout.

What can you do about it? For one you can use something higher level than the raw [PTX](https://developer.nvidia.com/blog/understanding-ptx-the-assembly-language-of-cuda-gpu-computing/) (the assembly language of CUDA) we've used in the examples. For example [CUTLASS](https://docs.nvidia.com/cutlass/latest/) if you want to remain in the manual tuning regime, or something like cuBLAS, cuDNN, etc if you want more help from Nvidia experience.

# Future

We've just scratched the tip of the iceberg. My little 5070Ti is a simple consumer grade gpu that doesn't have the latest and greatest features[^blackwell]

[^blackwell]: despite the "Blackwell" chip the capabilities are very different than the bigger server-grade siblings. When in doubt check the compute capability `sm_120` = RTX 50xx series while `sm_100` = B100/B200.

In the future I want to take a deeper look at some of the tricks up the sleeves of more advanced models such as:
- `wgmma.mma_async` for Hopper (sm\_90a) computes using four warps at once, operands from shared memory via descriptors. Need to wait with `wgmma.wait_group`
- `tcgen05.mma` for datacenter Blackwell (sm\_100a), issued by a single thread, accumulates into tensor memory. Wait for results with `tcgen05.commit` into an mbarrier

On H100, `mma.sync` tops out at about two thirds of the tensor core's peak. `wgmma` is what cuBLAS, the CUTLASS SM90 kernels, and FlashAttention-3 issue. FlashAttention-2, written with `mma.sync`, got 35% of H100 peak. FlashAttention-3 moved to `wgmma` and `TMA` and reaches about 75 percent ([link](https://tridao.me/blog/2024/flash3), [paper](https://arxiv.org/abs/2407.08608), [talk](https://research.colfax-intl.com/gpu-mode-cutlass-and-flashattention-3/)).

But for now that's all. Have fun and compute responsibly.

# Resources
- [Nvidia tensor core evolution from volta to blackwell](https://newsletter.semianalysis.com/p/nvidia-tensor-core-evolution-from-volta-to-blackwell)
- [Tensor Core MMA Instruction, Lei Mao](https://leimao.github.io/blog/NVIDIA-Tensor-Core-MMA-Instruction-TN-Layout/)
- [Dissecting Tensor Cores](https://arxiv.org/abs/2206.02874)
- [GEMM using Tensor Cores](https://am17an.bearblog.dev/a-gentle-introduction-to-gemm-using-mma-tensor-cores/)
- [Zen, CUDA, and Tensor Cores: Part 1](https://www.computerenhance.com/p/zen-cuda-and-tensor-cores-part-i)
- [How To Write A Fast Matrix Multiplication From Scratch With Tensor Cores](https://alexarmbr.github.io/2024/08/10/How-To-Write-A-Fast-Matrix-Multiplication-From-Scratch-With-Tensor-Cores.html)
- [Outperforming cublas on H100](https://cudaforfun.substack.com/p/outperforming-cublas-on-h100-a-worklog)
