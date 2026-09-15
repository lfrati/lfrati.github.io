// One warp computes D[16x8] = A[16x16] * B[16x8], fp16 in, fp32 out.
// Same as mma_manual.cu, but the fragments are filled with ldmatrix from shared memory.
#include <cuda_fp16.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cmath>

__global__ void mma_one_tile(const half* A, const half* B, float* D) {
    int lane = threadIdx.x;   // 0..31
    int g = lane >> 2;        // 0..7
    int t = lane & 3;         // 0..3

    // ---- ldmatrix reads shared memory only, so stage the tiles there first ----
    __shared__ __align__(16) half As[16 * 16];   // 512 bytes = 32 x 16-byte chunks: one per lane
    __shared__ __align__(16) half Bs[16 * 8];    // 256 bytes = 16 chunks: lanes 0..15
    ((uint4*)As)[lane] = ((const uint4*)A)[lane];
    if (lane < 16) ((uint4*)Bs)[lane] = ((const uint4*)B)[lane];
    __syncwarp();

    // ---- A fragment with one ldmatrix.x4 ----
    // ldmatrix moves four 8x8 tiles. Lanes 0-7 give the row addresses of tile 0, lanes 8-15 of tile 1, etc.
    // Tile i lands in a[i], and we want a[0]=A[0..7][0..7], a[1]=A[8..15][0..7], a[2]=A[0..7][8..15], a[3]=A[8..15][8..15].
    // So lane L points at row (L % 16), column (L / 16) * 8.
    uint32_t a[4];
    uint32_t a_addr = __cvta_generic_to_shared(&As[(lane % 16) * 16 + (lane / 16) * 8]);
    asm volatile("ldmatrix.sync.aligned.m8n8.x4.shared.b16 {%0,%1,%2,%3}, [%4];"
                 : "=r"(a[0]), "=r"(a[1]), "=r"(a[2]), "=r"(a[3]) : "r"(a_addr));

    // ---- B fragment with one ldmatrix.x2.trans ----
    // B is row-major K x N. Tile 0 is rows k=0..7, tile 1 is rows k=8..15, each row is 8 halfs = 16 bytes.
    // .trans hands lane (g,t) the elements (k=2t, 2t+1; n=g) instead of (k=g; n=2t, 2t+1): exactly b[0], b[1].
    // Lanes 0-15 give the 16 row addresses; lanes 16-31 are ignored for .x2 but must still be valid.
    uint32_t b[2];
    uint32_t b_addr = __cvta_generic_to_shared(&Bs[(lane % 16) * 8]);
    asm volatile("ldmatrix.sync.aligned.m8n8.x2.trans.shared.b16 {%0,%1}, [%2];"
                 : "=r"(b[0]), "=r"(b[1]) : "r"(b_addr));

    // ---- Identical from here on ----
    float c[4] = {0.f, 0.f, 0.f, 0.f};
    asm volatile(
        "mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32 "
        "{%0,%1,%2,%3}, {%4,%5,%6,%7}, {%8,%9}, {%0,%1,%2,%3};"
        : "+f"(c[0]), "+f"(c[1]), "+f"(c[2]), "+f"(c[3])
        : "r"(a[0]), "r"(a[1]), "r"(a[2]), "r"(a[3]), "r"(b[0]), "r"(b[1]));

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
