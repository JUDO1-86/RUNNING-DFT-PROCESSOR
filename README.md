# CORDIC-Based Running DFT Processor with Refreshing Mechanism

A SystemVerilog/Verilog HDL implementation of iterative/sequential CORDIC with refreshing mechanism.

This processor computes the $N$-point Running (Sliding-Window) Discrete Fourier Transform on a **sample-by-sample** basis without hardware multipliers and uses dual alternating Processing Elements (`PE(U)` and `PE(L)`) with periodic refreshing to bound finite-precision recursive quantization error.

---

## Key Features

- **16-Point Sliding-Window DFT ($N = 16$):** Updates spectral bin $F(r, k) = [F(r - 1, k) + s(r) - s(r - N)]e^{j\theta_k}$ on every incoming sample strobe (`sample_en`).
- **22-Bit Fixed-Point Datapath (`Q3.19`):** Uses 16-bit signed `Q1.15` complex inputs extended with **2 MSB guard bits** (overflow headroom) and **4 LSB guard bits** (truncation noise protection).
- **Multiplierless Rotational CORDIC (`0` Multipliers):** 16-iteration circular rotational CORDIC using a **9-term Canonical Signed-Digit (CSD)** shift-and-add scale-factor compensator ($1/K \approx 0.607253$) and **4-quadrant pre-rotation** supporting all 16 frequency bins ($k = 0\text{--}15$).
- **Uncompensated Vectoring CORDIC:** 16-iteration 4-quadrant vectoring CORDIC computing $K \cdot |F(r, k)|$ ($K \approx 1.64676$).
- **Dual-PE Refreshing Mechanism:** Alternates between `PE(U)` and `PE(L)` with a configurable refresh period (`SWAP_PERIOD = 512`) and $N$-sample warm-up masking so recursive error is periodically cleared with **zero interruption** to continuous spectrum output.
- **Multi-Bin Parallel Wrapper:** Includes `running_dft_all_bins_top` to compute all $N = 16$ spectral bins concurrently (`5N` CORDICs, `4N + 2` adders, `0` multipliers, `N`-deep DPRAM).

---

## Repository Structure

```text
running_dft_project/
├── rtl/
│   ├── rdft_params.vh          # Common bit-width & window parameters (N=16, IN_W=16, INT_W=22)
│   ├── sample_fifo.sv          # N-deep circular DPRAM FIFO storing complex samples s(r-N)
│   ├── complex_subtractor.sv   # Computes delta_s(r) = s(r) - s(r-N) in 22-bit Q3.19
│   ├── cordic_rotate.sv        # 16-stage rotational CORDIC with 4-quadrant pre-rotation & CSD scaling
│   ├── cordic_vector.sv        # 16-stage vectoring CORDIC for magnitude extraction
│   ├── running_dft_pe.sv       # Processing Element with warm-up masking and feedback registers
│   ├── refresh_controller.sv   # REFRCKT + DELAY refresh/swap controller for PE(U) and PE(L)
│   ├── output_mux.sv           # 2:1 complex multiplexer selecting the active PE output
│   └── running_dft_top.sv      # Top-level single-bin (running_dft_top) & 16-bin (running_dft_all_bins_top)
└── tb/
    ├── sample_fifo_tb.sv       # Unit test for circular FIFO delay and hold behavior
    ├── complex_subtractor_tb.sv# Unit test with corner cases and 2,000 random complex vectors
    ├── cordic_rotate_tb.sv     # Verifies all 16 DFT angles (0..360 deg) and 500 random rotations
    ├── cordic_vector_tb.sv     # Verifies 4-quadrant magnitude extraction across 500 random vectors
    ├── running_dft_pe_tb.sv    # Single-PE drift, refresh clear pulse, and warm-up validation
    ├── dual_pe_tb.sv           # Dual-PE seamless switching and bounded-error verification
    └── running_dft_top_tb.sv   # Full end-to-end verification (real paper signal + complex Quadrant-II)
```

---

## Architecture & Configuration

### Top-Level Ports (`running_dft_top`)

