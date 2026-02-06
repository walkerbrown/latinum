# Task: Build an iOS Predictive Latin Keyboard called "Latinum"

You are given:
- A large, unclean corpus of Latin text.
  - The corpus contains few to no macron diacritics.
  - The corpus may contain non-printable escape characters, mixed casing, punctuation, stray symbols, English fragments, and formatting artifacts.
- No external data sources are allowed for inference.
- All inference must be local and on-device.

Your goal is to design and implement the best possible predictive text keyboard for Latin, intended for Latin students, under strict mobile memory and performance constraints, prioritizing word and inflection completion over next-word prediction.

---

## AGENT OPERATIONAL PROTOCOLS FOR SAFE AND SECURE DEVELOPMENT WITHOUT CONTAINERIZATION ON macOS

1. Scope & Permissions
* Working directory: You have full read/write access to the current directory and all subdirectories (`./*`). You are authorized to create, edit, and delete files here without asking for permission for every single file operation.
* Boundary enforced: You are strictly forbidden from reading, writing, or traversing to parent directories (`../`). Treat the current folder as the root of the filesystem.

2. Tooling & Environment
* System integrity: You must not attempt to install software packages (e.g., via `brew`, `apt`, `npm -g`, `gem`) directly.
* Tool manifest: Maintain a file named `tool_manifest.md` in the root of this project.
    * Action: Before using a CLI tool (other than standard Unix utilities like `ls`, `grep`, `cat`), check if it is available (e.g., `which xcodegen`).
    * If missing: Do not fail. Append the tool name to `tool_manifest.md`, then pause and ask the user to install it before continuing.
    * If present: Continue without pausing to ask the user for permission.

3. Workflow Automation
* Proactive coding: Do not ask "Should I create this file?" for every step. If the plan requires a file, create it. If code needs to be written, write it.
* Error handling: If a shell command fails, read the error message, analyze it, attempt to fix the command or configuration, and retry *at most twice* before asking for human intervention.
* Xcode projects: When generating Xcode configurations or project files, prioritize using CLI-friendly tools (like `xcodegen` or raw directory structures) over manual GUI instructions whenever possible.

---

## Mobile Application Constraints (Non-Negotiable)

1. Platform
   - iOS only.
   - Deployment via Core ML.
   - Must be compatible with an iOS keyboard extension (tight memory + latency limits).
   - Assume a minimum target of iPhone 12 / A14-class devices.

2. Inference
   - Fully local inference only.
   - No network calls, no server components.
   - Model must load and run inside a keyboard extension.

3. Performance
   - Low latency per keystroke.
   - Small memory footprint.
   - Prefer incremental decoding and state caching where applicable.

4. Model Scope
   - Small model (keyboard-scale, not LLM-scale).
   - Transformer or simpler architecture is acceptable.
   - Quantization is encouraged if helpful.
   - Do not write custom Metal shaders unless strictly necessary; prefer Core ML abstractions.

---

## Privacy & Data Handling (Non-Negotiable)

1. No Telemetry or User Data Collection
   - The app must not collect, transmit, or store any user identifiers or personal information.
   - No analytics, logging, or telemetry related to user behavior or input.

2. No Keystroke Retention
   - The app must not retain user keystrokes or input text beyond what is strictly necessary for immediate, in-memory prediction.
   - No persistence of typed content to disk.

3. No Network Activity
   - The app must not make any network calls.
   - All functionality must work fully offline.

4. Documentation
   - These privacy guarantees must be made explicit in user-facing documentation and developer documentation.

---

## Linguistic Requirements (Latin-Specific)

1. Macron Normalization & Handling
   - The language model must be trained and queried using macron-free (normalized) text.
   - All macrons must be stripped during corpus cleaning and normalization.
   - At runtime:
     - User input must be normalized to macron-free text before being passed to the model.
     - Macrons already typed by the user must be preserved in the visible text buffer and must not be removed or altered by prediction logic.
   - Autocompletion must respect and extend the user’s already-entered macrons, but must not require the model itself to operate on macronized text.
   - Similar rules apply to ligatures:
     - The training data may include capitalized and non-capitalized ligatures.
     - These should be normalized into separate characters for model training and prediction.
     - Upper and lowercase ligatures should be accessible via long press of the appropriate starting character.
     - User entered ligatures should be respected by autocomplete logic, without requiring the model to operate on the ligature characters themselves.

2. Prediction Priorities
   - Word completion is more important than next-word prediction.
   - Especially important for highly inflected forms (case, number, tense, mood).

