import SwiftUI
import Speech
import AVFoundation
import CoreData
import MultipeerConnectivity
import Combine


// MARK: - Persistence Controller (Core Data & CloudKit)
// Manages the setup of the Core Data stack with iCloud synchronization.
struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        // The container name must match your .xcdatamodeld file name.
        container = NSPersistentCloudKitContainer(name: "wildkin")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // This is a critical error and should be handled gracefully in a production app.
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        // Automatically merge changes from other contexts (like background updates from iCloud).
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

class DataManager {
    static let shared = DataManager()
    
    // Properties are now initialized directly using the static load method.
    let superPowers: [Power] = DataManager.load("super_powers.json")
    let switchAbilities: [Power] = DataManager.load("switch_abilities.json")
    
    // The initializer is now empty as properties are initialized at declaration.
    private init() {}
    
    func power(byName name: String?) -> Power? {
        guard let name = name else { return nil }
        if let power = superPowers.first(where: { $0.name == name }) {
            return power
        }
        if let power = switchAbilities.first(where: { $0.name == name }) {
            return power
        }
        return nil
    }
    
    // The load method is now static to be callable during property initialization.
    private static func load<T: Decodable>(_ filename: String) -> T {
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

// MARK: - App-Wide Data & State Management

/// Enum to represent the main tabs of the unified app.
enum AppTab {
    case challenges
    case cards
    case battle // New tab for the battle mode.
}

/// The central manager for the app's state, handling everything from earning cards to initiating battles.
@MainActor
class AppManager: ObservableObject {
    // MARK: Published Properties
    @Published var selectedTab: AppTab = .challenges
    @Published var correctAnswerCount = 0
    @Published var newCardsEarned = 0
    @Published var showCardEarnedAlert = false
    @Published var cardToUnwrap: AnimalCard? = nil
    
    // Core Data context for saving and fetching cards.
    private let viewContext: NSManagedObjectContext
    
    // MARK: Data Pools for New Card Generation
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

    init(context: NSManagedObjectContext) {
        self.viewContext = context
        loadAllCardData()
    }
    
    /// Increments the user's score and checks if they've earned a new card.
    func incrementScore() {
        correctAnswerCount += 1
        if correctAnswerCount % 5 == 0 && correctAnswerCount > 0 {
            newCardsEarned += 1
            showCardEarnedAlert = true
        }
    }
    
    /// Generates a new `AnimalCard` object to be unwrapped by the user.
    func prepareNewCardForUnwrapping() {
        guard cardToUnwrap == nil, newCardsEarned > 0, let baseAnimal = wildkinDeck.randomElement() else { return }
        
        newCardsEarned -= 1
        
        let rarityRoll = Double.random(in: 0...1)
        var rarity: Rarity = .normal
        if rarityRoll > 0.95 { rarity = .epic }
        else if rarityRoll > 0.70 { rarity = .rare }
        
        var finalStamina = baseAnimal.stamina
        var finalStrength = baseAnimal.strength
        
        switch rarity {
        case .rare: finalStamina += 1
        case .epic: finalStamina += 2; finalStrength += 1
        case .normal: break
        }
        
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
    
    /// Saves the newly unwrapped card to the user's collection in Core Data.
    func addCardToCollection() {
        guard let newCard = cardToUnwrap else { return }
        
        let cardEntity = Card(context: viewContext)
        cardEntity.id = newCard.id
        cardEntity.name = newCard.name
        cardEntity.archetype = newCard.archetype
        cardEntity.rarity = newCard.rarity.rawValue
        cardEntity.stamina = Int16(newCard.stamina)
        cardEntity.strength = Int16(newCard.strength)
        cardEntity.shield = Int16(newCard.shield)
        cardEntity.speed = Int16(newCard.speed)
        cardEntity.superPowerName = newCard.superPower?.name
        cardEntity.superPowerDescription = newCard.superPower?.description
        cardEntity.switchAbilityName = newCard.switchAbility?.name
        cardEntity.switchAbilityDescription = newCard.switchAbility?.description
        cardEntity.timestamp = Date()
        
        do {
            try viewContext.save()
            withAnimation(.spring()) {
                cardToUnwrap = nil
            }
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
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
    @EnvironmentObject var appManager: AppManager

    var body: some View {
        ZStack {
            // The TabView is the primary navigation for the app.
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
                
                // The new Battle tab, which leads to the multiplayer lobby.
                NavigationStack {
                    LobbyView()
                }
                .tabItem {
                    Label("Battle", systemImage: "bolt.horizontal.icloud.fill")
                }
                .tag(AppTab.battle)
            }
            
            // Pop-up alert for earning a new card.
            if appManager.showCardEarnedAlert {
                CardEarnedPopup(onDismiss: {
                    appManager.showCardEarnedAlert = false
                    appManager.selectedTab = .cards // Switch to the cards tab to unwrap.
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


// MARK: - ------------------ CARD COLLECTION & DATA MODELS ------------------

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

/// Represents the mechanical effect of a power in the game.
struct PowerEffect: Codable, Equatable, Hashable {
    let type: String
    let target: String
    let value: Int
}

/// Represents a Super Power or Switch Ability.
struct Power: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let description: String
    // This new property will hold the game mechanic data from the JSON.
    // It's optional for flexibility.
    let effect: PowerEffect?
}

enum Rarity: String, Codable, CaseIterable {
    case normal
    case rare
    case epic
}

// This is the primary model for displaying and handling cards throughout the app.
// It is now CODABLE to be sent over the multiplayer connection and includes
// new properties for in-battle status effects.
struct AnimalCard: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let name: String
    let archetype: String
    let rarity: Rarity
    let stamina: Int
    let strength: Int
    let shield: Int
    let speed: Int
    let superPower: Power?
    let switchAbility: Power?
    
    // Battle-specific state properties
    var currentHP: Int
    var isSuperPowerUsed: Bool = false
    var isActive: Bool = false
    var attackBuff: Int = 0
    
    // NEW: Properties for Super Power & Switch Ability effects
    var isImmune: Bool = false         // For "Burrow" (Turn-based)
    var isInvincible: Bool = false     // For "Invincible" (Lasts until hit)
    var reflectsDamage: Int = 0        // For "Reflect Damage", stores percentage
    var temporaryShields: Int = 0      // For "Rock Wall" (Turn-based)
    
    var isKnockedOut: Bool { currentHP <= 0 }
    
    // Initializer to convert a Core Data 'Card' object into a displayable 'AnimalCard'
    init(cardEntity: Card) {
        self.id = cardEntity.id ?? UUID()
        self.name = cardEntity.name ?? "Unknown"
        self.archetype = cardEntity.archetype ?? "Unknown"
        self.rarity = Rarity(rawValue: cardEntity.rarity ?? "normal") ?? .normal
        self.stamina = Int(cardEntity.stamina)
        self.strength = Int(cardEntity.strength)
        self.shield = Int(cardEntity.shield)
        self.speed = Int(cardEntity.speed)
        
        // The Power structs are created using the JSON data loaded at app start.
        // We find the matching power by name.
        self.superPower = DataManager.shared.power(byName: cardEntity.superPowerName)
        self.switchAbility = DataManager.shared.power(byName: cardEntity.switchAbilityName)
        
        self.currentHP = Int(cardEntity.stamina)
    }
    
    // Initializer for generating a new card before it's saved
    init(name: String, archetype: String, rarity: Rarity, stamina: Int, strength: Int, shield: Int, speed: Int, superPower: Power?, switchAbility: Power?) {
        self.id = UUID()
        self.name = name
        self.archetype = archetype
        self.rarity = rarity
        self.stamina = stamina
        self.strength = strength
        self.shield = shield
        self.speed = speed
        self.superPower = superPower
        self.switchAbility = switchAbility
        
        self.currentHP = stamina
    }
    
    var imageName: String {
        switch rarity {
        case .epic: return name.lowercased() + "Epic"
        case .normal, .rare: return name.lowercased()
        }
    }
    
    var rarityColor: Color {
        switch rarity {
        case .normal: return .gray
        case .rare: return .blue
        case .epic: return .purple
        }
    }
}

// MARK: Card Collection Main View
struct CardCollectionView: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(\.managedObjectContext) private var viewContext

    // Fetch cards from Core Data and sort them by timestamp
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Card.timestamp, ascending: true)],
        animation: .default)
    private var cards: FetchedResults<Card>
    
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
                
                // Pass the fetched Core Data results to the grid view
                CollectedCardsGridView(
                    cards: cards, // Use the @FetchRequest result
                    onCardTapped: { cardEntity in
                        // Convert the Core Data entity to a displayable struct
                        withAnimation(.spring()) { selectedCard = AnimalCard(cardEntity: cardEntity) }
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
                } else if card.rarity == .epic {
                     Image(systemName: "crown.fill")
                        .foregroundColor(.purple)
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
    // This view now accepts FetchedResults<Card> directly
    let cards: FetchedResults<Card>
    let onCardTapped: (Card) -> Void
    
    private let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 3)
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("My Collection")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal)
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(cards) { cardEntity in
                        // Convert the Core Data entity to a displayable struct for the view
                        AnimalCardView(card: AnimalCard(cardEntity: cardEntity))
                            .aspectRatio(2.5/3.5, contentMode: .fit)
                            .id(cardEntity.id)
                            .onTapGesture { onCardTapped(cardEntity) }
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
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .environmentObject(AppManager(context: PersistenceController.shared.container.viewContext))
            .environmentObject(MultipeerConnectionManager.sharedInstance)
    }
}


// MARK: - ------------------ Battle Logic and Views ------------------

// MARK: - Battle Game State Models
// These models define the dynamic state of a live match.

/// Represents a player in the battle, including their team of cards.
struct Player: Identifiable, Equatable, Codable {
    let id: Int
    var name: String
    var team: [AnimalCard]
    
    var activeWildkin: AnimalCard? {
        team.first { $0.isActive && !$0.isKnockedOut }
    }
    
    var benchedWildkin: [AnimalCard] {
        team.filter { !$0.isActive && !$0.isKnockedOut }
    }
    
    var hasLost: Bool {
        team.allSatisfy { $0.isKnockedOut }
    }
}

/// The single source of truth for the entire battle state, synchronized between players.
struct GameState: Codable, Equatable {
    var players: [Player]
    var currentPlayerId: Int = 1
    var turnNumber: Int = 1
    var gameLog: [String] = ["Match Started!"]
    var winner: Player? = nil
    var isGameOver: Bool { winner != nil }
    
    /// This property holds the information for a pending action that requires a player to select a target.
    /// When this is non-nil, the game pauses until the specified player provides input.
    var pendingTargetInfo: TargetingInfo? = nil
}

/// Encapsulates all information needed for a pending targeting action.
/// This struct is now Codable to be included in the synchronized GameState.
struct TargetingInfo: Identifiable, Codable, Equatable {
    let id = UUID()
    let power: Power
    let sourceCard: AnimalCard
    let playerIndex: Int // The index of the player who needs to select a target.
}

// Defines the actions that can be sent between devices in a multiplayer match.

enum GameAction: Codable, Equatable {
    case sendTeam([AnimalCard])
    case syncGameState(GameState)
    case concede
    
    // Custom Equatable conformance for comparing actions.
    static func == (lhs: GameAction, rhs: GameAction) -> Bool {
        switch (lhs, rhs) {
        case (.sendTeam(let a), .sendTeam(let b)):
            return a == b
        case (.syncGameState(let a), .syncGameState(let b)):
            return a == b
        case (.concede, .concede):
            return true
        default:
            return false
        }
    }
}

struct MatchConfig: Identifiable, Hashable { let id = UUID(); let playerTeam: [AnimalCard]; let opponentTeam: [AnimalCard]; let isMultiplayer: Bool }


// MARK: - Multiplayer Connection Manager
// Manages the discovery, connection, and data transmission between devices using MultipeerConnectivity.
class MultipeerConnectionManager: NSObject, ObservableObject {
    static let sharedInstance = MultipeerConnectionManager()
    
    @Published var availablePeers: Set<MCPeerID> = []
    @Published var connectedPeer: MCPeerID?
    @Published var receivedAction: GameAction?
    @Published var isConnected: Bool = false
    
    var myPeerId: MCPeerID
    var currentUsername: String {
        let username = UsernameManager.shared.username
        return username.isEmpty ? UIDevice.current.name : username
    }
    
    private let serviceType = "wildkin-battle"
    private var session: MCSession
    private var serviceAdvertiser: MCNearbyServiceAdvertiser
    private var serviceBrowser: MCNearbyServiceBrowser
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        let peerID = MCPeerID(displayName: UsernameManager.shared.username.isEmpty ? UIDevice.current.name : UsernameManager.shared.username)
        self.myPeerId = peerID
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        self.serviceBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        
        super.init()
        
        self.session.delegate = self
        self.serviceAdvertiser.delegate = self
        self.serviceBrowser.delegate = self
        
        start()
    }
    
    deinit {
        stop()
    }
    
    func start() {
        serviceAdvertiser.startAdvertisingPeer()
        serviceBrowser.startBrowsingForPeers()
    }
    
    func stop() {
        serviceAdvertiser.stopAdvertisingPeer()
        serviceBrowser.stopBrowsingForPeers()
        session.disconnect()
    }
    
    func invitePeer(_ peerID: MCPeerID) {
        serviceBrowser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }
    
    func send(action: GameAction) {
        guard !session.connectedPeers.isEmpty else { return }
        
        do {
            let data = try JSONEncoder().encode(action)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Error sending action: \(error.localizedDescription)")
        }
    }
    
    func resetForNewUsername() {
        stop()
        
        let newPeerID = MCPeerID(displayName: self.currentUsername)
        self.myPeerId = newPeerID
        self.session = MCSession(peer: newPeerID, securityIdentity: nil, encryptionPreference: .required)
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: newPeerID, discoveryInfo: nil, serviceType: serviceType)
        self.serviceBrowser = MCNearbyServiceBrowser(peer: newPeerID, serviceType: serviceType)
        
        self.session.delegate = self
        self.serviceAdvertiser.delegate = self
        self.serviceBrowser.delegate = self
        
        start()
    }
}

// MARK: - Delegate Conformance for MultipeerConnectivity
extension MultipeerConnectionManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async { self.availablePeers.insert(peerID) }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.availablePeers.remove(peerID) }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations for a smoother user experience.
        invitationHandler(true, self.session)
    }
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectedPeer = peerID
                self.isConnected = true
                self.serviceBrowser.stopBrowsingForPeers()
            case .notConnected:
                if self.connectedPeer == peerID {
                    self.connectedPeer = nil
                    self.isConnected = false
                    self.serviceBrowser.startBrowsingForPeers()
                }
            case .connecting:
                break
            @unknown default:
                fatalError("Unknown MCSessionState received")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let action = try JSONDecoder().decode(GameAction.self, from: data)
            DispatchQueue.main.async {
                self.receivedAction = action
            }
        } catch {
            print("Error decoding received data: \(error.localizedDescription)")
        }
    }
    
    // Required delegate methods that are not used in this implementation.
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}


