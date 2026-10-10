# Project Specification: DMA-Based Pipelined Image-Enhancement Accelerator

**Course:** Digital System Design (DSD)  
**Team size:** Four students  
**Project duration:** Four weeks  
**Revision:** 1.0  
**Status:** Implementation baseline and TA/professor proposal

## 1. Title

**Design, Verification, and PPA Analysis of a DMA-Based Pipelined Multi-Clock Image-Enhancement Accelerator**

The accelerator processes an 8-bit grayscale image stream with a configurable 3×3 convolution engine. Its baseline is a bit-exact, single-clock design. A dual-clock DMA/CDC subsystem using an asynchronous FIFO is a planned upgrade, not a prerequisite for a functioning accelerator.

## 2. Abstract

This project designs and evaluates a synthesizable hardware accelerator for grayscale image enhancement. The design accepts an 8-bit grayscale image through a DMA-like streaming interface, constructs a 3×3 neighborhood using line buffers, applies a configurable signed 3×3 convolution kernel, performs rounding/saturation, and writes the enhanced result through an output streaming interface. The concrete demonstration kernel is sharpening. The core is organized as an elastic, pipelined datapath so that, after pipeline fill, it can accept and produce one pixel per enabled cycle when downstream storage is available.

The project emphasizes practical digital-system design: parameterized RTL, protocol-correct streaming, arithmetic sizing, reset behavior, verification against a software golden model, synthesis, static timing analysis (STA), and PPA reporting. The minimum demonstrator runs entirely in one clock domain on 64×64 images and must be bit-exact by the end of Week 2. The target configuration adds an optional dual-clock boundary between DMA/I/O and the processing core, protected by an asynchronous FIFO and reset synchronization. Gate-level simulation (GLS), formal/sequential equivalence checking, and SAIF-based power estimation are explicitly treated as upgrades after the baseline is stable.

## 3. Motivation and Problem Statement

Software image filters execute large numbers of small, regular arithmetic operations over pixel neighborhoods. A 3×3 convolution is therefore a compact but realistic workload for demonstrating spatial data reuse, pipelining, streaming control, buffering, and hardware cost/performance trade-offs. Reading each neighborhood directly from memory would repeatedly fetch the same pixels; line buffers allow each input pixel to be consumed once while supporting a sliding 3×3 window.

The design problem is to build a reliable, parameterized accelerator that:

- moves a framed grayscale pixel stream into and out of a processing engine;
- preserves correct frame geometry and border behavior;
- delivers a bit-exact 3×3 sharpened output;
- sustains one accepted input pixel per core cycle in the steady state when `valid && ready` permits it;
- handles stalls without loss, duplication, or reordering; and
- produces evidence for correctness, timing, area, and (where available) power.

The optional multi-clock variant adds a realistic systems concern: safely carrying streaming data between unrelated I/O/DMA and core clocks. This is a CDC design problem, distinct from a timing multi-cycle path (MCP) constraint.

## 4. Objectives and Research Question

### Primary objectives

1. Implement a synthesizable 8-bit grayscale 3×3 convolution accelerator with line buffers and a sliding window.
2. Demonstrate bit-exact 64×64 single-clock operation against an independent golden model by the end of Week 2.
3. Provide a DMA-like framed streaming wrapper with protocol-correct backpressure.
4. Parameterize useful architectural choices without destabilizing the baseline.
5. Verify functional correctness, protocol behavior, reset behavior, and corner cases.
6. Measure and discuss area, critical path/frequency, latency, throughput, and—if supported—power and energy per pixel.

### Target objectives

1. Add an independent `clk_io` to `clk_core` boundary via an asynchronous FIFO.
2. Demonstrate reset synchronization and CDC-safe control transfer.
3. Run synthesis and STA on the final RTL; run GLS/equivalence/SAIF power only after the baseline passes.

### Research question

**How do pipeline depth and buffering choices affect the area, maximum clock frequency, latency, and energy-per-pixel of a streaming 3×3 grayscale image-enhancement accelerator, while retaining bit-exact output and lossless flow control?**

## 5. Scope and Deliberate Non-Scope

### In scope

