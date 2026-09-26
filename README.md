# Honours Lab 316

A centralized repository for the **Digital VLSI, RTL Design, SoC, FPGA, and Hardware IP development work** carried out as part of Honours Lab 316.

The repository contains the ongoing **Honours Project – Packet Buffering** together with additional hardware IP and RTL projects developed during the lab, including **I2C, AXI-Lite UART, and AES**.

---

# 1. Current Work – Packet Buffering

## 1.1 Overview

The primary ongoing project in this repository is the design and development of a **hardware-based Packet Buffering architecture for an SoC-oriented system**.

Packet buffering is used when data packets arrive at a hardware block faster than they can be processed or forwarded. Instead of losing data when the downstream block is temporarily unavailable, the incoming packets are stored in a buffer and are transmitted or processed when the receiving side is ready.

This makes packet buffering an important part of communication-oriented SoCs, networking hardware, bus systems, and other digital systems where data can arrive in bursts or where producer and consumer modules may operate at different rates.

The project is being developed from an RTL-design perspective, with emphasis on:

- Digital hardware architecture
- Packet storage and forwarding
- Buffer management
- Read/write control
- Flow control
- Handshaking
- Full and empty handling
- Data integrity
- RTL verification
- Synthesis
- FPGA-oriented implementation

---

## 1.2 Why Packet Buffering is Required

Consider a simple producer-consumer system:

```text
+----------------+       Data Packets       +----------------+
|                | -----------------------> |                |
|  Packet        |                          |  Packet        |
|  Producer      |                          |  Consumer      |
|                | <----------------------- |                |
+----------------+       Flow Control       +----------------+
```

The producer and consumer do not necessarily operate at the same rate.

For example:

```text
Producer Rate  >  Consumer Rate
        |
        v
+------------------+
| Incoming Packets  |
+------------------+
        |
        v
+------------------+
|  PACKET BUFFER   |
|                  |
| P0               |
| P1               |
| P2               |
| P3               |
| ...              |
+------------------+
        |
        v
+------------------+
| Packet Consumer  |
+------------------+
```

The buffer temporarily absorbs the difference between the incoming and outgoing data rates.

Without sufficient buffering, packets may be dropped when the consumer is unable to accept data.

---

# 2. Packet Buffering – High-Level Architecture

The current project is being developed around the following high-level concept:

```text
                    PACKET BUFFERING SYSTEM

       Input / Producer
              |
              | Packet Data
              | Valid / Write
              v
     +----------------------+
     |                      |
     |   Input / Write      |
     |     Control          |
     |                      |
     +----------+-----------+
                |
                v
       +--------------------+
       |                    |
       |    PACKET BUFFER   |
       |                    |
       |  +--------------+  |
       |  | Packet Data  |  |
       |  | Storage      |  |
       |  +--------------+  |
       |                    |
       |  Buffer Management |
       |  Read / Write Ctrl |
       |  Occupancy Status  |
       +----------+---------+
                  |
                  v
       +--------------------+
       |                    |
       |  Output / Read     |
       |     Control        |
       |                    |
       +----------+---------+
                  |
                  | Packet Data
                  | Valid / Ready
                  v
          Output / Consumer
```

The exact internal architecture is being refined as the project progresses. The diagram above represents the conceptual data path and control flow rather than a fixed final RTL implementation.

---

# 3. Packet Buffering – Basic Operation

The operation can be understood in four stages.

## Stage 1 – Packet Arrival

A packet arrives from the input/producer interface.

```text
Producer
   |
   | Packet
   v
[Input Interface]
```

The input-side control logic determines whether the buffer can accept the packet.

---

## Stage 2 – Packet Storage

If the buffer has available space, the packet is written into the storage structure.

```text
Packet
  |
  v
+-------------------+
|   Packet Buffer   |
|-------------------|
| Packet 0          |
| Packet 1          |
| Packet 2          |
| Packet 3          |
| ...               |
+-------------------+
```

The write-side control keeps track of where the next packet/data item should be stored.

---

## Stage 3 – Buffer Management

The control logic maintains the state of the buffer.

Important conditions include:

```text
                +----------------+
                | Buffer Status  |
                +----------------+
                  /      |      \
                 /       |       \
                v        v        v
             EMPTY    PARTIAL    FULL
```

The buffer must correctly handle:

- Empty condition
- Full condition
- Valid write
- Valid read
- Simultaneous read/write
- Available space
- Available data
- Flow-control conditions

---

## Stage 4 – Packet Forwarding

When the downstream consumer is ready, a stored packet is read from the buffer and forwarded.

