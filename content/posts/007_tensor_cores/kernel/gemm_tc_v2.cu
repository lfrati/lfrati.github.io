#include <cuda_fp16.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <cstring>

// 280 independent m16n8k16 GEMMs — one per tensor core on a 5070 Ti.
// 70 blocks × 4 warps/block = 280 warps, each hitting one tensor core.
//
// Each warp computes: C_i[16x8] = A_i[16x16] * B_i[16x8]
// where i = global warp index (0..279).
constexpr int NUM_TCS   = 280;
constexpr int WARPS_PER_BLOCK = 4;    // = tensor cores per SM
constexpr int BLOCKS    = NUM_TCS / WARPS_PER_BLOCK;  // 70 = number of SMs
constexpr int M = 16, N = 8, K = 16;
constexpr int SZ_A = M * K;  // 256
constexpr int SZ_B = K * N;  // 128
constexpr int SZ_C = M * N;  // 128

__global__ void gemm_m16n8k16_x280(const half *__restrict__ gA,
                                    const half *__restrict__ gB,
                                    half *__restrict__ gC) {
    // 4 warps per block, each with its own shared memory region
    __shared__ half smem_a[WARPS_PER_BLOCK][SZ_A];  // 4 × 16×16
    __shared__ half smem_b[WARPS_PER_BLOCK][SZ_B];  // 4 × 16×8

    const int warp_in_block = threadIdx.x >> 5;     // 0..3
    const int lane          = threadIdx.x & 31;     // 0..31
    const int global_warp   = blockIdx.x * WARPS_PER_BLOCK + warp_in_block;

    // Each warp loads its own A and B into its shared memory slot
    const half *myA = gA + global_warp * SZ_A;
    const half *myB = gB + global_warp * SZ_B;
    for (int i = lane; i < SZ_A; i += 32)
        smem_a[warp_in_block][i] = myA[i];
    for (int i = lane; i < SZ_B; i += 32)
        smem_b[warp_in_block][i] = myB[i];
    __syncwarp();

    // ---- Load A[16x16] with ldmatrix.x4 ----
    uint32_t a[4];
    {
        int group = lane >> 3;
        int l     = lane & 7;
        int row   = (group & 1) * 8 + l;
        int col   = (group >> 1) * 8;
        uint32_t addr = static_cast<uint32_t>(
            __cvta_generic_to_shared(&smem_a[warp_in_block][row * 16 + col]));
        asm volatile(
            "ldmatrix.sync.aligned.m8n8.x4.shared.b16 "
            "{%0,%1,%2,%3}, [%4];\n"
            : "=r"(a[0]), "=r"(a[1]), "=r"(a[2]), "=r"(a[3])
            : "r"(addr));
    }

    // ---- Load B[16x8] with ldmatrix.x2 ----
    uint32_t b[2];
    {
        int idx;
        if (lane < 8)
            idx = lane * 16;
        else if (lane < 16)
            idx = (lane - 8) * 16 + 8;
        else
            idx = 0;
        uint32_t addr = static_cast<uint32_t>(
            __cvta_generic_to_shared(&smem_b[warp_in_block][idx]));
        asm volatile(
            "ldmatrix.sync.aligned.m8n8.x2.shared.b16 "
            "{%0,%1}, [%2];\n"
            : "=r"(b[0]), "=r"(b[1])
            : "r"(addr));
    }

    // ---- mma.sync ----
    uint32_t d[2] = {0, 0};
    asm volatile(
        "mma.sync.aligned.m16n8k16.row.col.f16.f16.f16.f16 "
        "{%0,%1}, {%2,%3,%4,%5}, {%6,%7}, {%8,%9};\n"
        : "=r"(d[0]), "=r"(d[1])
        : "r"(a[0]), "r"(a[1]), "r"(a[2]), "r"(a[3]),
          "r"(b[0]), "r"(b[1]),
          "r"(d[0]), "r"(d[1]));

    // ---- Store C[16x8] ----
    half *myC = gC + global_warp * SZ_C;
    int gid = lane >> 2;
    int c   = (lane & 3) << 1;
    *reinterpret_cast<half2 *>(&myC[gid * 8 + c])       = *reinterpret_cast<half2 *>(&d[0]);
    *reinterpret_cast<half2 *>(&myC[(gid + 8) * 8 + c]) = *reinterpret_cast<half2 *>(&d[1]);
}