- 8-bit, unsigned, single-channel grayscale pixels.
- Parameterized frame width/height; 64×64 is the mandatory verification image size.
- Signed, configurable 3×3 coefficients with a concrete sharpening default.
- Zero padding on all four borders.
- Line-buffer/window architecture, signed multiply-accumulate arithmetic, clamp-to-8-bit output.
- Ready/valid streaming and a simple DMA-like source/sink abstraction.
- Single-clock baseline; optional dual-clock async-FIFO wrapper.
- Simulation, synthesis, STA, and PPA reporting appropriate to available tools.

### Not mandatory / not claimed

- RGB, YUV, video color conversion, or multiple pixel lanes.
- A complete AXI4, AXI4-Stream, or vendor DMA IP implementation. Interface names may be AXI-like, but protocol compliance is not claimed unless separately implemented and verified.
- RTL simulation of 1080p frames. Larger resolutions may be estimated analytically or used only when simulation capacity permits.
- External DRAM controller design, cache coherency, OS drivers, physical layout, or tapeout signoff.
- Handshake-versus-FIFO comparison as a required experiment. The selected CDC implementation is async FIFO if the target tier is attempted.
- A cryptographic accelerator, neural network, or general-purpose image-processing library.
- A claim of one pixel/cycle during downstream backpressure. One pixel/cycle is a **steady-state enabled-transfer** capability, not a promise under stalls.

## 6. Design Decisions Versus External Context

The use of line buffers, sliding windows, pipelining, and asynchronous FIFOs follows established digital-design practice. These are general architectural concepts, not research claims unique to this project. The following are this team's explicit design decisions: 8-bit grayscale format, zero-padding rule, sharpening default, 64×64 Week-2 gate, compact DMA-like wrapper, and tiered CDC/GLS/equivalence/SAIF plan. The report will cite any external standards, tool documentation, or industry claims used for context; it will not present them as project measurements.

## 7. System Architecture

```text
  Testbench image / input memory
              |
              v
     +--------------------+      optional clk_io -> clk_core boundary
     | Input DMA-like     |----+  +-------------------+
     | stream source      |    +->| Async FIFO (target)|
     +--------------------+       +---------+---------+
                                            |
                                            v
   clk_core                         +-------------------+
                                    | Frame controller  |
                                    | + line buffers    |
                                    | + 3x3 window      |
                                    +---------+---------+
                                              |
                                              v
                                    +-------------------+
                                    | Pipelined 3x3 MAC |
                                    | + bias/round/sat  |
                                    +---------+---------+
                                              |
                                              v
     +--------------------+       +-------------------+
     | Output DMA-like    |<------| output elastic    |
     | stream sink/memory |       | buffer             |
     +--------------------+       +-------------------+
```

The mandatory baseline bypasses the FIFO and uses one `clk_core`. The wrapper remains logically separated from the convolution core, enabling the core to be verified independently.

### Block responsibilities

| Block | Responsibility | Baseline status |
|---|---|---|
| Configuration/control | Accept dimensions, kernel, start/reset status; prevent unsafe mid-frame changes | Required |
| Input DMA-like source | Reads or emits the input pixel frame as a ready/valid stream | Required (behavioral/simple RTL) |
| CDC FIFO | Safely transfers stream data and frame metadata across unrelated clocks | Target |
| Frame controller | Tracks accepted source pixels, positions, synthetic padding, and output coordinates | Required |
| Line buffers | Retain previous two image rows; allow a 3×3 window from a single-pass stream | Required |
| Window generator | Produces ordered 3×3 samples only when its center/output coordinate is valid | Required |
| MAC pipeline | Performs signed coefficient multiplication and addition with defined widths | Required |
| Normalizer/saturator | Applies optional arithmetic shift/bias then clamps to [0,255] | Required |
| Output elastic buffer | Holds result while sink is stalled; carries coordinate/end-of-frame markers | Required |
| Output DMA-like sink | Collects output frame and verifies ordering/length | Required (behavioral/simple RTL) |

## 8. Interfaces and Transaction Semantics

All stream interfaces use a conventional decoupled transfer rule: a beat transfers **only** on a rising edge where `valid && ready` is true. `data`, coordinate metadata, and frame flags must remain stable while `valid=1 && ready=0`.

