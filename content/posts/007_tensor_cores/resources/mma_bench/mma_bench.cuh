// mma_bench.cuh - shared harness for measuring tensor-core mma.sync instructions.
//
// Every kernel runs a loop of ITERS iterations; each iteration issues CHAINS
// *independent* mma instructions (independent accumulators).  CHAINS is a template
// parameter so the compiler emits straight-line unpredicated code.
//
// Three numbers are reported per instruction:
//   latency        : cycles per instruction with CHAINS=1, 1 warp per SM (dependent chain)
//   issue interval : cycles per instruction with CHAINS=8, 1 warp per SM (one sub-partition busy)
//   throughput     : whole-GPU TFLOPS with CHAINS=8, 8 warps/block, 8 blocks/SM (event timed)
//
// "MACs per instruction" is M*N*K.  For sparse mma.sp this is the dense-equivalent count
// (what NVIDIA's "sparse TOPS" marketing numbers use); real multiplies are half of that.
#pragma once
#include <cstdio>
#include <cuda_runtime.h>

#ifndef ITERS
#define ITERS 2048
#endif

// ---- kernel generator -------------------------------------------------------
// CT   : accumulator C type (float / int / unsigned)
// NC   : number of accumulator registers per thread (4 for f32/s32, 2 for f16x2 or m8n8)
// BODY : an asm statement using a[0..3], b[0..3], c[ch][0..NC-1], e (metadata), sf (scale)
#define MMA_KERNEL(NAME, CT, NC, BODY)                                                   \
template<int CHAINS> __global__ void NAME(CT* out, long long* cyc, unsigned seed) {      \
    unsigned a[4]={seed,seed+1,seed+2,seed+3};                                           \
    unsigned b[4]={seed+4,seed+5,seed+6,seed+7};                                         \
    unsigned e = 0x44444444u;  /* valid 2:4 metadata: nonzeros at cols 0,1 of each group */ \
    unsigned sf = seed+8;                                                                \
    (void)e; (void)sf;                                                                   \
    CT c[CHAINS][NC];                                                                    \
    for(int i=0;i<CHAINS;i++) for(int j=0;j<NC;j++) c[i][j]=0;                           \
    long long t0=clock64();                                                              \
    for(int it=0; it<ITERS; it++){                                                       \
        _Pragma("unroll") for(int ch=0; ch<CHAINS; ch++){ BODY }                         \
    }                                                                                    \
    long long t1=clock64();                                                              \
    CT s=0; for(int i=0;i<CHAINS;i++) for(int j=0;j<NC;j++) s+=c[i][j];                  \
    out[blockIdx.x*blockDim.x+threadIdx.x]=s;                                            \
    if(threadIdx.x==0 && blockIdx.x==0) *cyc=t1-t0;                                      \
}

// ---- operand-shape asm bodies ------------------------------------------------
// Naming: A<n>B<m> = n A registers, m B registers.  Suffix: _F = 4 x f32 acc ("+f"),
// _I = 4 x s32 acc ("+r"), _H = 2 x f16x2 acc ("+r"), _I2 = 2 x s32 acc (m8n8 shapes).
// _SP = sparse (adds metadata e and selector 0), _SF = block scale factors.
#define C4(CON) CON(c[ch][0]),CON(c[ch][1]),CON(c[ch][2]),CON(c[ch][3])
#define C2(CON) CON(c[ch][0]),CON(c[ch][1])
#define A4 "r"(a[0]),"r"(a[1]),"r"(a[2]),"r"(a[3])
#define A2 "r"(a[0]),"r"(a[1])
#define A1 "r"(a[0])
#define B4 "r"(b[0]),"r"(b[1]),"r"(b[2]),"r"(b[3])
#define B2 "r"(b[0]),"r"(b[1])
#define B1 "r"(b[0])

