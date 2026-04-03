import numpy as np
import tensorflow as tf
import os
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

class FPGA_Quantizer:
    def __init__(self, model_path):
        # 1. Load Model and MNIST Data
        self.model = tf.keras.models.load_model(model_path)
        (_, _), (x_test_raw, self.y_test) = tf.keras.datasets.mnist.load_data()
        
        # Prepare data: Raw for FPGA simulation, Normalized for Keras evaluation
        self.x_test_flat = x_test_raw.reshape(-1, 784)
        self.x_test_norm = self.x_test_flat / 255.0
        
        self.sweep_results = []
        self.best_params = None

    def simulate_fpga_inference(self, weight_shift, relu_shift):
        """Hardware-accurate simulation of the FPGA data path."""
        # Extract weights/biases
        w1_f, b1_f = self.model.layers[0].get_weights()
        w2_f, b2_f = self.model.layers[1].get_weights()

        # Step 1: Quantization (Weight S0.7, Bias S8.7)
        qW1 = np.clip(np.round(w1_f * 127), -128, 127).astype(np.int32)
        qW2 = np.clip(np.round(w2_f * 127), -128, 127).astype(np.int32)
        qb1 = np.clip(np.round(b1_f * 128), -32768, 32767).astype(np.int32)
        qb2 = np.clip(np.round(b2_f * 128), -32768, 32767).astype(np.int32)

        # Step 2: Hidden Layer MAC -> Shift -> ReLU saturation
        z1 = np.dot(self.x_test_flat.astype(np.int32), qW1) + qb1
        z1_shifted = z1 >> relu_shift
        a1 = np.clip(z1_shifted, 0, 255).astype(np.uint8)

        # Step 3: Output Layer MAC -> Final Shift
        z2 = np.dot(a1.astype(np.int32), qW2) + qb2
        z2_shifted = z2 >> weight_shift
        
        preds = np.argmax(z2_shifted, axis=1)
        return preds, (qW1, qb1, qW2, qb2)

    def run_sweep(self, w_shifts=[7, 8, 9], r_shifts=[7, 8, 9, 10, 11, 12]):
        """Iterates through shift combinations to find the best hardware config."""
        keras_acc = self.model.evaluate(self.x_test_norm, self.y_test, verbose=0)[1] * 100
        
        print(f"Keras Baseline Accuracy: {keras_acc:.2f}%\n")
        print(f"{'W_Shift':<8} | {'R_Shift':<8} | {'FPGA Acc':<10} | {'Drop':<8}")
        print("-" * 40)

        for j in w_shifts:
            for k in r_shifts:
                preds, params = self.simulate_fpga_inference(j, k)
                fpga_acc = np.mean(preds == self.y_test) * 100
                drop = keras_acc - fpga_acc
                
                self.sweep_results.append([j, k, keras_acc, fpga_acc, drop])
                print(f"{j:<8} | {k:<8} | {fpga_acc:<10.2f} | {drop:<8.2f}")

                # Save the params from the last iteration (or best) for export
                self.best_params = params

    def visualize(self, save_path='C:\\Users\\joons\\Desktop\\Advanced_verilog\\models\\quantization_results.png'):
            """Generates heatmaps of the sweep results and saves the image."""
            if not self.sweep_results:
                print("Error: No sweep results found. Run run_sweep() first.")
                return

            df = pd.DataFrame(self.sweep_results, 
                            columns=['Weight_Shift', 'ReLU_Shift', 'Keras_Acc', 'FPGA_Acc', 'Acc_Drop'])
            
            pivot_acc = df.pivot(index="Weight_Shift", columns="ReLU_Shift", values="FPGA_Acc")
            pivot_drop = df.pivot(index="Weight_Shift", columns="ReLU_Shift", values="Acc_Drop")

            fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
            
            # Plot A: Accuracy
            sns.heatmap(pivot_acc, annot=True, fmt=".2f", cmap="viridis", ax=ax1)
            ax1.set_title("FPGA Test Accuracy (%)")
            
            # Plot B: Drop
            sns.heatmap(pivot_drop, annot=True, fmt=".2f", cmap="YlOrRd", ax=ax2)
            ax2.set_title("Accuracy Drop (Keras - FPGA) %")
            
            plt.tight_layout()
            
            # --- Save the figure ---
            plt.savefig(save_path, dpi=300) 
            print(f"Visualization saved to: {save_path}")
            
            plt.show()
            plt.close(fig) 

    def export_final_model(self, w_shift=7, r_shift=11, folder="mem_files"):
            """
            Force-quantizes the model with specific shifts and exports to .mem.
            Designed for: 8-bit inputs, 8-bit weights, 16-bit biases.
            """
            # 1. Manually regenerate params for the specific shifts requested
            # This ensures the export isn't just the 'last' loop iteration
            w1_f, b1_f = self.model.layers[0].get_weights()
            w2_f, b2_f = self.model.layers[1].get_weights()

            # Weight Quantization: Float -> S0.7 (8-bit signed)
            qW1 = np.clip(np.round(w1_f * 127), -128, 127).astype(np.int32)
            qW2 = np.clip(np.round(w2_f * 127), -128, 127).astype(np.int32)

            # Bias Quantization: Float -> S8.7 (16-bit signed)
            # Note: We scale by 2^7 (128) to align decimal points with S0.7 weights
            qb1 = np.clip(np.round(b1_f * 128), -32768, 32767).astype(np.int32)
            qb2 = np.clip(np.round(b2_f * 128), -32768, 32767).astype(np.int32)

            # 2. Create the folder
            if not os.path.exists(folder): 
                os.makedirs(folder)
            
            # 3. Hex Export Configuration
            # w1, w2 = 8-bit (2 hex chars) | b1, b2 = 16-bit (4 hex chars)
            files = {
                "w1.mem": (qW1, 8), 
                "b1.mem": (qb1, 16),
                "w2.mem": (qW2, 8), 
                "b2.mem": (qb2, 16)
            }
            
            print(f"\n--- Exporting Params (W_Shift: {w_shift}, R_Shift: {r_shift}) ---")
            for name, (data, bits) in files.items():
                file_path = os.path.join(folder, name)
                with open(file_path, "w") as f:
                    # The mask (v & mask) handles two's complement for negative numbers
                    mask = (1 << bits) - 1
                    fmt = f"0{bits//4}x" 
                    
                    for v in data.flatten():
                        f.write(f"{format(v & mask, fmt)}\n")
                print(f"Created {name} ({len(data.flatten())} elements)")

# --- Usage in your main block ---


# --- Main Execution ---
if __name__ == "__main__":
    '''for i in range(5, 12):
        path= f'C:\\Users\\joons\\Desktop\\Advanced_verilog\\models\\mnist_{i}_neurons.h5'
        quantizer = FPGA_Quantizer(path)
        quantizer.run_sweep()
        quantizer.visualize(f'C:\\Users\\joons\\Desktop\\Advanced_verilog\\models\\quantization_results{i}.png')'''
    quantizer=FPGA_Quantizer(f'C:\\Users\\joons\\Desktop\\Advanced_verilog\\models\\mnist_8_neurons.h5')
    quantizer.export_final_model(w_shift=7, r_shift=11)