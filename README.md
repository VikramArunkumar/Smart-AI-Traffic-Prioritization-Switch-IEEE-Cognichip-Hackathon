# Smart-AI-Traffic-Prioritization-Switch-IEEE-Cognichip-Hackathon

**Academic Year:** 2025-2026 Spring Semester  
**Project Duration:** April 17 - 19, 2026

## Team Information

**Project Lead:** Vikram Arunkumar 
📧 Email: vikram.arunkumar@sjsu.edu 
💼 LinkedIn: https://www.linkedin.com/in/sdlc-software-engineer/
📱 Team Size: 1 member
🏢 Team Name: CogniVik


**Faculty Advisor:** IEEE/Cognichip 
📧 Email: [ieee@sjsu.edu]  
🏢 Office: [ENGR, 376]

## Team Members

| Name               | Role                     | School | Email |
|--------------------|--------------------------|-------|--------|
| [Vikram Arunkumar] | Chief Architect | SJSU | vikram.arunkumar@sjsu.edu |

## Project Statement & Project Goal

### The Problem
What hardware design challenge are you solving? What gap or limitation does your project address?

Network switches today treat most traffic similarly or rely on static rules. However, modern applications like video calls, gaming, and AI workloads have very different requirements.
This leads to high latency in real-time applications, packet loss during congestion, and poor overall user experience. A smarter system is needed to dynamically prioritize important traffic.

### Why It Matters
What would be the real-world impact of solving this problem?


### Project Goal
What did you set out to build or demonstrate? State your primary objective clearly.
In this project, I will design a simplified AI-powered network switch simulator that dynamically prioritizes traffic based on its importance. The system will classify traffic (video, gaming, file transfer), assign priority using a lightweight AI model, and route packets through priority-based queues. 
The switch will simulate congestion using limited buffers and demonstrate how AI reduces latency and packet loss. The system design overview would be: AI-driven Traffic Classification → Priority Assignment → Multi-Queue Scheduler → Packet Transmission.  This would include a high priority queue (video, real-time), a medium priority queue, and a low priority queue (bulk data). 
The implementation plan would be a python-based traffic simulator, then a simple ML model (decision tree or rules), then a queue-based scheduling system, and finally a visualization using Matplotlib or Streamlit.  Some stretch goals include reinforcement learning for adaptive scheduling, a real-time dashboard, and a comparison with FIFO scheduling.  

### Success Criteria
How would you know if your project succeeded? (e.g., timing closure, functional simulation, verified logic)

## Design Methodology

Design Approach
Describe your overall methodology: top-down, iterative, constraint-driven, etc.
AI-Assisted Workflow
How did you use Cognichip? What tasks did you delegate to AI vs. handle manually?
Iteration Process
How many design iterations did you go through? What changed between iterations?
Constraints & Tradeoffs
What were your primary design constraints (area, power, timing)? What tradeoffs did you make?



## Architechture & RTL Description
High-Level Architecture
Describe the major blocks/modules in your design and how they connect.
RTL Implementation
What language(s) did you use (Verilog, SystemVerilog, VHDL)? How many modules/files?
Key Design Decisions
What architectural choices had the most impact on your results?
Insert Diagram
[Paste your block diagram or architecture figure here]


## Tools Used
Cognichip (AI Co-designer)
Primary AI-assisted RTL generation, timing analysis, and design feedback
EDA / Simulation Tools
[e.g. Vivado, ModelSim, Cadence Xcelium, VCS — list what you used]
Synthesis & P&R
[e.g. Yosys, OpenROAD, Synopsys Design Compiler — if applicable]
Version Control & Collaboration
[e.g. GitHub, GitLab — include repo link if available]


**Project Stats:**

Lines of RTL Generated
[e.g. 197 lines of Verilog / N/A if not tracked]
Lines of Testbench Generated
[e.g. 540 lines / N/A if not tracked]
Tokens Used (approx.)
[e.g. ~150K tokens with Cognichip / N/A if not tracked]
Duration of Project
[e.g. 3 weeks / 21 days]
Team Size
[e.g. 2 members]
Target FPGA / ASIC Process
[e.g. Xilinx Artix-7 on Basys 3   OR   28nm CMOS, 1.5 GHz   OR   SkyWater 130nm PDK]

## Key Acheievements & Results

Key Achievements
[Describe the top 2–3 things your project achieved — e.g. timing closure, verified logic, novel architecture]
Simulation Results
[Summarize your simulation outcomes: did it pass functional tests? What coverage was achieved?]
✅ Simulation Results — TEST PASSED
Test Case	Result	Key Evidence
TC1 Classification	✅ PASSED	All 10 packets matched: types 0–7 + 2 latency_sensitive overrides
TC2 WRR Ratio	✅ PASSED	H=8, M=4, L=4 — satisfies H≥4, M≥2, L≥1 ratio
TC3 Starvation	✅ PASSED	starve_l asserted at cycle 37 (STARVE=32+5 cycles), packet 0xDEAD correctly served
TC4 Drop Counters	✅ PASSED	low_drop_cnt=3 after overflowing FIFO_L=4 by 3 packets
TC5 Backpressure	✅ PASSED	All 3 packets preserved intact after 8-cycle hold
TC6 Reset	✅ PASSED	out_valid=0, all counters cleared, starve flags cleared after reset


Waveform / Output Screenshot
[Insert a waveform screenshot or simulation output image here]
Performance Summary
[e.g. Max frequency: 125 MHz, Power: 18 mW, Area: 0.42 mm² — include what's relevant]



## Challlenges & Future Work

Challenges Encountered
What were the hardest problems you faced? (technical, tooling, time constraints)
How You Overcame Them
What strategies or workarounds did you use? What did you learn?
What You Would Do Differently
Hindsight reflections — any architectural or workflow changes you'd make?
Future Work
What would you build next? What improvements or extensions are planned (or dreamed of)?






## Repository Structure

```
Smart-AI-Traffic-Prioritization-Switch-IEEE-Cognichip-Hackathon/
├── README.md
├── requirements.txt
├── .gitignore
├── LICENSE
└── [additional_folder]/
```

## Quick Start Guide

### Prerequisites
- Python 3.8 or higher
- Git
- [Additional requirement 1]
- [Additional requirement 2]

### Installation Guide

1. **Clone the repository:**
   ```bash
   git clone https://github.com/VikramArunkumar/Smart-AI-Traffic-Prioritization-Switch-IEEE-Cognichip-Hackathon.git
   cd Smart-AI-Traffic-Prioritization-Switch-IEEE-Cognichip-Hackathon
   ```

2. **Create virtual environment:**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **[Additional setup step]:**
   ```bash
   [command or instruction]
   ```

## Technology Stack

- **Programming Language:** [Python]
- **ML/AI Libraries:** [LangChain, OpenAI]
- **Development:** [VisualCode, PyCharm]
- **Version Control:** [Git & GitHub]
- **[Category]:** [Tools/Technologies]
- **Database:** [Database Technology]
- **Deployment:** [Deployment Platform/Tools]

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Acknowledgment 1]
- [Acknowledgment 2]
- [Acknowledgment 3]

---

**Last Updated:** [3/1/26]  
**Next Review:** [3/15/26]

---