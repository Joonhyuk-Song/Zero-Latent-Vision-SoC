Zero-Latent Vision SoC
I. LARGER THE BETTER??
Low-latency Computer Vision algorithm currently runs on a GPU. Although GPUs offer high flexibility and computing power, there are a few problems when deploying AI models on edge devices with CPU and GPU architectures. 
Memory Bandwidth Bound
Despite GPUs offering massive compute throughput, real‑world latency is often limited by memory bandwidth(See Figure 1), especially when the workload isn’t very math‑intensive. For example, large language models (e.g., ChatGPT) spend most of their inference time in attention layers, which are computationally intensive and keep the GPU’s ALUs busy. In contrast, small CNN models tend to be bottlenecked by data movement: shuttling weights and activations between RAM, VRAM, and the GPU(See Figure 2). In these cases, memory transfers dominate the latency rather than computation.
GPU Overkill
GPUs can be overkill for edge devices. Running inference on a CPU would overload it, therefore not preferred. Meanwhile, edge devices face strict constraints on battery life, thermal limits, physical area, and cost. A general‑purpose GPU consumes too much power, generates too much heat, and occupies too much silicon for many embedded applications. Ultimately, there’s a tradeoff between the flexibility of GPU‑based acceleration and the efficiency required for real‑world edge deployments.

Fig. 1. Model performance. 

Fig. 2. CPU and GPU interaction.
We address this challenge by integrating the image‑sensor IC and the NPU IC into a single chip(a.k.a Zero‑Latent Vision IC). This unified architecture directly processes the 28×28 analog image‑sensor output, performs on‑chip digitization using multiple single-slope ADCs, and immediately feeds the data to an NPU implementing a fixed‑weight MNIST FNN(see Figure 3). By placing sensing, conversion, and inference in a single chip, the system functions as a sensor‑proximal edge‑AI engine with minimal power consumption and near‑zero data‑transfer latency.
This approach offloads computer‑vision tasks from the CPU and GPU, allowing them to focus on more computationally demanding workloads. The architecture is also inherently scalable: higher‑resolution sensors and more advanced models (e.g., YOLO‑based object detection) can be supported with additional design time and silicon resources.
For this hackathon, however, we have only three days, so we implemented a simplified version of the concept to demonstrate feasibility within the time constraints.


Fig. 3. High-level schematic.
II. Technical Requirements. 
The chip will be developed using the Cognichip AI platform, which automates the physical chip design process. Our primary responsibility is to create RTL-level Verilog modules that define the system architecture, including multiple single-slope column ADCs, a memory buffer, an NPU, and the top‑level control unit. Each module, as well as the fully integrated design, will be simulated and verified using Vivado Verilog. For the NPU block, we will design the FNN MNIST from scratch 
III. Roles

Module
Description
Tools
Name
Input,  SRAM
Find out the testbench for the input that comes from the image sensor(28x28)


Verilog
Dao
ADC
We will use the built-in ADC. Focus on implementing ADC in Verilog
https://www.youtube.com/watch?v=sHpjO-miYLI
Verilog
Quy
NPU
FNN MNIST Verilog
Verilog
Joon
Control
FSM
Verilog
Together


IV. Better to know
What is deep learning? https://www.youtube.com/watch?v=aircAruvnKk
What is CNN? https://www.youtube.com/watch?v=pj9-rr1wDhM
What are ADC and DAC? https://www.youtube.com/watch?v=HicZcgdGxZY





V. Project Timeline 
Phase
Description
Target Completion
Phase I
Study and write each module and test. 
by April 12
Phase II
Write the FSM control, integrate the modules, and run the test bench. 
by April 16




