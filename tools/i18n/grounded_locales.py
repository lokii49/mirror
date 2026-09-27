#!/usr/bin/env python3
# Source of truth for InsightService.groundedLocales (the fixed, translated text composed around
# quotes Gemma picks outside English). Edit here, run `python3 tools/i18n/grounded_locales.py
# --write`, review the Swift diff. `--csv` exports every user-facing string for a translator.
# Register: the AI voice is a close friend — du / tú / tu / tu / você / ты, polite です・ます / 해요체.
import sys, csv, re
NB = " "   # French: non-breaking space inside « » and before : ; ? !
T, S, D, G, N = "tired", "stressed", "sad", "good", "neutral"

L = {}
L["de"] = dict(
    open="„", close="“", joiner=" ", youWrote="Du hast geschrieben: ",
    moodWord={T: "erschöpft", S: "gestresst", D: "traurig", G: "gut"},
    pickNudge="Kopiere Wort für Wort den Satz aus dem Tagebucheintrag, der am besten erklärt, warum sich die Person {mood} fühlte. Gib nur diesen Satz aus.",
    pickNeutral="Kopiere Wort für Wort den Satz aus dem Tagebucheintrag, der das Wichtigste des Tages zeigt. Gib nur diesen Satz aus.",
    pickDigest="Kopiere drei Sätze Wort für Wort aus den Tagebucheinträgen, jeden in einer eigenen Zeile: zuerst den Satz, der zeigt, wann die Person am erschöpftesten wirkte, dann einen Satz über etwas Gutes, das wächst, dann einen Satz über etwas, das sie belasten könnte. Gib nur diese drei Sätze aus.",
    pickAsk="Kopiere Wort für Wort den einen Satz (oder höchstens zwei Sätze) aus den Tagebucheinträgen, die die Frage am besten beantworten, jeden in einer eigenen Zeile. Gib nur diese Sätze aus.",
    pickMonthly="Kopiere drei Sätze Wort für Wort aus den Tagebucheinträgen, jeden in einer eigenen Zeile: zuerst einen Satz über einen Moment, der in diesem Monat etwas verändert hat, dann einen hoffnungsvollen Satz, dann einen schweren Satz. Gib nur diese drei Sätze aus.",
    entryLabel="Tagebucheintrag:", weekLabel="Tagebucheinträge dieser Woche:", monthLabel="Tagebucheinträge dieses Monats:", entriesLabel="Tagebucheinträge:", questionLabel="Frage:",
    feel={T: ["Das klingt nach einem Tag, der viel Kraft gekostet hat. Gönn dir heute Abend etwas Ruhe.", "Du wirkst ziemlich erschöpft. Ein ruhiger, langsamer Abend könnte guttun."],
          S: ["Das klingt nach ziemlich viel auf einmal. Vielleicht hilft es, eine kleine Sache zuerst zu erledigen.", "Du wirkst unter Druck. Eine kurze Pause könnte dir helfen, durchzuatmen."],
          D: ["Das klingt schwer. Sei heute behutsam mit dir.", "Du wirkst niedergeschlagen. Es ist in Ordnung, es langsam angehen zu lassen."],
          G: ["Das klingt nach einem guten Moment. Halte ihn fest.", "Du wirkst leichter. Vielleicht lohnt es sich zu merken, was dir gutgetan hat."],
          N: ["Schön, dass du es aufgeschrieben hast.", "Das ist es wert, bemerkt zu werden."]},
    theme={T: "Eine Woche, die viel Kraft gekostet hat.", S: "Eine Woche mit viel Druck.", D: "Eine schwere Woche.", G: "Eine Woche mit guten Momenten.", N: "Eine Woche mit Höhen und Tiefen."},
    energyHard="Am schwersten wirkte es, als du schriebst: ", energyGood="Am leichtesten wirkte es, als du schriebst: ",
    buildingSuffix="Daran lässt sich anknüpfen.", watchSuffix="Behalte das im Blick.",
    boost={T: "Plane bewusst einen ruhigen Abend nur für dich ein.", S: "Such dir eine kleine Aufgabe aus, die du heute abschließen kannst.", D: "Melde dich bei jemandem, dem du vertraust.", G: "Mach mehr von dem, was dir diese Woche gutgetan hat.", N: "Nimm dir fünf Minuten für etwas, das dir guttut."},
    nextWeek={T: "Schütze deinen Schlaf und plane Pausen ein.", S: "Nimm dir jeden Tag nur eine wichtige Sache vor.", D: "Sei geduldig mit dir und schreib weiter auf, wie es dir geht.", G: "Halte fest, was funktioniert hat.", N: "Achte darauf, was dir Energie gibt und was sie nimmt."},
    askPrefix="Am nächsten kommt, was du geschrieben hast:",
    monthImage={T: "Eine Kerze, die an beiden Enden brennt.", S: "Ein Kessel kurz vor dem Kochen.", D: "Ein grauer Himmel, der noch nicht aufgeklart ist.", G: "Ein Fenster, das sich zum Morgenlicht öffnet.", N: "Wetter, das ständig wechselte – Sonne, dann Regen, dann wieder Sonne."},
    monthTension={T: "Zwischen allem, was deine Energie fordert, und der Ruhe, die du brauchst.", S: "Zwischen dem, was von dir erwartet wird, und dem, was du tragen kannst.", D: "Zwischen dem Wunsch weiterzugehen und der Zeit, die du zum Fühlen brauchst.", G: "Zwischen dem Genießen des Guten und der Frage, ob es bleibt.", N: "Zwischen den Tagen, die dich Kraft gekostet haben, und denen, die dir Kraft zurückgaben."},
    monthQuestion={T: "Was könntest du loslassen, um im nächsten Monat mehr Energie zu haben?", S: "Welche eine Sache könntest du dir im nächsten Monat vom Tisch nehmen?", D: "Wer oder was könnte dich im nächsten Monat ein bisschen mehr stützen?", G: "Was würde dir helfen, im nächsten Monat mehr davon zu behalten?", N: "Was hat dir diesen Monat Energie gegeben, und wie könntest du mehr Raum dafür schaffen?"},
    momentLead="Am {date} hast du geschrieben: ", momentSuffix="Solche Momente sagen viel über deinen Monat.",
    becomingSuffix="Du scheinst zu lernen, darauf zu achten, was dir guttut.", releaseSuffix="Vielleicht ist es Zeit, das nicht mehr so festzuhalten.",
    releaseFallback="Nichts in diesem Monat scheint danach zu verlangen, losgelassen zu werden – achte weiter darauf, was dir guttut.",
)
L["es"] = dict(
    open="“", close="”", joiner=" ", youWrote="Escribiste: ",
    moodWord={T: "agotada", S: "estresada", D: "triste", G: "bien"},
    pickNudge="Copia palabra por palabra la frase de la entrada del diario que mejor explica por qué la persona se sintió {mood}. Escribe solo esa frase.",
    pickNeutral="Copia palabra por palabra la frase de la entrada del diario que muestra lo más importante del día. Escribe solo esa frase.",
    pickDigest="Copia palabra por palabra tres frases de las entradas del diario, cada una en su propia línea: primero la frase que muestra cuándo la persona parecía más agotada, luego una frase sobre algo bueno que está creciendo, y luego una frase sobre algo que podría estar pesándole. Escribe solo esas tres frases.",
    pickAsk="Copia palabra por palabra la frase (o como máximo dos frases) de las entradas del diario que mejor responden a la pregunta, cada una en su propia línea. Escribe solo esas frases.",
    pickMonthly="Copia palabra por palabra tres frases de las entradas del diario, cada una en su propia línea: primero una frase sobre un momento que cambió algo este mes, luego una frase esperanzadora, luego una frase difícil. Escribe solo esas tres frases.",
    entryLabel="Entrada del diario:", weekLabel="Entradas del diario de esta semana:", monthLabel="Entradas del diario de este mes:", entriesLabel="Entradas del diario:", questionLabel="Pregunta:",
    feel={T: ["Suena a un día que te dejó sin energía. Esta noche date un respiro.", "Parece que fue agotador. Una tarde tranquila y sin prisas podría ayudarte."],
          S: ["Suena a mucho a la vez. Quizás ayude empezar por una sola cosa pequeña.", "Parece que hay bastante presión. Una pausa corta podría ayudarte a respirar."],
          D: ["Suena difícil. Trátate con cariño hoy.", "Parece un momento duro. Está bien ir despacio."],
          G: ["Suena a un buen momento. Vale la pena guardarlo.", "Parece que hubo algo de ligereza. Quizás valga la pena notar qué te ayudó."],
          N: ["Gracias por escribirlo.", "Vale la pena fijarse en esto."]},
    theme={T: "Una semana que te pidió mucha energía.", S: "Una semana con mucha presión.", D: "Una semana difícil.", G: "Una semana con buenos momentos.", N: "Una semana con altibajos."},
    energyHard="El momento más pesado pareció ser cuando escribiste: ", energyGood="El momento más ligero pareció ser cuando escribiste: ",
    buildingSuffix="Ahí hay algo que puede crecer.", watchSuffix="Vale la pena prestarle atención.",
    boost={T: "Reserva una tarde tranquila solo para ti.", S: "Elige una tarea pequeña que puedas terminar hoy.", D: "Escríbele a alguien de confianza.", G: "Haz más de lo que te sentó bien esta semana.", N: "Tómate cinco minutos para algo que te haga bien."},
    nextWeek={T: "Cuida tu descanso y deja espacio para pausas.", S: "Céntrate en una sola cosa importante cada día.", D: "Ten paciencia contigo y sigue escribiendo cómo estás.", G: "Repite lo que funcionó.", N: "Fíjate en qué te da energía y qué te la quita."},
    askPrefix="Lo más cercano que has escrito:",
    monthImage={T: "Una vela que arde por los dos extremos.", S: "Una tetera a punto de hervir.", D: "Un cielo gris que todavía no se ha despejado.", G: "Una ventana que se abre a la luz de la mañana.", N: "Un tiempo que no dejaba de cambiar: sol, luego lluvia, luego sol otra vez."},
    monthTension={T: "Entre todo lo que te pide energía y el descanso que necesitas.", S: "Entre lo que se espera de ti y lo que puedes cargar.", D: "Entre las ganas de seguir adelante y el tiempo que necesitas para sentirlo.", G: "Entre disfrutar lo bueno y preguntarte si va a durar.", N: "Entre los días que te dejaron sin energía y los que te la devolvieron."},
    monthQuestion={T: "¿Qué podrías soltar para tener más energía el próximo mes?", S: "¿Qué cosa podrías quitarte de encima el próximo mes?", D: "¿Quién o qué podría apoyarte un poco más el próximo mes?", G: "¿Qué te ayudaría a conservar más de esto el próximo mes?", N: "¿Qué te dio energía este mes y cómo podrías hacerle más espacio?"},
    momentLead="El {date} escribiste: ", momentSuffix="Momentos así dicen mucho de tu mes.",
    becomingSuffix="Parece que estás aprendiendo a notar lo que te hace bien.", releaseSuffix="Quizás es momento de dejar de cargar con esto con tanta fuerza.",
    releaseFallback="Nada de este mes parece pedir que lo sueltes; sigue fijándote en lo que te hace bien.",
)
L["fr"] = dict(
    open="«"+NB, close=NB+"»", joiner=" ", youWrote="Tu as écrit"+NB+": ",
    moodWord={T: "épuisée", S: "stressée", D: "triste", G: "bien"},
    pickNudge="Recopie mot pour mot la phrase de l'entrée du journal qui explique le mieux pourquoi la personne s'est sentie {mood}. Écris seulement cette phrase.",
    pickNeutral="Recopie mot pour mot la phrase de l'entrée du journal qui montre le plus important de la journée. Écris seulement cette phrase.",
    pickDigest="Recopie mot pour mot trois phrases des entrées du journal, chacune sur sa propre ligne"+NB+": d'abord la phrase qui montre quand la personne semblait le plus épuisée, puis une phrase sur quelque chose de bien qui grandit, puis une phrase sur quelque chose qui pourrait lui peser. Écris seulement ces trois phrases.",
    pickAsk="Recopie mot pour mot la phrase (ou au plus deux phrases) des entrées du journal qui répondent le mieux à la question, chacune sur sa propre ligne. Écris seulement ces phrases.",
    pickMonthly="Recopie mot pour mot trois phrases des entrées du journal, chacune sur sa propre ligne"+NB+": d'abord une phrase sur un moment qui a changé quelque chose ce mois-ci, puis une phrase pleine d'espoir, puis une phrase lourde. Écris seulement ces trois phrases.",
    entryLabel="Entrée du journal"+NB+":", weekLabel="Entrées du journal de cette semaine"+NB+":", monthLabel="Entrées du journal de ce mois-ci"+NB+":", entriesLabel="Entrées du journal"+NB+":", questionLabel="Question"+NB+":",
    feel={T: ["On dirait une journée très fatigante. Accorde-toi un peu de repos ce soir.", "Ça a l'air d'avoir été épuisant. Une soirée calme pourrait te faire du bien."],
          S: ["Ça fait beaucoup à la fois. Commencer par une seule petite chose pourrait aider.", "Tu sembles sous pression. Une courte pause pourrait t'aider à souffler."],
          D: ["Ça a l'air lourd. Prends soin de toi aujourd'hui.", "Ça semble difficile. C'est normal d'y aller doucement."],
          G: ["Ça ressemble à un bon moment. Garde-le en tête.", "Ça semble plus léger. Note peut-être ce qui t'a fait du bien."],
          N: ["Merci de l'avoir écrit.", "Ça vaut la peine de le remarquer."]},
    theme={T: "Une semaine qui t'a demandé beaucoup d'énergie.", S: "Une semaine sous pression.", D: "Une semaine difficile.", G: "Une semaine avec de bons moments.", N: "Une semaine en dents de scie."},
    energyHard="Le moment le plus lourd semble être quand tu as écrit"+NB+": ", energyGood="Le moment le plus léger semble être quand tu as écrit"+NB+": ",
    buildingSuffix="Il y a là quelque chose qui peut grandir.", watchSuffix="Garde un œil là-dessus.",
    boost={T: "Prévois une soirée calme rien que pour toi.", S: "Choisis une petite tâche que tu peux terminer aujourd'hui.", D: "Écris à quelqu'un en qui tu as confiance.", G: "Refais ce qui t'a fait du bien cette semaine.", N: "Prends cinq minutes pour quelque chose qui te fait du bien."},
    nextWeek={T: "Protège ton sommeil et prévois des pauses.", S: "Concentre-toi sur une seule chose importante par jour.", D: "Prends ton temps et continue d'écrire comment tu vas.", G: "Refais ce qui a marché.", N: "Observe ce qui te donne de l'énergie et ce qui t'en prend."},
    askPrefix="Ce que tu as écrit de plus proche"+NB+":",
    monthImage={T: "Une bougie qui brûle par les deux bouts.", S: "Une bouilloire sur le point de bouillir.", D: "Un ciel gris qui ne s'est pas encore dégagé.", G: "Une fenêtre qui s'ouvre sur la lumière du matin.", N: "Une météo qui changeait sans cesse"+NB+": soleil, puis pluie, puis soleil."},
    monthTension={T: "Entre tout ce qui réclame ton énergie et le repos dont tu as besoin.", S: "Entre ce qu'on attend de toi et ce que tu peux porter.", D: "Entre l'envie d'avancer et le temps qu'il te faut pour le ressentir.", G: "Entre profiter de ce qui est bon et te demander si ça va durer.", N: "Entre les jours qui t'ont pris de l'énergie et ceux qui t'en ont redonné."},
    monthQuestion={T: "Qu'est-ce que tu pourrais lâcher pour avoir plus d'énergie le mois prochain"+NB+"?", S: "Quelle chose pourrais-tu retirer de ton assiette le mois prochain"+NB+"?", D: "Qui ou quoi pourrait te soutenir un peu plus le mois prochain"+NB+"?", G: "Qu'est-ce qui t'aiderait à garder davantage de tout ça le mois prochain"+NB+"?", N: "Qu'est-ce qui t'a donné de l'énergie ce mois-ci, et comment lui faire plus de place"+NB+"?"},
    momentLead="Le {date}, tu as écrit"+NB+": ", momentSuffix="Ce genre de moment en dit long sur ton mois.",
    becomingSuffix="Tu sembles apprendre à remarquer ce qui te fait du bien.", releaseSuffix="Il est peut-être temps de ne plus porter ça aussi fort.",
    releaseFallback="Rien ce mois-ci ne semble demander à être lâché"+NB+"; continue de remarquer ce qui te fait du bien.",
)
L["it"] = dict(
    open="“", close="”", joiner=" ", youWrote="Hai scritto: ",
    moodWord={T: "esausta", S: "stressata", D: "triste", G: "bene"},
    pickNudge="Copia parola per parola la frase della voce del diario che spiega meglio perché la persona si è sentita {mood}. Scrivi solo quella frase.",
    pickNeutral="Copia parola per parola la frase della voce del diario che mostra la cosa più importante della giornata. Scrivi solo quella frase.",
    pickDigest="Copia parola per parola tre frasi dalle voci del diario, ognuna su una riga: prima la frase che mostra quando la persona sembrava più esausta, poi una frase su qualcosa di buono che sta crescendo, poi una frase su qualcosa che potrebbe pesarle. Scrivi solo queste tre frasi.",
    pickAsk="Copia parola per parola la frase (o al massimo due frasi) delle voci del diario che rispondono meglio alla domanda, ognuna su una riga. Scrivi solo quelle frasi.",
    pickMonthly="Copia parola per parola tre frasi dalle voci del diario, ognuna su una riga: prima una frase su un momento che ha cambiato qualcosa questo mese, poi una frase piena di speranza, poi una frase pesante. Scrivi solo queste tre frasi.",
    entryLabel="Voce del diario:", weekLabel="Voci del diario di questa settimana:", monthLabel="Voci del diario di questo mese:", entriesLabel="Voci del diario:", questionLabel="Domanda:",
    feel={T: ["Sembra una giornata che ti ha tolto tante energie. Stasera concediti un po' di riposo.", "Dev'essere stata una giornata faticosa. Una serata tranquilla potrebbe farti bene."],
          S: ["Sembra tanto tutto insieme. Forse aiuta iniziare da una sola piccola cosa.", "Sembra che ci sia parecchia pressione. Una breve pausa potrebbe aiutarti a respirare."],
          D: ["Sembra pesante. Oggi trattati con gentilezza.", "Sembra un momento difficile. Va bene prendersela con calma."],
          G: ["Sembra un bel momento. Vale la pena tenerlo a mente.", "Sembra che ci sia stata un po' di leggerezza. Forse vale la pena notare cosa ti ha aiutato."],
          N: ["Grazie per averlo scritto.", "Vale la pena notarlo."]},
    theme={T: "Una settimana che ti ha chiesto molte energie.", S: "Una settimana con molta pressione.", D: "Una settimana difficile.", G: "Una settimana con bei momenti.", N: "Una settimana di alti e bassi."},
    energyHard="Il momento più pesante sembra essere stato quando hai scritto: ", energyGood="Il momento più leggero sembra essere stato quando hai scritto: ",
    buildingSuffix="Qui c'è qualcosa che può crescere.", watchSuffix="Vale la pena tenerlo d'occhio.",
    boost={T: "Tieni libera una serata tranquilla solo per te.", S: "Scegli un piccolo compito da finire oggi.", D: "Scrivi a qualcuno di cui ti fidi.", G: "Fai di più di ciò che ti ha fatto bene questa settimana.", N: "Prenditi cinque minuti per qualcosa che ti fa bene."},
    nextWeek={T: "Proteggi il sonno e prevedi delle pause.", S: "Concentrati su una sola cosa importante al giorno.", D: "Prenditi il tuo tempo e continua a scrivere come stai.", G: "Ripeti ciò che ha funzionato.", N: "Nota cosa ti dà energia e cosa te la toglie."},
    askPrefix="Le cose più vicine che hai scritto:",
    monthImage={T: "Una candela che brucia da entrambe le estremità.", S: "Un bollitore sul punto di bollire.", D: "Un cielo grigio che non si è ancora rasserenato.", G: "Una finestra che si apre sulla luce del mattino.", N: "Un tempo che cambiava di continuo: sole, poi pioggia, poi di nuovo sole."},
    monthTension={T: "Tra tutto ciò che ti chiede energia e il riposo di cui hai bisogno.", S: "Tra ciò che ci si aspetta da te e ciò che riesci a portare.", D: "Tra la voglia di andare avanti e il tempo che ti serve per sentirlo.", G: "Tra il goderti ciò che va bene e il chiederti se durerà.", N: "Tra i giorni che ti hanno tolto energia e quelli che te l'hanno restituita."},
    monthQuestion={T: "Cosa potresti lasciar andare per avere più energia il mese prossimo?", S: "Quale cosa potresti toglierti di dosso il mese prossimo?", D: "Chi o cosa potrebbe sostenerti un po' di più il mese prossimo?", G: "Cosa ti aiuterebbe a conservare di più di tutto questo il mese prossimo?", N: "Cosa ti ha dato energia questo mese, e come potresti farle più spazio?"},
    momentLead="Il {date} hai scritto: ", momentSuffix="Momenti così dicono molto del tuo mese.",
    becomingSuffix="Sembra che tu stia imparando a notare ciò che ti fa bene.", releaseSuffix="Forse è il momento di smettere di portarlo con tanta fatica.",
    releaseFallback="Niente di questo mese sembra chiedere di essere lasciato andare; continua a notare ciò che ti fa bene.",
)
L["pt"] = dict(
    open="“", close="”", joiner=" ", youWrote="Você escreveu: ",
    moodWord={T: "exausta", S: "estressada", D: "triste", G: "bem"},
    pickNudge="Copie palavra por palavra a frase da entrada do diário que melhor explica por que a pessoa se sentiu {mood}. Escreva só essa frase.",
    pickNeutral="Copie palavra por palavra a frase da entrada do diário que mostra o mais importante do dia. Escreva só essa frase.",
    pickDigest="Copie palavra por palavra três frases das entradas do diário, cada uma em sua própria linha: primeiro a frase que mostra quando a pessoa parecia mais exausta, depois uma frase sobre algo bom que está crescendo, depois uma frase sobre algo que pode estar pesando. Escreva só essas três frases.",
    pickAsk="Copie palavra por palavra a frase (ou no máximo duas frases) das entradas do diário que melhor respondem à pergunta, cada uma em sua própria linha. Escreva só essas frases.",
    pickMonthly="Copie palavra por palavra três frases das entradas do diário, cada uma em sua própria linha: primeiro uma frase sobre um momento que mudou algo neste mês, depois uma frase esperançosa, depois uma frase pesada. Escreva só essas três frases.",
    entryLabel="Entrada do diário:", weekLabel="Entradas do diário desta semana:", monthLabel="Entradas do diário deste mês:", entriesLabel="Entradas do diário:", questionLabel="Pergunta:",
    feel={T: ["Parece um dia que tirou muita energia de você. Hoje à noite, dê-se um descanso.", "Parece ter sido cansativo. Uma noite tranquila pode fazer bem a você."],
          S: ["Parece muita coisa ao mesmo tempo. Talvez ajude começar por uma coisa pequena.", "Parece que há bastante pressão. Uma pausa curta pode ajudar você a respirar."],
          D: ["Parece pesado. Seja gentil com você hoje.", "Parece um momento difícil. Tudo bem ir devagar."],
          G: ["Parece um bom momento. Vale a pena guardá-lo.", "Parece que houve um pouco de leveza. Talvez valha notar o que ajudou."],
          N: ["Que bom que você escreveu isso.", "Vale a pena notar isso."]},
    theme={T: "Uma semana que pediu muita energia.", S: "Uma semana com muita pressão.", D: "Uma semana difícil.", G: "Uma semana com bons momentos.", N: "Uma semana de altos e baixos."},
    energyHard="O momento mais pesado parece ter sido quando você escreveu: ", energyGood="O momento mais leve parece ter sido quando você escreveu: ",
    buildingSuffix="Há algo aí que pode crescer.", watchSuffix="Vale a pena ficar de olho nisso.",
    boost={T: "Reserve uma noite tranquila só para você.", S: "Escolha uma tarefa pequena para terminar hoje.", D: "Mande uma mensagem para alguém de confiança.", G: "Faça mais do que fez bem a você esta semana.", N: "Tire cinco minutos para algo que faça bem a você."},
    nextWeek={T: "Proteja seu sono e reserve pausas.", S: "Foque em uma só coisa importante por dia.", D: "Vá com calma e continue escrevendo como você está.", G: "Repita o que funcionou.", N: "Repare no que dá energia a você e no que a tira."},
    askPrefix="O mais próximo que você escreveu:",
    monthImage={T: "Uma vela queimando dos dois lados.", S: "Uma chaleira quase fervendo.", D: "Um céu cinzento que ainda não abriu.", G: "Uma janela se abrindo para a luz da manhã.", N: "Um tempo que não parava de mudar: sol, depois chuva, depois sol de novo."},
    monthTension={T: "Entre tudo o que pede sua energia e o descanso de que você precisa.", S: "Entre o que esperam de você e o que você consegue carregar.", D: "Entre a vontade de seguir em frente e o tempo de que você precisa para sentir isso.", G: "Entre aproveitar o que é bom e se perguntar se vai durar.", N: "Entre os dias que tiraram sua energia e os que a devolveram."},
    monthQuestion={T: "O que você poderia deixar de lado para ter mais energia no próximo mês?", S: "Que coisa você poderia tirar dos seus ombros no próximo mês?", D: "Quem ou o que poderia apoiar você um pouco mais no próximo mês?", G: "O que ajudaria você a manter mais disso no próximo mês?", N: "O que deu energia a você este mês, e como você poderia abrir mais espaço para isso?"},
    momentLead="Em {date}, você escreveu: ", momentSuffix="Momentos assim dizem muito sobre o seu mês.",
    becomingSuffix="Parece que você está aprendendo a perceber o que faz bem a você.", releaseSuffix="Talvez seja hora de parar de carregar isso com tanta força.",
    releaseFallback="Nada neste mês parece pedir para ser deixado de lado; continue percebendo o que faz bem a você.",
)
L["ru"] = dict(
    open="«", close="»", joiner=" ", youWrote="Ты написал(а): ",
    moodWord={T: "измотанным", S: "напряжённым", D: "грустным", G: "хорошо"},
    pickNudge="Перепиши слово в слово предложение из записи в дневнике, которое лучше всего объясняет, почему человек чувствовал себя {mood}. Выведи только это предложение.",
    pickNeutral="Перепиши слово в слово предложение из записи в дневнике, которое показывает самое важное за день. Выведи только это предложение.",
    pickDigest="Перепиши слово в слово три предложения из записей в дневнике, каждое на отдельной строке: сначала предложение, показывающее, когда человек казался самым измотанным, затем предложение о чём-то хорошем, что растёт, затем предложение о том, что может его тяготить. Выведи только эти три предложения.",
    pickAsk="Перепиши слово в слово одно предложение (или не больше двух) из записей в дневнике, которые лучше всего отвечают на вопрос, каждое на отдельной строке. Выведи только эти предложения.",
    pickMonthly="Перепиши слово в слово три предложения из записей в дневнике, каждое на отдельной строке: сначала предложение о моменте, который что-то изменил в этом месяце, затем предложение с надеждой, затем тяжёлое предложение. Выведи только эти три предложения.",
    entryLabel="Запись в дневнике:", weekLabel="Записи в дневнике за эту неделю:", monthLabel="Записи в дневнике за этот месяц:", entriesLabel="Записи в дневнике:", questionLabel="Вопрос:",
    feel={T: ["Похоже, этот день забрал много сил. Позволь себе вечером отдохнуть.", "Похоже, это было изматывающе. Спокойный вечер может помочь."],
          S: ["Похоже, всего слишком много сразу. Возможно, стоит начать с одного небольшого дела.", "Похоже, давление немаленькое. Короткая пауза может помочь выдохнуть."],
          D: ["Похоже, это тяжело. Будь сегодня бережнее к себе.", "Похоже, сейчас непросто. Можно никуда не спешить."],
          G: ["Похоже на хороший момент. Его стоит запомнить.", "Похоже, стало немного легче. Возможно, стоит заметить, что помогло."],
          N: ["Спасибо, что записал(а) это.", "Это стоит заметить."]},
    theme={T: "Неделя, которая потребовала много сил.", S: "Неделя под давлением.", D: "Тяжёлая неделя.", G: "Неделя с хорошими моментами.", N: "Неделя со взлётами и падениями."},
    energyHard="Тяжелее всего, похоже, было, когда ты написал(а): ", energyGood="Легче всего, похоже, было, когда ты написал(а): ",
    buildingSuffix="Здесь есть то, что может вырасти.", watchSuffix="За этим стоит последить.",
    boost={T: "Выдели спокойный вечер только для себя.", S: "Выбери одно небольшое дело, которое можно закончить сегодня.", D: "Напиши тому, кому доверяешь.", G: "Делай больше того, что помогло на этой неделе.", N: "Удели пять минут тому, что тебе приятно."},
    nextWeek={T: "Береги сон и планируй паузы.", S: "Бери на себя одно важное дело в день.", D: "Не торопи себя и продолжай записывать, как ты.", G: "Повтори то, что сработало.", N: "Замечай, что даёт силы, а что их забирает."},
    askPrefix="Самое близкое из того, что ты написал(а):",
    monthImage={T: "Свеча, горящая с двух концов.", S: "Чайник, который вот-вот закипит.", D: "Серое небо, которое ещё не прояснилось.", G: "Окно, открытое навстречу утреннему свету.", N: "Погода, которая всё время менялась: солнце, потом дождь, потом снова солнце."},
    monthTension={T: "Между всем, что требует твоих сил, и отдыхом, который тебе нужен.", S: "Между тем, чего от тебя ждут, и тем, что ты можешь унести.", D: "Между желанием двигаться дальше и временем, которое нужно, чтобы это прожить.", G: "Между радостью от хорошего и вопросом, надолго ли это.", N: "Между днями, которые забирали силы, и теми, что их возвращали."},
    monthQuestion={T: "От чего ты мог(ла) бы отказаться, чтобы в следующем месяце было больше сил?", S: "Какое одно дело ты мог(ла) бы снять с себя в следующем месяце?", D: "Кто или что могло бы поддержать тебя чуть больше в следующем месяце?", G: "Что помогло бы тебе сохранить больше этого в следующем месяце?", N: "Что давало тебе силы в этом месяце и как освободить для этого больше места?"},
    momentLead="{date} ты написал(а): ", momentSuffix="Такие моменты многое говорят о твоём месяце.",
    becomingSuffix="Похоже, ты учишься замечать, что тебе помогает.", releaseSuffix="Может быть, пора перестать так крепко держаться за это.",
    releaseFallback="Похоже, в этом месяце нет ничего, что просит отпустить, — продолжай замечать, что тебе помогает.",
)
L["ja"] = dict(
    open="「", close="」", joiner="", youWrote="あなたはこう書きました：",
    moodWord={T: "疲れ切っていた", S: "ストレスを感じていた", D: "悲しかった", G: "気分がよかった"},
    pickNudge="次の日記から、その人がなぜ{mood}のかをいちばんよく表している一文を、そのまま書き写してください。その一文だけを出力してください。",
    pickNeutral="次の日記から、その日いちばん大事なことを表す一文をそのまま書き写してください。その一文だけを出力してください。",
    pickDigest="次の日記から、三つの文をそのまま書き写してください。それぞれ別の行に：まず、その人がいちばん疲れていたように見える文、次に、何かよいことが育っている文、最後に、その人の負担になっていそうな文。その三つの文だけを出力してください。",
    pickAsk="次の日記から、質問にいちばんよく答えている文を一つ（多くても二つ）、そのまま書き写してください。一文ずつ別の行に。その文だけを出力してください。",
    pickMonthly="次の日記から、三つの文をそのまま書き写してください。それぞれ別の行に：まず、今月何かが変わった瞬間を表す文、次に、希望が感じられる文、最後に、重さが感じられる文。その三つの文だけを出力してください。",
    entryLabel="日記：", weekLabel="今週の日記：", monthLabel="今月の日記：", entriesLabel="日記：", questionLabel="質問：",
    feel={T: ["とても疲れる一日だったようですね。今夜はゆっくり休んでください。", "かなり消耗しているように見えます。静かな夜を過ごすといいかもしれません。"],
          S: ["いろいろなことが一度に重なっているようですね。まず小さなことを一つだけ片づけてみてはどうでしょう。", "プレッシャーが大きそうです。少し休憩をとると楽になるかもしれません。"],
          D: ["つらい時間だったようですね。今日は自分にやさしくしてください。", "気持ちが沈んでいるようです。ゆっくりで大丈夫です。"],
          G: ["いい時間だったようですね。その気持ちを大切にしてください。", "少し心が軽くなったようですね。何が助けになったのか、覚えておくといいかもしれません。"],
          N: ["書き留めてくれてありがとうございます。", "気づいておく価値のあることですね。"]},
    theme={T: "たくさんのエネルギーを使った一週間。", S: "プレッシャーの多い一週間。", D: "つらい一週間。", G: "いい時間があった一週間。", N: "浮き沈みのあった一週間。"},
    energyHard="いちばん大変そうだったのは、こう書いたときです：", energyGood="いちばん軽やかだったのは、こう書いたときです：",
    buildingSuffix="――ここから育っていくものがありそうです。", watchSuffix="――ここは少し気にかけておきましょう。",
    boost={T: "今夜は自分のための静かな時間をつくってみてください。", S: "今日終わらせられる小さなことを一つ選んでみてください。", D: "信頼できる人に連絡してみてください。", G: "今週よかったことを、もう少し続けてみてください。", N: "自分をいたわる時間を五分とってみてください。"},
    nextWeek={T: "睡眠を守って、休憩を予定に入れましょう。", S: "一日ひとつの大事なことに集中しましょう。", D: "無理せず、気持ちを書き続けましょう。", G: "うまくいったことを繰り返しましょう。", N: "何が元気をくれて、何が奪うのかに気づいてみましょう。"},
    askPrefix="いちばん近いのは、あなたが書いたこの言葉です：",
    monthImage={T: "両端から燃えているろうそく。", S: "今にも沸騰しそうなやかん。", D: "まだ晴れない灰色の空。", G: "朝の光に向かって開く窓。", N: "晴れたり雨が降ったり、めまぐるしく変わる天気。"},
    monthTension={T: "エネルギーを求めてくるすべてのことと、あなたに必要な休息とのあいだ。", S: "あなたに期待されていることと、あなたが抱えられることとのあいだ。", D: "前に進みたい気持ちと、それを感じきるための時間とのあいだ。", G: "いいことを楽しむ気持ちと、それが続くのかという思いとのあいだ。", N: "エネルギーを奪われた日々と、取り戻せた日々とのあいだ。"},
    monthQuestion={T: "来月もっと元気でいるために、手放せることは何でしょうか？", S: "来月、抱えていることを一つ減らすとしたら何でしょうか？", D: "来月、誰や何があなたをもう少し支えてくれるでしょうか？", G: "来月もこの感じを続けるために、何が助けになるでしょうか？", N: "今月あなたに元気をくれたものは何で、それをもっと増やすにはどうしたらいいでしょうか？"},
    momentLead="{date}、あなたはこう書きました：", momentSuffix="――こうした瞬間が、今月をよく表しています。",
    becomingSuffix="――何が自分の助けになるかに気づける人になりつつあるようです。", releaseSuffix="――これを、そろそろ少し手放してもいいのかもしれません。",
    releaseFallback="今月は、手放すべきものは見当たりません。何が助けになるかに、引き続き気づいていきましょう。",
)
L["ko"] = dict(
    open="“", close="”", joiner=" ", youWrote="이렇게 썼어요: ",
    moodWord={T: "지쳤는지", S: "스트레스를 받았는지", D: "슬펐는지", G: "기분이 좋았는지"},
    pickNudge="아래 일기에서 이 사람이 왜 {mood}를 가장 잘 보여 주는 문장을 그대로 옮겨 적어 주세요. 그 문장만 출력하세요.",
    pickNeutral="아래 일기에서 그날 가장 중요한 일을 보여 주는 문장을 그대로 옮겨 적어 주세요. 그 문장만 출력하세요.",
    pickDigest="아래 일기에서 세 문장을 그대로 옮겨 적어 주세요. 각 문장은 한 줄씩: 먼저 이 사람이 가장 지쳐 보였던 문장, 다음으로 좋은 일이 자라고 있는 문장, 마지막으로 이 사람에게 부담이 될 수 있는 문장. 그 세 문장만 출력하세요.",
    pickAsk="아래 일기에서 질문에 가장 잘 답하는 문장 하나(많아야 두 개)를 그대로 옮겨 적어 주세요. 한 줄에 한 문장씩. 그 문장만 출력하세요.",
    pickMonthly="아래 일기에서 세 문장을 그대로 옮겨 적어 주세요. 각 문장은 한 줄씩: 먼저 이번 달 무언가를 바꾼 순간에 관한 문장, 다음으로 희망이 느껴지는 문장, 마지막으로 무거운 문장. 그 세 문장만 출력하세요.",
    entryLabel="일기:", weekLabel="이번 주 일기:", monthLabel="이번 달 일기:", entriesLabel="일기:", questionLabel="질문:",
    feel={T: ["많이 지친 하루였던 것 같아요. 오늘 밤은 푹 쉬어요.", "꽤 힘들었던 것 같아요. 조용한 저녁이 도움이 될 수 있어요."],
          S: ["한꺼번에 많은 일이 겹친 것 같아요. 작은 일 하나부터 시작해 보면 어떨까요.", "부담이 큰 것 같아요. 잠깐 쉬어 가면 숨 돌리는 데 도움이 될 거예요."],
          D: ["마음이 무거웠던 것 같아요. 오늘은 자신에게 다정하게 대해 주세요.", "힘든 때인 것 같아요. 천천히 가도 괜찮아요."],
          G: ["좋은 순간이었던 것 같아요. 잘 간직해 두세요.", "마음이 조금 가벼워진 것 같아요. 무엇이 도움이 됐는지 기억해 두면 좋겠어요."],
          N: ["적어 줘서 고마워요.", "눈여겨볼 만한 일이에요."]},
    theme={T: "힘을 많이 쓴 한 주.", S: "부담이 많았던 한 주.", D: "힘든 한 주.", G: "좋은 순간들이 있었던 한 주.", N: "기복이 있었던 한 주."},
    energyHard="가장 힘들어 보였던 건 이렇게 썼을 때예요: ", energyGood="가장 가벼워 보였던 건 이렇게 썼을 때예요: ",
    buildingSuffix="여기서 자라날 무언가가 있어 보여요.", watchSuffix="이 부분은 조금 지켜봐 주세요.",
    boost={T: "오늘 밤은 나만을 위한 조용한 시간을 가져 보세요.", S: "오늘 끝낼 수 있는 작은 일 하나를 골라 보세요.", D: "믿을 수 있는 사람에게 연락해 보세요.", G: "이번 주에 좋았던 일을 조금 더 해 보세요.", N: "나를 위한 5분을 가져 보세요."},
    nextWeek={T: "잠을 지키고 쉬는 시간을 계획해 보세요.", S: "하루에 중요한 일 하나에만 집중해 보세요.", D: "서두르지 말고 마음을 계속 적어 보세요.", G: "잘된 일을 다시 해 보세요.", N: "무엇이 힘을 주고 무엇이 힘을 빼는지 살펴보세요."},
    askPrefix="가장 가까운 건 이렇게 쓴 내용이에요:",
    monthImage={T: "양쪽 끝에서 타들어 가는 초.", S: "곧 끓어오를 것 같은 주전자.", D: "아직 개지 않은 잿빛 하늘.", G: "아침 햇살을 향해 열리는 창문.", N: "해가 났다가 비가 왔다가, 계속 바뀌는 날씨."},
    monthTension={T: "에너지를 요구하는 모든 일과 당신에게 필요한 휴식 사이.", S: "당신에게 기대되는 것과 당신이 감당할 수 있는 것 사이.", D: "앞으로 나아가고 싶은 마음과 그 감정을 충분히 느낄 시간 사이.", G: "좋은 것을 누리는 마음과 그것이 계속될지 묻는 마음 사이.", N: "힘을 빼앗긴 날들과 힘을 되찾은 날들 사이."},
    monthQuestion={T: "다음 달에 더 힘을 내기 위해 내려놓을 수 있는 건 무엇일까요?", S: "다음 달에 덜어낼 수 있는 일 하나는 무엇일까요?", D: "다음 달에 누가, 또는 무엇이 당신을 조금 더 지지해 줄 수 있을까요?", G: "다음 달에도 이 느낌을 이어가려면 무엇이 도움이 될까요?", N: "이번 달 당신에게 힘을 준 것은 무엇이었고, 그것을 위한 자리를 어떻게 더 만들 수 있을까요?"},
    momentLead="{date}에 이렇게 썼어요: ", momentSuffix="이런 순간이 이번 달을 잘 보여 줘요.",
    becomingSuffix="무엇이 도움이 되는지 알아차리는 사람이 되어 가고 있는 것 같아요.", releaseSuffix="이제는 이걸 조금 내려놓아도 괜찮을지 몰라요.",
    releaseFallback="이번 달에는 내려놓아야 할 것이 보이지 않아요. 무엇이 도움이 되는지 계속 살펴봐 주세요.",
)
L["zh"] = dict(
    open="“", close="”", joiner="", youWrote="你写道：",
    moodWord={T: "精疲力尽", S: "有压力", D: "难过", G: "心情不错"},
    pickNudge="请把下面日记中最能解释这个人为什么感到{mood}的那一句话原样抄写下来。只输出这一句话。",
    pickNeutral="请把下面日记中最能体现这一天最重要的事的那一句话原样抄写下来。只输出这一句话。",
    pickDigest="请从下面的日记中原样抄写三句话，每句一行：第一句是这个人看起来最累的时候，第二句是关于正在成长的好事，第三句是关于可能让这个人感到负担的事。只输出这三句话。",
    pickAsk="请从下面的日记中原样抄写最能回答这个问题的一句话（最多两句），每句一行。只输出这些句子。",
    pickMonthly="请从下面的日记中原样抄写三句话，每句一行：第一句是关于这个月改变了什么的时刻，第二句是充满希望的一句，第三句是沉重的一句。只输出这三句话。",
    entryLabel="日记：", weekLabel="本周日记：", monthLabel="本月日记：", entriesLabel="日记：", questionLabel="问题：",
    feel={T: ["听起来是很耗精力的一天。今晚好好休息一下吧。", "看起来真的很累。安静地过个晚上也许会有帮助。"],
          S: ["听起来很多事情同时压过来。也许可以先从一件小事开始。", "看起来压力不小。短暂休息一下，也许能喘口气。"],
          D: ["听起来很沉重。今天对自己温柔一点。", "看起来这段时间不容易。慢慢来就好。"],
          G: ["听起来是个美好的时刻。值得记住。", "看起来心情轻松了一些。也许可以留意一下是什么帮到了你。"],
          N: ["谢谢你把它写下来。", "这值得留意。"]},
    theme={T: "耗费了很多精力的一周。", S: "压力很大的一周。", D: "艰难的一周。", G: "有美好时刻的一周。", N: "有起有落的一周。"},
    energyHard="最辛苦的时候，似乎是你写下这句话时：", energyGood="最轻松的时候，似乎是你写下这句话时：",
    buildingSuffix="这里有值得培养的东西。", watchSuffix="这一点值得留意。",
    boost={T: "今晚给自己留一段安静的时间。", S: "选一件今天能完成的小事。", D: "联系一个你信任的人。", G: "多做一些这周让你感觉好的事。", N: "花五分钟做一件让自己舒服的事。"},
    nextWeek={T: "保护好睡眠，安排一些休息。", S: "每天只专注一件重要的事。", D: "别着急，继续写下自己的感受。", G: "重复那些有效的做法。", N: "留意什么给你能量，什么在消耗你。"},
    askPrefix="和这个问题最接近的是你写的这些：",
    monthImage={T: "一支两头烧的蜡烛。", S: "一壶快要烧开的水。", D: "一片还没有放晴的灰色天空。", G: "一扇向晨光打开的窗。", N: "忽晴忽雨、变个不停的天气。"},
    monthTension={T: "在所有消耗你精力的事和你需要的休息之间。", S: "在别人对你的期待和你能承担的之间。", D: "在想要往前走的心和需要时间去感受之间。", G: "在享受美好和担心它能否持续之间。", N: "在耗尽你精力的日子和让你恢复元气的日子之间。"},
    monthQuestion={T: "下个月，你可以放下什么，让自己更有精力？", S: "下个月，你可以卸下的一件事是什么？", D: "下个月，谁或什么能多支持你一点？", G: "下个月，什么能帮你留住更多这样的感觉？", N: "这个月是什么给了你能量？你可以怎样为它留出更多空间？"},
    momentLead="{date}，你写道：", momentSuffix="这样的时刻很能说明你这个月。",
    becomingSuffix="你似乎正在成为一个能察觉什么对自己有帮助的人。", releaseSuffix="也许是时候不再把它抓得那么紧了。",
    releaseFallback="这个月似乎没有什么需要放下的。继续留意什么对你有帮助。",
)

