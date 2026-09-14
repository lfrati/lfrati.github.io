#!/usr/bin/env bash
# isa_probe.sh - show which warp/warpgroup/tcgen05 matrix instructions ptxas accepts per target.
# Expected on consumer Blackwell: wgmma and tcgen05 rejected for sm_120a, accepted for sm_90a / sm_100a.
set -uo pipefail
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/wg.cu" <<'CU'
__global__ void k(float* c){ float d[4]={0,0,0,0};
 asm volatile("wgmma.fence.sync.aligned;");
 asm volatile("wgmma.mma_async.sync.aligned.m64n8k16.f32.f16.f16 {%0,%1,%2,%3}, %4, %5, 1,1,1,0,0;"
   : "+f"(d[0]),"+f"(d[1]),"+f"(d[2]),"+f"(d[3]) : "l"(0ull),"l"(0ull));
 asm volatile("wgmma.commit_group.sync.aligned;"); asm volatile("wgmma.wait_group.sync.aligned 0;");
 c[threadIdx.x]=d[0]+d[1]+d[2]+d[3]; }
CU
cat > "$tmp/tc5.cu" <<'CU'
__global__ void k(){ asm volatile("tcgen05.mma.cta_group::1.kind::f16 [%0], %1, %2, %3, 0;" :: "r"(0u),"l"(0ull),"l"(0ull),"r"(0u)); }
CU
cat > "$tmp/bs.cu" <<'CU'
__global__ void k(float* c){ float d[4]={0,0,0,0}; unsigned a=1,b=2,s=3;
 asm volatile("mma.sync.aligned.m16n8k64.row.col.kind::mxf4.block_scale.f32.e2m1.e2m1.f32.ue8m0 {%0,%1,%2,%3},{%4,%4,%4,%4},{%5,%5},{%0,%1,%2,%3},%6,{0,0},%6,{0,0};"
   : "+f"(d[0]),"+f"(d[1]),"+f"(d[2]),"+f"(d[3]) : "r"(a),"r"(b),"r"(s));
 c[threadIdx.x]=d[0]+d[1]+d[2]+d[3]; }
CU
probe(){ local src=$1 arch=$2
  if out=$(nvcc -gencode arch=compute_${arch},code=sm_${arch} -cubin -o "$tmp/o.cubin" "$tmp/$src" 2>&1); then
    printf "%-10s %-8s OK\n" "$src" "sm_$arch"
  else
    printf "%-10s %-8s REJECTED: %s\n" "$src" "sm_$arch" "$(echo "$out" | grep -m1 -oE "Instruction '[^']+'[^,]*|Feature '[^']+'[^,]*")"
  fi; }
for a in 90a 100a 120 120a; do probe wg.cu $a; done
for a in 90a 100a 120 120a; do probe tc5.cu $a; done
for a in 89 120 120a; do probe bs.cu $a; done