### Input stream

| Signal | Width | Meaning |
|---|---:|---|
| `s_valid` | 1 | Source presents a beat |
| `s_ready` | 1 | Accelerator can accept a beat |
| `s_pixel` | 8 | Unsigned grayscale sample, 0–255 |
| `s_sof` | 1 | First real pixel `(0,0)` of a frame |
| `s_eol` | 1 | Last real pixel in an input row |
| `s_eof` | 1 | Last real pixel of the frame |

Baseline dimensions are configured before `s_sof`; the implementation may derive `(x,y)` from accepted beats rather than transmit coordinates. `s_sof/eol/eof` are checked against configured dimensions in verification.

### Output stream

| Signal | Width | Meaning |
|---|---:|---|
| `m_valid` | 1 | Accelerator presents an output beat |
| `m_ready` | 1 | Sink accepts an output beat |
| `m_pixel` | 8 | Saturated convolution result |
| `m_sof` | 1 | First output pixel `(0,0)` |
| `m_eol` | 1 | Last output pixel in an output row |
| `m_eof` | 1 | Last output pixel `(W-1,H-1)` |

There are exactly `W×H` output transfers for each accepted frame, including borders. Under sink backpressure, `m_valid` may remain asserted and the same result must be retained until accepted. Upstream `s_ready` may deassert once internal elastic storage is full; no beat may be accepted unless it can be retained correctly.

### Configuration/control

Suggested minimal register/interface fields: `cfg_width`, `cfg_height`, nine signed coefficients, `cfg_bias`, `cfg_shift`, `cfg_start`, `cfg_busy`, `cfg_done`, and optional `cfg_error`. Configuration is sampled/latched at frame start and is immutable for that frame. Coefficient writes during `busy` are either rejected or staged for the next frame—never partially applied to a current frame.

## 9. Data Format and Arithmetic Specification

### Pixel and coefficient formats

- Pixel: unsigned 8-bit integer, `P ∈ [0,255]`.
- Coefficient: signed 10-bit two's-complement integer by default, `C ∈ [-512,511]`. The sharpening kernel needs only small values; 10 bits leave safe experimentation headroom.
- Product: signed 18-bit (`8-bit unsigned pixel` sign-extended to 11 bits before signed multiply by 10-bit coefficient; implementation may conservatively retain 21 bits). The RTL must state the exact chosen signed casts.
- Sum: use at least signed 22 bits for nine products. A robust general rule is `ACC_W = PIXEL_W + COEFF_W + ceil(log2(9)) + 1`; with 8/10-bit inputs this is 23 bits. The baseline shall use `ACC_W=24` to avoid accidental overflow from intermediate expression sizing.
- Bias: signed `ACC_W` bits.
- Output: unsigned 8-bit after arithmetic shift and saturation.

All operands are explicitly sign/zero extended before multiplication and addition. No unsized literals or implicit signedness conversions are permitted in datapath RTL.

### Default sharpening kernel

The initial implementation uses the following unnormalized kernel, applied to the zero-padded 3×3 neighborhood:

```text
  0  -1   0
 -1   5  -1
  0  -1   0
```

For this default, `bias=0` and `shift=0`. The output is `clamp(sum, 0, 255)`. Coefficients may later be configurable, but the above kernel is the named demo and golden-model default.

### Saturation function

```text
if normalized < 0      => 0
else if normalized >255 => 255
else                     normalized[7:0]
```

When `cfg_shift > 0`, use an explicitly documented arithmetic right shift before saturation. The baseline uses truncation after shift; it does not claim round-to-nearest unless that behavior is implemented and matched by the golden model.

## 10. Convolution Geometry and Border Policy

Output coordinate `(x,y)` is defined by:

`O[x,y] = clamp(bias + Σ(i=0..2, j=0..2) C[i,j] × Ipad[x+j-1,y+i-1], 0, 255)`

where `Ipad` equals the original image inside its bounds and zero outside. This is **zero padding** on top, bottom, left, and right. It yields an output with exactly the same `W×H` geometry as input.

