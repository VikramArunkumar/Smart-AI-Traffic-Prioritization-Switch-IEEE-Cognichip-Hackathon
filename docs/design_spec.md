# Smart AI Traffic Prioritization Switch — Design Specification

**Project:** Smart-AI-Traffic-Prioritization-Switch
**Team:** CogniVik — Vikram Arunkumar (SJSU)
**Hackathon:** IEEE / Cognichip Hackathon 2026
**Version:** 1.0 — April 2026

---

## 1. Introduction

### 1.1 Purpose

This document is the complete hardware design specification for the **Smart AI Traffic
Prioritization Switch** — an FPGA-friendly, synthesizable SystemVerilog implementation
of a network switch that dynamically classifies and prioritizes packet traffic using
rule-based AI-inspired logic.

### 1.2 Problem Statement

Modern applications (video calls, gaming, AI inference, bulk file transfers) have
fundamentally different latency and throughput requirements. Static FIFO-based switches
treat all traffic equally, causing high latency for real-time applications and packet
loss during congestion. This design classifies traffic at ingress, routes it into
priority-differentiated queues, and schedules egress using Weighted Round Robin (WRR)
with starvation prevention.

### 1.3 Design Goals

| Goal | Target |
|---|---|
| Classification | Rule-based, single-cycle combinational |
| Scheduling | WRR 4:2:1 default, FPGA-synthesizable |
| Starvation prevention | Per-queue counter, configurable threshold |
| FIFO architecture | Synchronous FWFT, per-queue parameterized depth |
| Observability | Occupancy, drop counters, rate measurement, congestion level |
| Target platform | FPGA-friendly (Xilinx Artix-7, Spartan-7) |
| Verification | Self-checking SystemVerilog TB, 6 TCs, Verilator clean |

---

## 2. Feature Summary

### 2.1 Requirements Table

| REQ_ID | Title | Type | Acceptance Criteria |
|---|---|---|---|
| REQ_001 | Packet metadata ingestion | Functional | Accept valid/type/size/latency_sensitive each cycle |
| REQ_002 | 3-class priority classification | Functional | Correct HIGH/MED/LOW for all 8 type codes + ls override |
| REQ_003 | Per-priority FIFO buffering | Functional | Independent depth per queue; FWFT; occupancy exported |
| REQ_004 | WRR scheduling | Functional | Output ratio H:M:L >= 4:2:1 when all queues non-empty |
| REQ_005 | Starvation prevention | Functional | Queue waiting >= STARVE_THRESH cycles gets guaranteed service |
| REQ_006 | Tail-drop and drop counters | Functional | Drops tracked per-queue; cleared on reset |
| REQ_007 | Congestion monitoring | Observability | 4-level output based on fill thresholds |
| REQ_008 | Admission control | Functional | in_ready de-asserts on HIGH severe fill or pause_req |
| REQ_009 | Rate measurement | Observability | RX/TX packet counts per configurable window |
| REQ_010 | Synchronous reset | Functional | All FIFOs, counters, starvation state cleared on reset |
| REQ_011 | Synthesizability | Implementation | No latches, no async logic, 0 Verilator warnings |

### 2.2 Ambiguity Log

| Q_ID | Question | Impact | Chosen Default |
|---|---|---|---|
| Q_001 | FIFO depths same or per-queue? | Buffer utilization | Per-queue: H=32, M=16, L=8 |
| Q_002 | WRR weights fixed or runtime? | Complexity | Compile-time parameters |
| Q_003 | Starvation threshold per-queue or global? | Fairness | Global STARVE_THRESH |
| Q_004 | Drop policy: tail or head? | Burst behavior | Tail-drop (FPGA-friendly) |
| Q_005 | Backpressure: per-priority or global? | Upstream complexity | Global in_ready from control_logic |

---

## 3. Functional Description

### 3.1 Packet Metadata Format

