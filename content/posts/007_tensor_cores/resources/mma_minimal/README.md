# Minimal `mma.sync` examples

Two complete, self-checking kernels that each compute one tensor core tile,
`D[16x8] = A[16x16] * B[16x8]`, fp16 in, fp32 out, with a single warp.
Both use the same `mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32`
instruction with C and D aliased (`"+f"` constraints), and differ only in how
the A and B fragments get into registers.

| file | fragment fill | memory read by the fill |
|---|---|---|
| `mma_manual.cu` | plain loads, indices computed per lane from the PTX fragment layout | global |
| `mma_ldmatrix.cu` | one `ldmatrix.x4` for A, one `ldmatrix.x2.trans` for B | shared |

The point of the pair: `mma.sync` has no address operands. It reads A, B and C
from registers and writes D to registers, and the instruction set fixes which
matrix element each lane's register must hold. `ldmatrix` is a convenience
that fills those registers from shared memory in one instruction; the manual
version does the same fill with ordinary loads and index arithmetic.

```
make run    # builds both and prints PASS/FAIL against a CPU reference
make sass   # lists the load and HMMA instructions of each binary
```

Verified on an RTX 5070 Ti with CUDA 12.9. Built with `-arch=sm_120`; any
`sm_80` or newer target works since neither kernel uses Blackwell-only
instructions.