// MARK: - Username Management
// A singleton class to manage the player's username across the app.
class UsernameManager: ObservableObject {
    static let shared = UsernameManager()
    
    @Published var username: String = ""
    private let usernameKey = "WildkinBattle_Username"
    
    private init() {
        loadUsername()
    }
    
    func loadUsername() {
        username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
    }
    
    func saveUsername(_ name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        username = trimmedName
        UserDefaults.standard.set(trimmedName, forKey: usernameKey)
        
        // When the username changes, the connection manager must be reset to broadcast the new name.
        MultipeerConnectionManager.sharedInstance.resetForNewUsername()
    }
    
    var hasUsername: Bool {
        !username.isEmpty
    }
}



// MARK: - MatchManager (The Game Engine)
// This class contains all the logic for a battle, including player actions and game state transitions.
class MatchManager: ObservableObject {
    @Published var gameState: GameState
    @Published var isShowingTurnSummary = false
    @Published var recentActionLog: [String] = []
    
    let isMultiplayer: Bool
    private var connectionManager: MultipeerConnectionManager?
    private var cancellables = Set<AnyCancellable>()

    init(playerTeam: [AnimalCard], opponentTeam: [AnimalCard], isMultiplayer: Bool = false, connectionManager: MultipeerConnectionManager? = nil) {
        self.isMultiplayer = isMultiplayer
        self.connectionManager = connectionManager
        
        let localPlayerName = connectionManager?.currentUsername ?? "Player 1"
        let opponentPlayerName = connectionManager?.connectedPeer?.displayName ?? "Player 2"
        
        // Determine turn order alphabetically to ensure consistency across devices.
        let names = [localPlayerName, opponentPlayerName].sorted()
        let localIsFirst = names[0] == localPlayerName
        
        let firstPlayer = Player(id: 1, name: localIsFirst ? localPlayerName : opponentPlayerName, team: localIsFirst ? playerTeam : opponentTeam)
        let secondPlayer = Player(id: 2, name: localIsFirst ? opponentPlayerName : localPlayerName, team: localIsFirst ? opponentTeam : playerTeam)
        
        self.gameState = GameState(players: [firstPlayer, secondPlayer])
        
        // Ensure the game can start.
        guard gameState.players.count == 2, !gameState.players[0].team.isEmpty, !gameState.players[1].team.isEmpty else { return }
        
        // Set the initial active cards.
        gameState.players[0].team[0].isActive = true
        gameState.players[1].team[0].isActive = true
        
        if isMultiplayer {
            listenForActions()
            // The first player is responsible for the initial state sync.
            if localIsFirst {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.syncGameState() }
            }
        }
    }
    
    // MARK: - Helper Functions
    private var currentPlayer: Player? { guard let index = getCurrentPlayerIndex() else { return nil }; return gameState.players[index] }
    func getPlayerIndex(for id: Int) -> Int? { gameState.players.firstIndex { $0.id == id } }
    func getCurrentPlayerIndex() -> Int? { getPlayerIndex(for: gameState.currentPlayerId) }
    func getAttackerPlayerIndex() -> Int? { getCurrentPlayerIndex() }
    func getDefenderPlayerIndex() -> Int? { guard let attackerIndex = getAttackerPlayerIndex() else { return nil }; return (attackerIndex == 0) ? 1 : 0 }
    func getLocalPlayerIndex() -> Int? {
        if !isMultiplayer { return 0 }
        guard let localPlayerName = connectionManager?.currentUsername else { return nil }
        return gameState.players.firstIndex { $0.name == localPlayerName }
    }
    func isLocalPlayerTurn() -> Bool { guard let localPlayerIndex = getLocalPlayerIndex() else { return false }; return gameState.currentPlayerId == gameState.players[localPlayerIndex].id }
    private func findCardIndex(_ id: UUID, in playerIndex: Int) -> Int? { gameState.players[playerIndex].team.firstIndex(where: { $0.id == id }) }
    private func findCardOwner(_ id: UUID) -> (card: AnimalCard, playerIndex: Int)? {
        for (pIndex, player) in gameState.players.enumerated() { if let card = player.team.first(where: { $0.id == id }) { return (card, pIndex) } }
        return nil
    }
    
    // MARK: - Action & Turn Flow
    
    private func performLocalAction(logic: @escaping () -> Void) {
        // Guard against actions when it's not the player's turn or an action is already pending.
        guard !isShowingTurnSummary, isLocalPlayerTurn(), gameState.pendingTargetInfo == nil else { return }
        
        recentActionLog.removeAll()
        logic() // Execute the core game logic (e.g., attack, use power).

        // After the logic runs, check if a targeting request was created.
        if gameState.pendingTargetInfo != nil {
            // If yes, the state has changed in a way the opponent needs to know about.
            // Sync the state immediately so the other player's UI can update to show the targeting prompt.
            syncGameState()
        } else {
            // If no targeting is needed, the action is complete. End the turn normally.
            endTurn()
        }
    }
    
    private func endTurn() {
        if let winner = checkForWinner() {
            gameState.winner = winner
            syncGameState()
            return
        }
        
        // Only advance the turn if there isn't a pending action.
        if gameState.pendingTargetInfo == nil {
            gameState.currentPlayerId = (gameState.currentPlayerId == 1) ? 2 : 1
            if gameState.currentPlayerId == 1 { gameState.turnNumber += 1 }
        }
        
        // This is the crucial change. Cleanup now happens for the new current player.
        startOfTurnCleanup(forPlayerId: gameState.currentPlayerId)
        
        syncGameState()
        isShowingTurnSummary = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.isShowingTurnSummary = false }
    }
    
    func selectTarget(cardId: UUID) {
        guard let targetInfo = gameState.pendingTargetInfo else { return }
        
        // Ensure the action is being performed by the correct player.
        if let localPlayerIndex = getLocalPlayerIndex(), targetInfo.playerIndex == localPlayerIndex {
            let sourceCard = targetInfo.sourceCard
            recentActionLog.removeAll()
            
            executeTargetedPower(targetInfo.power, with: cardId, by: sourceCard, forPlayer: targetInfo.playerIndex)
            
            // Mark Super Power as used if it was one.
            if targetInfo.power.id >= 200 {
                if let cardIndex = findCardIndex(sourceCard.id, in: targetInfo.playerIndex) {
                    gameState.players[targetInfo.playerIndex].team[cardIndex].isSuperPowerUsed = true
                }
            }
            
            // Clear the pending info and end the turn.
            gameState.pendingTargetInfo = nil
            endTurn()
        }
    }
    
    func cancelTargeting() {
        if let targetInfo = gameState.pendingTargetInfo {
            logAction("Targeting for \(targetInfo.power.name) was cancelled.")
            gameState.pendingTargetInfo = nil
            endTurn() // End the turn even if targeting is cancelled.
        }
    }
    
    // MARK: - Player Actions
    func performAttack() { performLocalAction { self.executeAttackLogic() } }
    
    func performSuperPower() {
        performLocalAction {
            guard let activeCard = self.currentPlayer?.activeWildkin,
                  let power = activeCard.superPower,
                  !activeCard.isSuperPowerUsed,
                  let playerIndex = self.getCurrentPlayerIndex() else { return }
            
            // If the power requires targeting, set up the pendingTargetInfo.
            // The performLocalAction wrapper will handle syncing the state.
            if power.effect?.target == "opponent_benched" || power.effect?.target == "any_friendly" {
                self.gameState.pendingTargetInfo = TargetingInfo(power: power, sourceCard: activeCard, playerIndex: playerIndex)
            } else {
                // Otherwise, execute the power directly.
                self.executePower(power, by: activeCard, forPlayer: playerIndex)
            }
        }
    }
    
    func performSwap(with benchedCardId: UUID) {
        guard let playerIndex = getCurrentPlayerIndex() else { return }
        performLocalAction {
            self.executeSwapLogic(with: benchedCardId, forPlayer: playerIndex)
        }
    }
    
    func concede() {
        if isMultiplayer { connectionManager?.send(action: .concede) }
        handleConcession()
    }

    // MARK: - Game Logic Execution
    private func executeAttackLogic() {
        guard let attacker = currentPlayer?.activeWildkin else { return }
        let damage = attacker.strength + attacker.attackBuff
        applyDamageToActive(damage, from: attacker.id)
        if let playerIndex = getCurrentPlayerIndex(), let cardIndex = findCardIndex(attacker.id, in: playerIndex) {
            gameState.players[playerIndex].team[cardIndex].attackBuff = 0
        }
    }
    
    private func executePower(_ power: Power, by sourceCard: AnimalCard, forPlayer playerIndex: Int) {
        logAction("\(sourceCard.name) uses \(power.name)!")
        guard let effect = power.effect else { return }
        
        switch effect.type {
        case "NEGATE_NEXT_DAMAGE":
            if let i = findCardIndex(sourceCard.id, in: playerIndex) { gameState.players[playerIndex].team[i].isInvincible = true }
        case "REFLECT_DAMAGE":
            if let i = findCardIndex(sourceCard.id, in: playerIndex) { gameState.players[playerIndex].team[i].reflectsDamage = effect.value }
        case "IMMUNE_UNTIL_NEXT_TURN":
            if let i = findCardIndex(sourceCard.id, in: playerIndex) { gameState.players[playerIndex].team[i].isImmune = true }
        case "BUFF_ATTACK":
            let totalDamage = sourceCard.strength + sourceCard.attackBuff + effect.value
            applyDamageToActive(totalDamage, from: sourceCard.id)
            if let i = findCardIndex(sourceCard.id, in: playerIndex) { gameState.players[playerIndex].team[i].attackBuff = 0 }
        case "HEAL":
            if effect.target == "self" {
                applyHeal(effect.value, to: sourceCard.id, onPlayer: playerIndex)
            } else if effect.target == "team" {
                gameState.players[playerIndex].team.forEach { applyHeal(effect.value, to: $0.id, onPlayer: playerIndex) }
            }
        case "ADD_TEMP_SHIELD":
            if let i = findCardIndex(sourceCard.id, in: playerIndex) { gameState.players[playerIndex].team[i].temporaryShields += effect.value }
        case "DEAL_DAMAGE":
            if effect.target == "opponent_active" { applyDamageToActive(effect.value, from: sourceCard.id) }
        case "BUFF_NEXT_ATTACK":
            if let i = findCardIndex(sourceCard.id, in: playerIndex) { gameState.players[playerIndex].team[i].attackBuff += effect.value }
        default:
            break
        }
        
        if power.id >= 200 {
            if let i = findCardIndex(sourceCard.id, in: playerIndex) { gameState.players[playerIndex].team[i].isSuperPowerUsed = true }
        }
    }
    
    private func executeTargetedPower(_ power: Power, with targetId: UUID, by sourceCard: AnimalCard, forPlayer playerIndex: Int) {
        guard let effect = power.effect else { return }
        
        switch effect.type {
        case "DEAL_DAMAGE_TO_BENCH":
            let opponentIndex = playerIndex == 0 ? 1 : 0
            applyDamage(effect.value, to: targetId, onPlayer: opponentIndex, from: sourceCard.id)
        case "HEAL_SINGLE_TARGET":
            applyHeal(effect.value, to: targetId, onPlayer: playerIndex)
        default:
            break
        }
    }
    
    private func executeSwapLogic(with benchedCardId: UUID, forPlayer playerIndex: Int) {
        guard let activeIndex = gameState.players[playerIndex].team.firstIndex(where: { $0.isActive }),
              let benchedIndex = findCardIndex(benchedCardId, in: playerIndex) else { return }
        
        gameState.players[playerIndex].team[activeIndex].isActive = false
        gameState.players[playerIndex].team[benchedIndex].isActive = true
        let newActiveCard = gameState.players[playerIndex].team[benchedIndex]
        logAction("\(gameState.players[playerIndex].name) swaps to \(newActiveCard.name).")
        
        // Check for and apply the new card's switch-in ability.
        applySwitchInPower(of: newActiveCard, forPlayer: playerIndex)
    }
    
    private func applySwitchInPower(of card: AnimalCard, forPlayer playerIndex: Int) {
        guard let power = card.switchAbility else { return }
        
        // This is where the targeting request is generated for the forced swap.
        if power.effect?.target == "any_friendly" {
            self.gameState.pendingTargetInfo = TargetingInfo(power: power, sourceCard: card, playerIndex: playerIndex)
        } else {
            executePower(power, by: card, forPlayer: playerIndex)
        }
    }
    
    private func applyDamage(_ amount: Int, to targetId: UUID, onPlayer playerIndex: Int, from attackerId: UUID) {
        guard let targetCardIndex = findCardIndex(targetId, in: playerIndex), let attackerInfo = findCardOwner(attackerId) else { return }
        
        let attacker = attackerInfo.card
        let targetCard = gameState.players[playerIndex].team[targetCardIndex]
        
        if targetCard.isImmune {
            logAction("\(attacker.name)'s attack has no effect on the immune \(targetCard.name)!")
            return
        }
        if targetCard.isInvincible {
            logAction("\(attacker.name)'s attack is negated by \(targetCard.name)'s invincibility!")
            gameState.players[playerIndex].team[targetCardIndex].isInvincible = false
            return
        }
        
        var incomingDamage = amount
        if targetCard.reflectsDamage > 0 {
            let reflectPercent = Double(targetCard.reflectsDamage) / 100.0
            let reflectedDamage = Int((Double(incomingDamage) * reflectPercent).rounded(.up))
            incomingDamage -= reflectedDamage
            logAction("\(targetCard.name) reflects \(reflectedDamage) damage back to \(attacker.name)!")
            applyDamage(reflectedDamage, to: attackerId, onPlayer: attackerInfo.playerIndex, from: targetId)
            gameState.players[playerIndex].team[targetCardIndex].reflectsDamage = 0
        }
        
        // **FIX 1:** Shield logic updated for Tier 1.
        // TIER 2 LOGIC: In the next tier, base shields will also block damage.
        // let totalShields = targetCard.shield + targetCard.temporaryShields
        
        // TIER 1 LOGIC: Only temporary shields from powers (like Rock Wall) block damage.
        let totalShields = targetCard.temporaryShields
        
        let damageToShields = min(incomingDamage, totalShields)
        if damageToShields > 0 {
            incomingDamage -= damageToShields
            logAction("\(targetCard.name)'s shield blocks \(damageToShields) damage!")
        }
        
        let finalDamage = max(0, incomingDamage)
        gameState.players[playerIndex].team[targetCardIndex].currentHP -= finalDamage
        
        let updatedCard = gameState.players[playerIndex].team[targetCardIndex]
        logAction("\(attacker.name) hits \(targetCard.name) for \(finalDamage) damage! (\(updatedCard.currentHP)/\(updatedCard.stamina) HP)")
        
        if updatedCard.isKnockedOut {
            logAction("\(updatedCard.name) is knocked out!")
            if updatedCard.isActive {
                forceSwap(forPlayer: playerIndex)
            }
        }
    }
    
    private func applyDamageToActive(_ amount: Int, from attackerId: UUID) {
        guard let defenderIndex = getDefenderPlayerIndex(), let targetCard = gameState.players[defenderIndex].activeWildkin else { return }
        applyDamage(amount, to: targetCard.id, onPlayer: defenderIndex, from: attackerId)
    }
    
    private func applyHeal(_ amount: Int, to targetId: UUID, onPlayer playerIndex: Int) {
        guard let targetIndex = findCardIndex(targetId, in: playerIndex) else { return }
        let card = gameState.players[playerIndex].team[targetIndex]
        let maxHP = card.stamina
        let currentHP = card.currentHP
        let healedAmount = min(amount, maxHP - currentHP)
        
        if healedAmount > 0 {
            gameState.players[playerIndex].team[targetIndex].currentHP += healedAmount
            logAction("\(card.name) heals for \(healedAmount) HP!")
        }
    }

    private func forceSwap(forPlayer playerIndex: Int) {
        if let benchedCard = gameState.players[playerIndex].benchedWildkin.first {
            executeSwapLogic(with: benchedCard.id, forPlayer: playerIndex)
        }
    }
    
    private func startOfTurnCleanup(forPlayerId playerId: Int) {
        guard let playerIndex = getPlayerIndex(for: playerId) else { return }
        for i in 0..<gameState.players[playerIndex].team.count {
            if gameState.players[playerIndex].team[i].isImmune {
                logAction("\(gameState.players[playerIndex].team[i].name) is no longer immune.")
                gameState.players[playerIndex].team[i].isImmune = false
            }
            if gameState.players[playerIndex].team[i].temporaryShields > 0 {
                logAction("\(gameState.players[playerIndex].team[i].name)'s temporary shield fades.")
                gameState.players[playerIndex].team[i].temporaryShields = 0
            }
        }
    }

    // MARK: - Networking & Syncing
    private func syncGameState() {
        if isMultiplayer {
            connectionManager?.send(action: .syncGameState(gameState))
        }
    }
    
    private func checkForWinner() -> Player? {
        if gameState.players[0].hasLost { return gameState.players[1] }
        if gameState.players[1].hasLost { return gameState.players[0] }
        return nil
    }
    
    private func handleConcession() {
        if let localPlayerIndex = getLocalPlayerIndex(), let winner = gameState.players.first(where: { $0.id != gameState.players[localPlayerIndex].id }) {
            gameState.winner = winner
            logToMainHistory("\(winner.name) wins by concession!")
            syncGameState()
        }
    }
    
    private func logAction(_ message: String) {
        recentActionLog.append(message)
        logToMainHistory(message)
    }
    
    private func logToMainHistory(_ message: String) {
        gameState.gameLog.insert("[\(gameState.turnNumber)] \(message)", at: 0)
    }
    
    private func listenForActions() {
        connectionManager?.$receivedAction
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] action in self?.executeReceivedAction(action) }
            .store(in: &cancellables)
    }
    
    private func executeReceivedAction(_ action: GameAction) {
        switch action {
        case .syncGameState(let receivedGameState):
            self.gameState = receivedGameState
            self.recentActionLog = receivedGameState.gameLog.first.map { [$0.replacingOccurrences(of: "[\(receivedGameState.turnNumber)] ", with: "")] } ?? []
            
            // Only show the turn summary if there isn't a pending targeting request for the local player.
            if let targetInfo = receivedGameState.pendingTargetInfo, let localIndex = getLocalPlayerIndex(), targetInfo.playerIndex == localIndex {
                // This is a targeting request for me, don't show the summary, show the sheet.
            } else {
                self.isShowingTurnSummary = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.isShowingTurnSummary = false }
            }
            
        case .concede:
            handleConcession()
        case .sendTeam:
            // This action is handled in the TeamSelectionView, not here.
            break
        }
    }
}