Each packet is described by a 20-bit word stored in the FIFOs:

    [19:17]  pkt_type[2:0]         Traffic class code
    [16:1]   pkt_size[15:0]        Payload size in bytes
    [0]      latency_sensitive      Real-time override flag

### 3.2 Classification Rules (packet_classifier)

| Condition | Priority |
|---|---|
| latency_sensitive = 1 | HIGH (overrides type) |
| type[2:1] == 2'b00 (types 0,1) | HIGH (Video, Gaming) |
| type[2:1] == 2'b01 (types 2,3) | MEDIUM (VoIP, Streaming) |
| type[2] == 1'b1  (types 4-7) | LOW (File, Bulk, BG, Best-effort) |

Outputs: one-hot high_prio / med_prio / low_prio — directly gate FIFO write enables.

### 3.3 FIFO Buffering (sync_fifo)

- Architecture: Synchronous FWFT. rd_data driven combinationally from rd_ptr slot.
- Full/empty: extra pointer bit method (empty = pointers equal, full = MSB differ + lower equal).
- Occupancy: wr_ptr - rd_ptr (unsigned wrap).
- Drop: write gated by !full; excess packets silently dropped; drop_cnt increments.

### 3.4 WRR + Starvation Prevention (wrr_scheduler)

WRR credits loaded when rr_ptr enters a queue. Decremented on each served packet.
When credits reach 1 (last packet): advance rr_ptr, reload new queue's credit.
Work-conserving: empty rr_ptr queue is skipped without credit penalty.

Starvation counters increment every cycle a queue is non-empty but unserved.
When counter >= STARVE_THRESH: starvation boost fires for that queue.
Most-starved wins (highest counter, H > M > L tie-break).
Boost does NOT consume WRR credits and does NOT advance rr_ptr.
Counter resets on service OR when queue drains empty.

### 3.5 Control Logic (control_logic)

Congestion thresholds (% of FIFO depth):
  WARNING  >= 50%    CRITICAL >= 75%    SEVERE >= 87.5%

Admission: in_ready = ~pause_req AND NOT (HIGH_severe OR (MED_severe AND LOW_severe))
High-priority traffic still accepted even when MED/LOW are saturated.

Drop alert: latched flag on any drop counter increment. Cleared via drop_alert_clr.
Rate measurement: rx_pkt_rate / tx_pkt_rate updated every RATE_WINDOW cycles.

---

## 4. Interface Description

### 4.1 traffic_switch_top

| Signal | Dir | Width | Description |
|---|---|---|---|
| clock | in | 1 | System clock (rising-edge) |
| reset | in | 1 | Synchronous active-high reset |
| in_valid | in | 1 | Packet metadata valid this cycle |
| in_type | in | 3 | Traffic type code |
| in_size | in | 16 | Payload size bytes |
| in_latency_sensitive | in | 1 | Force HIGH priority override |
| out_valid | out | 1 | Output packet available |
| out_type | out | 3 | Egress packet type |
| out_size | out | 16 | Egress packet size |
| out_latency_sensitive | out | 1 | Egress latency flag |
| out_priority | out | 2 | 2'b10=HIGH 2'b01=MED 2'b00=LOW |
| out_ready | in | 1 | Downstream accepts this cycle |
| high_occupancy | out | clog2(H)+1 | HIGH FIFO fill |
| med_occupancy | out | clog2(M)+1 | MED FIFO fill |
| low_occupancy | out | clog2(L)+1 | LOW FIFO fill |
| high_drop_cnt | out | DROP_CNT_W | Cumulative HIGH drops |
| med_drop_cnt | out | DROP_CNT_W | Cumulative MED drops |
| low_drop_cnt | out | DROP_CNT_W | Cumulative LOW drops |
| starve_h / starve_m / starve_l | out | 1 each | Queue starvation flags |

### 4.2 control_logic additional ports

