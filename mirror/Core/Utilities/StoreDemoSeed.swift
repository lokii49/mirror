#if DEBUG
import Foundation
import SwiftData

/// DEBUG-only App Store screenshot data: `--seedStoreDemo=<code>` (en de es fr it ja ko pt ru zh) together with
/// `--perfSeed=0`, the scratch store (never a real journal). Replaces every entry and insight and the new-entry
/// draft with a two-week synthetic journal in that language, plus the reflection, weekly digest and Ask answer
/// the app shows for it. Outside English the app's own grounded composers build the reflection, digest and Ask
/// quotes from fixed picks, so the cards read exactly as the app writes them; English uses the shapes the
/// Foundation Models paths produce. Synthetic text only.
enum StoreDemoSeed {
    static var requestedLanguage: String? {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--seedStoreDemo=") }) else { return nil }
        return String(arg.dropFirst("--seedStoreDemo=".count))
    }

    struct DemoEntry {
        let daysAgo: Int
        let hour: Int
        let mood: String
        let tag: String
        let text: String
    }

    struct Demo {
        /// Newest first. The first five fall in this week when seeded on a Friday; the last seven are 15-27 days old.
        let entries: [String]
        let tags: [String]
        let draftTitle: String
        let draftBody: String
        /// The first item is ticked.
        let checklist: [String]
        /// A sentence of today's entry for the reflection to quote.
        let reflectionQuote: String
        /// English only: the reflection's sentence after the quote.
        let feeling: String
        /// Digest picks: energy (a hard-mood sentence), something good, something to watch.
        let digestPicks: [String]
        /// English only: the digest's section bodies.
        let englishDigest: [String]
        let askQuestion: String
        let askAnswer: String
        let askQuotes: [String]
    }

    /// Day offset, hour and mood of each entry (newest first); tag index into `Demo.tags`.
    private static let plan: [(daysAgo: Int, hour: Int, mood: String, tag: Int)] = [
        (0, 8, "Hopeful", 0), (1, 21, "Grateful", 1), (2, 22, "Anxious", 0), (3, 7, "Joyful", 2),
        (4, 23, "Drained", 0), (5, 20, "Peaceful", 3), (6, 7, "Energized", 2), (8, 21, "Frustrated", 0),
        (9, 18, "Content", 1), (11, 22, "Grateful", 3), (13, 20, "Hopeful", 0),
        // Older entries that give Brain View more than Work to show: family, exercise, food, home,
        // sleep, outdoors, hobbies, friends, goals (words from BrainTopics' lists in each language).
        (15, 10, "Peaceful", 3), (17, 7, "Joyful", 2), (19, 23, "Anxious", 0), (21, 19, "Content", 1),
        (23, 18, "Grateful", 1), (25, 8, "Energized", 2), (27, 21, "Hopeful", 3),
    ]

    static func seed(into context: ModelContext, code: String) {
        // Scratch store only: this deletes every entry and insight.
        guard PerfSeed.isRequested, let demo = demos[code] else { return }
        for entry in (try? context.fetch(FetchDescriptor<Entry>())) ?? [] { context.delete(entry) }
        for insight in (try? context.fetch(FetchDescriptor<Insight>())) ?? [] { context.delete(insight) }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        var entries: [Entry] = []
        for (index, slot) in plan.enumerated() where index < demo.entries.count {
            let entry = Entry(text: demo.entries[index], mood: slot.mood, source: .typed)
            let day = calendar.date(byAdding: .day, value: -slot.daysAgo, to: startOfToday) ?? startOfToday
            var created = calendar.date(byAdding: .hour, value: slot.hour, to: day) ?? day
            if slot.daysAgo == 0 { created = min(created, Date().addingTimeInterval(-600)) }
            entry.createdAt = created
            entry.weekIdentifier = DateHelpers.weekIdentifier(for: created)
            entry.tags = [demo.tags[slot.tag]]
            context.insert(entry)
            entries.append(entry)
        }

        let today = entries.filter { calendar.isDateInToday($0.createdAt) }
        let week = entries.filter { DateHelpers.digestWeekIdentifier(for: $0.createdAt) == DateHelpers.digestWeekIdentifier(for: Date()) }
        if let reflection = reflection(code: code, demo: demo, today: today, background: entries) {
            context.insert(Insight(type: .dailyNudge, content: reflection,
                                   periodIdentifier: DateHelpers.dayIdentifier(for: Date()), generatedByEngine: .foundationModels))
        }
        if let digest = digest(code: code, demo: demo, week: week, all: entries) {
            context.insert(Insight(type: .weeklyDigest, content: digest,
                                   periodIdentifier: DateHelpers.digestWeekIdentifier(for: Date()), generatedByEngine: .foundationModels))
        }
        if let quotes = askQuotes(code: code, demo: demo, pool: entries) {
            context.insert(Insight(type: .askResponse, content: demo.askAnswer + "\n\n" + quotes,
                                   periodIdentifier: DateHelpers.dayIdentifier(for: Date()),
                                   question: demo.askQuestion, generatedByEngine: .foundationModels))
        }
        try? context.save()

        // The Write screen's new-entry draft: a title, a line, and a checklist with the first item done.
        let text = ([demo.draftTitle, demo.draftBody] + demo.checklist).joined(separator: "\n")
        let models: [NoteEditorCodec.ParagraphModel] = [
            .init(style: .title), .init(style: .body), .init(style: .checklistChecked),
        ] + demo.checklist.dropFirst().map { _ in .init(style: .checklistUnchecked) }
        var payload = WriteDraftStore.Payload()
        payload.text = text
        payload.textStyleData = NoteEditorCodec.encodeTextStyleData(models: models, entryFont: .system)
        _ = WriteDraftStore.save(payload)
    }