// FIX: This struct now holds all necessary info for targeting, including the source card.
//struct TargetingInfo: Identifiable {
//    let id = UUID()
//    let power: Power
//    let sourceCard: AnimalCard
//    let playerIndex: Int
//}



// MARK: - Lobby & Username Views

// The main entry point for the "Battle" tab.
//
//  BattleViews.swift
//  readingApp
//
//  Created by Joey Rubin on 7/16/25.
//

import SwiftUI
import CoreData

// MARK: - Lobby & Username Views

struct LobbyView: View {
    @EnvironmentObject var connectionManager: MultipeerConnectionManager
    @ObservedObject private var usernameManager = UsernameManager.shared
    @State private var showingUsernameSetup = false
    @State private var navigateToTeamSelection = false

    var body: some View {
        VStack(spacing: 20) {
            if connectionManager.isConnected, let peer = connectionManager.connectedPeer {
                VStack {
                    Text("Connected!").font(.largeTitle).bold().foregroundColor(.green)
                    Text("Playing against \(peer.displayName)").font(.headline)
                    if usernameManager.hasUsername {
                        Text("You'll play as '\(usernameManager.username)'").font(.subheadline).foregroundColor(.blue).padding(.top, 5)
                        HStack {
                            Button("Change Name") { showingUsernameSetup = true }.buttonStyle(ActionButtonStyle(color: .gray))
                            Button("Select Your Team") { navigateToTeamSelection = true }.buttonStyle(ActionButtonStyle(color: .blue))
                        }
                    } else {
                        Button("Choose Your Battle Name") { showingUsernameSetup = true }.buttonStyle(ActionButtonStyle(color: .blue)).padding(.top)
                    }
                }
            } else {
                Text("Find an Opponent").font(.largeTitle.bold())
                if usernameManager.hasUsername {
                    Text("Playing as '\(usernameManager.username)'").font(.subheadline).foregroundColor(.blue).padding(.bottom, 10)
                    Button("Change Name") { showingUsernameSetup = true }.buttonStyle(.bordered)
                }
                if connectionManager.availablePeers.isEmpty {
                    VStack(spacing: 15) {
                        ProgressView(); Text("Searching for players...").foregroundColor(.secondary)
                        Text("Make sure the other device is on this screen.").font(.caption).foregroundColor(.secondary)
                    }.padding()
                } else {
                    List {
                        Section(header: Text("Available Players")) {
                            ForEach(connectionManager.availablePeers.sorted(by: { $0.displayName < $1.displayName }), id: \.self) { peer in
                                Button(action: {
                                    if usernameManager.hasUsername { connectionManager.invitePeer(peer) } else { showingUsernameSetup = true }
                                }) { HStack { Text(peer.displayName); Spacer(); Image(systemName: "gamecontroller.fill") } }
                                .foregroundColor(.primary)
                            }
                        }
                    }.listStyle(.insetGrouped)
                }
            }
        }
        .padding()
        .sheet(isPresented: $showingUsernameSetup) {
            UsernameSetupView { username in
                showingUsernameSetup = false
                if connectionManager.isConnected { navigateToTeamSelection = true }
            }
        }
        .navigationDestination(isPresented: $navigateToTeamSelection) { TeamSelectionView(isMultiplayer: true) }
        .onAppear {
            connectionManager.start()
            if !usernameManager.hasUsername { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showingUsernameSetup = true } }
        }
        .navigationTitle("Battle Lobby")
    }
}