| Signal | Dir | Description |
|---|---|---|
| pause_req | in | Stall all ingress |
| drop_alert_clr | in | Pulse to clear drop alert latch |
| in_ready | out | Backpressure to upstream |
| congestion_lvl | out | 0=NORMAL 1=WARN 2=CRIT 3=SEVERE |
| high_watermark_h/m/l | out | Per-queue WARNING threshold crossed |
| drop_alert | out | Latched: drops detected since last clear |
| starvation_alert | out | Any queue currently starved |
| rx_pkt_rate | out | Ingress packets per last RATE_WINDOW |
| tx_pkt_rate | out | Egress packets per last RATE_WINDOW |

---

## 5. Parameterization Options

| Parameter | Module | Default | Description |
|---|---|---|---|
| FIFO_DEPTH_H | traffic_switch_top | 32 | HIGH queue depth (power of 2) |
| FIFO_DEPTH_M | traffic_switch_top | 16 | MED queue depth |
| FIFO_DEPTH_L | traffic_switch_top | 8 | LOW queue depth |
| DROP_CNT_W | traffic_switch_top | 16 | Drop counter width |
| WEIGHT_H | wrr_scheduler | 4 | WRR credits/round for HIGH |
| WEIGHT_M | wrr_scheduler | 2 | WRR credits/round for MED |
| WEIGHT_L | wrr_scheduler | 1 | WRR credits/round for LOW |
| STARVE_THRESH | wrr_scheduler | 256 | Starvation threshold in cycles |
| RATE_WINDOW | control_logic | 256 | Rate measurement window cycles |

---

## 6. Register and Counter Description

| Counter | Width | Reset | Description |
|---|---|---|---|
| high_drop_cnt | DROP_CNT_W | 0 | HIGH FIFO tail-drop accumulator |
| med_drop_cnt | DROP_CNT_W | 0 | MED FIFO tail-drop accumulator |
| low_drop_cnt | DROP_CNT_W | 0 | LOW FIFO tail-drop accumulator |
| high_occupancy | clog2(H)+1 | 0 | HIGH FIFO current fill |
| med_occupancy | clog2(M)+1 | 0 | MED FIFO current fill |
| low_occupancy | clog2(L)+1 | 0 | LOW FIFO current fill |
| starve_cnt_h/m/l | STARVE_W | 0 | Per-queue starvation counter (internal) |
| credit_h/m/l | 8 | WEIGHT | Per-queue WRR credit (internal) |
| rr_ptr | 2 | 0 | WRR pointer: 0=H 1=M 2=L (internal) |
| rx_pkt_rate | 16 | 0 | Ingress packet rate (last window) |
| tx_pkt_rate | 16 | 0 | Egress packet rate (last window) |

---

## 7. Design Guidelines

### 7.1 FPGA Synthesis Notes

- All registers are synchronous active-high reset — compatible with FPGA GSR primitives
- sync_fifo infers Block RAM for depth >= 512; distributed RAM/LUT for smaller depths
- $clog2 evaluated at elaboration time — supported by Vivado, Quartus, Yosys
- No floating-point, no division, no complex generates
- Occupancy counter widths auto-sized per queue via $clog2

### 7.2 Timing Considerations

- Critical path: wrr_scheduler starvation counter comparisons + srv_ptr mux
- For >200 MHz target: register srv_ptr (adds 1-cycle output latency)
- control_logic is non-critical-path and will not limit Fmax

### 7.3 FIFO Depth Constraints

- Must be power of 2 (pointer-wrap full/empty detection)
- Minimum depth: 2 (not recommended in practice)
- Recommended: H>=32 M>=16 L>=8 for latency-sensitive applications

### 7.4 WRR Weight Guidelines

| Scenario | WEIGHT_H | WEIGHT_M | WEIGHT_L |
|---|---|---|---|
| Real-time video dominant | 8 | 2 | 1 |
| Balanced (default) | 4 | 2 | 1 |
| Equal throughput | 1 | 1 | 1 |

### 7.5 Starvation Threshold at 100 MHz

