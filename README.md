# VoxNote

A professional on-device voice recorder for iOS that automatically transcribes and summarizes your recordings using on-device AI.

## Features

- **One-Tap Recording** — Large, prominent record button with live waveform visualization and pulse animations
- **Automatic Transcription** — On-device speech-to-text using Apple's Speech framework (no network required)
- **Smart Summarization** — Extractive summarization distills key points from your transcript. With Zetic Melange SDK, upgrade to AI-powered generative summaries via NPU acceleration
- **Editable Titles** — Auto-generated from transcript, fully editable inline
- **One-Tap Copy** — Copy summary or transcript with a single tap, with haptic feedback and toast confirmation
- **Audio Playback** — Built-in player with waveform progress visualization
- **Searchable Library** — Notes grouped by date with full-text search across titles, summaries, and transcripts
- **Swipe to Delete** — Context menus and swipe actions for quick management
- **Share** — Native share sheet for exporting notes
- **Apple Design Language** — Dark mode, SF Symbols, system materials, spring animations, haptic feedback

## Requirements

- Xcode 15+
- iOS 17.0+
- Real device recommended (microphone, Speech framework, NPU)

## Setup

1. Open `VoxNote.xcodeproj` in Xcode
2. Select your development team under Signing & Capabilities
3. Build and run on a device

### Optional: Zetic Melange Integration

For AI-powered generative summarization:

1. Add the Zetic MLange SDK: **File → Add Package Dependencies** → `https://github.com/zetic-ai/ZeticMLangeiOS.git`
2. Add your `ZETIC_MLANGE_KEY` to `Info.plist`
3. Upload a summarization model to the [Melange Dashboard](https://dashboard.zetic.ai)

Without the SDK, the app uses a built-in extractive summarization algorithm.

## Architecture

```
VoxNote/
├── App/                    # App entry point
├── Models/                 # SwiftData model (VoiceNote)
├── Services/
│   ├── AudioService        # AVAudioRecorder + AVAudioPlayer
│   ├── TranscriptionService # SFSpeechRecognizer (on-device)
│   └── SummarizationService # Zetic Melange + extractive fallback
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
       → SummarizationService (Zetic or extractive)
       → Summary text
       → VoiceNote persisted via SwiftData
```
