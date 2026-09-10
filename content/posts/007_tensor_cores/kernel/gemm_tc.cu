#include <cuda_fp16.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cmath>

// Minimal tensor core GEMM: C[16x8] = A[16x16] * B[16x8]
// One warp (32 threads), one mma.sync instruction, fp16 throughout.
//
// Memory layouts:
//   A: row-major  — A[m][k] at gA[m*16 + k]
//   B: col-major  — B[k][n] at gB[n*16 + k]  (each column contiguous)
//   C: row-major  — C[m][n] at gC[m*8 + n]
__global__ void gemm_m16n8k16(const half *__restrict__ gA,
                               const half *__restrict__ gB,
                               half *__restrict__ gC) {
    __shared__ half smem_a[16 * 16];  // row-major
    __shared__ half smem_b[8 * 16];   // col-major (matches input layout)

    const int tid = threadIdx.x;  // 0..31

    // Copy A and B straight into shared memory (no transpose needed)
    for (int i = tid; i < 256; i += 32)
        smem_a[i] = gA[i];
    for (int i = tid; i < 128; i += 32)
        smem_b[i] = gB[i];
    __syncwarp();

    // ---- Load A[16x16] with ldmatrix.x4 ----
    // 4 groups of 8 threads each load one 8x8 sub-matrix of A:
    //   group 0 (thr  0-7)  -> a[0] <- A[0..7 ][0..7 ]
    //   group 1 (thr  8-15) -> a[1] <- A[8..15][0..7 ]
    //   group 2 (thr 16-23) -> a[2] <- A[0..7 ][8..15]
    //   group 3 (thr 24-31) -> a[3] <- A[8..15][8..15]
    // Each thread points to one 128-bit row (8 halfs) in shared memory.
    uint32_t a[4];
    {
        int group = tid >> 3;           // 0..3
        int lane  = tid & 7;            // 0..7
        int row   = (group & 1) * 8 + lane;
        int col   = (group >> 1) * 8;
        uint32_t addr = static_cast<uint32_t>(
            __cvta_generic_to_shared(&smem_a[row * 16 + col]));
        asm volatile(
            "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
            "{%0,%1,%2,%3}, [%4];\n"
            : "=r"(a[0]), "=r"(a[1]), "=r"(a[2]), "=r"(a[3])
            : "r"(addr));
    }

    // ---- Load B[16x8] with ldmatrix.x2 ----
    // 2 groups of 8 threads load two 8x8 sub-matrices of B (col-major):
    //   group 0 (thr 0-7)  -> b[0] <- columns 0-7, k=0..7
    //   group 1 (thr 8-15) -> b[1] <- columns 0-7, k=8..15
    // Each thread loads one column segment (8 contiguous halfs along k).
    // Threads 16-31 are unused by x2 but must provide a valid address.
    uint32_t b[2];
    {
        int idx;
        if (tid < 8)
            idx = tid * 16;              // column tid, starting at k=0
        else if (tid < 16)
            idx = (tid - 8) * 16 + 8;   // column tid-8, starting at k=8
        else
            idx = 0;
        uint32_t addr = static_cast<uint32_t>(
            __cvta_generic_to_shared(&smem_b[idx]));
        asm volatile(
            "ldmatrix.sync.aligned.m8n8.x2.shared.b16 "
            "{%0,%1}, [%2];\n"
            : "=r"(b[0]), "=r"(b[1])
            : "r"(addr));
    }

    // ---- mma.sync: C[16x8] = A[16x16] * B[16x8] ----
    uint32_t d[2] = {0, 0};
    asm volatile(
        "mma.sync.aligned.m16n8k16.row.col.f16.f16.f16.f16 "
        "{%0,%1}, {%2,%3,%4,%5}, {%6,%7}, {%8,%9};\n"
        : "=r"(d[0]), "=r"(d[1])
        : "r"(a[0]), "r"(a[1]), "r"(a[2]), "r"(a[3]),
          "r"(b[0]), "r"(b[1]),
          "r"(d[0]), "r"(d[1]));

    // ---- Store C[16x8] row-major ----
    // Each thread holds two half2 from the result:
    //   d[0] = { C[gid  ][c], C[gid  ][c+1] }
    //   d[1] = { C[gid+8][c], C[gid+8][c+1] }
    // where gid = tid/4 (row 0-7), c = (tid%4)*2 (col 0,2,4,6).
    {
        int gid = tid >> 2;
        int c   = (tid & 3) << 1;

        *reinterpret_cast<half2 *>(&gC[gid * 8 + c])       = *reinterpret_cast<half2 *>(&d[0]);
        *reinterpret_cast<half2 *>(&gC[(gid + 8) * 8 + c]) = *reinterpret_cast<half2 *>(&d[1]);
    }
}