| STARVE_THRESH | Latency bound |
|---|---|
| 256 | 2.56 us |
| 1024 | 10.24 us |
| 65535 | 655 us |

---

## 8. Timing Diagrams

### 8.1 Normal WRR Operation

```wavedrom
{
  "comment": [
    "WRR H=4 M=2 L=1, all queues full, out_ready=1.",
    "Each p. = 1 cycle. Observe H served 4x before M, M 2x before L."
  ],
  "signal": [
    { "name": "clk",          "wave": "p.p.p.p.p.p.p.", "period": 2 },
    { "name": "reset",        "wave": "1...0........." },
    { "name": "out_ready",    "wave": "0...1........." },
    { "name": "out_valid",    "wave": "0...1........." },
    { "name": "out_priority", "wave": "0...2.2.2.2.3.", "data":["H","H","H","H","M"] },
    { "name": "starve_h",     "wave": "0............." },
    { "name": "starve_l",     "wave": "0............." }
  ],
  "config": { "hscale": 2 }
}
```

### 8.2 Starvation Prevention Scenario

```wavedrom
{
  "comment": [
    "LOW queue non-empty, out_ready=0 for STARVE_THRESH cycles.",
    "starve_l asserts. On out_ready release, LOW served first (boost)."
  ],
  "signal": [
    { "name": "clk",           "wave": "p.p.p.p.p.p.p.", "period": 2 },
    { "name": "reset",         "wave": "1...0........." },
    { "name": "low_empty",     "wave": "1.....0......." },
    { "name": "out_ready",     "wave": "0.........1..." },
    { "name": "starve_l",      "wave": "0.........1..." },
    { "name": "out_valid",     "wave": "0.........1..." },
    { "name": "out_priority",  "wave": "0.........2...", "data":["LOW boost"] },
    { "name": "congestion_lvl","wave": "0.....2.......", "data":["WARN"] }
  ],
  "config": { "hscale": 2 }
}
```

---

## 9. Verification Summary

### 9.1 Test Environment

| Parameter | Value |
|---|---|
| Simulator | Verilator 5.042 |
| FIFO depths (TB) | H=8 M=4 L=4 |
| STARVE_THRESH (TB) | 32 |
| Clock period | 10 ns |

### 9.2 Test Results

| Test Case | Description | Result |
|---|---|---|
| TC1 | Classification: all 8 types + latency_sensitive override (10 packets) | PASSED |
| TC2 | WRR ratio: H=8 M=4 L=4 counts satisfy H>=4 M>=2 L>=1 | PASSED |
| TC3 | Starvation: starve_l asserts after 37 cycles; packet 0xDEAD served | PASSED |
| TC4 | Drop counters: low_drop_cnt=3 after 3-packet FIFO overflow | PASSED |
| TC5 | Backpressure: 3 packets preserved after 8-cycle out_ready=0 hold | PASSED |
| TC6 | Reset: out_valid=0, counters=0, starve flags=0 after reset | PASSED |

Compile warnings: 0   Simulation errors: 0
Waveform: simulation_results/dumpfile.fst

---

## 10. Repository Structure

```
Smart-AI-Traffic-Prioritization-Switch/
+-  rtl/
|   +-  packet_classifier.sv     Combinational priority classifier
|   +-  sync_fifo.sv             Parameterized FWFT synchronous FIFO
|   +-  wrr_scheduler.sv         WRR + starvation prevention scheduler
|   +-  traffic_switch_top.sv    Top-level integration
|   +-  control_logic.sv         Congestion management + admission control
+-  sim/
|   +-  tb_traffic_switch_top.sv Self-checking testbench (6 TCs)
+-  docs/
|   +-  block_diagram.png        System architecture diagram
|   +-  design_spec.md           This document
+-  simulation_results/          Waveform dumps (*.fst)
+-  DEPS.yml                     Simulation dependency manifest
+-  README.md
```

---

*Document generated with Cognichip Co-Designer — April 2026*