The hardware may realize this by injecting synthetic zero samples before/after rows and before/after the frame, or by coordinate-aware window qualification. Both are valid only if the externally observed output exactly matches the formula. The implementation must not silently switch to “valid convolution,” replicated-edge borders, or cropped output.

## 11. Pipelining, Latency, and Throughput

Pipeline stages should be named and measured, for example: (1) window qualification, (2) partial products, (3) adder tree, (4) normalization/saturation, and (5) output elastic register. `PIPE_STAGES` may select one of a small number of verified register placements; it must not create an untested arbitrary pipeline topology.

- **Initiation interval (II):** one enabled transfer/cycle for the target datapath after fill, subject to source availability and output capacity.
- **Latency:** number of accepted/processed cycles from the required input/window event to the corresponding output transfer opportunity. Report it separately from total frame time.
- **Frame time:** includes fill/drain, padding handling, and all source/sink stalls.
- **Backpressure:** makes instantaneous throughput zero during a full downstream stall. Do not state “1 pixel/cycle” without the condition that the stream is enabled and no relevant stall occurs.

For a no-stall `W×H` frame, a useful reported estimate is:

`cycles_frame ≈ W×H + L_fill + L_drain + L_border`

where each latency term is measured from RTL simulation, not assumed. The output pixel rate is `f_core / II` only in the steady state.

## 12. DMA-Like Behavior

“DMA-based” here means a hardware-controlled, descriptor/register-configured movement of a contiguous pixel frame between a source/sink memory model and the accelerator stream without per-pixel software action. For the course baseline, input/output memories can be synthesizable arrays or testbench models, with base address and stride represented conceptually or with simple registers.

Required behavior:

1. On `start`, latch a complete frame configuration.
2. Read/emit exactly `W×H` input pixels in raster order.
3. Honor `s_ready`; do not advance source address/index when no transfer occurs.
4. Accept and store exactly `W×H` outputs in raster order, honoring `m_valid`.
5. Assert `done` only after final output transfer completes.
6. Make error/status behavior deterministic for invalid dimensions or a new `start` while busy.

No claim is made that this is a full bus-master DMA, burst engine, or standards-compliant AXI DMA.

## 13. Clock, Reset, CDC, and MCP Treatment

### Baseline clock/reset

The Week-2 hard gate uses one functional clock, `clk_core`, and a synchronous or asynchronously asserted/synchronously released reset that is consistently applied and verified. All state returns to an idle state; no stale partial frame may escape after reset.

### Optional dual-clock architecture

The target design has `clk_io` for the DMA-like wrapper and `clk_core` for the accelerator. Data crosses in a dual-clock asynchronous FIFO:

- write payload: pixel plus `sof/eol/eof` (or equivalent frame metadata);
- Gray-coded read/write pointers;
- pointer synchronization through dedicated multi-flop synchronizers in the receiving domain;
- full/empty derived locally from synchronized pointers;
- FIFO memory accessed only under its own clocking scheme;
- source respects `!full`; core-side consumer respects `!empty`.

Single-bit, infrequent control/status signals crossing domains use request/acknowledge handshakes or synchronizers only when their semantics permit it. Multi-bit configuration is not sent by independently synchronizing every bit. Safer choices are: configure before starting the frame; transfer a bundled stable payload with request/acknowledge; or retain configuration solely in the core domain.

### Reset methodology

An asynchronous assertion may place both domains promptly in reset; deassertion must be synchronized separately into each clock domain. FIFO reset release requires particular care: do not start traffic until both sides are known operational and pointer state is coherent. The report must state reset polarity, assertion/deassertion behavior, and the recovery rule for mid-frame reset.

### CDC is not an MCP

CDC and multi-cycle path constraints solve different problems:

- **CDC:** transfers between unrelated clocks; requires an architectural protection mechanism (FIFO, synchronizer, or handshake) and CDC analysis.
- **MCP:** an STA exception for a synchronous path intentionally given multiple same-clock cycles to settle. It does not make an asynchronous crossing safe.

Coefficient/control CDC must therefore not be labelled an MCP. If coefficients are configured only while idle in `clk_core`, there is no coefficient CDC. An MCP is considered only if a specific, fully synchronous, functionally multi-cycle datapath is designed and verified with matching setup/hold constraints. It is not needed for the baseline MAC pipeline.

