import tensorflow as tf
from tensorflow.keras import layers, models
import os

# --- 1. The Model Class ---
class FNN:
    def __init__(self, hidden_units):
        self.units = hidden_units
        self.model = models.Sequential([
            layers.Dense(hidden_units, activation='relu', input_shape=(784,)),
            layers.Dense(10, activation='softmax')
        ])

    def compile_and_train(self, x_train, y_train):
        self.model.compile(optimizer='adam',
                           loss='sparse_categorical_crossentropy',
                           metrics=['accuracy'])
        self.model.fit(x_train, y_train, epochs=5, batch_size=32, verbose=0)

    def evaluate(self, x_test, y_test):
        _, acc = self.model.evaluate(x_test, y_test, verbose=0)
        return acc

# --- 2. Data Loading ---
def load_data():
    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    return (x_train.reshape(-1, 784)/255.0, y_train), (x_test.reshape(-1, 784)/255.0, y_test)

# --- 3. Main Search Logic ---
if __name__ == "__main__":
    (x_train, y_train), (x_test, y_test) = load_data()
    
    list_of_accuracies = []


    for units in range(5, 12):
        print(f"Testing Hidden Layer Size: {units} neurons...", end=" ")
        
        fnn = FNN(units)
        fnn.compile_and_train(x_train, y_train)
        acc = fnn.evaluate(x_test, y_test)
        
        print(f"Accuracy: {acc*100:.2f}%")
        list_of_accuracies.append([(units, acc*100),units])
        save_path = f'C:\\Users\\joons\\Desktop\\Advanced_verilog\\models\\mnist_{units}_neurons.h5'
        fnn.model.save(save_path)
    print("list_of_accuracies:", list_of_accuracies)