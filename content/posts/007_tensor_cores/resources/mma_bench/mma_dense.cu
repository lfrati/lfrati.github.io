// mma_dense.cu - latency / issue interval / throughput of every dense mma.sync shape on sm_120a.
// Build: make   (nvcc -O3 -gencode arch=compute_120a,code=sm_120a)
#include "mma_bench.cuh"

MMA_KERNEL(k_f16_f32,   float,    4, A4B2_F("mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32"))
MMA_KERNEL(k_f16_f16,   unsigned, 2, A4B2_H("mma.sync.aligned.m16n8k16.row.col.f16.f16.f16.f16"))
MMA_KERNEL(k_bf16_f32,  float,    4, A4B2_F("mma.sync.aligned.m16n8k16.row.col.f32.bf16.bf16.f32"))
MMA_KERNEL(k_f16_k8,    float,    4, A2B1_F("mma.sync.aligned.m16n8k8.row.col.f32.f16.f16.f32"))
MMA_KERNEL(k_tf32_k8,   float,    4, A4B2_F("mma.sync.aligned.m16n8k8.row.col.f32.tf32.tf32.f32"))
MMA_KERNEL(k_tf32_k4,   float,    4, A2B1_F("mma.sync.aligned.m16n8k4.row.col.f32.tf32.tf32.f32"))
MMA_KERNEL(k_s8_k32,    int,      4, A4B2_I("mma.sync.aligned.m16n8k32.row.col.s32.s8.s8.s32"))
MMA_KERNEL(k_s8_k16,    int,      4, A2B1_I("mma.sync.aligned.m16n8k16.row.col.s32.s8.s8.s32"))
MMA_KERNEL(k_s4_k64,    int,      4, A4B2_I("mma.sync.aligned.m16n8k64.row.col.s32.s4.s4.s32"))
MMA_KERNEL(k_e4m3_f32,  float,    4, A4B2_F("mma.sync.aligned.m16n8k32.row.col.f32.e4m3.e4m3.f32"))
MMA_KERNEL(k_e4m3_f16,  unsigned, 2, A4B2_H("mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16"))
MMA_KERNEL(k_e4m3_k16,  float,    4, A2B1_F("mma.sync.aligned.m16n8k16.row.col.f32.e4m3.e4m3.f32"))
MMA_KERNEL(k_f8f6f4_e4m3, float,  4, A4B2_F("mma.sync.aligned.m16n8k32.row.col.kind::f8f6f4.f32.e4m3.e4m3.f32"))
MMA_KERNEL(k_f8f6f4_e3m2, float,  4, A4B2_F("mma.sync.aligned.m16n8k32.row.col.kind::f8f6f4.f32.e3m2.e3m2.f32"))
MMA_KERNEL(k_f8f6f4_e2m1, float,  4, A4B2_F("mma.sync.aligned.m16n8k32.row.col.kind::f8f6f4.f32.e2m1.e2m1.f32"))
MMA_KERNEL(k_f8f6f4_e2m1_h, unsigned, 2, A4B2_H("mma.sync.aligned.m16n8k32.row.col.kind::f8f6f4.f16.e2m1.e2m1.f16"))
MMA_KERNEL(k_mxf8,      float,    4, A4B2_F_SF("mma.sync.aligned.m16n8k32.row.col.kind::mxf8f6f4.block_scale.f32.e4m3.e4m3.f32.ue8m0"))
MMA_KERNEL(k_mxf6,      float,    4, A4B2_F_SF("mma.sync.aligned.m16n8k32.row.col.kind::mxf8f6f4.block_scale.f32.e3m2.e3m2.f32.ue8m0"))
MMA_KERNEL(k_mxf4_k32,  float,    4, A4B2_F_SF("mma.sync.aligned.m16n8k32.row.col.kind::mxf8f6f4.block_scale.f32.e2m1.e2m1.f32.ue8m0"))
MMA_KERNEL(k_mxf4,      float,    4, A4B2_F_SF("mma.sync.aligned.m16n8k64.row.col.kind::mxf4.block_scale.f32.e2m1.e2m1.f32.ue8m0"))
MMA_KERNEL(k_nvf4,      float,    4, A4B2_F_SF("mma.sync.aligned.m16n8k64.row.col.kind::mxf4nvf4.block_scale.scale_vec::4X.f32.e2m1.e2m1.f32.ue4m3"))