## 14. Verification Strategy

Verification is layered, self-checking, and independent of implementation structure.

### Golden model

Create a simple Python/MATLAB/SystemVerilog reference model that:

1. reads the same raw 8-bit input frame;
2. applies the exact zero-padding formula and coefficient order;
3. uses a sufficiently wide signed integer accumulator;
4. applies the same configured shift/bias/truncation and saturation;
5. writes an expected output image and/or transaction list.

The golden model must not reuse RTL arithmetic code or line-buffer logic. It is the single source for expected image pixels. Each regression log records image dimensions, coefficients, seed, expected checksum, and actual checksum.

### Test plan

| Test | Purpose / pass condition |
|---|---|
| Reset/idle | No output before valid frame; status and pointers reset cleanly |
| 1×1, 1×N, N×1 | Degenerate geometry and all-border behavior |
| 3×3 and 4×4 | Hand-checkable windows, coefficient ordering |
| 64×64 directed patterns | Constant, impulse, horizontal/vertical ramp, checkerboard, edge |
| 64×64 random | Multiple seeds; bit-exact match to golden model |
| Default sharpen | Exact results and visible enhancement on a representative image |
| Kernel variants | Identity and simple blur/edge coefficients within supported range |
| Input gaps | Random `s_valid` pauses; no loss/reorder |
| Output backpressure | Random/long `m_ready` deassertion; output remains stable and complete |
| Reset recovery | Reset before frame, during idle, and (if supported) during traffic; documented recovery |
| Config protection | Mid-frame writes do not alter active kernel |
| CDC FIFO (target) | Unrelated clock periods/phases, randomized stalls, reset release sequences |

### Assertions

SystemVerilog assertions or equivalent checks should include:

- A held input/output beat remains stable while `valid && !ready`.
- Source/output counters advance only on a handshake.
- Exactly one `sof` begins a frame; `eol` occurs after exactly `W` pixels; `eof` occurs after exactly `W×H` pixels.
- `done` cannot assert before the final output transfer.
- No output transfer when the output elastic buffer is empty.
- Active configuration is stable throughout `busy`.
- FIFO never writes when full or reads when empty (target).
- Gray-pointer transitions change no more than one bit per local increment (target, where practical).

### Coverage

Collect functional coverage for dimensions, first/interior/last rows and columns, positive/negative/zero coefficients, saturation-low/high/no-saturation outcomes, input gaps, output stalls, start/done, resets, and (target) FIFO empty/full transitions and varied clock ratios. Cross at least border location × saturation outcome and output-stall occurrence × frame position. Report coverage percentages with exclusions justified; coverage is evidence of exercised scenarios, not proof of correctness.

## 15. Implementation and Signoff Plan

### RTL and lint discipline

Use synthesizable SystemVerilog, `always_ff`/`always_comb`, nonblocking sequential assignments, explicit defaults, parameter checks, and no inferred latches. Keep core, wrapper, FIFO, and testbench separate. Define no implicit nets. Maintain a module diagram and a parameter table in the repository.

### Synthesis and STA

Synthesize the same RTL revision that passed regression. Report tool/library, constraints, top module, clock period, area, cell count, inferred memory/register usage, WNS/TNS, and critical path category. Apply ordinary clock constraints only to actual synchronous domains. For the target CDC design, declare asynchronous clock groups as appropriate and do not “fix” CDC paths using false-path constraints without architectural CDC protection.

STA results are implementation- and library-dependent. State all assumptions; do not call a synthesis-only result tapeout signoff.

### GLS, equivalence, SAIF power

- **GLS (target/stretch):** use the synthesized netlist with appropriate timing/zero-delay strategy and the same self-checking tests. Investigate X-propagation and reset differences.
- **Equivalence (target/stretch):** prove or check RTL vs synthesized netlist under compatible reset/black-box assumptions. Treat an equivalence tool result as separate evidence from simulation.
- **SAIF power (stretch):** generate activity from a representative passing workload, annotate it to the synthesized netlist, and report dynamic/leakage assumptions. A SAIF-based estimate is not silicon power.

