+++
title = 'Neural Network Architectures: From Perceptrons to Transformers'
date = 2023-02-15T09:00:00-07:00
draft = true
summary = "Explore the evolution of neural network architectures and understand how different designs solve specific problems in machine learning."
+++

The field of neural networks has evolved dramatically over the past few decades, from simple perceptrons to complex transformer architectures that power today's most advanced AI systems. Understanding these different architectures is crucial for anyone working in machine learning or artificial intelligence.

## The Perceptron: Where It All Began

The perceptron, introduced by Frank Rosenblatt in 1957, was the first artificial neural network. It's a simple binary classifier that can learn to separate linearly separable data.

```python
import numpy as np

class Perceptron:
    def __init__(self, learning_rate=0.01, n_iterations=100):
        self.learning_rate = learning_rate
        self.n_iterations = n_iterations
        self.weights = None
        self.bias = None
    
    def fit(self, X, y):
        n_samples, n_features = X.shape
        self.weights = np.zeros(n_features)
        self.bias = 0
        
        for _ in range(self.n_iterations):
            for idx, x_i in enumerate(X):
                linear_output = np.dot(x_i, self.weights) + self.bias
                y_predicted = self.activation_function(linear_output)
                
                # Update weights
                update = self.learning_rate * (y[idx] - y_predicted)
                self.weights += update * x_i
                self.bias += update
    
    def predict(self, X):
        linear_output = np.dot(X, self.weights) + self.bias
        return self.activation_function(linear_output)
    
    def activation_function(self, x):
        return np.where(x >= 0, 1, 0)
```

## Multi-Layer Perceptrons (MLPs)

MLPs introduced hidden layers, enabling the network to learn non-linear relationships. This was a significant breakthrough that made neural networks much more powerful.

## Convolutional Neural Networks (CNNs)

CNNs revolutionized computer vision by introducing convolutional layers that can detect spatial patterns in images. The key innovation was weight sharing, which dramatically reduced the number of parameters needed.

```python
import torch
import torch.nn as nn

class SimpleCNN(nn.Module):
    def __init__(self, num_classes=10):
        super(SimpleCNN, self).__init__()
        self.conv1 = nn.Conv2d(1, 32, kernel_size=3, padding=1)
        self.conv2 = nn.Conv2d(32, 64, kernel_size=3, padding=1)
        self.pool = nn.MaxPool2d(2, 2)
        self.fc1 = nn.Linear(64 * 7 * 7, 128)
        self.fc2 = nn.Linear(128, num_classes)
        self.relu = nn.ReLU()
        self.dropout = nn.Dropout(0.5)
    
    def forward(self, x):
        x = self.pool(self.relu(self.conv1(x)))
        x = self.pool(self.relu(self.conv2(x)))
        x = x.view(-1, 64 * 7 * 7)
        x = self.dropout(self.relu(self.fc1(x)))
        x = self.fc2(x)
        return x
```

## Recurrent Neural Networks (RNNs)

RNNs were designed to handle sequential data by maintaining internal memory. However, they suffered from the vanishing gradient problem, which limited their ability to learn long-term dependencies.

## Long Short-Term Memory (LSTM)

LSTMs solved the vanishing gradient problem by introducing a more sophisticated memory mechanism with input, forget, and output gates.

## Transformers: The Current Revolution

Transformers, introduced in the "Attention Is All You Need" paper, revolutionized natural language processing by using self-attention mechanisms instead of recurrence.

```python
import torch
import torch.nn as nn
import math

class MultiHeadAttention(nn.Module):
    def __init__(self, d_model, num_heads):
        super().__init__()
        self.num_heads = num_heads
        self.d_model = d_model
        assert d_model % num_heads == 0
        
        self.depth = d_model // num_heads
        self.wq = nn.Linear(d_model, d_model)
        self.wk = nn.Linear(d_model, d_model)
        self.wv = nn.Linear(d_model, d_model)
        self.dense = nn.Linear(d_model, d_model)
    
    def scaled_dot_product_attention(self, q, k, v, mask):
        matmul_qk = torch.matmul(q, k.transpose(-2, -1))
        dk = torch.tensor(k.shape[-1], dtype=torch.float32)
        scaled_attention_logits = matmul_qk / torch.sqrt(dk)
        
        if mask is not None:
            scaled_attention_logits += (mask * -1e9)
        
        attention_weights = torch.softmax(scaled_attention_logits, dim=-1)
        output = torch.matmul(attention_weights, v)
        return output, attention_weights
```

## Choosing the Right Architecture

The choice of neural network architecture depends on your specific problem:

- **CNNs**: Image classification, object detection, computer vision tasks
- **RNNs/LSTMs**: Sequential data, time series, natural language processing
- **Transformers**: Large language models, machine translation, text generation
- **MLPs**: Tabular data, simple classification/regression tasks

## The Future of Neural Network Architectures

Recent developments include:
- **Vision Transformers**: Applying transformer architecture to computer vision
- **Graph Neural Networks**: Processing graph-structured data
- **Neural Architecture Search**: Automatically discovering optimal architectures
- **Efficient Transformers**: Reducing computational complexity while maintaining performance

Understanding these architectures and their trade-offs is essential for building effective machine learning systems. Each architecture has its strengths and weaknesses, and the key is choosing the right tool for the job.