struct UsernameSetupView: View {
    @ObservedObject private var usernameManager = UsernameManager.shared
    @State private var inputUsername = ""
    @State private var showingNameTakenAlert = false
    @EnvironmentObject var connectionManager: MultipeerConnectionManager
    let onComplete: (String) -> Void
    private let suggestions = ["Dragon Trainer", "Star Hunter", "Magic Wolf", "Sky Explorer", "Storm Rider", "Fire Guardian"]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Choose Your Battle Name").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("This name will be shown to other players.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                TextField("Enter your battle name", text: $inputUsername).textFieldStyle(.roundedBorder).font(.title2).autocorrectionDisabled().onSubmit(saveUsername)
                if inputUsername.isEmpty {
                    Text("Pick a fun name or try one of these:").font(.caption).foregroundColor(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) { inputUsername = suggestion }.buttonStyle(.bordered).font(.caption)
                        }
                    }
                }
            }
            Spacer()
            Button("Start Playing!", action: saveUsername).buttonStyle(ActionButtonStyle(color: .green)).disabled(inputUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .alert("Name Already in Use", isPresented: $showingNameTakenAlert) { Button("Try Again") { } } message: { Text("Another player is already using that name. Please choose a different one!") }
        .onAppear { if usernameManager.hasUsername { inputUsername = usernameManager.username } }
    }
    
    private func saveUsername() {
        let trimmedName = inputUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        if let connectedPeer = connectionManager.connectedPeer, trimmedName == connectedPeer.displayName { showingNameTakenAlert = true; return }
        usernameManager.saveUsername(trimmedName)
        onComplete(trimmedName)
    }
}

