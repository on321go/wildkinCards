import SwiftUI
import Speech
import AVFoundation

// MARK: - App-Wide Enums and Models

enum AppMode: String, CaseIterable, Identifiable {
    case reading = "Reading Buddy"
    case math = "Math Buddy"
    var id: Self { self }
}

enum Grade: String, CaseIterable, Identifiable {
    case kindergarten = "Kindergarten"
    case firstGrade = "1st Grade"
    case secondGrade = "2nd Grade"
    case thirdGrade = "3rd Grade"
    var id: Self { self }
}

// MARK: - Main Content View (App Entry Point)

struct ContentView: View {
    @State private var selectedAppMode: AppMode = .reading
    
    var body: some View {
        VStack {
            Picker("App Mode", selection: $selectedAppMode) {
                ForEach(AppMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Conditionally show the selected view
            switch selectedAppMode {
            case .reading:
                ReadingChallengeView()
            case .math:
                MathChallengeView()
            }
        }
    }
}


// MARK: - ------------------ MATH BUDDY ------------------

// MARK: Math Data Structures
struct MathProblem {
    let question: String
    let answer: Int
    let num1: Int
    let num2: Int
    let operation: MathOperation
}

enum MathOperation: String {
    case add = "+"
    case subtract = "-"
    case multiply = "×"
    case divide = "÷"
}

// MARK: Problem Generator
struct ProblemGenerator {
    static func generateProblem(for grade: Grade) -> MathProblem {
        switch grade {
        case .kindergarten:
            // Addition/Subtraction with numbers up to 10
            let num1 = Int.random(in: 1...10)
            let num2 = Int.random(in: 1...num1) // Ensure subtraction result is not negative
            if Bool.random() {
                return MathProblem(question: "\(num1) + \(num2) = ?", answer: num1 + num2, num1: num1, num2: num2, operation: .add)
            } else {
                return MathProblem(question: "\(num1) - \(num2) = ?", answer: num1 - num2, num1: num1, num2: num2, operation: .subtract)
            }
            
        case .firstGrade:
            // Addition/Subtraction with numbers up to 20
            let num1 = Int.random(in: 1...20)
            let num2 = Int.random(in: 1...num1)
             if Bool.random() {
                return MathProblem(question: "\(num1) + \(num2) = ?", answer: num1 + num2, num1: num1, num2: num2, operation: .add)
            } else {
                return MathProblem(question: "\(num1) - \(num2) = ?", answer: num1 - num2, num1: num1, num2: num2, operation: .subtract)
            }
            
        case .secondGrade:
            // Two-digit addition/subtraction and simple multiplication
            if Bool.random() { // 50/50 chance of add/subtract vs multiply
                // Addition/Subtraction
                let num1 = Int.random(in: 10...99)
                let num2 = Int.random(in: 10...num1)
                if Bool.random() {
                     return MathProblem(question: "\(num1) + \(num2) = ?", answer: num1 + num2, num1: num1, num2: num2, operation: .add)
                } else {
                     return MathProblem(question: "\(num1) - \(num2) = ?", answer: num1 - num2, num1: num1, num2: num2, operation: .subtract)
                }
            } else {
                // Simple Multiplication
                let num1 = [2, 5, 10].randomElement()!
                let num2 = Int.random(in: 2...10)
                return MathProblem(question: "\(num1) × \(num2) = ?", answer: num1 * num2, num1: num1, num2: num2, operation: .multiply)
            }
            
        case .thirdGrade:
            // Multiplication and Division up to 12x12
            if Bool.random() {
                // Multiplication
                let num1 = Int.random(in: 2...12)
                let num2 = Int.random(in: 2...12)
                return MathProblem(question: "\(num1) × \(num2) = ?", answer: num1 * num2, num1: num1, num2: num2, operation: .multiply)
            } else {
                // Division (guaranteed whole number answer)
                let num2 = Int.random(in: 2...12)
                let answer = Int.random(in: 2...12)
                let num1 = num2 * answer
                return MathProblem(question: "\(num1) ÷ \(num2) = ?", answer: answer, num1: num1, num2: num2, operation: .divide)
            }
        }
    }
}

// MARK: Math Challenge View
struct MathChallengeView: View {
    @State private var selectedGrade: Grade = .kindergarten
    @State private var currentProblem: MathProblem = ProblemGenerator.generateProblem(for: .kindergarten)
    @State private var userAnswer: String = ""
    @State private var feedbackMessage: String = ""
    @State private var isCorrect: Bool = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.4), Color.green.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Grade", selection: $selectedGrade) {
                        ForEach(Grade.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: selectedGrade) { newGrade in
                        nextProblem(for: newGrade)
                    }
                    
                    ProblemVisualizerView(problem: currentProblem)
                        .padding()
                    
                    Text(currentProblem.question)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(userAnswer.isEmpty ? "?" : userAnswer)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(width: 100, height: 60)
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(10)
                    
                    Text(feedbackMessage)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(isCorrect ? .green : .orange)
                        .frame(height: 30)
                        .opacity(feedbackMessage.isEmpty ? 0 : 1)
                    
                    NumberPadView(onTap: numberPadTapped)
                    
                    BottomMathButton()
                }
                .padding()
            }
        }
    }
    
    @ViewBuilder
    private func BottomMathButton() -> some View {
        Button(action: {
            if isCorrect {
                nextProblem(for: selectedGrade)
            } else {
                checkAnswer()
            }
        }) {
            Text(isCorrect ? "Next" : "Check")
                .font(.title).fontWeight(.semibold).foregroundColor(.white).padding()
                .frame(maxWidth: .infinity).background(isCorrect ? Color.green : Color.blue)
                .cornerRadius(20).shadow(radius: 5)
        }
        .padding(.horizontal)
    }
    
    private func numberPadTapped(_ value: String) {
        if value == "del" {
            if !userAnswer.isEmpty {
                userAnswer.removeLast()
            }
        } else if userAnswer.count < 4 { // Limit answer length
            userAnswer += value
        }
    }
    
    private func checkAnswer() {
        guard let answerInt = Int(userAnswer) else {
            feedbackMessage = "Please enter a number!"
            return
        }
        
        if answerInt == currentProblem.answer {
            feedbackMessage = "Great job!"
            isCorrect = true
        } else {
            feedbackMessage = "Not quite, try again!"
            isCorrect = false
        }
    }
    
    private func nextProblem(for grade: Grade) {
        currentProblem = ProblemGenerator.generateProblem(for: grade)
        userAnswer = ""
        feedbackMessage = ""
        isCorrect = false
    }
}