// f64 m8n8k4: 1 A reg, 1 B reg, 2 C regs, all 64-bit
template<int CHAINS> __global__ void k_f64(double* out, long long* cyc, unsigned seed) {
    double a=seed, b=seed+1; double c[CHAINS][2]; for(int i=0;i<CHAINS;i++){c[i][0]=0;c[i][1]=0;}
    long long t0=clock64();
    for(int it=0; it<ITERS; it++){ _Pragma("unroll") for(int ch=0; ch<CHAINS; ch++){
        asm volatile("mma.sync.aligned.m8n8k4.row.col.f64.f64.f64.f64 {%0,%1},{%2},{%3},{%0,%1};"
            : "+d"(c[ch][0]),"+d"(c[ch][1]) : "d"(a),"d"(b)); } }
    long long t1=clock64();
    double s=0; for(int i=0;i<CHAINS;i++) s+=c[i][0]+c[i][1];
    out[blockIdx.x*blockDim.x+threadIdx.x]=s; if(threadIdx.x==0&&blockIdx.x==0) *cyc=t1-t0;
}

int main(){
    Bench B;
    RUN(B, float,    "f16->f32  m16n8k16",  k_f16_f32,  16*8*16);
    RUN(B, unsigned, "f16->f16  m16n8k16",  k_f16_f16,  16*8*16);
    RUN(B, float,    "bf16->f32 m16n8k16",  k_bf16_f32, 16*8*16);
    RUN(B, float,    "f16->f32  m16n8k8",   k_f16_k8,   16*8*8,  "half the work, same cost");
    RUN(B, float,    "tf32->f32 m16n8k8",   k_tf32_k8,  16*8*8);
    RUN(B, float,    "tf32->f32 m16n8k4",   k_tf32_k4,  16*8*4,  "half the work, same cost");
    RUN(B, int,      "s8->s32   m16n8k32",  k_s8_k32,   16*8*32);
    RUN(B, int,      "s8->s32   m16n8k16",  k_s8_k16,   16*8*16, "half the work, same cost");
    RUN(B, int,      "s4->s32   m16n8k64",  k_s4_k64,   16*8*64, "EMULATED (CALL + 2x IMMA.16832)");
    RUN(B, float,    "e4m3->f32 m16n8k32",  k_e4m3_f32, 16*8*32);
    RUN(B, unsigned, "e4m3->f16 m16n8k32",  k_e4m3_f16, 16*8*32);
    RUN(B, float,    "e4m3->f32 m16n8k16",  k_e4m3_k16, 16*8*16, "half the work, same cost");
    RUN(B, float,    "f8f6f4 e4m3->f32 k32", k_f8f6f4_e4m3, 16*8*32);
    RUN(B, float,    "f8f6f4 e3m2->f32 k32", k_f8f6f4_e3m2, 16*8*32);
    RUN(B, float,    "f8f6f4 e2m1->f32 k32", k_f8f6f4_e2m1, 16*8*32);
    RUN(B, unsigned, "f8f6f4 e2m1->f16 k32", k_f8f6f4_e2m1_h, 16*8*32);
    RUN(B, float,    "mxf8f6f4 e4m3 SF k32", k_mxf8,   16*8*32, "block-scaled");
    RUN(B, float,    "mxf8f6f4 e3m2 SF k32", k_mxf6,   16*8*32, "block-scaled");
    RUN(B, float,    "mxf8f6f4 e2m1 SF k32", k_mxf4_k32, 16*8*32, "block-scaled, fp4 in the k32 kind");
    RUN(B, float,    "mxf4 e2m1 SF m16n8k64", k_mxf4,  16*8*64, "block-scaled");
    RUN(B, float,    "nvf4 e2m1 SF m16n8k64", k_nvf4,  16*8*64, "block-scaled, ue4m3 scale 4X");
    RUN(B, double,   "f64->f64  m8n8k4",    k_f64,      8*8*4,   "correctness-only FP64 tensor cores");
}
