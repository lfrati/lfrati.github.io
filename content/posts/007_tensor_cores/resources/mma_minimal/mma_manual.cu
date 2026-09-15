// One warp computes D[16x8] = A[16x16] * B[16x8], fp16 in, fp32 out.
// No ldmatrix, no shared memory: every lane loads its own fragment pieces straight from global memory.
#include <cuda_fp16.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cmath>

// Two halfs into one 32-bit register: the lower-index element goes in the low 16 bits.
__device__ uint32_t pack(half lo, half hi) {
    return (uint32_t)__half_as_ushort(lo) | ((uint32_t)__half_as_ushort(hi) << 16);
}

__global__ void mma_one_tile(const half* A, const half* B, float* D) {
    int lane = threadIdx.x;   // 0..31
    int g = lane >> 2;        // "groupID"            0..7
    int t = lane & 3;         // "threadID_in_group"  0..3

    // ---- A fragment: 4 registers per lane. Register a[i] must hold A[row][col], A[row][col+1] ----
    //   a[0]: row g,   cols 2t, 2t+1
    //   a[1]: row g+8, cols 2t, 2t+1
    //   a[2]: row g,   cols 2t+8, 2t+9
    //   a[3]: row g+8, cols 2t+8, 2t+9
    // A is row-major with 16 columns, so the two halfs are adjacent: one 32-bit load each.
    uint32_t a[4];
    a[0] = *(const uint32_t*)&A[(g    ) * 16 + 2*t    ];
    a[1] = *(const uint32_t*)&A[(g + 8) * 16 + 2*t    ];
    a[2] = *(const uint32_t*)&A[(g    ) * 16 + 2*t + 8];
    a[3] = *(const uint32_t*)&A[(g + 8) * 16 + 2*t + 8];

    // ---- B fragment: 2 registers per lane. Register b[i] must hold B[k][n], B[k+1][n] with n = g ----
    //   b[0]: k = 2t, 2t+1
    //   b[1]: k = 2t+8, 2t+9
    // B is row-major K x N (8 columns), so B[k][g] and B[k+1][g] are 8 halfs apart: two loads and a pack.
    uint32_t b[2];
    b[0] = pack(B[(2*t    ) * 8 + g], B[(2*t + 1) * 8 + g]);
    b[1] = pack(B[(2*t + 8) * 8 + g], B[(2*t + 9) * 8 + g]);

    // ---- The instruction. Operands are registers only. There is no pointer anywhere. ----
    float c[4] = {0.f, 0.f, 0.f, 0.f};
    asm volatile(
        "mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32 "
        "{%0,%1,%2,%3}, {%4,%5,%6,%7}, {%8,%9}, {%0,%1,%2,%3};"
        : "+f"(c[0]), "+f"(c[1]), "+f"(c[2]), "+f"(c[3])
        : "r"(a[0]), "r"(a[1]), "r"(a[2]), "r"(a[3]), "r"(b[0]), "r"(b[1]));

    // ---- D fragment: same rule in reverse. c[0],c[1] = D[g][2t], D[g][2t+1]; c[2],c[3] = row g+8 ----
    D[(g    ) * 8 + 2*t    ] = c[0];
    D[(g    ) * 8 + 2*t + 1] = c[1];
    D[(g + 8) * 8 + 2*t    ] = c[2];
    D[(g + 8) * 8 + 2*t + 1] = c[3];
}

int main() {
    half hA[16*16], hB[16*8]; float ref[16*8], out[16*8];
    for (int i = 0; i < 16*16; i++) hA[i] = __float2half((float)(rand() % 7 - 3));
    for (int i = 0; i < 16*8;  i++) hB[i] = __float2half((float)(rand() % 7 - 3));
    for (int m = 0; m < 16; m++) for (int n = 0; n < 8; n++) {
        float s = 0; for (int k = 0; k < 16; k++) s += __half2float(hA[m*16+k]) * __half2float(hB[k*8+n]);
        ref[m*8+n] = s;
    }
    half *dA, *dB; float *dD;
    cudaMalloc(&dA, sizeof hA); cudaMalloc(&dB, sizeof hB); cudaMalloc(&dD, sizeof out);
    cudaMemcpy(dA, hA, sizeof hA, cudaMemcpyHostToDevice);
    cudaMemcpy(dB, hB, sizeof hB, cudaMemcpyHostToDevice);
    mma_one_tile<<<1, 32>>>(dA, dB, dD);
    cudaMemcpy(out, dD, sizeof out, cudaMemcpyDeviceToHost);
    int bad = 0; for (int i = 0; i < 16*8; i++) if (fabsf(out[i]-ref[i]) > 1e-3f) bad++;
    printf("%s  (%d/128 mismatches)\n", bad ? "FAIL" : "PASS", bad);
    printf("D[0][0..7] gpu: "); for (int n = 0; n < 8; n++) printf("%5.0f", out[n]); printf("\n");
    printf("D[0][0..7] ref: "); for (int n = 0; n < 8; n++) printf("%5.0f", ref[n]); printf("\n");
    return bad != 0;
}
