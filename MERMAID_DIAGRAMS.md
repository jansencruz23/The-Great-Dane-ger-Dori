# DORI Application Flow - Mermaid Diagrams

## 1. Overall Application Flow

```mermaid
flowchart TB
    subgraph STARTUP["🚀 App Startup"]
        A[Launch App] --> B[Splash Screen]
        B --> C{Check Auth}
        C -->|Not Logged In| D[Login Screen]
        C -->|Logged In| E{Check Role}
        D --> F[Firebase Auth]
        F --> E
    end

    subgraph ROLES["👥 Role-Based Navigation"]
        E -->|Patient| G[Patient Home]
        E -->|Caregiver| H[Caregiver Dashboard]
    end

    subgraph PATIENT["🧠 Patient Flow"]
        G --> I[Start Remembering]
        I --> J[Face Recognition Screen]
        J --> K{Face Detected?}
        K -->|Yes| L{Known Face?}
        K -->|No| M[Continue Scanning]
        M --> K
        L -->|Yes| N[Show AR Overlay]
        L -->|No| O{Wait 3 sec}
        O --> P[Show Enrollment Prompt]
        P --> Q{How do you feel?}
        Q -->|I feel safe| R[Start Enrollment]
        Q -->|I feel unsure| S[Add to Blocklist]
        N --> T[Record Interaction]
        T --> U[Transcribe Speech]
        U --> V[Generate Summary]
    end

    subgraph CAREGIVER["👨‍⚕️ Caregiver Flow"]
        H --> W[View Patients]
        H --> X[Manage Faces]
        H --> Y[View Activity Logs]
        X --> Z[Live Enrollment]
        X --> AA[Gallery Enrollment]
        Z --> AB[Capture 5 Poses]
        AB --> AC[Extract Embeddings]
        AC --> AD[Save to Firebase]
    end

    style STARTUP fill:#e8f5e9
    style ROLES fill:#e3f2fd
    style PATIENT fill:#fff3e0
    style CAREGIVER fill:#f3e5f5
```

## 2. Face Recognition Pipeline

```mermaid
flowchart LR
    subgraph INPUT["📷 Camera Input"]
        A[Camera Stream] --> B[YUV Image Buffer]
    end

    subgraph DETECTION["🔍 Face Detection"]
        B --> C[ML Kit Face Detector]
        C --> D[Face Bounding Boxes]
        D --> E[Face Landmarks]
    end

    subgraph EMBEDDING["🧮 Embedding Extraction"]
        B --> F[Crop Face Region]
        F --> G[Align Face]
        G --> H[Resize to 160x160]
        H --> I[TFLite FaceNet-512]
        I --> J[512-dim Embedding]
    end

    subgraph MATCHING["🎯 Face Matching"]
        J --> K[Normalize Embedding]
        K --> L{Compare with Known Faces}
        L --> M[Cosine Similarity]
        M --> N{Similarity > 0.75?}
        N -->|Yes| O[✅ Match Found]
        N -->|No| P[❓ Unknown Face]
    end

    subgraph OUTPUT["📱 UI Output"]
        O --> Q[AR Overlay Widget]
        P --> R[Enrollment Prompt]
        Q --> S[Show Name & Info]
        R --> T[Voice Input]
    end

    style INPUT fill:#e1f5fe
    style DETECTION fill:#f3e5f5
    style EMBEDDING fill:#fff8e1
    style MATCHING fill:#e8f5e9
    style OUTPUT fill:#fce4ec
```

## 3. Enrollment Flow

```mermaid
flowchart TB
    A[Unknown Face Detected] --> B{Persists 3+ seconds?}
    B -->|No| A
    B -->|Yes| C{In Blocklist?}
    C -->|Yes| D[Skip - Don't Prompt]
    C -->|No| E[Show: How do you feel?]
    
    E --> F{User Response}
    F -->|I feel safe| G[Collect Name via Voice]
    F -->|I feel unsure| H[Add to Blocklist]
    
    G --> I[Collect Relationship via Voice]
    I --> J[Capture 5 Poses]
    
    subgraph POSES["📸 Multi-Angle Capture"]
        J --> K[Center Pose]
        K --> L[Left Turn]
        L --> M[Right Turn]
        M --> N[Look Up]
        N --> O[Look Down]
    end
    
    O --> P[Extract 5 Embeddings]
    P --> Q[Save to Firebase]
    Q --> R[✅ Enrollment Complete]
    
    H --> S[Face Ignored in Session]
    D --> S

    style POSES fill:#e3f2fd
```

