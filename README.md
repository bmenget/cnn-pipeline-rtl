# Hardware CNN Pipeline
**Streaming convolution accelerator demonstrating dataflow-oriented RTL design, memory reuse, and pipelined compute**

Configurable 4×4 convolution pipeline operating on 1024×1024 image inputs with DRAM input/output, SRAM buffering, and pipelined MAC computation.

---

## Overview

This project implements a hardware convolutional neural network (CNN) pipeline designed to explore **dataflow-driven accelerator design** rather than software-level neural network modeling.

The primary goals of the design are:
- Sustaining high compute utilization through pipelining
- Minimizing external memory traffic via on-chip reuse
- Maintaining clear separation between datapath and control logic

This repository is intended for **technical review by hardware and systems engineers**, not as a deployable end-user application.

---

## What This Project Demonstrates

This project demonstrates the following concepts and skills:

- Hardware dataflow design for CNN-style workloads  
- Sliding-window reuse of input feature maps  
- SRAM scratchpad buffering to decouple DRAM latency from compute  
- Pipelined MAC-based convolution  
- RTL-level control sequencing for multi-stage pipelines  
- Verification of streaming hardware using module-level testbenches  

---

## High-Level Dataflow

At a high level, the accelerator operates as a streaming pipeline:

1. Input feature maps are read from DRAM in aligned bursts  
2. Data is staged into on-chip SRAM to enable reuse  
3. A sliding 4×4 window is constructed using shift-register-based buffering  
4. Window values are fed into a pipelined MAC array for convolution  
5. Results pass through activation and pooling stages  
6. Final outputs are written back to memory  

Once the pipeline is primed, the design is capable of producing continuous outputs without stalling on memory latency.

---

## Pipeline Stages

The design is organized into the following conceptual stages:

### Memory Ingress
Handles burst reads from DRAM and populates SRAM after undergoing a staging process.  
This stage isolates compute from variable external memory latency.

### Window Staging and Reuse
Constructs a 4×4 sliding window over the input feature map.  
Each input value is reused across multiple MAC operations, significantly reducing memory bandwidth requirements.

### Convolution (MAC Pipeline)
A pipelined multiply-accumulate datapath performs convolution across the window.  
Pipeline depth is chosen to balance throughput and timing closure.

### Memory Egress
Completed outputs are written back to memory using aligned access patterns.

---

## Key Architectural Decisions

### Sliding Window via Shift Registers
- **Options considered:** Re-reading from SRAM vs explicit window buffering  
- **Chosen approach:** Shift-register-based window staging  
- **Rationale:** Enables deterministic reuse and sustained throughput with minimal control complexity  

### SRAM as a Scratchpad Buffer
- **Options considered:** Direct DRAM streaming vs intermediate SRAM scratchpad  
- **Chosen approach:** SRAM scratchpad  
- **Rationale:** Decouples compute from DRAM latency and enables burst-aligned accesses  

### Fully Streaming Pipeline
- **Options considered:** Batch-style processing vs streaming  
- **Chosen approach:** Streaming pipeline after initial fill  
- **Rationale:** Maximizes hardware utilization and simplifies steady-state control  

---

## Control Strategy

The pipeline is coordinated by a centralized controller responsible for:
- Sequencing DRAM burst reads and writebacks  
- Managing SRAM read/write phases  
- Advancing the sliding window  
- Ensuring correct pipeline priming and draining  

Control logic is intentionally separated from the datapath to simplify verification and future extension.

---

## Verification and Testing

Correctness was validated using:
- Module-level RTL testbenches  
- Directed test cases for window staging and accumulation  
- Boundary-condition testing at image edges  
- Consistency checks on output feature maps  

Testing focused on validating **dataflow correctness and control sequencing** rather than ML accuracy metrics.

---

## Results and Current Status

- End-to-end convolution pipeline implemented and verified  
- Correct sliding-window behavior across full image dimensions  
- Sustained streaming operation after pipeline fill  
- Modular structure supports future extension (e.g., additional channels or kernels)

---

## Known Limitations

- Single input/output channel (no multi-channel accumulation)
- DRAM read/write speeds is the primary throughput bottleneck
- Fixed kernel size
- Intermediate register files are reliant on SRAM read/write sizes 

These limitations were accepted to keep the design analyzable and verifiable.

---
## Repository Structure
```markdown
├── Results – Timing and Cell reports from synthesization
├── Vivado-Testing – Module-level source code and tailored testbenches
├── projectFall2025.v3 – Provided project structure
├── dut_rtl – RTL scripts for all levels of pipelining
└── README.md

```
---

## Future Work

- Register file size minimization  
- Leaky ReLu and pooling implementation  
- Alternative DRAM ingress/egress handling

---

