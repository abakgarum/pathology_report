# PathLab Pro — Voice-First Pathology Report System

A modern Flutter app that transforms how doctors create pathology reports through voice dictation and AI.

## 🎯 Quick Start

### Prerequisites
- Flutter SDK (macos/linux/windows)
- `.env` file with Gemini API key (already configured)

### Run
```bash
cd ~/Desktop/projects/pathology_report

# First time setup
flutter pub get

# Run on macOS desktop
flutter run -d macos

# Or run on web (Chrome)
flutter run -d chrome
```

---

## 🎤 Doctor's Workflow

### New Voice Report (Main Feature)
1. **Click "New Voice Report"** in sidebar
2. Fill quick patient info (name, age, gender)
3. **Hit mic button** → Start dictating your findings
4. See **live waveform** + **real-time transcript** appearing
5. Pause/Resume/Stop as needed
6. **Multiple recordings** per report (each auto-saved)
7. Click **"Generate Report"** → Gemini AI processes transcript
8. Review **structured report** in right panel with:
   - Patient details
   - Specimen info
   - Microscopic findings
   - Diagnosis (highlighted)
   - IHC, special stains, molecular studies
   - Clinical summary
9. **See raw recordings** anytime (expandable panel with playback)
10. Click **"Save Report"** → Added to database

---

## 📱 Desktop Layout (No Screen Transitions)

```
┌─────────────┬──────────────────────────────────┐
│             │                                  │
│  Dashboard  │   Voice Report Panel             │
│  New Voice  │                                  │
│  All Reports│   Split View:                    │
│  Templates  │   Left: Recording + Transcript   │
│  Analytics  │   Right: Generated Report        │
│  Settings   │                                  │
│             │                                  │
│   (Sidebar) │    (Content Area)                │
└─────────────┴──────────────────────────────────┘
```

Everything happens in one window. Click sidebar = content updates inline.

---

## 🔑 Key Features

### Voice Recording
- **Real-time waveform visualization** while speaking
- Duration timer (MM:SS)
- Pause/Resume/Stop controls
- Multiple recordings per report
- Raw audio saved as `.m4a` files

### AI-Powered Report Generation
- **Gemini 2.0 Flash API** processes full transcript
- Extracts structured data:
  - Patient name, age, gender
  - Specimen type & site
  - Clinical history & gross description
  - Microscopic findings
  - Diagnosis (primary field)
  - Grade & Stage
  - IHC, special stains, molecular studies
  - Auto-generated clinical summary
- Returns as JSON → seamless import into report form

### Raw Recording Access
- **Doctor can always review** original voice recordings
- See original transcript + generated text side-by-side
- Catch any AI mistakes and see what the doctor actually said
- Expandable "Raw Voice Transcript" section

### Desktop-Friendly
- **Single-pane architecture** — no modal popups or page transitions
- Sidebar navigation (instant content switching)
- Responsive split-pane on large screens
- Mobile fallback with bottom navigation

---

## 📂 Project Structure

```
lib/
├── main.dart                    # App entry + Gemini API init
├── models/
│   └── report_models.dart       # Patient, Specimen, Report, VoiceRecording
├── services/
│   ├── gemini_service.dart      # AI report generation
│   └── audio_service.dart       # Voice recording + amplitude tracking
├── screens/
│   ├── desktop_shell.dart       # Sidebar + main layout
│   ├── voice_report_screen.dart # 🎤 Main voice dictation UI
│   ├── dashboard_screen.dart    # Overview + quick stats
│   ├── reports_list_screen.dart # Search/filter all reports
│   ├── report_detail_screen.dart# Full report view
│   └── create_report_screen.dart# Legacy form-based creation
├── theme/
│   └── app_theme.dart           # Medical teal color scheme
├── widgets/
│   ├── report_card.dart
│   ├── stat_card.dart
│   └── section_header.dart
└── utils/
    └── demo_data.dart           # Sample reports
```

---

## 🤖 Gemini Integration

### Setup (Already Done)
- API key in `.env` file
- `flutter_dotenv` loads at startup
- Gemini 2.0 Flash model selected (fast + affordable)

### How It Works
1. Doctor clicks "Generate Report"
2. App sends **full transcript** to Gemini
3. Prompt asks for structured JSON extraction
4. Gemini returns:
   ```json
   {
     "patient_name": "...",
     "diagnosis": "...",
     "summary": "Clinical summary here...",
     ...
   }
   ```
5. App parses JSON → fills report form
6. Doctor reviews + saves

### Error Recovery
- If AI makes mistakes, doctor can:
  1. Play back raw recording (verify what was said)
  2. Manually edit extracted fields
  3. Re-generate if needed

---

## 🎨 Design System

### Colors (Medical Theme)
- **Primary**: Teal/Blue (`#0D7377`) — Trust, medical authority
- **Accent**: Mint green (`#32E0C4`) — Modern, friendly
- **Status**:
  - Success: Green (Completed)
  - Warning: Orange (Pending)
  - Error: Red (Draft)
  - Blue: Info/Default

### Typography
- **Font**: Google Fonts "Inter" (clean, modern)
- **Headings**: Bold, large sizes
- **Body**: Regular weight, optimized for reading

---

## 🧪 Demo Data

Sample reports pre-loaded with realistic pathology cases:
- Lung adenocarcinoma (Grade 2)
- Breast fibroadenoma (Benign)
- Pending colon biopsy
- Thyroid resection (Draft)

---

## 📦 Dependencies

| Package | Purpose |
|---------|---------|
| `record` 4.4.4 | Audio recording |
| `just_audio` | Audio playback |
| `http` | Gemini API calls |
| `flutter_dotenv` | Load .env credentials |
| `uuid` | Unique IDs for reports |
| `path_provider` | Save recordings to disk |
| `google_fonts` | Professional typography |

---

## 🚀 Next Steps (Future Enhancements)

1. **Real STT** — Replace demo transcript with:
   - Google Speech-to-Text API
   - OpenAI Whisper
   - Platform native (iOS/Android dictation)

2. **Database** — Replace in-memory storage:
   - Firebase Firestore
   - SQLite local + sync
   - Cloud backup

3. **PDF Export** — Generate professional reports:
   - Signature field
   - Lab letterhead
   - DICOM/image attachments

4. **Collaboration** — Add peer review:
   - Share reports
   - Comment threads
   - Sign-off workflow

5. **Analytics** — Dashboard stats:
   - Reports per day/week/month
   - Diagnosis trends
   - Turn-around time metrics

6. **Multi-user** — Support clinic teams:
   - User roles (Pathologist, Technician, Admin)
   - Report assignment
   - Audit trail

---

## 🐛 Troubleshooting

### "Microphone permission denied"
→ Grant microphone access in System Preferences > Security & Privacy

### "Build fails on Linux"
→ We've pinned `record: 4.4.4` (stable). Linux support is partial.

### "Gemini API error"
→ Check:
  - `.env` file exists with valid `API_KEY`
  - Internet connection
  - API quota not exceeded

### "Waveform not showing"
→ Amplitude stream may have platform-specific issues. Works on macOS/iOS/desktop.

---

## 📄 License

Proprietary — PathLab Pro

---

**Built with ❤️ for doctors who prefer voice over typing.**
# pathology_report
