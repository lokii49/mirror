# Mirror Local AI

Mirror runs daily reflection, weekly digest, Ask Mirror, and mood detection locally with:

- Model: `Gemma 3 1B IT`
- Format: GGUF
- Quantization: `Q4_K_M`
- Runtime: `swift-llama-cpp` / llama.cpp
- Context window: 4096 tokens
- GPU acceleration: enabled

The app looks for this exact file name:

```text
gemma-3-1b-it-Q4_K_M.gguf
```

Lookup order:

1. Bundled app resource named `gemma-3-1b-it-Q4_K_M.gguf`
2. Application Support path:

```text
Application Support/Mirror/Models/gemma-3-1b-it-Q4_K_M.gguf
```

Do not commit the model file to git. Deliver it as an on-demand resource or in-app download.

## Generation behavior

Mirror creates a fresh llama.cpp context for each local AI request, streams output, and stops generation when Gemma emits `<end_of_turn>` or `<eos>`. It also enforces per-task character caps to prevent runaway generation if an end token is not recognized.

Sampling is task-specific:

- Emotion detection: low temperature, short output cap.
- Daily nudge and Ask Mirror: moderate temperature.
- Weekly digest and monthly report: slightly higher temperature with longer output caps.

## Privacy

Journal entry content, media payloads, generated insights, and Ask Mirror questions are encrypted before SwiftData/CloudKit persistence. The local model receives decrypted text only inside the app process on the user's device.

This is not yet complete multi-device E2E sync because the content key is generated and stored in the local Keychain. A second device will need a recovery-key or passphrase-based key import flow before it can decrypt synced ciphertext from the first device.