BUCKET = {T: ".tired", S: ".stressed", D: ".sad", G: ".good", N: ".neutral"}
SCALARS = ["open","close","joiner","youWrote","pickNudge","pickNeutral","pickDigest","pickAsk","pickMonthly","entryLabel","weekLabel","monthLabel","entriesLabel","questionLabel","energyHard","energyGood","buildingSuffix","watchSuffix","askPrefix","momentLead","momentSuffix","becomingSuffix","releaseSuffix","releaseFallback"]
DICTS = ["moodWord","theme","boost","nextWeek","monthImage","monthTension","monthQuestion"]
ORDER = ["open","close","joiner","youWrote","moodWord","pickNudge","pickNeutral","pickDigest","pickAsk","pickMonthly","entryLabel","weekLabel","monthLabel","entriesLabel","questionLabel","feel","theme","energyHard","energyGood","buildingSuffix","watchSuffix","boost","nextWeek","askPrefix","monthImage","monthTension","monthQuestion","momentLead","momentSuffix","becomingSuffix","releaseSuffix","releaseFallback"]

def sw(v):
    return '"' + v.replace("\\","\\\\").replace('"','\\"').replace(NB, "\\u{00A0}") + '"'

def swift():
    out = ["    static let groundedLocales: [String: GroundedLocale] = ["]
    for code, d in L.items():
        assert set(d) == set(ORDER), (code, set(ORDER) ^ set(d))
        out.append(f'        "{code}": GroundedLocale(')
        parts = []
        for k in ORDER:
            v = d[k]
            if k == "feel":
                inner = ", ".join(f'{BUCKET[b]}: [{", ".join(sw(x) for x in v[b])}]' for b in [T,S,D,G,N])
                parts.append(f"            feel: [{inner}]")
            elif k in DICTS:
                keys = [T,S,D,G] if k == "moodWord" else [T,S,D,G,N]
                inner = ", ".join(f"{BUCKET[b]}: {sw(v[b])}" for b in keys)
                parts.append(f"            {k}: [{inner}]")
            else:
                parts.append(f"            {k}: {sw(v)}")
        out.append(",\n".join(parts))
        out.append("        ),")
    out.append("    ]")
    return "\n".join(out)

