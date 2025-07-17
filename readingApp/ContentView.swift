import SwiftUI
import Speech
import AVFoundation

// MARK: - App-Wide Data & State Management

/// An enum to represent the main tabs of the app.
enum AppTab {
    case challenges
    case cards
}

/// A central manager for the app's state, including user progress and card collection.
@MainActor
class AppManager: ObservableObject {
    // MARK: Published Properties
    @Published var selectedTab: AppTab = .challenges
    @Published var correctAnswerCount = 0
    @Published var newCardsEarned = 0
    @Published var showCardEarnedAlert = false
    
    // Properties from the original CardStore
    @Published var collectedCards: [AnimalCard] = []
    @Published var cardToUnwrap: AnimalCard? = nil
    
    // MARK: Data Pools for Card Generation
    private var wildkinDeck: [WildkinData] = []
    private var superPowerPool: [Power] = []
    private var switchAbilityPool: [Power] = []
    
    // Archetype-Specific Power Pools
    private var guardianSuperPowers: [Power] = []
    private var strikerSuperPowers: [Power] = []
    private var supporterSuperPowers: [Power] = []
    private var guardianSwitchAbilities: [Power] = []
    private var strikerSwitchAbilities: [Power] = []
    private var supporterSwitchAbilities: [Power] = []

    init() {
        loadAllCardData()
    }
    
    /// Increments the user's score and checks if they've earned a new card.
    func incrementScore() {
        correctAnswerCount += 1
        if correctAnswerCount % 15 == 0 && correctAnswerCount > 0 {
            newCardsEarned += 1
            showCardEarnedAlert = true
        }
    }
    
    /// Generates a new card to be unwrapped.
    func prepareNewCardForUnwrapping() {
        guard cardToUnwrap == nil, newCardsEarned > 0, let baseAnimal = wildkinDeck.randomElement() else { return }
        
        newCardsEarned -= 1
        
        // 1. Determine Rarity
        let rarityRoll = Double.random(in: 0...1)
        var rarity: Rarity = .normal
        if rarityRoll > 0.95 { rarity = .epic }
        else if rarityRoll > 0.70 { rarity = .rare }
        
        // 2. Apply stat modifications based on rarity
        var finalStamina = baseAnimal.stamina
        var finalStrength = baseAnimal.strength
        
        switch rarity {
        case .rare: finalStamina += 1
        case .epic: finalStamina += 2; finalStrength += 1
        case .normal: break
        }
        
        // 3. Assign Powers based on Archetype
        var assignedSuperPower: Power?
        var assignedSwitchAbility: Power?

        switch baseAnimal.archetype {
        case "Guardian":
            assignedSuperPower = guardianSuperPowers.randomElement()
            assignedSwitchAbility = guardianSwitchAbilities.randomElement()
        case "Striker":
            assignedSuperPower = strikerSuperPowers.randomElement()
            assignedSwitchAbility = strikerSwitchAbilities.randomElement()
        case "Supporter":
            assignedSuperPower = supporterSuperPowers.randomElement()
            assignedSwitchAbility = supporterSwitchAbilities.randomElement()
        default: break
        }
        
        // 4. Create the final AnimalCard instance
        let newCard = AnimalCard(
            name: baseAnimal.name,
            archetype: baseAnimal.archetype,
            rarity: rarity,
            stamina: finalStamina,
            strength: finalStrength,
            shield: baseAnimal.shield,
            speed: baseAnimal.speed,
            superPower: assignedSuperPower,
            switchAbility: assignedSwitchAbility
        )
        
        self.cardToUnwrap = newCard
    }
    
    /// Moves the unwrapped card to the user's collection.
    func addCardToCollection() {
        guard let newCard = cardToUnwrap else { return }
        withAnimation(.spring()) {
            collectedCards.append(newCard)
            cardToUnwrap = nil
        }
    }
    
    // MARK: - Data Loading and Parsing
    private func loadAllCardData() {
        wildkinDeck = load("wildkins.json")
        superPowerPool = load("super_powers.json")
        switchAbilityPool = load("switch_abilities.json")
        mapPowersToArchetypes()
    }
    