```text
+-------------------+
|   Packet Buffer   |
+---------+---------+
          |
          | Stored Packet
          v
+-------------------+
| Output Interface  |
+---------+---------+
          |
          v
      Consumer
```

This allows the producer and consumer to operate without requiring them to process every packet at exactly the same time.

---

# 4. Packet Buffering – Flow Control

Flow control is an important part of the project.

A typical conceptual handshake can be represented as:

```text
Producer                         Buffer / Consumer
   |                                   |
   | -------- VALID -----------------> |
   |                                   |
   | <--------- READY ---------------- |
   |                                   |
   |       Data Transfer               |
   |                                   |
```

A transfer takes place when the required handshake conditions are satisfied.

The buffering logic therefore has to ensure that:

- Data is accepted only when storage is available.
- Data is not overwritten before it is consumed.
- Data is not read when no valid data is available.
- Backpressure can be propagated when required.
- Packet ordering is maintained.
- Valid data is forwarded to the consumer.

---

# 5. Packet Buffering – Full and Empty Conditions

Two fundamental buffer conditions are:

## Empty

The buffer contains no valid data.

```text
+-------------------+
|   PACKET BUFFER   |
|-------------------|
|                   |
|       EMPTY       |
|                   |
+-------------------+

        READ
         |
         X
     No valid data
```

A read operation should not remove or forward invalid data when the buffer is empty.

---

## Full

The buffer has no remaining storage space.

```text
+-------------------+
|   PACKET BUFFER   |
|-------------------|
| Packet 0          |
| Packet 1          |
| Packet 2          |
| Packet 3          |
| Packet ...        |
| Packet N          |
+-------------------+

          FULL
```

When the buffer is full, additional incoming data must be controlled so that existing data is not overwritten.

The exact full/empty implementation depends on the final buffer architecture selected for the project.

---

# 6. Packet Buffering – Important Design Requirements

The project is being developed with the following design requirements in mind.

### 6.1 Data Integrity

Every accepted packet must be stored correctly and must be retrieved without corruption.

### 6.2 Packet Ordering

Packets should be forwarded in the correct order unless the final architecture explicitly defines another scheduling mechanism.

```text
Input:

P0 -> P1 -> P2 -> P3

Output:

P0 -> P1 -> P2 -> P3
```

### 6.3 Overflow Protection

The design must prevent writes from corrupting valid data when the buffer is full.

### 6.4 Underflow Protection

The design must prevent invalid reads when the buffer contains no valid packet/data.

### 6.5 Flow Control

The design must correctly indicate when it can accept new data and when the downstream side can receive data.

### 6.6 Simultaneous Operations

The design should correctly handle cases where reading and writing occur during the same clock cycle, according to the final architecture and interface specification.

### 6.7 Synthesizable RTL

The implementation is intended to use synthesizable Verilog/SystemVerilog RTL suitable for FPGA and hardware implementation.

---

# 7. Packet Buffering – Verification

Verification is an important part of the project.

The verification process is intended to check:

- Reset behavior
- Packet write operation
- Packet read operation
- Buffer empty behavior
- Buffer full behavior
- Continuous packet transfers
- Back-to-back packets
- Simultaneous read/write operations
- Flow-control behavior
- Packet ordering
- Data integrity
- Boundary and corner cases

A conceptual verification flow is:

```text
              +------------------+
              |   RTL DUT        |
              | Packet Buffer    |
              +--------+---------+
                       |
                       |
              +--------v---------+
              |    Testbench     |
              +--------+---------+
                       |
          +------------+------------+
          |            |            |
          v            v            v
       Stimulus     Monitor      Checker
          |            |            |
          +------------+------------+
                       |
                       v
                Expected vs Actual
                       |
                       v
                  PASS / FAIL
```

As development progresses, the verification environment will be expanded to cover functional and corner-case behavior.

---

# 8. Packet Buffering – Development Flow

The project follows a standard RTL development flow:

```text
Specification
      |
      v
Architecture Definition
      |
      v
RTL Design
      |
      v
Testbench Development
      |
      v
Simulation
      |
      v
Functional Verification
      |
      v
Synthesis
      |
      v
FPGA Implementation
      |
      v
Hardware Evaluation
```

The final stages depend on the project implementation and available hardware resources.

---

# 9. Additional Projects Developed in Honours Lab

In addition to the current Packet Buffering project, this repository contains other hardware design projects and IP development work.

---

# 9.1 AXI-Lite UART IP Core

The repository contains an **AXI4-Lite based UART IP core** developed as a reusable SoC peripheral.

The main objective of this work is to understand the implementation of a memory-mapped peripheral and its connection to an SoC through the AXI4-Lite interface.

## Main Components