3. Language Characteristics
   - Rich morphology
   - Free-ish word order
   - Agreement-driven syntax

   Therefore:
   - Do NOT assume English-style next-word prediction is reliable.
   - Subword, morpheme-aware, or character-aware modeling is encouraged.

4. Scope
   - The keyboard language is pure Latin only.
   - Do NOT include a modern-language fallback or bilingual logic.

5. Common Latin Phenomena
   - Enclitics (`-que`, `-ve`, `-ne`)
   - Orthographic variation
   - Inflectional ambiguity

---

## Keyboard UI & Interaction Requirements (Non-Negotiable)

1. Native Layout Parity
   - The keyboard layout should be as close as possible to the native iOS system keyboard.
   - Standard key sizing, spacing, and row structure should be preserved.

2. Case Handling
   - Both lowercase and uppercase letters must be supported.
   - Case switching should follow native behavior:
     - Single tap on shift for temporary uppercase
     - Double tap on shift for caps lock

3. Macron Input
   - Macronized vowels (uppercase and lowercase) must be accessible via long-press on the corresponding base vowel (e.g., `a → ā`, `A → Ā`).
   - Long-press behavior should mirror native iOS diacritic selection as closely as possible.
   - Same behavior to access common Latin ligatures `a → æ`, `A → Æ`, etc.

4. User Experience
   - The keyboard should feel immediately familiar to users of the native iOS keyboard.
   - No novel or experimental input gestures should be introduced without strong justification.

---

## Testing & Build Quality (Non-Negotiable)

1. Test Coverage
   - The project must include automated test cases.
   - Tests should cover, at minimum:
     - Text normalization and macron stripping
     - Preservation of user-entered macrons in UI-visible text
     - Prediction and completion logic
     - Any heuristic or hybrid ranking components

2. Test Execution
   - All provided tests must pass.
   - Test execution instructions must be clearly documented.

3. Build Cleanliness
   - The project must compile successfully using default Xcode build settings.
   - The build must produce:
     - No errors
     - No warnings at the default warning level

---

## Allowed External Knowledge (Design & Training Only)

- You may use external resources (e.g., grammars, morphological analyses, linguistic descriptions of Latin) to:
  - Improve understanding of Latin morphology and syntax.
  - Inform model design, tokenization strategy, normalization, or training objectives.
- You may not incorporate additional textual corpora beyond the provided Latin corpus into training data.
- All runtime inference must rely solely on the trained model and local logic.

---

## Required Output (You Must Produce All of the Following)

### 1. Data Pipeline
- Describe and implement corpus cleaning and normalization.
  - Explicitly strip non-printable escape characters.
  - Explicitly normalize all text to be macron-free.
- Explain the tokenization strategy and why it fits:
  - Latin morphology
  - Keyboard-scale inference constraints

### 2. Model Design
- Specify the model architecture and approximate parameter count.
- Explain why it is suitable for:
  - Resource-constrained inference
  - Incremental word and inflection completion
- Clearly state what the model predicts (e.g., next subword, character continuation).

### 3. Training Strategy
- Describe training objective(s).
- Explain how the model learns useful completions from noisy, normalized (macron-free) data.

### 4. Core ML Deployment
- Show how the trained model is converted to Core ML.
- Indicate how Core ML selects CPU/GPU/ANE execution.
- Address memory and latency concerns specific to a keyboard extension.

### 5. Keyboard Integration Strategy
- Describe how predictions are generated incrementally as the user types.
- Explicitly explain how macron-preserving UI text is reconciled with macron-normalized model input.
- Explain how suggestions are ranked.
  - Hybrid or heuristic components are allowed if justified.
- Include a fallback strategy if the model fails to load or runs under memory pressure.

### 6. Evaluation
- Define success metrics appropriate for a Latin keyboard.
- Do NOT rely solely on English-centric metrics (e.g., generic next-word accuracy).

---

## Strong Preferences (You May Justify Deviations)

- Subword or character-level modeling over word-level modeling.
- Small, interpretable systems over maximal complexity.
- Practical UX quality over theoretical optimality.

---

## Deliverables Format

Provide:
- Clear architectural explanation.
- Pseudocode or code sketches where appropriate.
- Concrete design decisions with justification.
- Test cases and instructions for running them.
- No unnecessary boilerplate.

Assume the reader will actually build and ship this keyboard.

Optimize for clarity, correctness, and real-world usability, not academic novelty.