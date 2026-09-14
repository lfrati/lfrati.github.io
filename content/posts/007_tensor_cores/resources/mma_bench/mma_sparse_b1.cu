// mma_sparse_b1.cu - latency / issue interval / throughput of 2:4 sparse mma.sp and
// single-bit (b1) mma.sync shapes on sm_120a.
// Sparse MAC counts are DENSE-EQUIVALENT (M*N*K); actual multiplies are half.
#include "mma_bench.cuh"

// ---- sparse f16 / bf16 ----
MMA_KERNEL(sp_f16_k16_f32,  float,    4, A2B2_F_SP("mma.sp.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32"))
MMA_KERNEL(sp_f16_k32_f32,  float,    4, A4B4_F_SP("mma.sp.sync.aligned.m16n8k32.row.col.f32.f16.f16.f32"))
MMA_KERNEL(sp_f16_k32_f16,  unsigned, 2, A4B4_H_SP("mma.sp.sync.aligned.m16n8k32.row.col.f16.f16.f16.f16"))
MMA_KERNEL(spo_f16_k32_f32, float,    4, A4B4_F_SP("mma.sp::ordered_metadata.sync.aligned.m16n8k32.row.col.f32.f16.f16.f32"))
MMA_KERNEL(spo_f16_k32_f16, unsigned, 2, A4B4_H_SP("mma.sp::ordered_metadata.sync.aligned.m16n8k32.row.col.f16.f16.f16.f16"))
MMA_KERNEL(sp_bf16_k32,     float,    4, A4B4_F_SP("mma.sp.sync.aligned.m16n8k32.row.col.f32.bf16.bf16.f32"))
// ---- sparse tf32 ----
MMA_KERNEL(sp_tf32_k8,      float,    4, A2B2_F_SP("mma.sp.sync.aligned.m16n8k8.row.col.f32.tf32.tf32.f32"))
MMA_KERNEL(sp_tf32_k16,     float,    4, A4B4_F_SP("mma.sp.sync.aligned.m16n8k16.row.col.f32.tf32.tf32.f32"))
// ---- sparse int ----
MMA_KERNEL(sp_s8_k32,       int,      4, A2B2_I_SP("mma.sp.sync.aligned.m16n8k32.row.col.s32.s8.s8.s32"))
MMA_KERNEL(sp_s8_k64,       int,      4, A4B4_I_SP("mma.sp.sync.aligned.m16n8k64.row.col.s32.s8.s8.s32"))
MMA_KERNEL(spo_s8_k64,      int,      4, A4B4_I_SP("mma.sp::ordered_metadata.sync.aligned.m16n8k64.row.col.s32.s8.s8.s32"))
MMA_KERNEL(sp_s4_k128,      int,      4, A4B4_I_SP("mma.sp.sync.aligned.m16n8k128.row.col.s32.s4.s4.s32"))
// ---- sparse fp8 / f6 / f4 ----
MMA_KERNEL(sp_e4m3_k64_f32, float,    4, A4B4_F_SP("mma.sp.sync.aligned.m16n8k64.row.col.f32.e4m3.e4m3.f32"))
MMA_KERNEL(sp_e4m3_k64_f16, unsigned, 2, A4B4_H_SP("mma.sp::ordered_metadata.sync.aligned.m16n8k64.row.col.f16.e4m3.e4m3.f16"))
MMA_KERNEL(spo_e4m3_k64_f32,float,    4, A4B4_F_SP("mma.sp::ordered_metadata.sync.aligned.m16n8k64.row.col.f32.e4m3.e4m3.f32"))
MMA_KERNEL(spo_f8f6f4_e2m1, float,    4, A4B4_F_SP("mma.sp::ordered_metadata.sync.aligned.m16n8k64.row.col.kind::f8f6f4.f32.e2m1.e2m1.f32"))
MMA_KERNEL(spo_f8f6f4_e2m1_h, unsigned, 2, A4B4_H_SP("mma.sp::ordered_metadata.sync.aligned.m16n8k64.row.col.kind::f8f6f4.f16.e2m1.e2m1.f16"))
MMA_KERNEL(spo_mxf8,        float,    4, A4B4_F_SP_SF("mma.sp::ordered_metadata.sync.aligned.m16n8k64.row.col.kind::mxf8f6f4.block_scale.f32.e4m3.e4m3.f32.ue8m0"))
MMA_KERNEL(spo_mxf4,        float,    4, A4B4_F_SP_SF("mma.sp::ordered_metadata.sync.aligned.m16n8k128.row.col.kind::mxf4.block_scale.f32.e2m1.e2m1.f32.ue8m0"))
MMA_KERNEL(spo_nvf4,        float,    4, A4B4_F_SP_SF("mma.sp::ordered_metadata.sync.aligned.m16n8k128.row.col.kind::mxf4nvf4.block_scale.scale_vec::4X.f32.e2m1.e2m1.f32.ue4m3"))
// ---- single bit ----
MMA_KERNEL(b1_k256_xor,     int,      4, A4B2_I("mma.sync.aligned.m16n8k256.row.col.s32.b1.b1.s32.xor.popc"))
MMA_KERNEL(b1_k256_and,     int,      4, A4B2_I("mma.sync.aligned.m16n8k256.row.col.s32.b1.b1.s32.and.popc"))
MMA_KERNEL(b1_k128_xor,     int,      4, A2B1_I("mma.sync.aligned.m16n8k128.row.col.s32.b1.b1.s32.xor.popc"))
MMA_KERNEL(b1_88k128_xor,   int,      2, A1B1_I2("mma.sync.aligned.m8n8k128.row.col.s32.b1.b1.s32.xor.popc"))