```text
                 AXI4-Lite
                    |
                    v
          +-------------------+
          |   AXI-Lite Slave  |
          |    Interface      |
          +---------+---------+
                    |
                    v
          +-------------------+
          |  UART Registers   |
          +---------+---------+
                    |
                    v
          +-------------------+
          |   UART Control    |
          +----+---------+----+
               |         |
               v         v
             UART TX    UART RX
```

### Areas Covered

- AXI4-Lite slave interface
- Memory-mapped registers
- UART transmitter
- UART receiver
- Baud-rate related logic
- Control and status registers
- RTL simulation
- IP development and organization

### Repository Path

```text
Honours_lab_316/
└── axi-lite-uart-ipcore/
    ├── documentation/
    ├── scripts/
    ├── src/
    ├── LICENSE
    ├── Makefile
    ├── README.md
    └── project.config
```

---

# 9.2 AES Hardware Core

An **AES hardware encryption core** has also been developed as part of the Honours Lab work.

The AES project includes RTL, testbench, simulation, supporting data, documentation, and synthesis-related files.

## High-Level Architecture

```text
                  AXI Interface
                       |
                       v
              +------------------+
              |   AES Registers  |
              +--------+---------+
                       |
                       v
              +------------------+
              |   AES Control    |
              +--------+---------+
                       |
                       v
              +------------------+
              |   AES Core       |
              |                  |
              |  AES Round Logic |
              |  S-Box           |
              |  Key Expansion   |
              +--------+---------+
                       |
                       v
                Ciphertext
```

### Main Components

- AES encryption core
- AES key expansion
- AES S-Box
- AES register set
- AXI interface
- RTL testbench
- Simulation environment
- Supporting data
- Synthesis-related files

### Repository Path

```text
Honours_lab_316/
└── aes_core-master/
    ├── bench/verilog/
    ├── data/
    ├── doc/
    ├── rtl/verilog/
    ├── sim/rtl_sim/
    ├── syn/bin/
    ├── aes_core.core
    ├── novas.rc
    └── vim_session.vim
```

---

# 9.3 I2C IP

An **I2C hardware IP** is another project developed as part of Honours Lab.

The project focuses on RTL implementation of the I2C communication interface and development of reusable digital hardware for communication with I2C-compatible peripherals.

## High-Level Concept

```text
                 SoC / Controller
                       |
                       v
              +------------------+
              |     I2C IP       |
              |------------------|
              | Control Logic    |
              | Protocol Logic   |
              | Data Registers   |
              +--------+---------+
                       |
                 +-----+-----+
                 |           |
                SDA         SCL
                 |           |
                 +-----+-----+
                       |
                       v
                I2C Peripheral
```

### Development Areas

- I2C protocol
- RTL design
- Control logic
- Serial data transfer
- Clock/control generation
- Peripheral communication
- Simulation and verification
- Hardware IP development

### Repository Path

```text
Honours_lab_316/
└── I2C/
```

The internal structure of the I2C project is maintained within its dedicated directory.

---

# 10. Complete Repository Organization

The current repository is organized as follows:

```text
Honours_lab_316/
│
├── Honours-Project-Packet-Buffering/
│   │
│   └── Current Honours Project
│       └── Packet Buffering
│
├── I2C/
│   │
│   └── I2C Hardware IP
│
├── aes_core-master/
│   │
│   ├── bench/verilog/
│   ├── data/
│   ├── doc/
│   ├── rtl/verilog/
│   ├── sim/rtl_sim/
│   ├── syn/bin/
│   ├── aes_core.core
│   ├── novas.rc
│   └── vim_session.vim
│
├── axi-lite-uart-ipcore/
│   │
│   ├── documentation/
│   ├── scripts/
│   ├── src/
│   ├── LICENSE
│   ├── Makefile
│   ├── README.md
│   └── project.config
│
├── aes_core.core
│
└── README.md
```

The repository is intentionally organized so that each major project has its own directory while all work remains under a single Honours Lab repository.

---

# 11. Project Organization Philosophy

The repository follows a modular hardware-development structure.

```text
                    Honours Lab 316
                          |
          +---------------+---------------+
          |               |               |
          v               v               v
   Current Project   Hardware IPs    Additional RTL
          |               |               |
          v               v               v
 Packet Buffering     UART / I2C       AES
          |
          v
    SoC / RTL Design
```

Each project can be developed independently and can later be integrated into larger SoC or FPGA systems.

This organization also makes it easier to:

- Maintain independent RTL projects.
- Reuse developed IPs.
- Maintain project-specific documentation.
- Maintain separate simulation environments.
- Develop and verify IPs independently.
- Integrate multiple IPs into a larger SoC.
- Track the progression of Honours Lab work.