| Port | Direction | Width / Format | Description |
| :--- | :--- | :--- | :--- |
| `clk` | Input | 1-bit | System clock (CORDIC iteration clock). |
| `rst_n` | Input | 1-bit | Active-low synchronous reset. |
| `sample_en` | Input | 1-bit | Single-cycle strobe indicating a valid input sample (spaced $\ge \text{ITER}+1$ cycles). |
| `s_re`, `s_im` | Input | 16-bit signed (`Q1.15`) | Real and imaginary parts of incoming sample $s(r)$. |
| `theta` | Input | 24-bit signed (`Q3.20`) | Bin angle $\theta_k = \frac{2\pi k}{N}$ in radians scaled by $2^{20}$ (e.g., `411775` for $k=1$). |
| `f_re`, `f_im` | Output | 22-bit signed (`Q3.19`) | Complex DFT output $F(r, k)$ from the active PE. |
| `mag` | Output | 22-bit signed (`Q3.19`) | Uncompensated spectral magnitude $K \cdot \|F(r, k)\|$. |
| `mag_done` | Output | 1-bit | Single-cycle pulse when `mag` updates. |
| `mag_ok` | Output | 1-bit | High when the active PE has accumulated a full $N$-sample window. |
| `swap_sel` | Output | 1-bit | Active PE indicator (`0` = `PE(U)`, `1` = `PE(L)`). |

### Key Parameters

| Parameter | Default | Description |
| :--- | :--- | :--- |
| `N` | `16` | Sliding DFT window length. |
| `W` | `22` | Internal datapath width (`Q3.19`). |
| `ITER` | `16` | Number of CORDIC micro-rotation iterations. |
| `SWAP_PERIOD` | `512` | Refresh interval in samples ($512 T_s$). |
| `PAPER_FIG3_MODE` | `0` | `1` = Paper Fig. 2/3 `REFRCKT + DELAY` timing ($N$-sample warm-up delay before swap); `0` = testbench-compatible swap mode. |
| `SINGLE_CYCLE_COMP` | `0` | `1` = 16-cycle CORDIC latency (combinational CSD stage); `0` = 17-cycle registered CSD stage. |
| `PAPER_TRUNC_SCALE` | `0` | `1` = 16-bit truncated shift-add scaling (reproduces Paper Fig. 6b decay curve); `0` = 24-bit rounded CSD scaling. |

---

## Verification & Simulation Results

All 7 testbenches were verified in **Xilinx Vivado** (`xsim`). In `running_dft_top_tb.sv` (`SWAP_PERIOD = 512`), both the paper's real test signal $x(n) = \frac{2}{N}\sum_{k=1}^{7}\sin(n\theta_k)$ and a full complex input at Quadrant-II bin $k=5$ ($\theta_5 = 112.5^\circ$) pass with zero errors:

| Metric | Phase 1: Real Input ($k = 1$, 8,192 samples) | Phase 2: Complex Input ($k = 5$, 1,024 samples) |
| :--- | :--- | :--- |
| **Continuous Updates (`mag_done`)** | `8192 / 8192` (100%) | `1024 / 1024` (100%) |
| **Max Normalized Magnitude Error** | `2.684621e-04` | `8.261793e-05` |
| **Max Complex Vector Error** | `2.712727e-02` | `2.996588e-02` |
| **Last-Sample Complex Error** | `1.339566e-02` | — |

---

## How to Run Simulation

### Xilinx Vivado
1. Create a Vivado project and add all files from `rtl/` as **Design Sources** and all files from `tb/` as **Simulation Sources**.
2. Place `input_re.hex` (and `input_im.hex`) in your simulation run directory (`*.sim/sim_1/behav/xsim/`) if running `running_dft_pe_tb` or `dual_pe_tb`.
3. Set `running_dft_top_tb` as the top simulation module, launch **Run Behavioral Simulation**, and run `run all` in the Tcl Console.

### Icarus Verilog (`iverilog`)
```bash
iverilog -g2012 -Irtl -o top_tb.vvp rtl/*.sv tb/running_dft_top_tb.sv
vvp top_tb.vvp
```

---