int main(){
    Bench B;
    printf("--- 2:4 sparse (MAC counts are dense-equivalent) ---\n");
    RUN(B, float,    "sp f16->f32 m16n8k16",    sp_f16_k16_f32,  16*8*16);
    RUN(B, float,    "sp f16->f32 m16n8k32",    sp_f16_k32_f32,  16*8*32);
    RUN(B, unsigned, "sp f16->f16 m16n8k32",    sp_f16_k32_f16,  16*8*32);
    RUN(B, float,    "sp::om f16->f32 k32",     spo_f16_k32_f32, 16*8*32, "ordered_metadata");
    RUN(B, unsigned, "sp::om f16->f16 k32",     spo_f16_k32_f16, 16*8*32, "ordered_metadata");
    RUN(B, float,    "sp bf16->f32 m16n8k32",   sp_bf16_k32,     16*8*32);
    RUN(B, float,    "sp tf32->f32 m16n8k8",    sp_tf32_k8,      16*8*8);
    RUN(B, float,    "sp tf32->f32 m16n8k16",   sp_tf32_k16,     16*8*16);
    RUN(B, int,      "sp s8->s32 m16n8k32",     sp_s8_k32,       16*8*32);
    RUN(B, int,      "sp s8->s32 m16n8k64",     sp_s8_k64,       16*8*64);
    RUN(B, int,      "sp::om s8->s32 k64",      spo_s8_k64,      16*8*64, "ordered_metadata");
    RUN(B, int,      "sp s4->s32 m16n8k128",    sp_s4_k128,      16*8*128, "expect emulation");
    RUN(B, float,    "sp e4m3->f32 m16n8k64",   sp_e4m3_k64_f32, 16*8*64);
    RUN(B, unsigned, "sp::om e4m3->f16 k64",    sp_e4m3_k64_f16, 16*8*64, "plain .sp rejected with f16 acc");
    RUN(B, float,    "sp::om e4m3->f32 k64",    spo_e4m3_k64_f32,16*8*64, "ordered_metadata");
    RUN(B, float,    "sp::om f8f6f4 e2m1 k64",  spo_f8f6f4_e2m1, 16*8*64);
    RUN(B, unsigned, "sp::om f8f6f4 e2m1->f16", spo_f8f6f4_e2m1_h, 16*8*64);
    RUN(B, float,    "sp::om mxf8 e4m3 SF k64", spo_mxf8,        16*8*64, "block-scaled");
    RUN(B, float,    "sp::om mxf4 e2m1 SF k128",spo_mxf4,        16*8*128, "block-scaled");
    RUN(B, float,    "sp::om nvf4 e2m1 SF k128",spo_nvf4,        16*8*128, "block-scaled");
    printf("--- single-bit (b1): 'MAC' = one AND/XOR + popcount ---\n");
    RUN(B, int,      "b1 xor.popc m16n8k256",   b1_k256_xor,     16*8*256);
    RUN(B, int,      "b1 and.popc m16n8k256",   b1_k256_and,     16*8*256);
    RUN(B, int,      "b1 xor.popc m16n8k128",   b1_k128_xor,     16*8*128, "half the work, same cost?");
    RUN(B, int,      "b1 xor.popc m8n8k128",    b1_88k128_xor,   8*8*128,  "Turing-era shape");
}
