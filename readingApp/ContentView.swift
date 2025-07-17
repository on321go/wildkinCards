//
//  ContentView.swift
//  readingApp
//
//  Created by Joey Rubin on 7/16/25.
//

import SwiftUI
import Speech
import AVFoundation

struct ContentView: View {
    var body: some View {
        ReadingChallengeView()
    }
}

// MARK: - Data Models for JSON
// These structs match the structure of our new sentences.json file.
struct Story: Codable, Hashable {
    let title: String
    let sentences: [String]
}

struct GradeContent: Codable {
    let random: [String]
    let stories: [Story]
}

struct ContentData: Codable {
    let grades: [String: GradeContent]
}

// MARK: - Speech Recognizer
// This helper class remains unchanged.
class SpeechRecognizerManager: ObservableObject {
    @Published var transcribedText: String = ""
    @Published var isRecording: Bool = false
    @Published var isAvailable: Bool = true
    @Published var errorDescription: String? = nil
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized: self.isAvailable = true
                default: self.isAvailable = false; self.errorDescription = "Speech recognition authorization was denied."
                }
            }
        }
    }

    func startRecording() {
        guard !isRecording, let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        errorDescription = nil
        
        // Clear the text at the beginning of a new recording session.
        self.transcribedText = ""
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest!.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        do { try audioEngine.start() } catch {
            self.errorDescription = "Audio engine failed to start: \(error.localizedDescription)"; return
        }
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            if let result = result {
                DispatchQueue.main.async { self?.transcribedText = result.bestTranscription.formattedString }
            }
            if error != nil || result?.isFinal == true { self?.stopRecording() }
        }
        DispatchQueue.main.async { self.isRecording = true }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        DispatchQueue.main.async { self.isRecording = false }
    }
}

// MARK: - Enums for State
enum Grade: String, CaseIterable, Identifiable {
    case kindergarten = "Kindergarten"
    case firstGrade = "1st Grade"
    case secondGrade = "2nd Grade"
    case thirdGrade = "3rd Grade"
    var id: Self { self }
}

enum ReadingMode: String, CaseIterable, Identifiable {
    case random = "Random"
    case story = "Stories"
    var id: Self { self }
}

// MARK: - Main View
struct ReadingChallengeView: View {
    
    // --- State Management ---
    @StateObject private var speechManager = SpeechRecognizerManager()
    @State private var contentData: ContentData?
    @State private var selectedGrade: Grade = .kindergarten
    @State private var selectedMode: ReadingMode = .random
    
    // --- Content State ---
    @State private var sentenceToRead = "Loading..."
    @State private var storyTitle: String? = nil
    
    // --- Story-specific State ---
    @State private var currentStory: Story? = nil
    @State private var storySentenceIndex: Int = 0
    
    // --- UI State ---
    @State private var feedbackMessage: String = ""
    @State private var isCorrect: Bool = false
    
    // --- Text-to-Speech Engine ---
    private let speechSynthesizer = AVSpeechSynthesizer()

    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.yellow.opacity(0.4), Color.purple.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer()
                
                Text("Reading Buddy").font(.largeTitle).fontWeight(.bold).foregroundColor(.blue)
                