// MARK: Math Helper Views
struct ProblemVisualizerView: View {
    let problem: MathProblem
    
    var body: some View {
        // Only show blocks for addition and subtraction, as they are most helpful there.
        if problem.operation == .add || problem.operation == .subtract {
            HStack(spacing: 15) {
                BlockGroupView(count: problem.num1, color: .blue)
                Text(problem.operation.rawValue).font(.largeTitle)
                BlockGroupView(count: problem.num2, color: .green)
            }
            .frame(minHeight: 80)
        } else {
            // For multiplication and division, reserve the space but don't show blocks.
            Color.clear.frame(minHeight: 80)
        }
    }
}

struct BlockGroupView: View {
    let count: Int
    let color: Color
    
    let columns: [GridItem] = Array(repeating: .init(.fixed(20)), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: 20, height: 20)
            }
        }
    }
}

struct NumberPadView: View {
    let onTap: (String) -> Void
    let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 3)
    let buttons = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "del"]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(buttons, id: \.self) { button in
                Button(action: { onTap(button) }) {
                    Text(button == "del" ? "⌫" : button)
                        .font(.title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.5))
                        .cornerRadius(10)
                        .foregroundColor(.black)
                }
                .disabled(button.isEmpty)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - ------------------ READING BUDDY ------------------

// MARK: Reading Data Structures
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

// MARK: Speech Recognizer
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
                self.isAvailable = authStatus == .authorized
            }
        }
    }

    func startRecording() {
        guard isAvailable else { return }
        transcribedText = ""
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest!.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        do { try audioEngine.start() } catch { return }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            if let result = result {
                self?.transcribedText = result.bestTranscription.formattedString
            }
            if error != nil || result?.isFinal == true {
                self?.stopRecording()
            }
        }
        isRecording = true
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
}