## 16. Metrics and Calculation Methods

| Metric | Method |
|---|---|
| Correctness | Pixel-for-pixel comparison against golden output; zero mismatches |
| Latency | Measured accepted-input/window event to corresponding output-valid opportunity, excluding deliberate sink stall from intrinsic latency |
| Sustained throughput | `f_core / II` pixels/s, only for continuous enabled transfers |
| Frame rate | `f_core / measured_cycles_per_frame` frames/s for stated frame size and stall assumptions |
| Area | Synthesized area/cell area and sequential/combinational breakdown |
| Timing | Target period, achieved Fmax estimate, WNS/TNS, critical path |
| Power | Tool estimate using stated activity, voltage, library, and workload |
| Energy/pixel | `average_power_watts / processed_pixels_per_second` joules/pixel; commonly report pJ/pixel or nJ/pixel |

Do **not** use “mW per Mpixel/s” as energy: it is a power-normalized rate, not energy per pixel. If the frame has stalls, calculate processed pixel rate using observed output transfers/time, then compute energy/pixel with that same workload.

Example (illustrative only): if the measured estimate is 12 mW while producing 40 Mpixel/s, then energy/pixel = 0.012/40,000,000 J ≈ 300 pJ/pixel. This is not a predicted project result.

## 17. Parameterization

| Parameter | Baseline | Allowed range / notes |
|---|---:|---|
| `PIXEL_W` | 8 | Fixed at 8 for this project |
| `COEFF_W` | 10 | 8–12 only after regression |
| `FRAME_W`, `FRAME_H` | 64 | Positive; verify at least 1, 3, 64 sizes |
| `ACC_W` | 24 | Derived minimum or larger; never silently narrower |
| `FIFO_DEPTH` | 16/32 | Target only; power of two |
| `PIPE_MODE` | documented default | A small set of verified stage layouts |
| `cfg_shift` | 0 | Nonnegative bounded range |

Parameterization is a maintainability feature, not a requirement to test every conceivable combination. The report lists exactly which configurations were verified.

## 18. Milestones and Four-Week Schedule

### Non-negotiable hard gate

**By the end of Week 2, demonstrate single-clock, 64×64, bit-exact operation against the golden model with zero padding and the default sharpening kernel.** No CDC, GLS, equivalence, or SAIF task may displace this gate.

| Week | Planned outcome | Exit criteria |
|---|---|---|
| 1 | Specification, golden model, interface testbench skeleton, arithmetic/window micro-tests | Signed arithmetic and border examples reviewed; golden model produces expected files |
| 2 | Single-clock core and wrapper baseline | 64×64 directed + random regressions bit-exact; randomized backpressure test passes; hard gate met |
| 3 | Pipelining cleanup, synthesis/STA, PPA table; begin optional FIFO only after baseline is stable | Regressions remain green; synthesis/STA evidence collected; CDC FIFO smoke test if time permits |
| 4 | Target upgrades, report, demo, reproducibility | Final regression; report tables/plots; demo script; GLS/equivalence/SAIF only if baseline and STA are complete |

Daily practice: one reproducible regression command, an issue list with owner/status, and a short change log. Freeze interfaces after Week 1 unless a correctness defect demands revision.

## 19. Four-Person Work Split

| Member | Primary ownership | Secondary/review responsibility |
|---|---|---|
| A: Architecture/RTL lead | Frame controller, line buffers, sliding window, integration | Arithmetic review and code-quality gate |
| B: Datapath lead | MAC pipeline, coefficient/control register behavior, saturation | Synthesis/STA support |
| C: Verification lead | Golden model, scoreboard, directed/random tests, assertions/coverage | Demo output and regression automation |
| D: Systems/PPA lead | DMA-like wrapper, optional async FIFO/reset, constraints, PPA/report evidence | CDC review and final demo orchestration |

Everyone reviews interfaces and participates in regression triage. Ownership does not create isolated code: each critical module has a second reviewer. If CDC work threatens Week-2 delivery, Member D switches to testbench/PPA/documentation support until the core passes.

## 20. Risk Register and Mitigations