    private func mapPowersToArchetypes() {
        guardianSuperPowers = superPowerPool.filter { [201, 202, 203].contains($0.id) }
        guardianSwitchAbilities = switchAbilityPool.filter { [101, 102].contains($0.id) }
        strikerSuperPowers = superPowerPool.filter { [204, 205].contains($0.id) }
        strikerSwitchAbilities = switchAbilityPool.filter { [103, 104, 105].contains($0.id) }
        supporterSuperPowers = superPowerPool.filter { [206, 207].contains($0.id) }
        supporterSwitchAbilities = switchAbilityPool.filter { [106, 107].contains($0.id) }
    }
    
    private func load<T: Decodable>(_ filename: String) -> T {
        let data: Data
        guard let file = Bundle.main.url(forResource: filename, withExtension: nil) else {
            fatalError("Couldn't find \(filename) in main bundle.")
        }
        do {
            data = try Data(contentsOf: file)
        } catch {
            fatalError("Couldn't load \(filename) from main bundle:\n\(error)")
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            fatalError("Couldn't parse \(filename) as \(T.self):\n\(error)")
        }
    }
}

// MARK: - Main App View (Entry Point)
struct ContentView: View {
    @StateObject private var appManager = AppManager()

    var body: some View {
        ZStack {
            TabView(selection: $appManager.selectedTab) {
                ChallengesView()
                    .tabItem {
                        Label("Challenges", systemImage: "gamecontroller.fill")
                    }
                    .tag(AppTab.challenges)
                
                CardCollectionView()
                    .tabItem {
                        Label("My Cards", systemImage: "sparkles.rectangle.stack.fill")
                    }
                    .tag(AppTab.cards)
                    .badge(appManager.newCardsEarned > 0 ? "★" : nil)
            }
            .environmentObject(appManager)
            
            // Pop-up alert for earning a new card
            if appManager.showCardEarnedAlert {
                CardEarnedPopup(onDismiss: {
                    appManager.showCardEarnedAlert = false
                    appManager.selectedTab = .cards // Switch to the cards tab
                })
            }
        }
    }
}

// MARK: - Popup View
struct CardEarnedPopup: View {
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.yellow)
            
            Text("You've Earned a New Card!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Go to your collection to reveal it.")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Button(action: onDismiss) {
                Text("Awesome!")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.gradient)
                    .cornerRadius(15)
            }
        }
        .padding(30)
        .background(.regularMaterial)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.4))
        .ignoresSafeArea()
    }
}


// MARK: - ------------------ CHALLENGES CONTAINER VIEW ------------------
enum AppMode: String, CaseIterable, Identifiable {
    case reading = "Reading Buddy"
    case math = "Math Buddy"
    var id: Self { self }
}

struct ChallengesView: View {
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
            let num1 = Int.random(in: 1...10)
            let num2 = Int.random(in: 1...num1)
            if Bool.random() {
                return MathProblem(question: "\(num1) + \(num2) = ?", answer: num1 + num2, num1: num1, num2: num2, operation: .add)
            } else {
                return MathProblem(question: "\(num1) - \(num2) = ?", answer: num1 - num2, num1: num1, num2: num2, operation: .subtract)
            }
            
        case .firstGrade:
            let num1 = Int.random(in: 1...20)
            let num2 = Int.random(in: 1...num1)
            if Bool.random() {
                return MathProblem(question: "\(num1) + \(num2) = ?", answer: num1 + num2, num1: num1, num2: num2, operation: .add)
            } else {
                return MathProblem(question: "\(num1) - \(num2) = ?", answer: num1 - num2, num1: num1, num2: num2, operation: .subtract)
            }
            
        case .secondGrade:
            if Bool.random() {
                let num1 = Int.random(in: 10...99)
                let num2 = Int.random(in: 10...num1)
                if Bool.random() {
                    return MathProblem(question: "\(num1) + \(num2) = ?", answer: num1 + num2, num1: num1, num2: num2, operation: .add)
                } else {
                    return MathProblem(question: "\(num1) - \(num2) = ?", answer: num1 - num2, num1: num1, num2: num2, operation: .subtract)
                }
            } else {
                let num1 = [2, 5, 10].randomElement()!
                let num2 = Int.random(in: 2...10)
                return MathProblem(question: "\(num1) × \(num2) = ?", answer: num1 * num2, num1: num1, num2: num2, operation: .multiply)
            }
            