    private static func pick(_ wanted: String, in options: [String]) -> String? {
        options.first { $0 == wanted } ?? options.first { $0.contains(wanted) || wanted.contains($0) } ?? options.first
    }

    private static func reflection(code: String, demo: Demo, today: [Entry], background: [Entry]) -> String? {
        if code == "en" {
            return "You wrote, \"\(demo.reflectionQuote)\" \(demo.feeling)"
        }
        guard let grounded = InsightService.localizedGroundedNudge(recent: today, background: background, recentNudges: []),
              let validator = grounded.validator,
              let quote = pick(demo.reflectionQuote, in: grounded.quoteOptions) else { return nil }
        return try? validator(quote)
    }

    private static func digest(code: String, demo: Demo, week: [Entry], all: [Entry]) -> String? {
        if code == "en" {
            let labels = InsightService.weeklyDigestSectionLabels.map { $0["en"] ?? "" }
            return zip(labels, demo.englishDigest).map { "\($0): \($1)" }.joined(separator: "\n")
        }
        guard let grounded = InsightService.localizedGroundedDigest(weekEntries: week, languageSource: all),
              let validator = grounded.validator, grounded.digestOptions.count == 3 else { return nil }
        let lines = zip(demo.digestPicks, grounded.digestOptions).compactMap { pick($0, in: $1) }
        guard lines.count == 3 else { return nil }
        return try? validator(lines.joined(separator: "\n"))
    }

    private static func askQuotes(code: String, demo: Demo, pool: [Entry]) -> String? {
        if code == "en" {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "d MMM"
            let shown: [String] = demo.askQuotes.compactMap { quote in
                guard let entry = pool.first(where: { $0.text.contains(quote) }) else { return nil }
                return "On \(formatter.string(from: entry.createdAt)), you wrote, \"\(quote)\""
            }
            return shown.isEmpty ? nil : InsightService.groundedAskPrefix + shown.joined(separator: " ")
        }
        guard let grounded = InsightService.localizedGroundedAsk(question: demo.askQuestion, pool: pool),
              let validator = grounded.validator else { return nil }
        if let text = try? validator(demo.askQuotes.joined(separator: "\n")) { return text }
        return demo.askQuotes.lazy.compactMap { try? validator($0) }.first
    }

    // MARK: - The journals

