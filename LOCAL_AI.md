# Mirror Local AI

Mirror runs daily reflection, weekly digest, Ask Mirror, and mood detection locally with:

- Model: `Qwen2.5 1.5B Instruct`
- Format: GGUF
- Quantization: `Q4_K_M`
- Runtime: `swift-llama-cpp` / llama.cpp

The app looks for this exact file name:

```text
Qwen2.5-1.5B-Instruct-Q4_K_M.gguf
```

Lookup order:

1. Bundled app resource named `Qwen2.5-1.5B-Instruct-Q4_K_M.gguf`
2. Application Support path:

```text
Application Support/Mirror/Models/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf
```

Do not commit the model file to git. Deliver it as an on-demand resource or in-app download.

## Privacy

Journal entry content, media payloads, generated insights, and Ask Mirror questions are encrypted before SwiftData/CloudKit persistence. The local model receives decrypted text only inside the app process on the user's device.

This is not yet complete multi-device E2E sync because the content key is generated and stored in the local Keychain. A second device will need a recovery-key or passphrase-based key import flow before it can decrypt synced ciphertext from the first device.
