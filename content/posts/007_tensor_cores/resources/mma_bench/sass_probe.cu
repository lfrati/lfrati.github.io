// sass_probe.cu - compile-only probe: what does each PTX primitive become in SASS?
// Build with `make build/sass_probe.cubin`, inspect with `./sass_count.sh build/sass_probe.cubin`.
#include <mma.h>
#include <cuda_fp16.h>
using namespace nvcuda;

// wmma 16x16x16 f16: expect 2x HMMA.16816 (the "bigger primitive" is split by the compiler)
__global__ void probe_wmma_16x16x16(const half* a, const half* b, float* c) {
    wmma::fragment<wmma::matrix_a,16,16,16,half,wmma::row_major> fa;
    wmma::fragment<wmma::matrix_b,16,16,16,half,wmma::col_major> fb;
    wmma::fragment<wmma::accumulator,16,16,16,float> fc;
    wmma::fill_fragment(fc,0.f);
    wmma::load_matrix_sync(fa,a,16); wmma::load_matrix_sync(fb,b,16);
    wmma::mma_sync(fc,fa,fb,fc);
    wmma::store_matrix_sync(c,fc,16,wmma::mem_row_major);
}
// wmma 32x8x16: expect 2x HMMA.16816 as well (32x8 = two 16x8 tiles)
__global__ void probe_wmma_32x8x16(const half* a, const half* b, float* c) {
    wmma::fragment<wmma::matrix_a,32,8,16,half,wmma::row_major> fa;
    wmma::fragment<wmma::matrix_b,32,8,16,half,wmma::col_major> fb;
    wmma::fragment<wmma::accumulator,32,8,16,float> fc;
    wmma::fill_fragment(fc,0.f);
    wmma::load_matrix_sync(fa,a,16); wmma::load_matrix_sync(fb,b,32);
    wmma::mma_sync(fc,fa,fb,fc);
    wmma::store_matrix_sync(c,fc,8,wmma::mem_row_major);
}
#define ONE(NAME, OP) \
__global__ void NAME(const unsigned* a, const unsigned* b, float* c) { \
    unsigned a0=a[threadIdx.x],a1=a[threadIdx.x+32],a2=a[threadIdx.x+64],a3=a[threadIdx.x+96]; \
    unsigned b0=b[threadIdx.x],b1=b[threadIdx.x+32]; float c0=0,c1=0,c2=0,c3=0; \
    asm volatile(OP " {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9},{%0,%1,%2,%3};" \
        : "+f"(c0),"+f"(c1),"+f"(c2),"+f"(c3) : "r"(a0),"r"(a1),"r"(a2),"r"(a3),"r"(b0),"r"(b1)); \
    c[threadIdx.x]=c0+c1+c2+c3; }
ONE(probe_mma_16816_f16,  "mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32")
ONE(probe_mma_16832_e4m3, "mma.sync.aligned.m16n8k32.row.col.f32.e4m3.e4m3.f32")
ONE(probe_mma_16832_e2m1, "mma.sync.aligned.m16n8k32.row.col.kind::f8f6f4.f32.e2m1.e2m1.f32")
// m8n8k4 f16 (Volta shape): how is it lowered on Blackwell?
__global__ void probe_mma_884_f16(const unsigned* a, const unsigned* b, float* c) {
    unsigned a0=a[threadIdx.x],a1=a[threadIdx.x+32],b0=b[threadIdx.x],b1=b[threadIdx.x+32];
    float d[8]={0,0,0,0,0,0,0,0};
    asm volatile("mma.sync.aligned.m8n8k4.row.col.f32.f16.f16.f32 {%0,%1,%2,%3,%4,%5,%6,%7},{%8,%9},{%10,%11},{%0,%1,%2,%3,%4,%5,%6,%7};"
        : "+f"(d[0]),"+f"(d[1]),"+f"(d[2]),"+f"(d[3]),"+f"(d[4]),"+f"(d[5]),"+f"(d[6]),"+f"(d[7]) : "r"(a0),"r"(a1),"r"(b0),"r"(b1));
    c[threadIdx.x]=d[0]+d[1]+d[2]+d[3]+d[4]+d[5]+d[6]+d[7];
}
