# Frozen Baseline — Agree on this BEFORE writing any code

This is the hackathon-scoped (1-day) subset of the full 4-week spec
(`docs/image-enhancement-accelerator-project-specification.md`). Do not
revisit these numbers mid-day — if something needs to change, the whole
team re-agrees out loud first.

| Item | Frozen value |
|---|---|
| Image size | **8x8** (fallback: 4x4 if integration is slow by hour 6) |
| Pixel format | unsigned 8-bit, 0-255, raster order |
| Kernel | `[[0,-1,0],[-1,5,-1],[0,-1,0]]` (sharpen) |
| Coefficient width | signed 10-bit |
| Bias / shift | 0 / 0 |
| Accumulator width | signed 24-bit |
| Borders | zero-padded, output same W x H as input |
| Output | clamp(sum, 0, 255) |
| Clocking | single `clk`, no CDC, no FIFO |
| Stream rule | a pixel transfers only when `valid && ready` both true on the clock edge |
| Pipeline | fully combinational datapath is fine for today (no pipeline registers required) |
| Out of scope today | synthesis, STA, GLS, coverage, async FIFO, configurable coefficients |

## Interface (frozen — do not add/rename signals mid-day)

### Input stream
| Signal | Width | Meaning |
|---|---|---|
| `s_valid` | 1 | source presents a pixel |
| `s_ready` | 1 | accelerator can accept it |
| `s_pixel` | 8 | pixel value |
| `s_sof` | 1 | this is pixel (0,0) of the frame |
| `s_eol` | 1 | this is the last pixel in its row |
| `s_eof` | 1 | this is the last pixel in the frame |

### Output stream
| Signal | Width | Meaning |
|---|---|---|
| `m_valid` | 1 | accelerator presents a result |
| `m_ready` | 1 | sink accepts it |
| `m_pixel` | 8 | saturated convolution result |
| `m_sof` / `m_eol` / `m_eof` | 1 each | same meaning, output side |

**Golden rule:** a beat transfers only on a clock edge where `valid && ready`
are both 1. While `valid=1 && ready=0`, the data/flags must hold steady —
no changing `s_pixel` or `m_pixel` mid-stall.

## Ownership (from the 4-week spec, Section 19, scoped to today)

| Member | Owns | File(s) |
|---|---|---|
| A — Architecture | Frame controller, line buffers, 3x3 window | `rtl/frame_controller.sv`, `rtl/line_buffer.sv`, `rtl/window_gen.sv` |
| B — Datapath | MAC pipeline + saturation | `rtl/mac_pipeline.sv` |
| C — Verification | Golden model, test images, comparison | `golden_model/*.py` |
| D — Systems | Stream source/sink, testbench harness | `tb/*.sv` |

Integration point: `rtl/accelerator_top.sv` wires A's window output into B's
MAC pipeline, and is driven by D's testbench.