// MARK: - Team Selection View
struct TeamSelectionView: View {
    @EnvironmentObject var connectionManager: MultipeerConnectionManager
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Card.timestamp, ascending: false)], animation: .default)
    private var collectedCards: FetchedResults<Card>

    @State private var playerTeam: Set<AnimalCard> = []
    @State private var opponentTeamInstances: [AnimalCard]? = nil
    @State private var teamSize = 2
    let isMultiplayer: Bool
    @State private var localPlayerIsReady = false
    @State private var opponentIsReady = false
    @State private var matchConfig: MatchConfig?
    @State private var shouldDismiss = false

    var body: some View {
        VStack(spacing: 20) {
            Picker("Game Mode", selection: $teamSize) { Text("2 vs 2").tag(2); Text("3 vs 3").tag(3) }
                .pickerStyle(.segmented).disabled(isMultiplayer && localPlayerIsReady)
                .onChange(of: teamSize) { _ in playerTeam.removeAll() }
            
            TeamIconView(team: Array(playerTeam), teamSize: teamSize, title: "Your Team")
            if isMultiplayer { TeamIconView(team: opponentTeamInstances ?? [], teamSize: teamSize, title: "Opponent's Team") }
            
            if collectedCards.isEmpty {
                Spacer(); Text("No cards in your collection!").font(.title); Text("Go to the Challenges tab to earn some cards first.").font(.headline).foregroundColor(.secondary); Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
                        ForEach(collectedCards) { cardEntity in
                            let card = AnimalCard(cardEntity: cardEntity)
                            Button(action: { toggleSelection(for: card) }) { CardSelectionView(card: card, isSelected: playerTeam.contains(card)) }
                                .disabled(isMultiplayer && localPlayerIsReady)
                        }
                    }
                }
            }
            if isMultiplayer { multiplayerControls }
        }
        .padding()
        .navigationTitle("Build Your Team")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $matchConfig) { config in
            MatchView(playerTeam: config.playerTeam, opponentTeam: config.opponentTeam, isMultiplayer: config.isMultiplayer, onPlayAgain: {
                self.matchConfig = nil; if config.isMultiplayer { self.shouldDismiss = true }
            })
        }
        .onChange(of: shouldDismiss) { newValue in if newValue { dismiss() } }
        .onReceive(connectionManager.$receivedAction) { action in
            guard isMultiplayer, let action = action else { return }
            handleReceivedAction(action)
        }
    }
    
    @ViewBuilder private var multiplayerControls: some View {
        VStack(spacing: 15) {
            if opponentIsReady { Text("Opponent is ready!").font(.headline).foregroundColor(.green) }
            else { Text("Select your team and tap Ready.").font(.headline).foregroundColor(.secondary) }
            Button(localPlayerIsReady ? "Waiting for Opponent..." : "Ready Up") {
                localPlayerIsReady = true; connectionManager.send(action: .sendTeam(Array(playerTeam))); checkForMatchStart()
            }.buttonStyle(ActionButtonStyle(color: localPlayerIsReady ? .gray : .green)).disabled(playerTeam.count != teamSize || localPlayerIsReady)
        }
    }

    private func handleReceivedAction(_ action: GameAction) {
        switch action {
        case .sendTeam(let receivedTeam): self.opponentTeamInstances = receivedTeam; self.opponentIsReady = true; checkForMatchStart()
        default: break
        }
    }

    private func checkForMatchStart() {
        guard localPlayerIsReady, opponentIsReady, let opponentTeam = opponentTeamInstances else { return }
        self.matchConfig = MatchConfig(playerTeam: Array(playerTeam), opponentTeam: opponentTeam, isMultiplayer: true)
    }

    private func toggleSelection(for card: AnimalCard) {
        if playerTeam.contains(card) { playerTeam.remove(card) }
        else if playerTeam.count < teamSize { playerTeam.insert(card) }
    }
}