## 4. Summarization Flow

```mermaid
flowchart TB
    subgraph CAPTURE["📝 Interaction Capture"]
        A[Face Recognized] --> B[Start Recording]
        B --> C[Speech-to-Text]
        C --> D[Store Transcription]
        D --> E[Face Leaves Frame]
        E --> F[Stop Recording]
    end

    subgraph STORAGE["💾 Data Storage"]
        F --> G[Create Activity Log]
        G --> H[Save to Firestore]
        H --> I[Link to Patient & Person]
    end

    subgraph SUMMARIZATION["🤖 AI Summary"]
        I --> J{Generate Summary?}
        J -->|Interaction End| K[Single Interaction Summary]
        J -->|Daily Recap| L[Day-by-Day Summary]
        
        K --> M[Build Prompt with Context]
        L --> N[Aggregate Day's Activities]
        
        M --> O[Call Gemini API]
        N --> O
        
        O --> P[Receive AI Response]
        P --> Q[Store Summary]
    end

    subgraph DISPLAY["📱 User Display"]
        Q --> R[AR Overlay Info]
        Q --> S[Daily Recap Screen]
        R --> T[Show Recent Summary]
        S --> U[Show Day Stories]
    end

    style CAPTURE fill:#e8f5e9
    style STORAGE fill:#fff3e0
    style SUMMARIZATION fill:#e3f2fd
    style DISPLAY fill:#fce4ec
```

## 5. State Management Flow

```mermaid
flowchart TB
    subgraph PROVIDERS["🔄 Provider State"]
        A[UserProvider] --> B[Current User]
        A --> C[Auth State]
        A --> D[Role: Patient/Caregiver]
    end

    subgraph SERVICES["⚙️ Services"]
        E[FaceRecognitionService] --> F[TFLite Model]
        E --> G[ML Kit Detector]
        E --> H[Known Faces Cache]
        
        I[DatabaseService] --> J[Firestore Operations]
        I --> K[User Management]
        I --> L[Face CRUD]
        
        M[SpeechService] --> N[Speech Recognition]
        M --> O[Text-to-Speech]
        
        P[SummarizationService] --> Q[Gemini API]
    end

    subgraph SCREENS["📱 Screen States"]
        R[Face Recognition Screen]
        R --> S[_detectedFaces]
        R --> T[_enrollmentMode]
        R --> U[_isRecording]
        R --> V[_activeRecognition]
        R --> W[_blockedFaceEmbeddings]
    end

    B --> R
    H --> R
    J --> R
    N --> R

    style PROVIDERS fill:#e1f5fe
    style SERVICES fill:#f3e5f5
    style SCREENS fill:#fff8e1
```

## 6. Data Flow Architecture

```mermaid
flowchart LR
    subgraph CLIENT["📱 Flutter App"]
        A[UI Layer] --> B[State Management]
        B --> C[Service Layer]
    end

    subgraph LOCAL["💾 On-Device"]
        C --> D[TFLite Model]
        C --> E[ML Kit]
        C --> F[Speech Recognition]
    end

    subgraph CLOUD["☁️ Firebase"]
        C --> G[Authentication]
        C --> H[Cloud Firestore]
        C --> I[Firebase Storage]
    end

    subgraph AI["🤖 Google AI"]
        C --> J[Gemini API]
    end

    H --> K[(Users Collection)]
    H --> L[(Known Faces)]
    H --> M[(Activity Logs)]
    I --> N[(Face Images)]

    style CLIENT fill:#e8f5e9
    style LOCAL fill:#fff3e0
    style CLOUD fill:#e3f2fd
    style AI fill:#fce4ec
```

---

## How to Use These Diagrams

1. **Copy the Mermaid code** between the ```mermaid``` blocks
2. **Paste into any Mermaid-compatible tool:**
   - [Mermaid Live Editor](https://mermaid.live/)
   - GitHub Markdown (renders automatically)
   - VS Code with Mermaid extension
   - Notion, Confluence, etc.
3. **Export as SVG or PNG** for presentations

## Quick Mermaid Live Editor Links

For quick rendering, paste this URL format in your browser:
```
https://mermaid.live/edit
```

Then paste the diagram code to see it rendered!
