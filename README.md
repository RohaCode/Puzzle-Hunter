# PuzzleHunter GPU

**PuzzleHunter GPU** is a high-performance, compact OpenCL tool designed to search for compressed secp256k1 private keys by a target `HASH160` (corresponding to compressed Bitcoin public addresses). It is optimized for AMD Radeon GPUs, but other OpenCL-capable devices may work as well.

The program generates candidate private keys inside a selected range (puzzle range or custom range), computes the corresponding compressed public key, performs the `RIPEMD160(SHA256(compressed_pubkey))` hashing directly on the GPU, and compares it with the target `HASH160`.

---

## ⚡ Key Optimizations & Performance Achievements

The GPU mathematical pipeline has been heavily optimized, increasing the search hashrate on an **AMD Radeon RX 6600 XT** from the baseline **~733 Mkeys/s** to a peak of **~820 Mkeys/s** (a **~12%** performance improvement):

1. **Custom Fast 256-bit Squaring (Elliptic Curve Arithmetic)**:
   - Implemented a dedicated `squareModP256k_internal` function in [secp256k1.cl](file:///e:/c++/HASH/secp256k1.cl).
   - By exploiting the symmetry of the cross-terms ($a_i \cdot a_j = a_j \cdot a_i$), the number of 32-bit multiplications is reduced from **64** to **36** (a **43%** reduction for squaring operations).
   - This optimization is applied across all modular squaring steps, including modular inversion.
2. **OpenCL Bitselect and Rotation Intrinsics**:
   - Replaced manual bitwise operations in SHA-256 ([sha256.cl](file:///e:/c++/HASH/sha256.cl)) and RIPEMD-160 ([ripemd160.cl](file:///e:/c++/HASH/ripemd160.cl)) with OpenCL's built-in `bitselect` and `rotate` functions.
   - These compile directly to single-cycle GPU hardware instructions (e.g. `v_bfi_b32` and `v_alignbit_b32` on AMD GCN/RDNA architectures).
3. **Compiler Optimization Flags**:
   - Added compiler options `-cl-denorms-are-zero`, `-cl-no-signed-zeros`, and `-cl-strict-aliasing` for the OpenCL compiler to enable aggressive driver-level optimization.

---

## 📁 Project Layout

```text
.
|-- main_gpu.cpp              # Host C++ code (OpenCL setup, CLI, keyboard input, CPU verification)
|-- puzzle_hunter_kernel.cl   # Main OpenCL search kernels
|-- secp256k1.cl              # OpenCL secp256k1 math helper functions
|-- sha256.cl                 # OpenCL SHA-256 implementation
|-- ripemd160.cl              # OpenCL RIPEMD-160 implementation
|-- hash160.cl                # HASH160 adapter and comparison helper functions
|-- Int.* / Point.*           # CPU bigint/point math libraries (for verification)
|-- SECP256K1.*               # CPU GTable generation and candidate verification
|-- OpenCL/                   # Minimal OpenCL headers and import library for Windows MinGW
|-- Makefile                  # Build script
`-- hunter.exe                # Built executable (after compilation)
```

---

## 🛠 Requirements & Build

To compile the project, you need a C++ compiler supporting C++17 and the OpenCL SDK.

### Build on Windows (via MSYS2 / MinGW-w64):
1. Install gcc and make in the MSYS2 terminal:
   ```powershell
   pacman -S mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-make
   ```
2. Make sure the paths to `g++` and `mingw32-make` are added to your system `PATH`.
3. Build the project:
   ```powershell
   mingw32-make clean
   mingw32-make
   ```

### Build on Linux (Ubuntu / Debian):
1. Install the required packages:
   ```bash
   sudo apt install build-essential ocl-icd-opencl-dev
   ```
2. Build the project:
   ```bash
   make clean
   make
   ```

---

## 🚀 Usage & Parameters

```powershell
.\hunter.exe -h <hash160_hex> [-p <puzzle> | -r <startHex:endHex>] [-b <prefix_bytes>] [-G <blocks>] [-t <threads>] [-n <points>] [-w <work_size>]
```

### Command Line Arguments:
- `-h <hex>`: Target HASH160 (exactly 40 hex characters).
- `-p <bits>`: Puzzle range bit length. Search space: `[2^(bits-1), 2^bits - 1]`.
- `-r <start:end>`: Custom search range (`startHex:endHex`).
- `-b <bytes>`: Number of leading HASH160 bytes to check (1..20, default: 20).
- `-G <blocks>`: Number of OpenCL blocks (default: 64).
- `-t <threads>`: Number of threads per block (default: 256).
- `-n <points>`: Number of points checked per thread per loop iteration (BATCH_SIZE) (default: 1024).
- `-w <size>`: OpenCL global work size (manual override).
- `--bench <n>`: Run `n` benchmark loops to test performance.

---

## 💡 Recommended Parameters for RX 6600 XT

Searching by HASH160 is significantly more resource-intensive on the GPU than public key searches. Select a profile based on your cooling and hotspot temperature limits:

### 1. Balanced Profile 🌿
- **Parameters:** `-G 128 -t 256 -n 1024` or `-G 256 -t 256 -n 1024`
- **Speed:** **~600 - 750 Mkeys/s**
- **Pros:** Quiet fans, safe hotspot temperatures, uses 1-2 GB VRAM.

### 2. Max Performance Profile ⚡ (Recommended)
- **Parameters:** `-G 384 -t 256 -n 1024`
- **Speed:** **~800 - 820 Mkeys/s**
- **Pros:** Optimal hashrate-to-temperature balance. Maximizes the usage of AMD Radeon RX 6600 XT compute units with moderate heat output. Uses ~3 GB VRAM.

### 3. Aggressive Profile 🔥
- **Parameters:** `-G 512 -t 256 -n 1024` or `-G 1024 -t 256 -n 512`
- **Speed:** **~800 - 820 Mkeys/s**
- **Pros/Cons:** Maximum heat generation and power consumption. Requires robust cooling. Uses ~4 GB VRAM.

> **Note:** If the program crashes with error `-61` (Out of resources), reduce `-G` (blocks) or `-n` (points per thread).

---

## 📈 Examples

1. **Run a benchmark to test GPU hashrate:**
   ```powershell
   .\hunter.exe -h f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8 -p 71 -G 256 -t 256 -n 1024 --bench 30
   ```

2. **Search for a full HASH160 match inside Puzzle 71:**
   ```powershell
   .\hunter.exe -h f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8 -p 71 -G 256 -t 256 -n 1024
   ```

3. **Fast partial search (match first 4 bytes of HASH160):**
   ```powershell
   .\hunter.exe -h f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8 -p 71 -b 4 -G 256 -t 256 -n 1024
   ```
   *Partial matches are displayed on the screen as the search continues. Once a full 20-byte match is found, the search terminates and results are written to a file.*

### Example Search Output (Puzzle 35, partial and full match):

```powershell
.\hunter.exe -p 35 -h f6d8ce225ffbdecec170f8298c3fc28ae686df25 -G 384 -t 256 -b 4
```

```text
=== PuzzleHunter OpenCL GPU v1.0 ===
Preparing CPU : GTable (5 bytes)
Platform      : AMD Accelerated Parallel Processing
Device        : AMD Radeon RX 6600 XT
Device type   : GPU
Compute units : 16
Max clock     : 2428 MHz
Global memory : 8176 MB
Target HASH160: f6d8ce225ffbdecec170f8298c3fc28ae686df25
Prefix bytes  : 4
Mode          : Random GPU
Batch kernel  : thread-global-chain
Puzzle        : 35
Range         : 400000000:7FFFFFFFF
Max Byte Count: 5
Blocks        : 384
Threads       : 256
Points/Thread : 1024
Checked/loop  : 201326592
Search started. Press [SPACE] to pause, [ESC] to exit.
================== PARTIAL HASH160 MATCH ===========
Prefix bytes  : 4
Private Key   : 00000000000000000000000000000000000000000000000000000007f08a3866
Found HASH160 : f6d8ce224257542d16d1da1c298e0bcd27d220a7
Target HASH160: f6d8ce225ffbdecec170f8298c3fc28ae686df25
================== FOUND MATCH! ====================
Private Key   : 00000000000000000000000000000000000000000000000000000004aed21170
Found HASH160 : f6d8ce225ffbdecec170f8298c3fc28ae686df25
Target HASH160: f6d8ce225ffbdecec170f8298c3fc28ae686df25
```

---

## 💾 Output File

Upon finding a full match, the program saves the results in a file named `KEYFOUND.txt` in the current directory. The file contains:
- Target and found HASH160 values.
- Found private key in hex format.
- Corresponding compressed public key.
- Total number of checked combinations.
- Elapsed time and average search speed.

---

## Thanks

If this project helped you and you want to say thanks:

```text
BTC: bc1qa3c5xdc6a3n2l3w0sq3vysustczpmlvhdwr8vc
```
