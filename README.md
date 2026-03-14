# Flow Pad

A professional on-device voice recorder for iOS that automatically transcribes and summarizes your recordings using on-device AI.

## Features

- **One-Tap Recording** — Large, prominent record button with live waveform visualization and pulse animations
- **Automatic Transcription** — On-device speech-to-text using Apple's Speech framework (no network required)
- **Smart Summarization** — Apple’s on-device Foundation Model (Apple Intelligence) generates bullet-point summaries when available; falls back to built-in extractive summarization otherwise
- **Editable Titles** — Auto-generated from transcript, fully editable inline
- **One-Tap Copy** — Copy summary or transcript with a single tap, with haptic feedback and toast confirmation
- **Audio Playback** — Built-in player with waveform progress visualization
- **Searchable Library** — Notes grouped by date with full-text search across titles, summaries, and transcripts
- **Swipe to Delete** — Context menus and swipe actions for quick management
- **Share** — Native share sheet for exporting notes
- **Apple Design Language** — Dark mode, SF Symbols, system materials, spring animations, haptic feedback

## Requirements

- Xcode 16+ (for Foundation Models framework)
- iOS 26.0+
- Real device recommended (microphone, Speech framework). For AI summaries, Apple Intelligence must be enabled on a supported device.

## Setup

1. Open `VoxNote.xcodeproj` in Xcode (project folder is still named VoxNote)
2. Select your development team under Signing & Capabilities
3. Build and run on a device

Summarization uses Apple’s **Foundation Models** framework when the on-device language model is available (Apple Intelligence on). Otherwise the app uses built-in extractive summarization.

## Architecture

```
FlowPad/
├── App/                    # App entry point
├── Models/                 # SwiftData model (VoiceNote)
├── Services/
│   ├── AudioService        # AVAudioRecorder + AVAudioPlayer
│   ├── TranscriptionService # SFSpeechRecognizer (on-device)
│   └── SummarizationService # Apple Foundation Models + extractive fallback
├── Views/
│   ├── NotesListView       # Main list with search + grouping
│   ├── RecordingView       # Full-screen recorder with waveform
│   ├── NoteDetailView      # Detail view with edit/copy/share
│   └── Components/
│       ├── WaveformView    # Live + static waveform visualizations
│       └── AudioPlayerView # Playback controls with progress
└── Resources/              # Assets, colors
```

## Data Flow

```
Record → AudioService (AVAudioRecorder)
       → m4a file saved to Documents
       → TranscriptionService (SFSpeechRecognizer)
       → Transcript text
       → SummarizationService (Apple LLM or extractive)
       → Summary text
       → VoiceNote persisted via SwiftData
```
