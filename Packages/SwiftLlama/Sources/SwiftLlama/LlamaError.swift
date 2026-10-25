//
//  LlamaError.swift
//  swift-llama-cpp
//
//  Created by Piotr Gorzelany on 30/07/2025.
//

public enum LlamaError: Error{
    case couldNotInitializeContext
    case contextSizeLimitExeeded
    case decodingError
    case emptyMessageArray
    /// mirror patch: the app is in the background, so the GPU can't take work (`LlamaGPUGate`).
    case gpuUnavailable
}