// dense
#define A4B2_F(OP)  asm volatile(OP " {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9},{%0,%1,%2,%3};" : C4("+f") : A4, B2);
#define A4B2_I(OP)  asm volatile(OP " {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9},{%0,%1,%2,%3};" : C4("+r") : A4, B2);
#define A4B2_H(OP)  asm volatile(OP " {%0,%1},{%2,%3,%4,%5},{%6,%7},{%0,%1};"             : C2("+r") : A4, B2);
#define A2B1_F(OP)  asm volatile(OP " {%0,%1,%2,%3},{%4,%5},{%6},{%0,%1,%2,%3};"         : C4("+f") : A2, B1);
#define A2B1_I(OP)  asm volatile(OP " {%0,%1,%2,%3},{%4,%5},{%6},{%0,%1,%2,%3};"         : C4("+r") : A2, B1);
#define A1B1_I2(OP) asm volatile(OP " {%0,%1},{%2},{%3},{%0,%1};"                         : C2("+r") : A1, B1);
#define A4B2_F_SF(OP) asm volatile(OP " {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9},{%0,%1,%2,%3},%10,{0,0},%11,{0,0};" : C4("+f") : A4, B2, "r"(sf), "r"(sf));
// sparse: operands ... , e, selector
#define A2B2_F_SP(OP) asm volatile(OP " {%0,%1,%2,%3},{%4,%5},{%6,%7},{%0,%1,%2,%3},%8,0;"             : C4("+f") : A2, B2, "r"(e));
#define A2B2_I_SP(OP) asm volatile(OP " {%0,%1,%2,%3},{%4,%5},{%6,%7},{%0,%1,%2,%3},%8,0;"             : C4("+r") : A2, B2, "r"(e));
#define A2B2_H_SP(OP) asm volatile(OP " {%0,%1},{%2,%3},{%4,%5},{%0,%1},%6,0;"                         : C2("+r") : A2, B2, "r"(e));
#define A4B4_F_SP(OP) asm volatile(OP " {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9,%10,%11},{%0,%1,%2,%3},%12,0;" : C4("+f") : A4, B4, "r"(e));
#define A4B4_I_SP(OP) asm volatile(OP " {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9,%10,%11},{%0,%1,%2,%3},%12,0;" : C4("+r") : A4, B4, "r"(e));
#define A4B4_H_SP(OP) asm volatile(OP " {%0,%1},{%2,%3,%4,%5},{%6,%7,%8,%9},{%0,%1},%10,0;"             : C2("+r") : A4, B4, "r"(e));
#define A4B4_F_SP_SF(OP) asm volatile(OP " {%0,%1,%2,%3},{%4,%5,%6,%7},{%8,%9,%10,%11},{%0,%1,%2,%3},%12,0,%13,{0,0},%14,{0,0};" : C4("+f") : A4, B4, "r"(e), "r"(sf), "r"(sf));

// ---- runner --------------------------------------------------------------------
struct Bench {
    int sms = 0; double clk_ghz = 0;
    Bench() {
        cudaDeviceGetAttribute(&sms, cudaDevAttrMultiProcessorCount, 0);
        int khz; cudaDeviceGetAttribute(&khz, cudaDevAttrClockRate, 0); clk_ghz = khz/1e6;
        cudaDeviceProp p; cudaGetDeviceProperties(&p, 0);
        printf("%s  sm_%d%d  %d SMs  (nominal clock %.3f GHz; actual clock under load may differ)\n",
               p.name, p.major, p.minor, sms, clk_ghz);
        printf("%-28s %7s %9s %9s %10s %12s\n", "instruction", "MAC/ins", "lat(cyc)", "issue(cyc)", "MAC/clk/TC", "GPU TFLOPS");
    }
    template<typename CT, typename K>
    void run(const char* name, K k1, K k8, long macs, const char* note = "") {
        CT* d; long long* cyc;
        cudaMalloc(&d, (size_t)sms*8*256*sizeof(CT)); cudaMalloc(&cyc, 8);
        long long c1=0, c8=0; float ms=0;
        // latency: dependent chain, 1 warp per SM
        k1<<<sms,32>>>(d,cyc,1); cudaDeviceSynchronize();
        k1<<<sms,32>>>(d,cyc,1); cudaMemcpy(&c1,cyc,8,cudaMemcpyDeviceToHost);
        // issue interval: 8 independent chains, still 1 warp per SM (one sub-partition)
        k8<<<sms,32>>>(d,cyc,1); cudaDeviceSynchronize();
        k8<<<sms,32>>>(d,cyc,1); cudaMemcpy(&c8,cyc,8,cudaMemcpyDeviceToHost);
        // throughput: saturate all 4 sub-partitions of every SM
        cudaEvent_t e0,e1; cudaEventCreate(&e0); cudaEventCreate(&e1);
        k8<<<sms*8,256>>>(d,cyc,1); cudaDeviceSynchronize();
        cudaEventRecord(e0); k8<<<sms*8,256>>>(d,cyc,1); cudaEventRecord(e1); cudaEventSynchronize(e1);
        cudaEventElapsedTime(&ms,e0,e1);
        cudaError_t err=cudaGetLastError();
        if(err!=cudaSuccess){ printf("%-28s ERROR %s\n", name, cudaGetErrorString(err)); cudaGetLastError(); return; }
        double lat=(double)c1/ITERS, ii=(double)c8/(ITERS*8.0);
        double insts=(double)sms*8*8*ITERS*8;   // blocks*warps*iters*chains
        double tflops=insts*macs*2/(ms*1e-3)/1e12;
        printf("%-28s %7ld %9.1f %9.1f %10.0f %12.1f  %s\n", name, macs, lat, ii, macs/ii, tflops, note);
        cudaFree(d); cudaFree(cyc); cudaEventDestroy(e0); cudaEventDestroy(e1);
    }
};
#define RUN(B, CT, NAME, K, MACS, ...) B.run<CT>(NAME, K<1>, K<8>, MACS, ##__VA_ARGS__)