---

# 12. Technologies and Tools

## Hardware Description Languages

- Verilog
- SystemVerilog

## Digital Design

- RTL Design
- Combinational Logic
- Sequential Logic
- FSM Design
- Datapath Design
- FIFO Architecture
- Buffer Architecture
- Pipelining
- Flow Control
- Handshaking
- SoC Architecture
- Hardware IP Design

## SoC / Bus Interfaces

- AXI
- AXI4-Lite
- Memory-Mapped Interfaces
- Peripheral IP Integration
- SoC Interconnect Concepts

## Communication Interfaces

- UART
- I2C

## FPGA / EDA

- Xilinx / AMD Vivado
- RTL Simulation
- Synthesis
- FPGA Implementation
- Linux-based EDA workflow

## Development Tools

- Linux
- Git
- GitHub
- Make
- Vim / GVim

## Verification

- RTL Testbenches
- Functional Simulation
- Directed Testing
- Corner-Case Testing
- Hardware IP Verification
- Simulation Debugging

---

# 13. Overall RTL / VLSI Development Flow

The projects in this repository are developed with the following general hardware-design methodology:

```text
+----------------------+
|  System Requirement  |
+----------+-----------+
           |
           v
+----------------------+
| Architecture Design |
+----------+-----------+
           |
           v
+----------------------+
|     RTL Coding      |
|  Verilog/SystemVerilog
+----------+-----------+
           |
           v
+----------------------+
| Testbench Development|
+----------+-----------+
           |
           v
+----------------------+
|      Simulation      |
+----------+-----------+
           |
           v
+----------------------+
| Functional Verification|
+----------+-----------+
           |
           v
+----------------------+
|      Synthesis       |
+----------+-----------+
           |
           v
+----------------------+
| FPGA Implementation  |
+----------+-----------+
           |
           v
+----------------------+
| Hardware Evaluation  |
+----------------------+
```

---

# 14. Project Status

| Project | Status |
|---|---|
| Packet Buffering | 🚧 In Progress |
| I2C IP | 🔄 Under Development |
| AXI-Lite UART IP | ✅ Developed |
| AES Hardware Core | ✅ Developed |
| RTL Verification | 🔄 Ongoing |
| FPGA Implementation | 🔄 Project Dependent |

---

# 15. Current Development Direction

The primary development effort is currently focused on the **Packet Buffering Honours Project**.

The upcoming work includes:

- Finalizing the packet buffering architecture.
- Completing the RTL implementation.
- Refining buffer management logic.
- Implementing robust flow-control mechanisms.
- Handling full, empty, and boundary conditions.
- Testing continuous and burst packet traffic.
- Developing a comprehensive verification environment.
- Performing functional and corner-case verification.
- Running synthesis and analyzing hardware resources.
- Implementing the design on FPGA where applicable.
- Evaluating performance and resource utilization.
- Documenting the final architecture and results.

The additional UART, I2C, and AES projects provide supporting experience in reusable IP design, SoC interfaces, communication protocols, RTL implementation, and hardware verification.

---

# 16. Learning and Technical Focus

The overall technical focus of the Honours Lab work is:

```text
Digital Logic
     |
     v
RTL Design
     |
     v
Hardware IP Development
     |
     v
SoC Interfaces
     |
     v
Verification
     |
     v
Synthesis
     |
     v
FPGA Implementation
```

The work is primarily oriented toward **front-end Digital VLSI and digital hardware design**.

---

# 17. Summary

Honours Lab 316 provides practical experience in designing and developing digital hardware systems from architecture to RTL and verification.

The repository currently brings together:

- **Packet Buffering** – current primary Honours Project
- **I2C IP** – digital communication IP development
- **AXI-Lite UART IP** – memory-mapped UART peripheral
- **AES Hardware Core** – cryptographic hardware implementation

The central development focus is:

> **Digital VLSI → RTL Design → Hardware IP → SoC Integration → Verification → FPGA Implementation**

This repository will be continuously updated as the Packet Buffering project and other hardware-development activities progress.

---

# 18. Author

**Sai Charan**

Electronics & Communication Engineering  
Vasavi College of Engineering

**Technical Focus:**

- Digital VLSI
- RTL Design
- SoC Architecture
- Hardware IP Development
- FPGA Design
- Verilog / SystemVerilog
- Digital Hardware Verification

---

## Note

This repository contains academic, research-oriented, and project-development work carried out as part of **Honours Lab 316**.

Individual project directories may contain their own README files, source code, simulation environments, scripts, documentation, and project-specific instructions.