enum ReadingMode: String, CaseIterable, Identifiable {
    case random = "Random"
    case story = "Stories"
    var id: Self { self }
}

// MARK: Reading Challenge View
struct ReadingChallengeView: View {
    @StateObject private var speechManager = SpeechRecognizerManager()
    @State private var contentData: ContentData?
    @State private var selectedGrade: Grade = .kindergarten
    @State private var selectedMode: ReadingMode = .random
    @State private var sentenceToRead = "Loading..."
    @State private var storyTitle: String?
    @State private var currentStory: Story?
    @State private var storySentenceIndex: Int = 0
    @State private var feedbackMessage: String = ""
    @State private var isCorrect: Bool = false
    private let speechSynthesizer = AVSpeechSynthesizer()

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.yellow.opacity(0.4), Color.purple.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer()
                
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
                
                if let title = storyTitle {
                    Text(title).font(.headline).foregroundColor(.secondary)
                }
                
                TappableWordsView(fullSentence: sentenceToRead) { word in speak(word: word) }
                    .padding().background(Color.white.opacity(0.7)).cornerRadius(10).padding(.horizontal)

                if !isCorrect {
                    Button(action: toggleRecording) {
                        Text(speechManager.isRecording ? "Stop Recording" : "Start Recording")
                            .font(.title).fontWeight(.semibold).foregroundColor(.white).padding()
                            .frame(maxWidth: .infinity).background(speechManager.isRecording ? Color.red : Color.green)
                            .cornerRadius(20).shadow(radius: 5)
                    }.padding(.horizontal)
                }
                
                VStack(spacing: 15) {
                    Text("What I heard:").font(.headline)
                    Text(speechManager.transcribedText.isEmpty ? "..." : speechManager.transcribedText)
                        .font(.body).foregroundColor(.secondary).italic()
                    
                    Text(feedbackMessage)
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(isCorrect ? .green : .orange)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(10)
                        .opacity(feedbackMessage.isEmpty ? 0 : 1)
                        .animation(.easeInOut, value: feedbackMessage.isEmpty)
                }
                
                Spacer()
                BottomReadingButtonView()
            }
            .padding()
            .onAppear(perform: loadContent)
        }
    }
    
    @ViewBuilder
    private func BottomReadingButtonView() -> some View {
        let mainButton = Button(action: nextSentence) {
            Text(buttonText()).font(.title2).fontWeight(.semibold).foregroundColor(.white)
                .padding().frame(maxWidth: .infinity).background(Color.blue)
                .cornerRadius(20).shadow(radius: 5)
        }
        .disabled(speechManager.isRecording)
        
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

    private func buttonText() -> String {
        if !isCorrect { return "Pass" }
        if selectedMode == .random { return "Next Sentence" }
        else {
            if let story = currentStory, storySentenceIndex < story.sentences.count - 1 {
                return "Next Sentence"
            } else {
                return "Next Story"
            }
        }
    }

    private func toggleRecording() {
        if speechManager.isRecording {
            speechManager.stopRecording()
            validateSentence()
        } else {
            feedbackMessage = ""
            isCorrect = false
            speechManager.startRecording()
        }
    }
    
    private func validateSentence() {
        let punctuation = CharacterSet.punctuationCharacters
        let cleanTarget = sentenceToRead.lowercased().components(separatedBy: punctuation).joined().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let cleanTranscription = speechManager.transcribedText.lowercased().components(separatedBy: punctuation).joined().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        
        if cleanTarget == cleanTranscription && !cleanTarget.isEmpty {
            feedbackMessage = "Great job! That's correct!"; isCorrect = true
        } else {
            feedbackMessage = "Not quite, try reading it again!"; isCorrect = false
        }
    }
    
    private func loadContent() {
        guard let url = Bundle.main.url(forResource: "sentences", withExtension: "json") else { return }
        do {
            let data = try Data(contentsOf: url)
            contentData = try JSONDecoder().decode(ContentData.self, from: data)
            nextSentence()
        } catch {}
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
        } else {
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

// MARK: Reading Helper Views
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