| Risk | Impact | Mitigation / trigger |
|---|---|---|
| Border/window off-by-one | Wrong image despite interior correctness | Hand-check 1×1/3×3/impulse cases before 64×64 |
| Signed arithmetic mistakes | Catastrophic pixel mismatch | Explicit widths/casts; golden tests with negative coefficients and saturation |
| Backpressure data loss | Protocol failure | Elastic output buffer; random stalls; stability assertions |
| CDC consumes schedule | Baseline missed | CDC is target only; freeze single-clock core at Week-2 gate |
| Tool/setup unavailable | Missing PPA evidence | Use available educational flow; document limitation and retain reproducible RTL results |
| Over-parameterization | Unverified feature surface | Restrict to listed, tested parameter configurations |
| Large-image simulation time | Slow regressions | Mandatory 64×64; use analytical throughput scaling, not mandatory 1080p RTL sim |
| Mid-frame reconfiguration | Mixed-kernel output | Latch configuration at start; reject/stage writes while busy |

## 21. Tiered Completion Definition

### Minimum (required for a credible project)

- Single `clk_core`, 8-bit grayscale, zero-padded 3×3 default sharpen.
- Correct `W×H` output count and markers.
- 64×64 bit-exact match against independent golden model by Week 2.
- Random input gaps and output backpressure verified.
- Basic synthesis and at least preliminary timing report where tools permit.

### Target

- Configurable coefficients/bias/shift with configuration latched per frame.
- Clearly defined pipeline alternatives and measured PPA trade-off.
- DMA-like input/output memory wrapper.
- Optional `clk_io`/`clk_core` asynchronous FIFO with reset synchronization and CDC-focused tests.
- Clean final synthesis/STA report.

### Stretch

- Gate-level simulation with passing self-checking regressions.
- RTL-to-netlist equivalence result.
- SAIF-based power estimate and energy/pixel calculation.
- Additional kernel demonstrations or carefully verified parameter configurations.

## 22. Acceptance Criteria

The project is accepted at the minimum tier when all of the following are demonstrated:

1. The stated 3×3 sharpening equation with zero padding is implemented exactly.
2. At least one 64×64 frame and multiple directed corner cases have zero mismatches against the independent golden model.
3. Randomized backpressure and source-gap tests show no loss, duplication, reorder, or unstable held output.
4. A frame produces exactly `W×H` output beats, correctly marking SOF/EOL/EOF.
5. Reset behavior is documented and tested.
6. The submitted RTL, testbench, model, scripts, and report identify their versions and can be rerun by the team/TA.
7. Measured versus estimated metrics are clearly distinguished.

Target/stretch claims require corresponding evidence (CDC tests/review, STA, GLS, equivalence, SAIF) in the final package.

## 23. Expected Results Tables (Populate After Measurement)

### Functional results

| Configuration | Image / seed | Stalls enabled? | Expected pixels | Actual pixels | Mismatches | Pass |
|---|---|---:|---:|---:|---:|---|
| Default sharpen, single-clock | 64×64 directed edge | No | 4096 | TBD | TBD | TBD |
| Default sharpen, single-clock | 64×64 random seed TBD | Yes | 4096 | TBD | TBD | TBD |
| Configured kernel | TBD | Yes | TBD | TBD | TBD | TBD |
| Async FIFO target | TBD | Yes | TBD | TBD | TBD | TBD |

### PPA/timing results

| RTL configuration | Clock target | Area | WNS/TNS | Estimated Fmax | Core latency | Steady-state II | Notes |
|---|---:|---:|---:|---:|---:|---:|---|
| Baseline | TBD | TBD | TBD | TBD | TBD | 1 when enabled | TBD |
| Pipeline option | TBD | TBD | TBD | TBD | TBD | 1 when enabled | TBD |
| Dual-clock target | `clk_io`: TBD; `clk_core`: TBD | TBD | TBD | TBD | TBD | 1 when enabled | FIFO excluded/included as stated |

### Energy/power results (only if tool flow supports it)

| Workload | Annotated activity? | Avg. power | Pixel rate | Energy/pixel | Assumptions |
|---|---|---:|---:|---:|---|
| 64×64 continuous stream | TBD | TBD | TBD | TBD | library, voltage, frequency, SAIF window |