// MARK: - Match & Battle Views
struct MatchView: View {
    @StateObject private var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss
    let onPlayAgain: () -> Void

    init(playerTeam: [AnimalCard], opponentTeam: [AnimalCard], isMultiplayer: Bool, onPlayAgain: @escaping () -> Void) {
        let manager = MatchManager(playerTeam: playerTeam, opponentTeam: opponentTeam, isMultiplayer: isMultiplayer, connectionManager: isMultiplayer ? MultipeerConnectionManager.sharedInstance : nil)
        _matchManager = StateObject(wrappedValue: manager)
        self.onPlayAgain = onPlayAgain
    }

    private var localPlayerTargetingInfo: Binding<TargetingInfo?> {
        Binding<TargetingInfo?>(
            get: {
                guard let targetInfo = matchManager.gameState.pendingTargetInfo,
                      let localPlayerIndex = matchManager.getLocalPlayerIndex(),
                      targetInfo.playerIndex == localPlayerIndex else {
                    return nil
                }
                return targetInfo
            },
            set: {
                if $0 == nil {
                    matchManager.gameState.pendingTargetInfo = nil
                }
            }
        )
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    PlayerView(player: opponentPlayer, isCurrentPlayer: matchManager.gameState.currentPlayerId == opponentPlayer.id, isLocalPlayer: false)
                    Divider()
                    PlayerView(player: localPlayer, isCurrentPlayer: matchManager.gameState.currentPlayerId == localPlayer.id, isLocalPlayer: true)
                    if !matchManager.gameState.isGameOver { ActionButtonsView(matchManager: matchManager) }
                    else { EndGameView(winner: matchManager.gameState.winner, onPlayAgain: self.onPlayAgain) }
                    GameLogView(log: matchManager.gameState.gameLog)
                }.padding()
            }
            .blur(radius: matchManager.isShowingTurnSummary || matchManager.gameState.pendingTargetInfo != nil ? 3 : 0)
            .disabled(matchManager.gameState.pendingTargetInfo != nil)
            
            if matchManager.isShowingTurnSummary { TurnSummaryView(log: matchManager.recentActionLog) }
            
            if let targetInfo = matchManager.gameState.pendingTargetInfo,
               let localPlayerIndex = matchManager.getLocalPlayerIndex(),
               targetInfo.playerIndex != localPlayerIndex {
                VStack {
                    Text("Waiting for \(opponentPlayer.name) to select a target...")
                        .font(.headline).padding().background(.regularMaterial)
                        .cornerRadius(12).shadow(radius: 5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.1))
                .transition(.opacity)
            }
        }
        .animation(.default, value: matchManager.gameState)
        .animation(.easeInOut, value: matchManager.isShowingTurnSummary)
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Concede") { matchManager.concede(); dismiss() }.foregroundColor(.red) } }
        .sheet(item: localPlayerTargetingInfo, onDismiss: {
            if matchManager.gameState.pendingTargetInfo != nil {
                matchManager.cancelTargeting()
            }
        }) { targetInfo in
            TargetSelectionSheet(matchManager: matchManager, targetInfo: targetInfo)
        }
    }
    
    private var localPlayer: Player {
        guard let index = matchManager.getLocalPlayerIndex(), matchManager.gameState.players.indices.contains(index) else { return matchManager.gameState.players.first! }
        return matchManager.gameState.players[index]
    }
    private var opponentPlayer: Player {
        guard let index = matchManager.getLocalPlayerIndex(), matchManager.gameState.players.indices.contains(index) else { return matchManager.gameState.players.last! }
        return matchManager.gameState.players[index == 0 ? 1 : 0]
    }
}