        case .thirdGrade:
            if Bool.random() {
                let num1 = Int.random(in: 2...12)
                let num2 = Int.random(in: 2...12)
                return MathProblem(question: "\(num1) × \(num2) = ?", answer: num1 * num2, num1: num1, num2: num2, operation: .multiply)
            } else {
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
    @EnvironmentObject var appManager: AppManager
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
        } else if userAnswer.count < 4 {
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
            appManager.incrementScore() // Notify the manager of a correct answer
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
        if problem.operation == .add || problem.operation == .subtract {
            HStack(spacing: 15) {
                BlockGroupView(count: problem.num1, color: .blue)
                Text(problem.operation.rawValue).font(.largeTitle)
                BlockGroupView(count: problem.num2, color: .green)
            }
            .frame(minHeight: 80)
        } else {
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
enum Grade: String, CaseIterable, Identifiable {
    case kindergarten = "Kindergarten"
    case firstGrade = "1st Grade"
    case secondGrade = "2nd Grade"
    case thirdGrade = "3rd Grade"
    var id: Self { self }
}

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
    @EnvironmentObject var appManager: AppManager
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
            appManager.incrementScore() // Notify the manager of a correct answer
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


// MARK: - ------------------ CARD COLLECTION ------------------

// MARK: Card Data Models
struct WildkinData: Codable, Identifiable {
    let id: Int
    let name: String
    let archetype: String
    let stamina: Int
    let strength: Int
    let shield: Int
    let speed: Int
}

struct Power: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let description: String
}

enum Rarity: String, Codable {
    case normal
    case rare
    case epic
}

struct AnimalCard: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let archetype: String
    let rarity: Rarity
    
    // Final stats after rarity modifications
    let stamina: Int
    let strength: Int
    let shield: Int
    let speed: Int
    
    // Assigned powers
    let superPower: Power?
    let switchAbility: Power?
    
    /// The name of the image asset for the card, adjusted for rarity.
    var imageName: String {
        switch rarity {
        case .epic:
            // Assumes you have assets named like "dolphinEpic.png"
            return name.lowercased() + "Epic"
        case .normal, .rare:
            return name.lowercased()
        }
    }
}

// MARK: Card Collection Main View
struct CardCollectionView: View {
    @EnvironmentObject var appManager: AppManager
    @State private var showFireworks = false
    @State private var selectedCard: AnimalCard? = nil
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Text("Animal Cards")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 40)
                
                unwrappingZone.frame(maxHeight: .infinity)
                
                CollectedCardsGridView(
                    cards: appManager.collectedCards,
                    onCardTapped: { card in
                        withAnimation(.spring()) { selectedCard = card }
                    }
                )
            }
            
            if showFireworks {
                FireworksView().ignoresSafeArea().allowsHitTesting(false)
            }
            
            if let card = selectedCard {
                CardDetailView(card: card, onDismiss: {
                    withAnimation(.easeOut) { selectedCard = nil }
                })
            }
        }
    }
    
    private var unwrappingZone: some View {
        VStack {
            if let card = appManager.cardToUnwrap {
                UnwrapView(
                    card: card,
                    onReveal: { showFireworks = true },
                    onComplete: {
                        appManager.addCardToCollection()
                        showFireworks = false
                    }
                )
            } else {
                Button(action: {
                    withAnimation { appManager.prepareNewCardForUnwrapping() }
                }) {
                    VStack {
                        if appManager.newCardsEarned > 0 {
                            Text("Reveal New Card!")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                        } else {
                            Text("Answer questions to earn cards!")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(appManager.newCardsEarned > 0 ? Color.green : Color.gray)
                    .cornerRadius(16)
                    .shadow(radius: 8)
                }
                .disabled(appManager.newCardsEarned <= 0)
                .padding(.top, 100)
            }
        }
    }
}


// MARK: - Unwrap Animation View
struct UnwrapView: View {
    let card: AnimalCard
    let onReveal: () -> Void
    let onComplete: () -> Void
    
    @State private var isWrapped = true
    @State private var isShaking = false
    @State private var showParticles = false
    @State private var showRevealedCard = false
    @State private var showRarityText = false

    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 280

    var body: some View {
        VStack {
            if showRarityText {
                Text(card.rarity.rawValue.uppercased() + "!")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(card.rarity == .epic ? .purple.opacity(0.8) : .yellow.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 5)
                    .transition(.asymmetric(insertion: .scale.animation(.spring()), removal: .opacity))
                    .padding(.bottom, 10)
            }
            
            ZStack {
                if showRevealedCard {
                    AnimalCardView(card: card)
                        .frame(width: cardWidth, height: cardHeight)
                        .transition(.scale.animation(.spring(response: 0.4, dampingFraction: 0.6)))
                        .onTapGesture { onComplete() }
                }

                if isWrapped {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.purple.gradient)
                            .frame(width: cardWidth, height: cardHeight)
                            .shadow(color: .black.opacity(0.4), radius: 10, y: 10)
                        
                        Image(systemName: "questionmark.diamond.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.8))
                        
                        FairyDustView()
                            .frame(width: cardWidth, height: cardHeight)
                            .allowsHitTesting(false)
                    }
                    .rotationEffect(.degrees(isShaking ? 0 : 4))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true)) {
                            isShaking = true
                        }
                    }
                    .onTapGesture { triggerUnwrapAnimation() }
                }
                
                if showParticles {
                    ParticleEffectView()
                        .frame(width: cardWidth, height: cardHeight)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 400)
    }
    
    private func triggerUnwrapAnimation() {
        withAnimation(.easeOut(duration: 0.2)) { isWrapped = false }
        showParticles = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showRevealedCard = true
            onReveal()
            if card.rarity != .normal {
                showRarityText = true
            }
        }
    }
}


