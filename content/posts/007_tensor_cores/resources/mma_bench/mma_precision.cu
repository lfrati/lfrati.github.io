// mma_precision.cu - does the accumulator really carry f32 precision for each mma kind (esp. the full-rate block-scaled ones)?
// Thread 0 holds A[0][0..3] in a[0] and B[0..3][0] in b[0] (byte/half 0), C[0][0] in c[0].
// Everything else is zero, so C[0][0] = 1.0 + A*B*(scales).  We pick A*B*scales = 2^-22 (or 2^-12 / 2^-20)
// and check whether the returned value is exactly 1+2^-22 (true f32), or rounded (f16/tf32-like).
#include <cstdio>
#include <cstring>
#include <cmath>
#include <cuda_runtime.h>

#define K4(NAME, OP, EXTRA_OPS, ...) \
__global__ void NAME(float* out, unsigned a0, unsigned b0, unsigned sf) { \
    unsigned a[4]={0,0,0,0}, b[2]={0,0}; float c[4]={1.f,0.f,0.f,0.f}; \
    if(threadIdx.x==0){a[0]=a0;b[0]=b0;} \
    asm volatile(OP " {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9},{%0,%1,%2,%3}" EXTRA_OPS ";" \
        : "+f"(c[0]),"+f"(c[1]),"+f"(c[2]),"+f"(c[3]) : "r"(a[0]),"r"(a[1]),"r"(a[2]),"r"(a[3]),"r"(b[0]),"r"(b[1]) __VA_ARGS__); \
    if(threadIdx.x==0) out[0]=c[0]; }
#define K2H(NAME, OP) \
__global__ void NAME(float* out, unsigned a0, unsigned b0, unsigned sf) { \
    unsigned a[4]={0,0,0,0}, b[2]={0,0}; unsigned c[2]={0x3c00u,0u}; /* f16 1.0 in low half */ \
    if(threadIdx.x==0){a[0]=a0;b[0]=b0;} \
    asm volatile(OP " {%0,%1},{%2,%3,%4,%5},{%6,%7},{%0,%1};" \
        : "+r"(c[0]),"+r"(c[1]) : "r"(a[0]),"r"(a[1]),"r"(a[2]),"r"(a[3]),"r"(b[0]),"r"(b[1])); \
    if(threadIdx.x==0){ unsigned h=c[0]&0xffff; /* f16->f32 */ unsigned s=(h>>15)&1,e=(h>>10)&31,m=h&1023; float v; \
        if(e==0) v=ldexpf((float)m,-24); else v=ldexpf(1.f+m/1024.f,(int)e-15); if(s) v=-v; out[0]=v; } }

K4(p_f16_f32,  "mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32", "")
K2H(p_f16_f16, "mma.sync.aligned.m16n8k16.row.col.f16.f16.f16.f16")
K4(p_e4m3_f32, "mma.sync.aligned.m16n8k32.row.col.f32.e4m3.e4m3.f32", "")
K4(p_f8f6f4_e4m3, "mma.sync.aligned.m16n8k32.row.col.kind::f8f6f4.f32.e4m3.e4m3.f32", "")
K4(p_mxf8, "mma.sync.aligned.m16n8k32.row.col.kind::mxf8f6f4.block_scale.f32.e4m3.e4m3.f32.ue8m0", ",%10,{0,0},%11,{0,0}", ,"r"(sf),"r"(sf))
K4(p_mxf4_k32, "mma.sync.aligned.m16n8k32.row.col.kind::mxf8f6f4.block_scale.f32.e2m1.e2m1.f32.ue8m0", ",%10,{0,0},%11,{0,0}", ,"r"(sf),"r"(sf))
__global__ void p_mxf4(float* out, unsigned a0, unsigned b0, unsigned sf) {
    unsigned a[4]={0,0,0,0}, b[2]={0,0}; float c[4]={1.f,0.f,0.f,0.f};
    if(threadIdx.x==0){a[0]=a0;b[0]=b0;}
    asm volatile("mma.sync.aligned.m16n8k64.row.col.kind::mxf4.block_scale.f32.e2m1.e2m1.f32.ue8m0 {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9},{%0,%1,%2,%3},%10,{0,0},%11,{0,0};"
        : "+f"(c[0]),"+f"(c[1]),"+f"(c[2]),"+f"(c[3]) : "r"(a[0]),"r"(a[1]),"r"(a[2]),"r"(a[3]),"r"(b[0]),"r"(b[1]),"r"(sf),"r"(sf));
    if(threadIdx.x==0) out[0]=c[0]; }
__global__ void p_nvf4(float* out, unsigned a0, unsigned b0, unsigned sf) {
    unsigned a[4]={0,0,0,0}, b[2]={0,0}; float c[4]={1.f,0.f,0.f,0.f};
    if(threadIdx.x==0){a[0]=a0;b[0]=b0;}
    asm volatile("mma.sync.aligned.m16n8k64.row.col.kind::mxf4nvf4.block_scale.scale_vec::4X.f32.e2m1.e2m1.f32.ue4m3 {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9},{%0,%1,%2,%3},%10,{0,0},%11,{0,0};"
        : "+f"(c[0]),"+f"(c[1]),"+f"(c[2]),"+f"(c[3]) : "r"(a[0]),"r"(a[1]),"r"(a[2]),"r"(a[3]),"r"(b[0]),"r"(b[1]),"r"(sf),"r"(sf));
    if(threadIdx.x==0) out[0]=c[0]; }