    static let demos: [String: Demo] = [
        "en": Demo(
            entries: [
                "First week leading the new project. I was nervous this morning, but the kickoff went better than I expected. Priya said my plan was the clearest she's seen.",
                "Called my sister after dinner and we laughed about the summer we got lost in Lisbon. I want to visit her before the year ends.",
                "Couldn't switch off tonight. I keep going over tomorrow's presentation in my head. I wrote three versions of the opening and deleted them all.",
                "Ran 10k this morning without stopping. My legs were heavy at the start, then everything felt easy. Made pancakes to celebrate.",
                "Long day of back-to-back meetings. I said yes to two more tasks I don't have time for. Tomorrow I need to say no to something.",
                "Quiet evening at home. I repotted the plants on the balcony and read until the light went. The phone stayed in the other room.",
                "Early run by the river before work. The air was cold and clear. I came back with a list of ideas for the project.",
                "The release slipped again because of one missing approval. I'm tired of waiting on decisions I can't make myself.",
                "Sunday lunch at Mum's. She showed me her tomatoes and sent me home with far too many. A simple, good day.",
                "Noor fixed my bike and wouldn't take anything for it. I left a note and her favourite tea on the doorstep.",
                "Got the email: the project is mine. I'm excited and a little scared. Starting a list of what I want this to feel like.",
                "Rain all day, so I stayed home. I finished my book with a cup of coffee and let the dishes wait.",
                "Went running in the park with Noor, my friend from work. We signed up for the spring race and started training together.",
                "Couldn't sleep before the interview. My manager says the team needs someone to lead the next project.",
                "Cooked dinner for my sister and Mum. We sat in the garden and talked about a trip to Lisbon.",
                "Mum's birthday. The whole family came, and my sister baked her famous cake.",
                "First run after a week of bad sleep. Slow, but the river path was beautiful and I felt like myself again.",
                "Wrote down my goal for the autumn: a run, a book and an evening without my phone every week.",
            ],
            tags: ["work", "family", "running", "home"],
            draftTitle: "Weekend plan",
            draftBody: "A slow Saturday, then dinner with Noor.",
            checklist: ["Book the train to see my sister", "Call Mum about Sunday", "Buy flowers for Noor"],
            reflectionQuote: "I was nervous this morning, but the kickoff went better than I expected.",
            feeling: "You sound hopeful about what this project could become.",
            digestPicks: [],
            englishDigest: [
                "A new project, and learning to protect your evenings.",
                "Highest after your morning run, lowest after the day of back-to-back meetings.",
                "Making time for the people close to you, like visiting your sister before the year ends.",
                "Saying yes to tasks you don't have time for.",
                "A run by the river before work.",
                "Pick one thing to say no to before Monday.",
            ],
            askQuestion: "What keeps lifting my mood?",
            askAnswer: "Moving and the people close to you. Your lighter days follow a morning run or time with family, and the heavier ones come after long days of meetings.",
            askQuotes: ["Ran 10k this morning without stopping.", "Called my sister after dinner and we laughed about the summer we got lost in Lisbon."]
        ),
        "de": Demo(
            entries: [
                "Erste Woche als Leiterin des neuen Projekts. Heute Morgen war ich nervös, aber der Auftakt lief besser als erwartet. Lena meinte, mein Plan sei der klarste, den sie je gesehen hat.",
                "Nach dem Abendessen habe ich meine Schwester angerufen, und wir haben über den Sommer gelacht, in dem wir uns in Lissabon verlaufen haben. Ich will sie noch vor Jahresende besuchen.",
                "Heute Abend konnte ich nicht abschalten. Ich gehe die Präsentation von morgen immer wieder im Kopf durch. Ich habe drei Anfänge geschrieben und alle wieder gelöscht.",
                "Heute Morgen bin ich zehn Kilometer ohne Pause gelaufen. Am Anfang waren meine Beine schwer, dann ging alles leicht. Zur Feier gab es Pfannkuchen.",
                "Ein langer Tag mit Meetings ohne Pause. Ich habe zwei weiteren Aufgaben zugesagt, für die ich keine Zeit habe. Morgen muss ich zu etwas Nein sagen.",
                "Ein ruhiger Abend zu Hause. Ich habe die Pflanzen auf dem Balkon umgetopft und gelesen, bis es dunkel wurde. Das Handy blieb im anderen Zimmer.",
                "Früh am Fluss gelaufen, vor der Arbeit. Die Luft war kalt und klar. Ich kam mit einer Liste von Ideen für das Projekt zurück.",
                "Der Release hat sich wieder verschoben, weil eine Freigabe fehlt. Ich bin es leid, auf Entscheidungen zu warten, die ich nicht selbst treffen kann.",
                "Sonntagsessen bei Mama. Sie hat mir ihre Tomaten gezeigt und mir viel zu viele mitgegeben. Ein einfacher, guter Tag.",
                "Mia hat mein Fahrrad repariert und wollte nichts dafür. Ich habe ihr einen Zettel und ihren Lieblingstee vor die Tür gestellt.",
                "Die Mail ist da: Das Projekt gehört mir. Ich freue mich und habe ein bisschen Angst. Ich fange eine Liste an, wie sich das anfühlen soll.",
                "Den ganzen Tag Regen, also bin ich zuhause geblieben. Ich habe mein Buch mit einem Kaffee ausgelesen und das Geschirr stehen lassen.",
                "Mit Mia, meiner Freundin aus der Arbeit, im Park laufen gewesen. Wir haben uns für den Frühlingslauf angemeldet und mit dem Training angefangen.",
                "Vor dem Vorstellungsgespräch konnte ich nicht schlafen. Meine Chefin sagt, das Team braucht jemanden, der das nächste Projekt leitet.",
                "Für meine Schwester und Mama Abendessen gekocht. Wir saßen im Garten und haben über eine Reise nach Lissabon gesprochen.",
                "Geburtstag von Mama. Die ganze Familie kam, und meine Schwester hat ihren berühmten Kuchen gebacken.",
                "Nach einer Woche mit schlechtem Schlaf endlich wieder laufen. Langsam, aber der Weg am Fluss war wunderschön, und ich habe mich wieder wie ich selbst gefühlt.",
                "Mein Ziel für den Herbst aufgeschrieben: jede Woche einmal laufen, ein Buch und ein Abend ohne Handy.",
            ],
            tags: ["arbeit", "familie", "laufen", "zuhause"],
            draftTitle: "Wochenendplan",
            draftBody: "Ein ruhiger Samstag, dann Abendessen mit Mia.",
            checklist: ["Zug zu meiner Schwester buchen", "Mama wegen Sonntag anrufen", "Blumen für Mia kaufen"],
            reflectionQuote: "Heute Morgen war ich nervös, aber der Auftakt lief besser als erwartet.",
            feeling: "",
            digestPicks: [
                "Ich gehe die Präsentation von morgen immer wieder im Kopf durch.",
                "Ich will sie noch vor Jahresende besuchen.",
                "Ich habe zwei weiteren Aufgaben zugesagt, für die ich keine Zeit habe.",
            ],
            englishDigest: [],
            askQuestion: "Was hebt meine Stimmung immer wieder?",
            askAnswer: "Bewegung und die Menschen, die dir nahe sind. Deine leichteren Tage folgen auf einen Lauf am Morgen oder Zeit mit der Familie, die schweren kommen nach langen Tagen voller Meetings.",
            askQuotes: ["Heute Morgen bin ich zehn Kilometer ohne Pause gelaufen.", "Ich will sie noch vor Jahresende besuchen."]
        ),
        "es": Demo(
            entries: [
                "Primera semana al frente del nuevo proyecto. Esta mañana estaba nerviosa, pero el arranque salió mejor de lo que esperaba. Lucía dijo que mi plan era el más claro que ha visto.",
                "Después de cenar llamé a mi hermana y nos reímos del verano en que nos perdimos en Lisboa. Quiero ir a verla antes de que acabe el año.",
                "Esta noche no podía desconectar. Repaso una y otra vez la presentación de mañana en la cabeza. Escribí tres comienzos y los borré todos.",
                "Esta mañana corrí diez kilómetros sin parar. Al principio tenía las piernas pesadas y luego todo fue fácil. Hice tortitas para celebrarlo.",
                "Un día largo de reuniones seguidas. Dije que sí a dos tareas más para las que no tengo tiempo. Mañana tengo que decir que no a algo.",
                "Una tarde tranquila en casa. Trasplanté las plantas del balcón y leí hasta que se fue la luz. El móvil se quedó en la otra habitación.",
                "Salí a correr temprano junto al río antes del trabajo. El aire era frío y limpio. Volví con una lista de ideas para el proyecto.",
                "El lanzamiento se retrasó otra vez por una aprobación que falta. Estoy cansada de esperar decisiones que no puedo tomar yo.",
                "Comida del domingo en casa de mamá. Me enseñó sus tomates y me dio demasiados para llevar. Un día sencillo y bueno.",
                "Marta me arregló la bici y no quiso nada a cambio. Le dejé una nota y su té favorito en la puerta.",
                "Llegó el correo: el proyecto es mío. Estoy ilusionada y un poco asustada. Empiezo una lista de cómo quiero que se sienta esto.",
                "Lluvia todo el día, así que me quedé en casa. Terminé mi libro con un café y dejé los platos para luego.",
                "Salí a correr al parque con Marta, mi amiga del trabajo. Nos apuntamos a la carrera de primavera y empezamos el entrenamiento juntas.",
                "No pude dormir antes de la entrevista. Mi jefa dice que el equipo necesita a alguien que lidere el próximo proyecto.",
                "Hice la cena para mi hermana y mamá. Nos sentamos en el jardín y hablamos de un viaje a Lisboa.",
                "Cumpleaños de mamá. Vino toda la familia y mi hermana hizo su famosa tarta.",
                "Primera carrera después de una semana de mal sueño. Despacio, pero el camino junto al río era precioso y volví a sentirme yo.",
                "Apunté mi meta para el otoño: correr, un libro y una tarde sin móvil cada semana.",
            ],
            tags: ["trabajo", "familia", "correr", "casa"],
            draftTitle: "Plan de fin de semana",
            draftBody: "Un sábado tranquilo y luego cena con Marta.",
            checklist: ["Reservar el tren para ver a mi hermana", "Llamar a mamá por lo del domingo", "Comprar flores para Marta"],
            reflectionQuote: "Esta mañana estaba nerviosa, pero el arranque salió mejor de lo que esperaba.",
            feeling: "",
            digestPicks: [
                "Repaso una y otra vez la presentación de mañana en la cabeza.",
                "Quiero ir a verla antes de que acabe el año.",
                "Dije que sí a dos tareas más para las que no tengo tiempo.",
            ],
            englishDigest: [],
            askQuestion: "¿Qué me sube el ánimo?",
            askAnswer: "Moverte y la gente cercana. Tus días más ligeros vienen después de correr por la mañana o de pasar tiempo con la familia, y los más pesados, tras días largos de reuniones.",
            askQuotes: ["Esta mañana corrí diez kilómetros sin parar.", "Quiero ir a verla antes de que acabe el año."]
        ),
        "fr": Demo(
            entries: [
                "Première semaine à la tête du nouveau projet. Ce matin j'étais nerveuse, mais le lancement s'est mieux passé que prévu. Camille a dit que mon plan était le plus clair qu'elle ait vu.",
                "Après le dîner, j'ai appelé ma sœur et on a ri de l'été où on s'était perdues à Lisbonne. Je veux aller la voir avant la fin de l'année.",
                "Impossible de décrocher ce soir. Je repasse sans arrêt la présentation de demain dans ma tête. J'ai écrit trois débuts et je les ai tous effacés.",
                "Ce matin, j'ai couru dix kilomètres sans m'arrêter. Au début mes jambes étaient lourdes, puis tout est devenu facile. J'ai fait des crêpes pour fêter ça.",
                "Une longue journée de réunions enchaînées. J'ai accepté deux tâches de plus pour lesquelles je n'ai pas le temps. Demain, je dois dire non à quelque chose.",
                "Une soirée calme à la maison. J'ai rempoté les plantes du balcon et j'ai lu jusqu'à la tombée de la nuit. Le téléphone est resté dans l'autre pièce.",
                "Course matinale au bord de la rivière avant le travail. L'air était froid et clair. Je suis revenue avec une liste d'idées pour le projet.",
                "La sortie a encore été repoussée à cause d'une validation manquante. J'en ai assez d'attendre des décisions que je ne peux pas prendre moi-même.",
                "Déjeuner du dimanche chez maman. Elle m'a montré ses tomates et m'en a donné beaucoup trop. Une journée simple et bonne.",
                "Inès a réparé mon vélo et n'a rien voulu en échange. Je lui ai laissé un mot et son thé préféré devant la porte.",
                "Le mail est arrivé : le projet est à moi. Je suis contente et un peu effrayée. Je commence une liste de ce que je veux ressentir.",
                "Pluie toute la journée, alors je suis restée à la maison. J'ai fini mon livre avec un café et laissé la vaisselle attendre.",
                "Je suis allée courir au parc avec Inès, mon amie du travail. On s'est inscrites à la course du printemps et on a commencé l'entraînement ensemble.",
                "Impossible de dormir avant l'entretien. Ma manager dit que l'équipe a besoin de quelqu'un pour mener le prochain projet.",
                "J'ai préparé le dîner pour ma sœur et maman. On s'est assises au jardin et on a parlé d'un voyage à Lisbonne.",
                "L'anniversaire de maman. Toute la famille est venue, et ma sœur a fait son fameux gâteau.",
                "Première course après une semaine de mauvais sommeil. Lentement, mais le chemin le long de la rivière était magnifique et je me suis retrouvée.",
                "J'ai noté mon objectif pour l'automne : courir, un livre et une soirée sans téléphone chaque semaine.",
            ],
            tags: ["travail", "famille", "course", "maison"],
            draftTitle: "Programme du week-end",
            draftBody: "Un samedi tranquille, puis dîner avec Inès.",
            checklist: ["Réserver le train pour voir ma sœur", "Appeler maman pour dimanche", "Acheter des fleurs pour Inès"],
            reflectionQuote: "Ce matin j'étais nerveuse, mais le lancement s'est mieux passé que prévu.",
            feeling: "",
            digestPicks: [
                "Je repasse sans arrêt la présentation de demain dans ma tête.",
                "Je veux aller la voir avant la fin de l'année.",
                "J'ai accepté deux tâches de plus pour lesquelles je n'ai pas le temps.",
            ],
            englishDigest: [],
            askQuestion: "Qu'est-ce qui me remonte le moral ?",
            askAnswer: "Bouger et les personnes proches de vous. Vos journées plus légères suivent une course matinale ou un moment en famille, et les plus lourdes arrivent après de longues journées de réunions.",
            askQuotes: ["Ce matin, j'ai couru dix kilomètres sans m'arrêter.", "Je veux aller la voir avant la fin de l'année."]
        ),
        "it": Demo(
            entries: [
                "Prima settimana alla guida del nuovo progetto. Stamattina ero nervosa, ma il kickoff è andato meglio del previsto. Giulia ha detto che il mio piano è il più chiaro che abbia mai visto.",
                "Dopo cena ho chiamato mia sorella e abbiamo riso dell'estate in cui ci siamo perse a Lisbona. Voglio andarla a trovare prima della fine dell'anno.",
                "Stasera non riuscivo a staccare. Continuo a ripassare in testa la presentazione di domani. Ho scritto tre inizi e li ho cancellati tutti.",
                "Stamattina ho corso dieci chilometri senza fermarmi. All'inizio avevo le gambe pesanti, poi è diventato tutto facile. Ho fatto i pancake per festeggiare.",
                "Una lunga giornata di riunioni una dopo l'altra. Ho detto di sì ad altri due compiti per cui non ho tempo. Domani devo dire di no a qualcosa.",
                "Una sera tranquilla a casa. Ho rinvasato le piante del balcone e ho letto finché c'era luce. Il telefono è rimasto nell'altra stanza.",
                "Corsa presto lungo il fiume prima del lavoro. L'aria era fredda e limpida. Sono tornata con una lista di idee per il progetto.",
                "Il rilascio è slittato di nuovo per un'approvazione mancante. Sono stanca di aspettare decisioni che non posso prendere io.",
                "Pranzo della domenica dalla mamma. Mi ha mostrato i suoi pomodori e me ne ha dati fin troppi. Una giornata semplice e bella.",
                "Sara mi ha aggiustato la bici e non ha voluto niente in cambio. Le ho lasciato un biglietto e il suo tè preferito davanti alla porta.",
                "È arrivata la mail: il progetto è mio. Sono emozionata e un po' spaventata. Comincio una lista di come voglio che sia.",
                "Pioggia tutto il giorno, così sono rimasta a casa. Ho finito il mio libro con un caffè e ho lasciato i piatti per dopo.",
                "Sono andata a correre al parco con Sara, la mia amica del lavoro. Ci siamo iscritte alla corsa di primavera e abbiamo iniziato l'allenamento insieme.",
                "Non riuscivo a dormire prima del colloquio. Il mio capo dice che la squadra ha bisogno di qualcuno che guidi il prossimo progetto.",
                "Ho preparato la cena per mia sorella e la mamma. Ci siamo sedute in giardino e abbiamo parlato di un viaggio a Lisbona.",
                "Il compleanno della mamma. È venuta tutta la famiglia e mia sorella ha fatto la sua famosa torta.",
                "Prima corsa dopo una settimana di sonno pessimo. Piano, ma il sentiero lungo il fiume era bellissimo e mi sono sentita di nuovo me stessa.",
                "Ho scritto il mio obiettivo per l'autunno: una corsa, un libro e una sera senza telefono ogni settimana.",
            ],
            tags: ["lavoro", "famiglia", "corsa", "casa"],
            draftTitle: "Piano del weekend",
            draftBody: "Un sabato lento, poi cena con Sara.",
            checklist: ["Prenotare il treno per andare da mia sorella", "Chiamare la mamma per domenica", "Comprare dei fiori per Sara"],
            reflectionQuote: "Stamattina ero nervosa, ma il kickoff è andato meglio del previsto.",
            feeling: "",
            digestPicks: [
                "Continuo a ripassare in testa la presentazione di domani.",
                "Voglio andarla a trovare prima della fine dell'anno.",
                "Ho detto di sì ad altri due compiti per cui non ho tempo.",
            ],
            englishDigest: [],
            askQuestion: "Cosa mi tira su di morale?",
            askAnswer: "Muoverti e le persone vicine a te. Le giornate più leggere arrivano dopo una corsa al mattino o del tempo con la famiglia, quelle più pesanti dopo lunghe giornate di riunioni.",
            askQuotes: ["Stamattina ho corso dieci chilometri senza fermarmi.", "Voglio andarla a trovare prima della fine dell'anno."]
        ),
        "ja": Demo(
            entries: [
                "新しいプロジェクトのリーダーになって最初の週。今朝は緊張していたけれど、キックオフは思っていたよりうまくいった。美咲さんが、こんなに分かりやすい計画は初めてだと言ってくれた。",
                "夕食のあと姉に電話して、リスボンで迷子になった夏の話で笑った。年内に姉に会いに行きたい。",
                "今夜は頭を切り替えられなかった。明日のプレゼンを何度も頭の中でなぞっている。冒頭を三回書いて、全部消した。",
                "今朝は十キロを止まらずに走った。最初は脚が重かったけれど、途中から楽になった。お祝いにパンケーキを焼いた。",
                "会議が続いた長い一日だった。時間がないのに、また二つの仕事を引き受けてしまった。明日は何かを断らないといけない。",
                "家で静かな夜を過ごした。ベランダの植物を植え替えて、暗くなるまで本を読んだ。スマホは別の部屋に置いたままだった。",
                "仕事の前に川沿いを走った。空気は冷たくて澄んでいた。プロジェクトのアイデアをたくさん持ち帰った。",
                "承認が一つ足りないせいで、リリースがまた延びた。自分では決められないことを待つのに疲れた。",
                "日曜のお昼を母の家で食べた。母が育てたトマトを見せてくれて、たくさん持たせてくれた。シンプルでいい一日だった。",
                "由佳さんが自転車を直してくれて、お礼を受け取ってくれなかった。手紙と好きな紅茶をドアの前に置いてきた。",
                "メールが来た。プロジェクトを任されることになった。うれしいけれど、少し怖い。どんな気持ちで進めたいか、リストを書き始めた。",
                "一日中雨だったので、家で過ごした。コーヒーを飲みながら本を読み終えて、皿洗いは後回しにした。",
                "職場の友達の由佳さんと公園でランニングした。春のマラソンに申し込んで、一緒にトレーニングを始めた。",
                "面接の前の夜は眠りが浅かった。上司が、次のプロジェクトを任せられる人がチームに必要だと言っていた。",
                "姉と母のために夕食を作った。庭に座って、リスボン旅行の話をした。",
                "母の誕生日。家族みんなが集まって、姉が得意のケーキを焼いた。",
                "寝不足の一週間のあと、久しぶりのランニング。ゆっくりだったけれど、川沿いの道がきれいで、自分を取り戻せた気がした。",
                "秋の目標を書き出した。毎週、ランニングと読書を一回ずつ、スマホを見ない夜を一晩。",
            ],
            tags: ["仕事", "家族", "ランニング", "家"],
            draftTitle: "週末の予定",
            draftBody: "のんびり土曜日、夜は由佳さんと夕食。",
            checklist: ["姉に会いに行く電車を予約する", "日曜のことで母に電話する", "由佳さんに花を買う"],
            reflectionQuote: "今朝は緊張していたけれど、キックオフは思っていたよりうまくいった。",
            feeling: "",
            digestPicks: [
                "明日のプレゼンを何度も頭の中でなぞっている。",
                "年内に姉に会いに行きたい。",
                "時間がないのに、また二つの仕事を引き受けてしまった。",
            ],
            englishDigest: [],
            askQuestion: "何が気分を上げてくれている？",
            askAnswer: "体を動かすことと、身近な人たちです。気持ちが軽い日は朝のランニングや家族との時間のあとに続き、重い日は会議の多い長い一日のあとに来ています。",
            askQuotes: ["今朝は十キロを止まらずに走った。", "年内に姉に会いに行きたい。"]
        ),
        "ko": Demo(
            entries: [
                "새 프로젝트를 맡고 맞은 첫 주. 오늘 아침엔 긴장했는데, 킥오프는 생각보다 훨씬 잘 끝났다. 지은 씨가 이렇게 명확한 계획은 처음 본다고 했다.",
                "저녁을 먹고 언니에게 전화했고, 리스본에서 길을 잃었던 여름 이야기로 한참 웃었다. 올해가 가기 전에 언니를 보러 가고 싶다.",
                "오늘 밤은 도무지 머리가 꺼지지 않았다. 내일 발표를 머릿속으로 계속 되풀이하고 있다. 첫 부분을 세 번이나 썼다가 전부 지웠다.",
                "오늘 아침 10킬로미터를 쉬지 않고 달렸다. 처음엔 다리가 무거웠는데 어느 순간 다 가벼워졌다. 기념으로 팬케이크를 구웠다.",
                "회의가 쉴 틈 없이 이어진 긴 하루였다. 시간도 없는데 일을 두 개나 더 맡아 버렸다. 내일은 뭔가 하나는 거절해야 한다.",
                "집에서 조용한 저녁을 보냈다. 베란다 화분을 분갈이하고 해가 질 때까지 책을 읽었다. 휴대폰은 다른 방에 두었다.",
                "출근 전에 강가를 따라 일찍 달렸다. 공기가 차갑고 맑았다. 프로젝트 아이디어를 잔뜩 들고 돌아왔다.",
                "승인 하나가 빠져서 출시가 또 미뤄졌다. 내가 내릴 수 없는 결정을 기다리는 데 지쳤다.",
                "일요일 점심을 엄마 집에서 먹었다. 엄마가 키운 토마토를 보여 주고 잔뜩 싸 주셨다. 소박하고 좋은 하루였다.",
                "수진 씨가 자전거를 고쳐 주고는 아무것도 받지 않았다. 문 앞에 쪽지와 좋아하는 차를 두고 왔다.",
                "메일이 왔다. 프로젝트를 내가 맡게 됐다. 설레면서도 조금 무섭다. 어떤 마음으로 해 나가고 싶은지 목록을 쓰기 시작했다.",
                "하루 종일 비가 와서 집에 있었다. 커피를 마시며 책을 끝까지 읽고 설거지는 나중으로 미뤘다.",
                "회사 친구 수진 씨와 공원에서 달리기를 했다. 봄 마라톤에 신청하고 함께 운동을 시작했다.",
                "면접 전날 밤에 잠을 거의 못 잤다. 팀장님이 다음 프로젝트를 이끌 사람이 팀에 필요하다고 했다.",
                "언니와 엄마를 위해 저녁을 만들었다. 정원에 앉아 리스본 여행 이야기를 했다.",
                "엄마 생일. 가족이 다 모였고, 언니가 자랑하는 케이크를 구웠다.",
                "잠을 설친 한 주 끝에 오랜만에 달리기를 했다. 느렸지만 강가 길이 아름다워서 다시 나 자신이 된 기분이었다.",
                "가을 목표를 적었다. 매주 달리기 한 번, 책 한 권, 휴대폰 없는 저녁 한 번.",
            ],
            tags: ["일", "가족", "달리기", "집"],
            draftTitle: "주말 계획",
            draftBody: "느긋한 토요일, 저녁엔 수진 씨와 식사.",
            checklist: ["언니 보러 가는 기차 예매하기", "일요일 일로 엄마에게 전화하기", "수진 씨에게 줄 꽃 사기"],
            reflectionQuote: "오늘 아침엔 긴장했는데, 킥오프는 생각보다 훨씬 잘 끝났다.",
            feeling: "",
            digestPicks: [
                "내일 발표를 머릿속으로 계속 되풀이하고 있다.",
                "올해가 가기 전에 언니를 보러 가고 싶다.",
                "시간도 없는데 일을 두 개나 더 맡아 버렸다.",
            ],
            englishDigest: [],
            askQuestion: "무엇이 내 기분을 좋게 해 줄까?",
            askAnswer: "몸을 움직이는 것과 가까운 사람들이에요. 가벼운 날은 아침 달리기나 가족과 보낸 시간 뒤에 오고, 무거운 날은 회의가 많은 긴 하루 뒤에 와요.",
            askQuotes: ["오늘 아침 10킬로미터를 쉬지 않고 달렸다.", "올해가 가기 전에 언니를 보러 가고 싶다."]
        ),
        "pt": Demo(
            entries: [
                "Primeira semana à frente do novo projeto. Hoje de manhã eu estava nervosa, mas o kickoff foi melhor do que eu esperava. A Ana disse que meu plano era o mais claro que ela já viu.",
                "Depois do jantar liguei para minha irmã e rimos do verão em que nos perdemos em Lisboa. Quero visitá-la antes de o ano acabar.",
                "Não consegui desligar hoje à noite. Fico repassando a apresentação de amanhã na cabeça. Escrevi três começos e apaguei todos.",
                "Hoje de manhã corri dez quilômetros sem parar. No começo as pernas estavam pesadas, depois tudo ficou fácil. Fiz panquecas para comemorar.",
                "Um dia longo de reuniões seguidas. Disse sim a mais duas tarefas para as quais não tenho tempo. Amanhã preciso dizer não a alguma coisa.",
                "Uma noite tranquila em casa. Troquei as plantas da varanda de vaso e li até escurecer. O celular ficou no outro quarto.",
                "Corri cedo na beira do rio antes do trabalho. O ar estava frio e limpo. Voltei com uma lista de ideias para o projeto.",
                "O lançamento atrasou de novo por causa de uma aprovação que falta. Estou cansada de esperar decisões que não posso tomar sozinha.",
                "Almoço de domingo na casa da minha mãe. Ela me mostrou os tomates dela e me deu tomates demais para levar. Um dia simples e bom.",
                "A Bia consertou minha bicicleta e não quis nada em troca. Deixei um bilhete e o chá favorito dela na porta.",
                "Chegou o e-mail: o projeto é meu. Estou animada e um pouco assustada. Começando uma lista de como quero que isso seja.",
                "Chuva o dia todo, então fiquei em casa. Terminei meu livro com um café e deixei a louça para depois.",
                "Fui correr no parque com a Bia, minha amiga do trabalho. Nos inscrevemos na corrida da primavera e começamos o treino juntas.",
                "Não consegui dormir antes da entrevista. Minha chefe diz que a equipe precisa de alguém para liderar o próximo projeto.",
                "Fiz o jantar para minha irmã e minha mãe. Sentamos no jardim e conversamos sobre uma viagem a Lisboa.",
                "Aniversário da minha mãe. A família toda veio, e minha irmã fez o famoso bolo dela.",
                "Primeira corrida depois de uma semana de sono ruim. Devagar, mas o caminho à beira do rio estava lindo e voltei a me sentir eu mesma.",
                "Anotei minha meta para o outono: uma corrida, um livro e uma noite sem celular toda semana.",
            ],
            tags: ["trabalho", "família", "corrida", "casa"],
            draftTitle: "Plano do fim de semana",
            draftBody: "Um sábado tranquilo e depois jantar com a Bia.",
            checklist: ["Comprar o trem para visitar minha irmã", "Ligar para minha mãe sobre domingo", "Comprar flores para a Bia"],
            reflectionQuote: "Hoje de manhã eu estava nervosa, mas o kickoff foi melhor do que eu esperava.",
            feeling: "",
            digestPicks: [
                "Fico repassando a apresentação de amanhã na cabeça.",
                "Quero visitá-la antes de o ano acabar.",
                "Disse sim a mais duas tarefas para as quais não tenho tempo.",
            ],
            englishDigest: [],
            askQuestion: "O que costuma melhorar meu humor?",
            askAnswer: "Se mexer e as pessoas próximas. Seus dias mais leves vêm depois de uma corrida de manhã ou de um tempo com a família, e os mais pesados, depois de dias longos de reuniões.",
            askQuotes: ["Hoje de manhã corri dez quilômetros sem parar.", "Quero visitá-la antes de o ano acabar."]
        ),
        "ru": Demo(
            entries: [
                "Первая неделя во главе нового проекта. Утром я нервничала, но запуск прошёл лучше, чем я ожидала. Аня сказала, что такого понятного плана она ещё не видела.",
                "После ужина позвонила сестре, и мы смеялись над тем летом, когда заблудились в Лиссабоне. Хочу съездить к ней до конца года.",
                "Сегодня вечером никак не могла отключиться. Снова и снова прокручиваю в голове завтрашнюю презентацию. Написала три вступления и все удалила.",
                "Утром пробежала десять километров без остановки. Сначала ноги были тяжёлыми, а потом стало легко. В честь этого испекла блинчики.",
                "Длинный день сплошных встреч. Согласилась ещё на две задачи, на которые у меня нет времени. Завтра нужно от чего-то отказаться.",
                "Тихий вечер дома. Пересадила растения на балконе и читала, пока не стемнело. Телефон остался в другой комнате.",
                "Рано утром перед работой пробежка вдоль реки. Воздух был холодный и чистый. Вернулась со списком идей для проекта.",
                "Релиз снова сдвинулся из-за одного недостающего согласования. Я устала ждать решений, которые не могу принять сама.",
                "Воскресный обед у мамы. Она показала мне свои помидоры и дала с собой слишком много. Простой и хороший день.",
                "Катя починила мой велосипед и ничего не взяла. Я оставила у её двери записку и её любимый чай.",
                "Пришло письмо: проект мой. Я рада и немного боюсь. Начинаю список того, каким я хочу видеть этот проект.",
                "Весь день шёл дождь, так что я осталась дома. Дочитала книгу за чашкой кофе и оставила посуду на потом.",
                "Бегала в парке с Катей, моей подругой с работы. Мы записались на весенний забег и начали тренировки вместе.",
                "Перед собеседованием совсем не было сна. Начальница говорит, что команде нужен человек, который возглавит следующий проект.",
                "Приготовила ужин для сестры и мамы. Мы сидели в саду и говорили о поездке в Лиссабон.",
                "День рождения мамы. Приехала вся семья, а сестра испекла свой знаменитый торт.",
                "Первая пробежка после недели плохого сна. Медленно, но тропа вдоль реки была красивой, и я снова почувствовала себя собой.",
                "Записала цель на осень: пробежка, книга и вечер без телефона каждую неделю.",
            ],
            tags: ["работа", "семья", "бег", "дом"],
            draftTitle: "Планы на выходные",
            draftBody: "Спокойная суббота, а вечером ужин с Катей.",
            checklist: ["Купить билет на поезд к сестре", "Позвонить маме насчёт воскресенья", "Купить цветы для Кати"],
            reflectionQuote: "Утром я нервничала, но запуск прошёл лучше, чем я ожидала.",
            feeling: "",
            digestPicks: [
                "Снова и снова прокручиваю в голове завтрашнюю презентацию.",
                "Хочу съездить к ней до конца года.",
                "Согласилась ещё на две задачи, на которые у меня нет времени.",
            ],
            englishDigest: [],
            askQuestion: "Что поднимает мне настроение?",
            askAnswer: "Движение и близкие люди. Лёгкие дни идут после утренней пробежки или времени с семьёй, а тяжёлые — после долгих дней со встречами.",
            askQuotes: ["Утром пробежала десять километров без остановки.", "Хочу съездить к ней до конца года."]
        ),
        "zh": Demo(
            entries: [
                "带领新项目的第一周。今天早上我很紧张，但启动会比我预想的顺利。林悦说我的计划是她见过最清楚的。",
                "晚饭后给姐姐打了电话，我们聊起那年夏天在里斯本迷路的事，笑了很久。我想在年底前去看她。",
                "今晚怎么也停不下来。我在脑子里一遍遍过明天的演讲。开头写了三个版本，全都删掉了。",
                "今天早上一口气跑了十公里。一开始腿很沉，后来一切都变得轻松了。做了松饼庆祝一下。",
                "一整天的会议一个接一个。我又答应了两件根本没时间做的事。明天得拒绝点什么。",
                "在家度过了一个安静的晚上。我给阳台的植物换了盆，一直看书到天黑。手机一直放在另一个房间。",
                "上班前沿着河边早跑。空气又冷又清新。我带着一串项目的想法回来了。",
                "因为少了一个审批，发布又推迟了。我已经厌倦了等待那些我自己做不了的决定。",
                "周日在妈妈家吃午饭。她带我看了她种的番茄，还让我带走了太多。简单而美好的一天。",
                "小雨帮我修好了自行车，什么都不肯收。我在她门口留了一张便条和她最爱的茶。",
                "邮件来了：这个项目交给我了。我很兴奋，也有点害怕。开始列一张清单，写下我希望它是什么样子。",
                "下了一整天的雨，我就待在家里。喝着咖啡看完了一本书，洗碗的事先放一放。",
                "和小雨在公园跑步，她是我工作上的朋友。我们报名了春季马拉松，开始一起锻炼。",
                "面试前一晚失眠了。经理说团队需要有人来带下一个项目。",
                "给姐姐和妈妈做了晚饭。我们坐在花园里，聊起去里斯本旅行的事。",
                "妈妈的生日。家人都来了，姐姐做了她拿手的蛋糕。",
                "睡眠不好的一周之后，终于又去跑步了。很慢，但河边的小路很美，我又找回了自己。",
                "写下了秋天的目标：每周跑步一次、读一本书、有一个不碰手机的晚上。",
            ],
            tags: ["工作", "家人", "跑步", "家"],
            draftTitle: "周末计划",
            draftBody: "悠闲的周六，晚上和小雨吃饭。",
            checklist: ["订去看姐姐的火车票", "给妈妈打电话说周日的事", "给小雨买花"],
            reflectionQuote: "今天早上我很紧张，但启动会比我预想的顺利。",
            feeling: "",
            digestPicks: [
                "我在脑子里一遍遍过明天的演讲。",
                "我想在年底前去看她。",
                "我又答应了两件根本没时间做的事。",
            ],
            englishDigest: [],
            askQuestion: "什么总能让我心情变好？",
            askAnswer: "运动和身边的人。你轻松的日子往往跟在晨跑或陪家人之后，沉重的日子则出现在开了一整天会之后。",
            askQuotes: ["今天早上一口气跑了十公里。", "我想在年底前去看她。"]
        ),
    ]
}
#endif