// MARK: - Reusable Card and Collection Views
struct AnimalCardView: View {
    let card: AnimalCard
    
    var body: some View {
        GeometryReader { proxy in
            let cardWidth = proxy.size.width
            let scaledFontSize = cardWidth * 0.08

            ZStack(alignment: .bottom) {
                Image(card.imageName)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(cardWidth * 0.06)
                    .padding(cardWidth * 0.025)

                VStack(spacing: cardWidth * 0.02) {
                    HStack(spacing: cardWidth * 0.03) {
                        HStack(spacing: cardWidth * 0.001) {
                            Image(systemName: "heart.fill").foregroundColor(.red)
                            Text("\(card.stamina)")
                        }
                        HStack(spacing: cardWidth * 0.001) {
                            Image(systemName: "shield.fill").foregroundColor(.cyan)
                            Text("\(card.shield)")
                        }
                        Text("💥\(card.strength)")
                        HStack(spacing: cardWidth * 0.001) {
                            Image(systemName: "bolt.fill").foregroundColor(.yellow)
                            Text("\(card.speed)")
                        }
                    }
                    .font(.system(size: scaledFontSize, weight: .bold))
                    .padding(cardWidth * 0.04)
                    .background(.black.opacity(0.5))
                    .cornerRadius(cardWidth * 0.05)
                    .padding(.bottom, cardWidth * 0.05)
                }
                .foregroundColor(.white)
                
                if card.rarity == .rare {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: scaledFontSize * 1.5))
                        .shadow(radius: 3)
                        .position(x: cardWidth * 0.15, y: cardWidth * 0.15)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct CollectedCardsGridView: View {
    let cards: [AnimalCard]
    let onCardTapped: (AnimalCard) -> Void
    
    private let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 3)
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("My Collection")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal)
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(cards) { card in
                        AnimalCardView(card: card)
                            .aspectRatio(2.5/3.5, contentMode: .fit)
                            .id(card.id)
                            .onTapGesture { onCardTapped(card) }
                    }
                }
                .padding()
            }
        }
        .frame(height: 300)
        .background(Color.black.opacity(0.2))
        .cornerRadius(20, corners: [.topLeft, .topRight])
    }
}

struct CardDetailView: View {
    let card: AnimalCard
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture(perform: onDismiss)
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        AnimalCardView(card: card)
                            .frame(width: 300, height: 420)
                            .padding(.top)
                            
                        VStack(spacing: 15) {
                            if let switchAbility = card.switchAbility {
                                PowerDetailRow(title: "Switch Ability", power: switchAbility)
                            }
                            
                            if let superPower = card.superPower {
                                PowerDetailRow(title: "Super Power", power: superPower)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(20)
                        .padding(.horizontal)
                    }
                }
                