                // --- Control Pickers ---
                VStack {
                    Picker("Mode", selection: $selectedMode) {
                        ForEach(ReadingMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    
                    Picker("Grade", selection: $selectedGrade) {
                        ForEach(Grade.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .onChange(of: selectedGrade) { _ in nextSentence() }
                .onChange(of: selectedMode) { _ in nextSentence() }

                Spacer()
                
                // --- Story Title Display ---
                if let title = storyTitle {
                    Text(title).font(.headline).foregroundColor(.secondary)
                }
                
                // --- Sentence Display with Tappable Words ---
                TappableWordsView(fullSentence: sentenceToRead) { word in speak(word: word) }
                    .padding().background(Color.white.opacity(0.7)).cornerRadius(10).padding(.horizontal)

                // --- Recording Button ---
                if !isCorrect {
                    Button(action: toggleRecording) {
                        Text(speechManager.isRecording ? "Stop Recording" : "Start Recording")
                            .font(.title).fontWeight(.semibold).foregroundColor(.white).padding()
                            .frame(maxWidth: .infinity).background(speechManager.isRecording ? Color.red : Color.green)
                            .cornerRadius(20).shadow(radius: 5)
                    }.padding(.horizontal)
                }
                
                // --- Transcription and Feedback ---
                VStack(spacing: 15) {
                    Text("What I heard:").font(.headline)
                    Text(speechManager.transcribedText.isEmpty ? "..." : speechManager.transcribedText)
                        .font(.body).foregroundColor(.secondary).italic()
                    
                    // --- Feedback Message Area ---
                    // This view now always occupies space, but is invisible when there's no message.
                    Text(feedbackMessage)
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(isCorrect ? .green : .orange)
                        .padding()
                        .frame(maxWidth: .infinity) // Ensure it takes up horizontal space
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(10)
                        .opacity(feedbackMessage.isEmpty ? 0 : 1) // Control visibility
                        .animation(.easeInOut, value: feedbackMessage.isEmpty)
                }
                
                Spacer()
                
                // --- Next/Pass Button ---
                // This view now handles all bottom button logic for a stable UI.
                BottomButtonView()
            }
            .padding()
            .onAppear(perform: loadContent)
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func BottomButtonView() -> some View {
        // This is the main button that shows after an attempt.
        let mainButton = Button(action: nextSentence) {
            Text(buttonText()).font(.title2).fontWeight(.semibold).foregroundColor(.white)
                .padding().frame(maxWidth: .infinity).background(Color.blue)
                .cornerRadius(20).shadow(radius: 5)
        }
        .disabled(speechManager.isRecording) // Disable button while recording.
        
        // This is a placeholder that only shows when no feedback is visible,
        // to prevent the layout from shifting.
        let placeholder = Color.clear.frame(height: 60)

        VStack {
            if isCorrect || !feedbackMessage.isEmpty {
                mainButton
            } else {
                placeholder
            }
        }
        .padding(.horizontal)
    }

    // MARK: - View Logic
    
    /// Determines the correct text for the bottom button based on the current state.
    private func buttonText() -> String {
        if !isCorrect {
            return "Pass"
        }

        // If we get here, isCorrect is true.
        if selectedMode == .random {
            return "Next Sentence"
        } else { // Story Mode
            if let story = currentStory, storySentenceIndex < story.sentences.count - 1 {
                return "Next Sentence" // Not the last sentence of the story.
            } else {
                return "Next Story" // It is the last sentence of the story.
            }
        }
    }

    private func toggleRecording() {
        if speechManager.isRecording {
            speechManager.stopRecording()
            validateSentence()
        } else {
            // Clear previous feedback and start a new recording attempt.
            // The transcribed text is now cleared inside the manager's startRecording() method.
            feedbackMessage = ""
            isCorrect = false
            speechManager.startRecording()
        }
    }
    
    private func validateSentence() {
        let punctuationToRemove = CharacterSet.punctuationCharacters
        
        let cleanTarget = sentenceToRead
            .lowercased()
            .components(separatedBy: punctuationToRemove)
            .joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let cleanTranscription = speechManager.transcribedText
            .lowercased()
            .components(separatedBy: punctuationToRemove)
            .joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        if cleanTarget == cleanTranscription && !cleanTarget.isEmpty {
            feedbackMessage = "Great job! That's correct!"
            isCorrect = true
        } else {
            feedbackMessage = "Not quite, try reading it again!"
            isCorrect = false
        }
    }
    
    private func loadContent() {
        guard let url = Bundle.main.url(forResource: "sentences", withExtension: "json") else {
            sentenceToRead = "Error: Missing sentences file."; return
        }
        do {
            let data = try Data(contentsOf: url)
            contentData = try JSONDecoder().decode(ContentData.self, from: data)
            nextSentence()
        } catch {
            sentenceToRead = "Error: Could not load sentences."
        }
    }
    
    private func nextSentence() {
        guard let gradeContent = contentData?.grades[selectedGrade.rawValue] else { return }
        
        if selectedMode == .story {
            if isCorrect, let story = currentStory, storySentenceIndex < story.sentences.count - 1 {
                storySentenceIndex += 1
                sentenceToRead = story.sentences[storySentenceIndex]
            } else {
                currentStory = gradeContent.stories.randomElement()
                storySentenceIndex = 0
                storyTitle = currentStory?.title
                sentenceToRead = currentStory?.sentences.first ?? "No stories found."
            }
        } else { // Random Mode
            storyTitle = nil
            currentStory = nil
            sentenceToRead = gradeContent.random.randomElement() ?? "No sentences found."
        }

        feedbackMessage = ""
        isCorrect = false
        speechManager.transcribedText = ""
    }
    
    private func speak(word: String) {
        let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
        let utterance = AVSpeechUtterance(string: cleanWord)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.8
        speechSynthesizer.speak(utterance)
    }
}


// MARK: - Tappable Words View
struct TappableWordsView: View {
    let fullSentence: String
    let onTapWord: (String) -> Void
    
    private var words: [String] { fullSentence.components(separatedBy: .whitespaces) }
    @State private var viewHeight: CGFloat = .zero

    var body: some View {
        GeometryReader { geometry in self.generateContent(in: geometry) }.frame(height: viewHeight)
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero; var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            ForEach(Array(self.words.enumerated()), id: \.offset) { index, word in
                self.item(for: word)
                    .padding([.horizontal, .vertical], 4)
                    .alignmentGuide(.leading) { d in
                        if (abs(width - d.width) > g.size.width) { width = 0; height -= d.height }
                        let result = width
                        if index == self.words.count - 1 { width = 0 } else { width -= d.width }
                        return result
                    }
                    .alignmentGuide(.top) { d in
                        let result = height
                        if index == self.words.count - 1 { height = 0 }
                        return result
                    }
            }
        }.background(viewHeightUpdater($viewHeight))
    }

    private func item(for word: String) -> some View {
        Text(word).font(.title2).fontWeight(.medium).onTapGesture { onTapWord(word) }
    }
    
    private func viewHeightUpdater(_ binding: Binding<CGFloat>) -> some View {
        return GeometryReader { geometry -> Color in
            let rect = geometry.frame(in: .local)
            DispatchQueue.main.async { binding.wrappedValue = rect.size.height }
            return .clear
        }
    }
}
