# Mirror Local AI

Mirror is configured to run insight generation locally with:

- Model: `Qwen2.5 1.5B Instruct`
- Format: GGUF
- Quantization: `Q4_K_M`
- Size: ~1GB
- Runtime: `swift-llama-cpp` / llama.cpp
- Min device: iPhone 12+ (4GB RAM)
- Source: `bartowski/Qwen2.5-1.5B-Instruct-GGUF` on Hugging Face
- Upstream model: `Qwen/Qwen2.5-1.5B-Instruct`
- License: Apache-2.0

## Model File

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

Do not commit the model file to git. Deliver via on-demand resource or in-app download on first launch.

For development, download the model with:

```bash
bash scripts/download-local-model.sh
```

The script downloads the GGUF from Hugging Face and writes it to `mirror/LocalModels/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf`. Add that file to the app bundle in Xcode when you want the app to ship with the model.

## License Notes

Qwen2.5 1.5B Instruct is Apache-2.0 licensed. Keep Apache-2.0 attribution and third-party notices with the app and update the privacy policy if any future feature sends journal content to a third-party AI service.

## Privacy

Daily reflection, weekly digest, Ask Mirror, and mood detection use the local model. Voice note transcription uses Apple's on-device speech recognition with `requiresOnDeviceRecognition = true`.

The OpenAI Worker backend is no longer used by these app flows.