                VStack {
                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .font(.headline.bold())
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.gradient)
                            .cornerRadius(15)
                    }
                    .padding()
                }
                .background(Color(UIColor.systemBackground))
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.85)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct PowerDetailRow: View {
    let title: String
    let power: Power
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .foregroundColor(.gray)
            
            Text(power.name)
                .font(.title3.bold())
                .foregroundColor(.black)
            
            Text(power.description)
                .font(.body)
                .foregroundColor(.black.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


// MARK: - Reusable Components & Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}


// MARK: - Animation Effects

struct DustParticle: Identifiable {
    let id = UUID()
    let creationDate = Date()
    let position: CGPoint
    let color: Color
    let xDrift: CGFloat
    let yDrift: CGFloat
}

struct FairyDustView: View {
    @State private var particles: [DustParticle] = []
    private let timer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()
    private let colors: [Color] = [.yellow, .white, .cyan, Color(red: 1, green: 0.3, blue: 0.8)]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    let now = timeline.date
                    for particle in particles {
                        let timeAlive = now.timeIntervalSince(particle.creationDate)
                        guard timeAlive <= 1.5 else { continue }
                        let fadeProgress = timeAlive / 1.5
                        let newX = particle.position.x + (particle.xDrift * fadeProgress)
                        let newY = particle.position.y + (particle.yDrift * fadeProgress)
                        context.opacity = 1.0 - fadeProgress
                        context.fill(Path(ellipseIn: CGRect(x: newX, y: newY, width: 5, height: 5)), with: .color(particle.color))
                    }
                }
            }
            .onReceive(timer) { _ in
                let side = Int.random(in: 0...3)
                var position: CGPoint
                var xDrift: CGFloat
                var yDrift: CGFloat
                switch side {
                case 0: // Top edge
                    position = CGPoint(x: .random(in: 0...size.width), y: 0)
                    xDrift = .random(in: -20...20)
                    yDrift = .random(in: -60 ... -20)
                case 1: // Right edge
                    position = CGPoint(x: 60, y: .random(in: 0...size.height))
                    xDrift = .random(in: 160 ... 190)
                    yDrift = .random(in: 20...20)
                case 2: // Bottom edge
                    position = CGPoint(x: .random(in: 0...size.width), y: 290)
                    xDrift = .random(in: -20...20)
                    yDrift = .random(in: -60 ... -20)
                default: // Left edge
                    position = CGPoint(x: 0, y: .random(in: 0...size.height))
                    xDrift = .random(in: -60 ... -20)
                    yDrift = .random(in: -20...20)
                }
                particles.append(DustParticle(position: position, color: colors.randomElement()!, xDrift: xDrift, yDrift: yDrift))
                particles.removeAll { p in Date.now.timeIntervalSince(p.creationDate) > 1.5 }
            }
        }
    }
}

struct Firework: Identifiable {
    let id = UUID()
    let creationDate: Date = .now
    let position: CGPoint
    let color: Color
}

struct FireworksView: View {
    @State private var fireworks: [Firework] = []
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
    private let colors: [Color] = [.yellow, .red, .blue, .white, .cyan, .purple, .orange]

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date
                    for firework in fireworks {
                        let timeAlive = now.timeIntervalSince(firework.creationDate)
                        guard timeAlive <= 2.0 else { continue }
                        let explosionProgress = timeAlive / 2.0
                        for _ in 0..<30 {
                            let angle = Double.random(in: 0...(2 * .pi))
                            let distance = Double.random(in: 0...1) * (size.width / 4) * explosionProgress
                            let particleX = firework.position.x + cos(angle) * distance
                            let particleY = firework.position.y + sin(angle) * distance
                            context.opacity = max(0, 1.0 - (explosionProgress * 1.5))
                            context.fill(Path(ellipseIn: CGRect(x: particleX - 2.5, y: particleY - 2.5, width: 5, height: 5)), with: .color(firework.color))
                        }
                    }
                }
            }
            .onReceive(timer) { _ in
                let newFirework = Firework(position: CGPoint(x: .random(in: (proxy.size.width*0.2)...(proxy.size.width*0.8)), y: .random(in: (proxy.size.height*0.2)...(proxy.size.height*0.5))), color: colors.randomElement()!)
                fireworks.append(newFirework)
                fireworks.removeAll { fw in Date.now.timeIntervalSince(fw.creationDate) > 2.0 }
            }
        }
    }
}

struct ParticleEffectView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<50 {
                    let id = Double(i)
                    let progress = (now - id * 0.01).truncatingRemainder(dividingBy: 1.5) / 1.5
                    let angle = Angle.degrees(id * 25).radians
                    let distance = progress * size.width * 0.8
                    let x = size.width / 2 + cos(angle) * distance
                    let y = size.height / 2 + sin(angle) * distance
                    context.opacity = 1.0 - progress
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 15, height: 15)), with: .color(particleColors[i % particleColors.count]))
                }
            }
        }
    }
    private var particleColors: [Color] = [.yellow, .orange, .red, .pink, .cyan]
}


// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