struct PlayerView: View {
    let player: Player
    let isCurrentPlayer: Bool
    let isLocalPlayer: Bool
    @State private var selectedCard: AnimalCard?

    var body: some View {
        VStack(spacing: 10) {
            HStack { Text(player.name).font(.headline); if isLocalPlayer { Text("(You)").font(.caption).foregroundColor(.blue) } }.opacity(isCurrentPlayer ? 1.0 : 0.6)
            HStack(alignment: .top, spacing: 16) {
                if let active = player.activeWildkin { Button(action: { selectedCard = active }) { BattleCardView(card: active, isActive: true) }.buttonStyle(.plain) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: -20) {
                        ForEach(player.benchedWildkin) { card in Button(action: { selectedCard = card }) { BattleCardView(card: card, isActive: false) }.buttonStyle(.plain) }
                    }.padding(.leading, 20)
                }
            }
        }
        .padding(12).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isCurrentPlayer ? Color.blue : Color.clear, lineWidth: 3))
        .sheet(item: $selectedCard) { card in CardDetailView(card: card, onDismiss: { selectedCard = nil }) }
    }
}

struct BattleCardView: View {
    let card: AnimalCard
    let isActive: Bool
    private let cardAspectRatio: CGFloat = 2.5 / 3.5
    private var cardWidth: CGFloat { 140.0 }
    
    // **FIX 2:** This computed property determines if any status icons should be shown.
    private var hasStatusEffects: Bool {
        card.isSuperPowerUsed || card.isImmune || card.isInvincible || card.reflectsDamage > 0
    }

    var body: some View {
        ZStack {
            Image(card.imageName).resizable().scaledToFill()
            VStack { Spacer(); LinearGradient(gradient: Gradient(colors: [.clear, .black.opacity(0.8)]), startPoint: .top, endPoint: .bottom).frame(height: cardWidth * 0.7) }
            VStack {
                Spacer()
                VStack(spacing: 4) {
                    Text("HP: \(card.currentHP)/\(card.stamina)").font(.caption.bold())
                    ProgressView(value: Double(card.currentHP), total: Double(card.stamina)).tint(progressColor)
                    Text("💥 \(card.strength) | 🛡️ \(card.shield + card.temporaryShields)").font(.caption).bold()
                }.padding(8).background(.black.opacity(0.5)).cornerRadius(8).foregroundColor(.white)
            }.padding(8)
            
            VStack {
                HStack {
                    Spacer()
                    // **FIX 2:** The status icon container now only appears if `hasStatusEffects` is true,
                    // preventing the empty black circle from showing up.
                    if hasStatusEffects {
                        VStack(spacing: 4) {
                            if card.isSuperPowerUsed { Image(systemName: "star.slash.fill").foregroundColor(.yellow) }
                            if card.isImmune { Image(systemName: "eye.slash.fill").foregroundColor(.purple) }
                            if card.isInvincible { Image(systemName: "shield.checkered").foregroundColor(.white) }
                            if card.reflectsDamage > 0 { Image(systemName: "arrow.left.arrow.right.circle.fill").foregroundColor(.orange) }
                        }
                        .font(.caption.bold())
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }
                }
                Spacer()
            }.padding(8)
        }
        .frame(width: cardWidth, height: cardWidth / cardAspectRatio)
        .background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(12).shadow(color: .black.opacity(0.2), radius: 5, y: 3)
        .opacity(card.isKnockedOut ? 0.5 : 1.0).overlay(card.isKnockedOut ? Text("KO").font(.largeTitle.bold()).foregroundColor(.red.opacity(0.8)) : nil)
        .scaleEffect(isActive ? 1.0 : 0.95).offset(y: isActive ? 0 : 10)
    }
    
