verilator \
-cc -exe --public --trace --savable \
--compiler msvc +define+SIMULATION=1 \
-O3 --x-assign fast --x-initial fast --noassert \
--converge-limit 6000 \
-Wno-fatal \
--top-module top sim.v \
../rtl/rcastudioii.sv \
../rtl/cdp1802new.v \
../rtl/dpram.sv \
../rtl/dma.v \
../rtl/rom.v \
../rtl/pixie.v