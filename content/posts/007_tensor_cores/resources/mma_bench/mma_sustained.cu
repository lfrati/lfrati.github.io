// mma_sustained.cu - whole-GPU tensor throughput under a sustained (~2.5 s) load with distinct operands per instruction.
// Reports TFLOPS at the clock the card actually sustains; run `nvidia-smi dmon -s pc` alongside to see clock/power.
// Usage: ./build/mma_sustained [seconds]
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cuda_runtime.h>
#ifndef ITERS
#define ITERS 4096
#endif
// each chain has its own A (4 regs) and B (2 regs) operand set; consecutive MMAs see different data
#define KERN(NAME, CT, NC, OP, CACC)                                                          \
template<int CHAINS> __global__ void NAME(CT* out, long long* cyc, unsigned seed, int distinct) { \
    unsigned tid = blockIdx.x*blockDim.x+threadIdx.x;                                           \
    unsigned a[CHAINS][4], b[CHAINS][2]; unsigned sf=seed+8; (void)sf;                          \
    for(int ch=0;ch<CHAINS;ch++){ unsigned s = distinct ? (tid*2654435761u + ch*0x9E3779B9u) : 1u; \
        for(int i=0;i<4;i++) a[ch][i]= distinct ? (s*(i+1)*747796405u + 2891336453u) : seed+i;  \
        for(int i=0;i<2;i++) b[ch][i]= distinct ? (s*(i+5)*277803737u ^ 0xA5A5A5A5u) : seed+4+i; } \
    CT c[CHAINS][NC]; for(int i=0;i<CHAINS;i++) for(int j=0;j<NC;j++) c[i][j]=0;               \
    long long t0=clock64();                                                                     \
    for(int it=0; it<ITERS; it++){ _Pragma("unroll") for(int ch=0; ch<CHAINS; ch++){            \
        asm volatile(OP : CACC : "r"(a[ch][0]),"r"(a[ch][1]),"r"(a[ch][2]),"r"(a[ch][3]),"r"(b[ch][0]),"r"(b[ch][1]),"r"(sf),"r"(sf)); } } \
    long long t1=clock64();                                                                     \
    CT s=0; for(int i=0;i<CHAINS;i++) for(int j=0;j<NC;j++) s+=c[i][j];                         \
    out[tid]=s; if(threadIdx.x==0 && blockIdx.x==0) *cyc=t1-t0; }
#define C4F "+f"(c[ch][0]),"+f"(c[ch][1]),"+f"(c[ch][2]),"+f"(c[ch][3])
#define C4I "+r"(c[ch][0]),"+r"(c[ch][1]),"+r"(c[ch][2]),"+r"(c[ch][3])
#define C2H "+r"(c[ch][0]),"+r"(c[ch][1])
KERN(k_f16_f32, float,4, "mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32 {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9},{%0,%1,%2,%3};", C4F)
KERN(k_f16_f16, unsigned,2, "mma.sync.aligned.m16n8k16.row.col.f16.f16.f16.f16 {%0,%1},{%2,%3,%4,%5},{%6,%7},{%0,%1};", C2H)
KERN(k_s8,      int,4, "mma.sync.aligned.m16n8k32.row.col.s32.s8.s8.s32 {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9},{%0,%1,%2,%3};", C4I)
KERN(k_e4m3_f16,unsigned,2, "mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16 {%0,%1},{%2,%3,%4,%5},{%6,%7},{%0,%1};", C2H)
KERN(k_mxf8,    float,4, "mma.sync.aligned.m16n8k32.row.col.kind::mxf8f6f4.block_scale.f32.e4m3.e4m3.f32.ue8m0 {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9},{%0,%1,%2,%3},%10,{0,0},%11,{0,0};", C4F)
KERN(k_mxf4,    float,4, "mma.sync.aligned.m16n8k64.row.col.kind::mxf4.block_scale.f32.e2m1.e2m1.f32.ue8m0 {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9},{%0,%1,%2,%3},%10,{0,0},%11,{0,0};", C4F)
template<typename CT, typename K>
void run(const char* name, K k, long macs, int distinct, double secs){
    int sms; cudaDeviceGetAttribute(&sms, cudaDevAttrMultiProcessorCount, 0);
    int nb=0; cudaOccupancyMaxActiveBlocksPerMultiprocessor(&nb, k, 256, 0);
    CT* d; long long* cyc; cudaMalloc(&d,(size_t)sms*8*256*sizeof(CT)); cudaMalloc(&cyc,8);
    cudaEvent_t e0,e1; cudaEventCreate(&e0); cudaEventCreate(&e1);
    for(int i=0;i<3;i++) k<<<sms*8,256>>>(d,cyc,1,distinct);
    cudaDeviceSynchronize();
    float ms=0; cudaEventRecord(e0); k<<<sms*8,256>>>(d,cyc,1,distinct); cudaEventRecord(e1); cudaEventSynchronize(e1);
    cudaEventElapsedTime(&ms,e0,e1);
    int n=(int)(secs*1000.0/ms)+1;
    cudaEventRecord(e0); for(int i=0;i<n;i++) k<<<sms*8,256>>>(d,cyc,1,distinct); cudaEventRecord(e1); cudaEventSynchronize(e1);
    cudaEventElapsedTime(&ms,e0,e1);
    long long c=0; cudaMemcpy(&c,cyc,8,cudaMemcpyDeviceToHost);
    double insts=(double)sms*8*8*ITERS*8*n, tflops=insts*macs*2/(ms*1e-3)/1e12;
    cudaError_t err=cudaGetLastError();
    printf("%-22s distinct=%d  maxblk/SM=%d  %5d launches %7.1f ms  %7.1f TFLOPS  blk0 cyc/inst=%.1f  %s\n",
        name, distinct, nb, n, ms, tflops, (double)c/(ITERS*8.0), err==cudaSuccess?"":cudaGetErrorString(err));
    cudaFree(d); cudaFree(cyc);
}
int main(int argc,char**argv){
    double secs = argc>1 ? atof(argv[1]) : 2.0;
    for(int distinct=0; distinct<2; distinct++){
        run<float>("f16->f32 m16n8k16", k_f16_f32<8>, 16*8*16, distinct, secs);
        run<unsigned>("f16->f16 m16n8k16", k_f16_f16<8>, 16*8*16, distinct, secs);
        run<int>("s8->s32 m16n8k32", k_s8<8>, 16*8*32, distinct, secs);
        run<unsigned>("e4m3->f16 m16n8k32", k_e4m3_f16<8>, 16*8*32, distinct, secs);
        run<float>("mxf8 e4m3->f32 k32", k_mxf8<8>, 16*8*32, distinct, secs);
        run<float>("mxf4 e2m1->f32 k64", k_mxf4<8>, 16*8*64, distinct, secs);
    }
}