int main() {
    constexpr int M = 16, N = 8, K = 16;

    half  h_A[M * K], h_B[K * N], h_C[M * N];
    float ref[M * N];

    // Small integers so fp16 is exact
    srand(42);
    for (int i = 0; i < M * K; i++)
        h_A[i] = __float2half(static_cast<float>(rand() % 5));
    for (int i = 0; i < K * N; i++)
        h_B[i] = __float2half(static_cast<float>(rand() % 5));

    // Prepare B col-major for the kernel: B_colmaj[n*K + k] = B[k][n]
    half h_B_col[K * N];
    for (int k = 0; k < K; k++)
        for (int n = 0; n < N; n++)
            h_B_col[n * K + k] = h_B[k * N + n];

    // Reference: C[m][n] = sum_k A[m][k] * B[k][n]
    for (int m = 0; m < M; m++)
        for (int n = 0; n < N; n++) {
            float acc = 0.f;
            for (int k = 0; k < K; k++)
                acc += __half2float(h_A[m * K + k]) * __half2float(h_B[k * N + n]);
            ref[m * N + n] = acc;
        }

    // Arena: all device memory in one allocation, one memcpy
    struct Arena {
        half A[M * K];
        half B[K * N];
        half C[M * N];
    };
    Arena h_arena{};
    memcpy(h_arena.A, h_A, sizeof(h_arena.A));
    memcpy(h_arena.B, h_B_col, sizeof(h_arena.B));
    // C is zero-initialized by {}

    Arena *d_arena;
    cudaMalloc(&d_arena, sizeof(Arena));
    cudaMemcpy(d_arena, &h_arena, sizeof(Arena), cudaMemcpyHostToDevice);

    gemm_m16n8k16<<<1, 32>>>(d_arena->A, d_arena->B, d_arena->C);

    cudaError_t err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        printf("CUDA error: %s\n", cudaGetErrorString(err));
        return 1;
    }

    cudaMemcpy(h_C, d_arena->C, M * N * sizeof(half), cudaMemcpyDeviceToHost);

    float max_err = 0.f;
    int worst_r = 0, worst_c = 0;
    for (int i = 0; i < M * N; i++) {
        float g = __half2float(h_C[i]);
        float e = fabsf(g - ref[i]);
        if (e > max_err) { max_err = e; worst_r = i / N; worst_c = i % N; }
    }

    printf("Max abs error: %e\n", max_err);
    if (max_err < 1.0f) {
        printf("PASS\n");
    } else {
        printf("FAIL  (worst at C[%d][%d]: gpu=%.1f ref=%.1f)\n",
               worst_r, worst_c,
               __half2float(h_C[worst_r * N + worst_c]),
               ref[worst_r * N + worst_c]);
        printf("\nGPU:\n");
        for (int i = 0; i < M; i++) {
            for (int j = 0; j < N; j++)
                printf("%6.1f", __half2float(h_C[i * N + j]));
            printf("\n");
        }
        printf("\nRef:\n");
        for (int i = 0; i < M; i++) {
            for (int j = 0; j < N; j++)
                printf("%6.1f", ref[i * N + j]);
            printf("\n");
        }
        cudaFree(d_arena);
        return 1;
    }

    cudaFree(d_arena);
    return 0;
}