## 24. Report Structure

1. Title, team, abstract, and contribution statement.
2. Motivation, problem statement, scope, and non-scope.
3. Specification: formats, kernel, zero padding, interface semantics, configuration.
4. Architecture: block diagram, line-buffer/window timing, pipeline and CDC boundaries.
5. RTL implementation choices and arithmetic-width rationale.
6. Verification environment, golden model, assertions, coverage, and results.
7. Synthesis/STA/PPA methodology and measured results.
8. Optional CDC/GLS/equivalence/SAIF evidence, clearly labelled by tier.
9. Trade-offs, limitations, risks, and lessons learned.
10. Conclusion and future work.
11. Appendix: register map, kernel table, commands, test list, and selected waveforms.

## 25. Demonstration Plan

The live/demo recording should take five to seven minutes:

1. State the problem and show the architecture in one slide.
2. Show the input grayscale image, default sharpened golden output, and RTL output (or a difference image showing zero mismatch).
3. Show a waveform for frame markers, a representative 3×3 window, and pipeline/output handshakes.
4. Demonstrate a deliberate `m_ready` stall; explain that the output is held and source throughput pauses as needed.
5. Present synthesis/STA/PPA table and state the operating assumptions.
6. If implemented, show the async FIFO boundary with distinct clocks and summarize CDC/reset safeguards.
7. Close with the tier achieved and honest limitations.

Keep a prerecorded fallback with fixed seeds and tool outputs. Avoid a demo that depends on a long synthesis run or unverified external memory hardware.

## 26. Resume Framing and Claims Discipline

### Appropriate resume wording after completion

> Designed and verified a parameterized SystemVerilog 8-bit grayscale 3×3 convolution accelerator using line buffers, a pipelined MAC datapath, ready/valid flow control, and zero-padded border handling; achieved bit-exact matching against a software golden model and analyzed synthesized PPA/STA results.

If the target is genuinely complete, add:

> Integrated a dual-clock streaming boundary using an asynchronous FIFO with synchronized reset release and CDC-focused verification.

### Do not claim

- “AXI DMA” or “full DMA controller” unless protocol and bus-master features were actually implemented and tested.
- “CDC-safe” merely because synchronizer flops were added to a multi-bit bus; cite the FIFO/handshake architecture and test evidence.
- “1 pixel/cycle” without saying “in steady state with enabled transfers/no backpressure.”
- “1080p real-time” unless demonstrated or calculated with stated assumptions at the relevant clock and bandwidth.
- Silicon power, tapeout signoff, or ASIC closure from RTL/synthesis estimates alone.
- Formal proof, GLS clean, equivalence passed, or SAIF power analysis unless the corresponding flow completed successfully.

## 27. Final Submission Deliverables

- This frozen specification and a concise change log.
- Synthesizable RTL with module-level documentation.
- Independent golden-model source and sample input/output images.
- Self-checking testbench, assertions, coverage configuration, and regression logs.
- Constraints, synthesis/STA scripts, and raw/reproducible key reports where permitted.
- Optional CDC/FIFO, GLS, equivalence, and SAIF artifacts clearly marked by completion tier.
- Final report, slide deck, demo script/video, and a one-page results summary.
- README with tool versions, commands, expected outcomes, and known limitations.

## 28. Configuration Baseline to Freeze Before Coding

Unless the team explicitly records a revision, implement the following exact baseline:

| Item | Frozen value |
|---|---|
| Input/output | 8-bit unsigned grayscale, raster order |
| Frame | 64×64 for hard-gate regression |
| Kernel | `[[0,-1,0],[-1,5,-1],[0,-1,0]]` |
| Borders | Zero padded, output same size as input |
| Bias / shift | 0 / 0 |
| Output conversion | Clamp signed result to `[0,255]` |
| Clocking | Single `clk_core` for minimum tier |
| Stream rule | Transfer only on `valid && ready` |
| Week-2 success | Zero pixel mismatches on directed and seeded-random 64×64 tests |

This baseline is intentionally narrow. It gives the team a strong, demonstrable accelerator before extending it into optional CDC and advanced implementation-flow work.