    private var progressColor: Color {
        let ratio = Double(card.currentHP) / Double(card.stamina)
        if ratio > 0.5 { return .green }
        if ratio > 0.2 { return .orange }
        return .red
    }
}

// MARK: - Helper Views for Battle
struct ActionButtonsView: View {
    @ObservedObject var matchManager: MatchManager
    @State private var showSwapSheet = false
    
    private var isPlayerTurn: Bool { !matchManager.isShowingTurnSummary && matchManager.isLocalPlayerTurn() && matchManager.gameState.pendingTargetInfo == nil }
    private var localPlayer: Player? { guard let index = matchManager.getLocalPlayerIndex() else { return nil }; return matchManager.gameState.players[index] }
    private var canSwap: Bool { (localPlayer?.benchedWildkin.count ?? 0) > 0 }
    private var canUseSuper: Bool { !(localPlayer?.activeWildkin?.isSuperPowerUsed ?? true) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: { matchManager.performAttack() }) { Label("Attack", systemImage: "bolt.fill") }.buttonStyle(ActionButtonStyle())
                Button(action: { showSwapSheet = true }) { Label("Swap", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(ActionButtonStyle(color: .orange)).disabled(!canSwap)
                Button(action: { matchManager.performSuperPower() }) { Label("Super", systemImage: "star.fill") }.buttonStyle(ActionButtonStyle(color: .purple)).disabled(!canUseSuper)
            }
            .disabled(!isPlayerTurn).opacity(isPlayerTurn ? 1.0 : 0.6)
        }
        .sheet(isPresented: $showSwapSheet) {
            if let benched = localPlayer?.benchedWildkin {
                SwapSelectionSheet(benchedCards: benched) { selectedId in matchManager.performSwap(with: selectedId); showSwapSheet = false }
            }
        }
    }
}

struct SwapSelectionSheet: View {
    let benchedCards: [AnimalCard]
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 15) {
            Text("Swap To...").font(.largeTitle.bold()).padding()
            ForEach(benchedCards) { card in
                Button(action: { onSelect(card.id) }) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Image(systemName: "pawprint.fill"); Text(card.name).font(.title2.bold()); Spacer(); Text("❤️\(card.currentHP)/\(card.stamina)") }
                        if let switchAbility = card.switchAbility { Text("\(switchAbility.name):").font(.headline); Text(switchAbility.description).font(.caption).foregroundColor(.secondary) }
                    }.padding().frame(maxWidth: .infinity).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(12)
                }.buttonStyle(.plain)
            }
            Spacer()
            Button("Cancel") { dismiss() }.padding()
        }.padding()
    }
}

struct TargetSelectionSheet: View {
    @ObservedObject var matchManager: MatchManager
    let targetInfo: TargetingInfo
    private var power: Power { targetInfo.power }

    var body: some View {
        VStack(spacing: 15) {
            Text("Select Target for \(power.name)").font(.largeTitle.bold()).padding()
            Text(power.description).font(.headline).foregroundColor(.secondary)
            
            let targets = getTargetCards()
            ForEach(targets) { card in
                Button(action: { matchManager.selectTarget(cardId: card.id) }) {
                    HStack {
                        Image(systemName: "pawprint.fill"); Text(card.name).font(.title2.bold()); Spacer(); Text("❤️\(card.currentHP)/\(card.stamina)")
                    }.padding().frame(maxWidth: .infinity).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(12)
                }.buttonStyle(.plain)
            }
            
            Spacer()
            Button("Cancel") { matchManager.cancelTargeting() }
                .buttonStyle(ActionButtonStyle(color: .gray))
                .padding(.horizontal)

        }.padding()
    }
    
    private func getTargetCards() -> [AnimalCard] {
        guard let effectTarget = power.effect?.target else { return [] }
        switch effectTarget {
        case "opponent_benched":
            let opponentIndex = targetInfo.playerIndex == 0 ? 1 : 0
            return matchManager.gameState.players[opponentIndex].benchedWildkin
        case "any_friendly":
            return matchManager.gameState.players[targetInfo.playerIndex].team.filter { !$0.isKnockedOut }
        default:
            return []
        }
    }
}

struct GameLogView: View {
    let log: [String]
    var body: some View {
        VStack(spacing: 8) {
            Text("Game Log").font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(log.indices, id: \.self) { index in Text(log[index]).font(.caption).frame(maxWidth: .infinity, alignment: .leading).id(index) }
                    }.padding(8)
                }.onChange(of: log) { proxy.scrollTo(0, anchor: .top) }
            }
        }.frame(height: 150).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(16)
    }
}

struct EndGameView: View {
    let winner: Player?
    let onPlayAgain: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("Game Over!").font(.largeTitle.bold())
            if let winner = winner { Text("\(winner.name) is the winner!").font(.title2) }
            Button(action: onPlayAgain) { Label("New Game", systemImage: "arrow.clockwise") }.buttonStyle(ActionButtonStyle(color: .green))
        }.padding()
    }
}

struct TurnSummaryView: View {
    let log: [String]
    var body: some View {
        VStack(spacing: 8) {
            ForEach(log, id: \.self) { message in Text(message).font(.headline).multilineTextAlignment(.center) }
        }.padding(20).background(.regularMaterial).cornerRadius(20).shadow(radius: 10).transition(.scale.combined(with: .opacity))
    }
}

// MARK: - General Helper Views & Styles
struct ActionButtonStyle: ButtonStyle {
    var color: Color = .blue
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline.weight(.semibold)).foregroundColor(.white).padding().frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(color).shadow(color: color.opacity(0.4), radius: configuration.isPressed ? 0 : 5, y: configuration.isPressed ? 0 : 5))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0).animation(.spring(), value: configuration.isPressed)
    }
}

struct TeamIconView: View {
    let team: [AnimalCard]
    let teamSize: Int
    let title: String
    var body: some View {
        VStack {
            Text(title).font(.title2.bold())
            HStack {
                ForEach(0..<teamSize, id: \.self) { index in
                    if index < team.count { Image(systemName: "pawprint.circle.fill").font(.title).frame(width: 50, height: 50).background(Color.gray.opacity(0.2)).clipShape(Circle()) }
                    else { Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5])).foregroundColor(.gray.opacity(0.5)).frame(width: 50, height: 50) }
                }
            }
        }.frame(height: 80)
    }
}

struct CardSelectionView: View {
    let card: AnimalCard
    let isSelected: Bool
    var body: some View {
        VStack { AnimalCardView(card: card).aspectRatio(2.5/3.5, contentMode: .fit) }
            .padding(4).background(isSelected ? Color.blue.opacity(0.3) : Color.clear).cornerRadius(16)
    }
}
