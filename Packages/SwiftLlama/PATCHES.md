# Local patches to swift-llama-cpp (vendored from lokii49/swift-llama-cpp at a79abb8)

All marked `mirror patch` in the source.

1. **`LlamaSampler.init`: removed `print(config)`.** The sampling config carries the GBNF grammar,
   and mirror's grammars are built from sentences in the user's journal — every generation printed
   them to stdout (found 2026-09-27 in an on-device test log).
2. **`Llama.processPrompt`: empty-final-batch fix.** Logits are requested on the prompt's last token
   as it's added, and a leftover batch is decoded only if non-empty. Before, a prompt that was an
   exact multiple of `batchSize` tokens wrote `logits[-1]` and then failed `llama_decode` on zero
   tokens, deterministically. `LlamaBatch.setLastTokenLogits` also no-ops on an empty batch now.
3. **`LlamaLog.silence()`** — a no-op log callback. `setLogger(nil)` restores llama.cpp's default
   stderr logger, which echoes grammar text on grammar parse errors.
4. **`LlamaModel.vocabularyOnly(path:)`** — tokenizer-only load with parameters built inside the
   package, so the app's test bundle (which doesn't link llama's C symbols) can do tokenizer-level
   checks without loading weights.
5. **`LlamaModel.tokenize`: token limit is the buffer size.** It passed `trainedContextSize()`,
   which is 0 for a vocab-only model — every tokenize failed — and could exceed the buffer otherwise.