int main() {
    // 280 independent problems
    half  *h_A   = new half[NUM_TCS * SZ_A];
    half  *h_B   = new half[NUM_TCS * SZ_B];  // row-major, will be transposed
    half  *h_C   = new half[NUM_TCS * SZ_C];
    float *h_ref = new float[NUM_TCS * SZ_C];

    srand(42);
    for (int i = 0; i < NUM_TCS * SZ_A; i++)
        h_A[i] = __float2half(static_cast<float>(rand() % 5));
    for (int i = 0; i < NUM_TCS * SZ_B; i++)
        h_B[i] = __float2half(static_cast<float>(rand() % 5));

    // Transpose each B to col-major
    half *h_B_col = new half[NUM_TCS * SZ_B];
    for (int w = 0; w < NUM_TCS; w++)
        for (int k = 0; k < K; k++)
            for (int n = 0; n < N; n++)
                h_B_col[w * SZ_B + n * K + k] = h_B[w * SZ_B + k * N + n];

    // Reference
    for (int w = 0; w < NUM_TCS; w++)
        for (int m = 0; m < M; m++)
            for (int n = 0; n < N; n++) {
                float acc = 0.f;
                for (int k = 0; k < K; k++)
                    acc += __half2float(h_A[w * SZ_A + m * K + k])
                         * __half2float(h_B[w * SZ_B + k * N + n]);
                h_ref[w * SZ_C + m * N + n] = acc;
            }

    // Arena: one allocation, one memcpy
    struct Arena {
        half A[NUM_TCS * SZ_A];
        half B[NUM_TCS * SZ_B];
        half C[NUM_TCS * SZ_C];
    };
    Arena *h_arena = new Arena{};
    memcpy(h_arena->A, h_A, sizeof(h_arena->A));
    memcpy(h_arena->B, h_B_col, sizeof(h_arena->B));

    Arena *d_arena;
    cudaMalloc(&d_arena, sizeof(Arena));
    cudaMemcpy(d_arena, h_arena, sizeof(Arena), cudaMemcpyHostToDevice);

    // 70 blocks × 128 threads = 280 warps
    gemm_m16n8k16_x280<<<BLOCKS, WARPS_PER_BLOCK * 32>>>(d_arena->A, d_arena->B, d_arena->C);

    cudaError_t err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        printf("CUDA error: %s\n", cudaGetErrorString(err));
        return 1;
    }

    cudaMemcpy(h_C, d_arena->C, sizeof(h_arena->C), cudaMemcpyDeviceToHost);

    // Verify all 280
    float max_err = 0.f;
    int worst_w = 0, worst_r = 0, worst_c = 0;
    for (int i = 0; i < NUM_TCS * SZ_C; i++) {
        float g = __half2float(h_C[i]);
        float e = fabsf(g - h_ref[i]);
        if (e > max_err) {
            max_err = e;
            worst_w = i / SZ_C;
            worst_r = (i % SZ_C) / N;
            worst_c = (i % SZ_C) % N;
        }
    }

    printf("280 independent m16n8k16 GEMMs on 280 tensor cores\n");
    printf("Max abs error: %e\n", max_err);
    if (max_err < 1.0f)
        printf("PASS\n");
    else
        printf("FAIL  (worst at warp %d, C[%d][%d]: gpu=%.1f ref=%.1f)\n",
               worst_w, worst_r, worst_c,
               __half2float(h_C[worst_w * SZ_C + worst_r * N + worst_c]),
               h_ref[worst_w * SZ_C + worst_r * N + worst_c]);

    cudaFree(d_arena);
    delete[] h_A; delete[] h_B; delete[] h_B_col; delete[] h_C; delete[] h_ref;
    delete h_arena;
    return max_err < 1.0f ? 0 : 1;
}
