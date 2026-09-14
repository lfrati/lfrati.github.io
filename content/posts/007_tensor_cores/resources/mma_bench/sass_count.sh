#!/usr/bin/env bash
# sass_count.sh <cubin-or-binary> [function-substring]
# Prints, per kernel, the count of each tensor-core SASS opcode (HMMA/IMMA/QMMA/OMMA/DMMA/BMMA)
# plus CALL (emulation subroutines).  Register operands are stripped so identical ops collapse.
set -euo pipefail
f=$1; filt=${2:-}
cuobjdump -sass "$f" | awk -v filt="$filt" '
  /Function :/ { fn=$3; on = (filt=="" || index(fn,filt)>0); next }
  on && /MMA|CALL/ {
     line=$0; sub(/\/\*[0-9a-f]+\*\//,"",line); sub(/;.*/,"",line); sub(/^[ \t]+/,"",line)
     gsub(/(@!?U?P[0-9T] )/,"",line); sub(/ .*/,"",line)     # keep opcode + modifiers only
     cnt[fn"\t"line]++
  }
  END { for (k in cnt) printf "%5d  %s\n", cnt[k], k }' | sort -k2