if __name__ == "__main__":
    if "--csv" in sys.argv:
        # "kind" tells a translator what a change costs:
        # - model instruction: Gemma's prompt — changing it changes model behaviour; re-measure on
        #   tools/llmrig (CLAUDE.md) before shipping.
        # - detection anchor: saved insights are recognized by this exact text (widget/lock-screen
        #   quote stripping, isGrammarGrounded, Sentinel sheet). Changing it after release needs
        #   the old wording kept and still recognized, or saved insights lose that protection.
        # - user text: shown verbatim; free to improve.
        INSTRUCTION = {"moodWord", "pickNudge", "pickNeutral", "pickDigest", "pickAsk", "pickMonthly", "entryLabel", "weekLabel", "monthLabel", "entriesLabel", "questionLabel"}
        ANCHOR = {"open", "close", "joiner", "youWrote", "energyHard", "energyGood", "becomingSuffix", "releaseFallback", "askPrefix"}
        kind = lambda k: "model instruction" if k in INSTRUCTION else "detection anchor" if k in ANCHOR else "user text"
        w = csv.writer(sys.stdout)
        w.writerow(["language", "key", "kind", "mood/variant", "text"])
        for code, d in L.items():
            for k in ORDER:
                v = d[k]
                if isinstance(v, dict):
                    for b, x in v.items():
                        for i, t in enumerate(x if isinstance(x, list) else [x]):
                            w.writerow([code, k, kind(k), f"{b}{'/' + str(i+1) if isinstance(x, list) else ''}", t])
                else:
                    w.writerow([code, k, kind(k), "", v])
    elif "--write" in sys.argv:
        p = "mirror/Core/Services/InsightService.swift"
        s = open(p).read()
        start = s.index("    static let groundedLocales: [String: GroundedLocale] = [")
        end = s.index("\n    ]\n", start) + len("\n    ]")
        s = s[:start] + swift() + s[end:]
        open(p, "w").write(s)
        print("wrote", p)
    else:
        print(swift())