typedef void(*KF)(float*,unsigned,unsigned,unsigned);
static void run(const char* name, KF k, unsigned a0, unsigned b0, unsigned sf, double expect){
    float *d; cudaMalloc(&d,4); cudaMemset(d,0,4);
    k<<<1,32>>>(d,a0,b0,sf); cudaError_t e=cudaDeviceSynchronize();
    float h=0; cudaMemcpy(&h,d,4,cudaMemcpyDeviceToHost); cudaFree(d);
    unsigned bits; memcpy(&bits,&h,4);
    double delta=(double)h-1.0;
    const char* verdict = (e!=cudaSuccess) ? "ERROR" : (h==(float)expect) ? "EXACT (f32 accumulate)" :
        (h==1.0f) ? "LOST (rounded to 1.0)" : "PARTIAL/OTHER";
    printf("%-32s add=2^%-4.0f got=%.10f (0x%08x, delta=2^%.1f)  %s %s\n", name, log2(expect-1.0), h, bits,
           delta>0?log2(delta):-INFINITY, verdict, e!=cudaSuccess?cudaGetErrorString(e):"");
}
int main(){
    // f16: 2^-6 = 0x2400 ; product 2^-12.  f16 acc ulp at 1.0 is 2^-10 -> should be lost with f16 acc.
    run("f16->f32  m16n8k16 (+2^-12)", p_f16_f32, 0x2400u, 0x2400u, 0, 1.0+ldexp(1,-12));
    run("f16->f16  m16n8k16 (+2^-12)", p_f16_f16, 0x2400u, 0x2400u, 0, 1.0+ldexp(1,-12));
    // f16: 2^-11 = 0x1000 ; product 2^-22 (needs full f32 mantissa)
    run("f16->f32  m16n8k16 (+2^-22)", p_f16_f32, 0x1000u, 0x1000u, 0, 1.0+ldexp(1,-22));
    // e4m3: 2^-6 = 0x08 ; product 2^-12
    run("e4m3->f32 m16n8k32 (+2^-12)", p_e4m3_f32, 0x08u, 0x08u, 0, 1.0+ldexp(1,-12));
    run("f8f6f4 e4m3->f32   (+2^-12)", p_f8f6f4_e4m3, 0x08u, 0x08u, 0, 1.0+ldexp(1,-12));
    // e4m3 subnormal 2^-9 = 0x01 ; product 2^-18
    run("e4m3->f32 m16n8k32 (+2^-18)", p_e4m3_f32, 0x01u, 0x01u, 0, 1.0+ldexp(1,-18));
    // mxf8: 2^-6 * 2^-6 * scale 2^-5 * 2^-5 (ue8m0 = 127-5 = 122) = 2^-22
    run("mxf8f6f4 e4m3 SF   (+2^-12, sf=1)", p_mxf8, 0x08u, 0x08u, 127u, 1.0+ldexp(1,-12));
    run("mxf8f6f4 e4m3 SF   (+2^-22)", p_mxf8, 0x08u, 0x08u, 122u, 1.0+ldexp(1,-22));
    run("mxf8f6f4 e4m3 SF   (+2^-16)", p_mxf8, 0x08u, 0x08u, 125u, 1.0+ldexp(1,-16));
    // e2m1 1.0 = 0x2 (e=1,m=0). In the k32 kinds (f8f6f4 / mxf8f6f4) each e2m1 sits in an 8-bit container at bits 5:2
    // (PTX ISA fig. 199), so 1.0 is byte 0x08; in kind::mxf4 (k64) e2m1 is nibble-packed, 1.0 = 0x2.
    // scales 2^-11 (116) -> 2^-22 ; 2^-6 (121) -> 2^-12
    run("mxf8f6f4 e2m1 SF k32 (+2^-12)", p_mxf4_k32, 0x08u, 0x08u, 121u, 1.0+ldexp(1,-12));
    run("mxf8f6f4 e2m1 SF k32 (+2^-22)", p_mxf4_k32, 0x08u, 0x08u, 116u, 1.0+ldexp(1,-22));
    run("mxf4 e2m1 SF k64   (+2^-12)", p_mxf4, 0x2u, 0x2u, 121u, 1.0+ldexp(1,-12));
    run("mxf4 e2m1 SF k64   (+2^-22)", p_mxf4, 0x2u, 0x2u, 116u, 1.0+ldexp(1,-22));
    // nvf4: ue4m3 scale 2^-6 = 0x08 each -> 2^-12 ; ue4m3 subnormal 2^-9=0x01 each -> 2^-18 ; e2m1 0.5=0x1 each -> x2^-2 => 2^-20
    run("nvf4 e2m1 SF k64   (+2^-12)", p_nvf4, 0x2u, 0x2u, 0x08u, 1.0+ldexp(1,-12));
    run("nvf4 e2m1 SF k64   (+2^-20)", p_nvf4, 0x1u, 0x1u, 0x01u, 1.0+ldexp(1,-20));
    return 0;
}
