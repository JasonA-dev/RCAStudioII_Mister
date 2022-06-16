verilator \
-cc -exe --public --trace --savable \
--compiler msvc +define+SIMULATION=1 \
-O3 --x-assign fast --x-initial fast --noassert \
--converge-limit 6000 \
-Wno-fatal \
--top-module top sim.v \
../rtl/rcastudioii.v \
../rtl/cdp1802.v \
../rtl/cdp1861.v \
../rtl/bram.v \
../rtl/dma.v \
../rtl/rom.v
