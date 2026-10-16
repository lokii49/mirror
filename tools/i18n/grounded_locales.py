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
    feel={T: ["Das klingt nach einem Tag, der viel Kraft gekostet hat. Gönn dir heute Abend etwas Ruhe.", "Du wirkst ziemlich erschöpft. Ein ruhiger, entspannter Abend könnte dir guttun."],
          S: ["Das klingt nach ziemlich viel auf einmal. Vielleicht hilft es, erst mal mit einer kleinen Sache anzufangen.", "Du scheinst ziemlich unter Druck zu stehen. Eine kurze Pause könnte dir helfen, durchzuatmen."],
          D: ["Das klingt belastend. Geh heute behutsam mit dir um.", "Du wirkst niedergeschlagen. Es ist in Ordnung, es langsam angehen zu lassen."],
          G: ["Das klingt nach einem guten Moment. Halte ihn fest.", "Du wirkst gelöster. Vielleicht lohnt es sich, dir zu merken, was dir gutgetan hat."],
          N: ["Schön, dass du es aufgeschrieben hast.", "Es lohnt sich, darauf zu achten."]},
    theme={T: "Eine Woche, die viel Kraft gekostet hat.", S: "Eine Woche mit viel Druck.", D: "Eine schwere Woche.", G: "Eine Woche mit guten Momenten.", N: "Eine Woche mit Höhen und Tiefen."},
    energyHard="Am schwersten wirkte es, als du schriebst: ", energyGood="Am leichtesten wirkte es, als du schriebst: ",
    buildingSuffix="Daran lässt sich anknüpfen.", watchSuffix="Behalte das im Blick.",
    boost={T: "Plane bewusst einen ruhigen Abend nur für dich ein.", S: "Such dir eine kleine Aufgabe aus, die du heute abschließen kannst.", D: "Melde dich bei jemandem, dem du vertraust.", G: "Mach mehr von dem, was dir diese Woche gutgetan hat.", N: "Nimm dir fünf Minuten für etwas, das dir guttut."},
    nextWeek={T: "Schütze deinen Schlaf und plane Pausen ein.", S: "Nimm dir jeden Tag nur eine wichtige Sache vor.", D: "Sei geduldig mit dir und schreib weiter auf, wie es dir geht.", G: "Bleib bei dem, was funktioniert hat.", N: "Achte darauf, was dir Energie gibt und was sie nimmt."},
    askPrefix="Am ehesten passt dazu, was du geschrieben hast:",
    monthImage={T: "Eine Kerze, die an beiden Enden brennt.", S: "Ein Topf kurz vor dem Überkochen.", D: "Ein grauer Himmel, der noch nicht aufgeklart ist.", G: "Ein Fenster, das sich zum Morgenlicht öffnet.", N: "Wetter, das ständig wechselte – Sonne, dann Regen, dann wieder Sonne."},
    monthTension={T: "Zwischen allem, was deine Energie fordert, und der Ruhe, die du brauchst.", S: "Zwischen dem, was von dir erwartet wird, und dem, was du tragen kannst.", D: "Zwischen dem Wunsch, nach vorn zu schauen, und der Zeit, die du brauchst, um das zu verarbeiten.", G: "Zwischen der Freude am Guten und der Frage, ob es bleibt.", N: "Zwischen den Tagen, die dich Kraft gekostet haben, und denen, die dir Kraft zurückgaben."},
    monthQuestion={T: "Was könntest du loslassen, um im nächsten Monat mehr Energie zu haben?", S: "Welche Aufgabe könntest du im nächsten Monat abgeben oder streichen?", D: "Wer oder was könnte dich im nächsten Monat ein bisschen mehr stützen?", G: "Was würde dir helfen, im nächsten Monat mehr davon zu behalten?", N: "Was hat dir diesen Monat Energie gegeben, und wie könntest du mehr Raum dafür schaffen?"},
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
    feel={T: ["Suena a un día que te dejó sin energía. Esta noche date un respiro.", "Parece que fue agotador. Una noche tranquila y sin prisas podría ayudarte."],
          S: ["Parece que son muchas cosas a la vez. Quizás ayude empezar por una sola cosa pequeña.", "Parece que hay bastante presión. Una pausa corta podría ayudarte a respirar."],
          D: ["Suena difícil. Trátate con cariño hoy.", "Parece un momento duro. Está bien ir despacio."],
          G: ["Suena a un buen momento. Vale la pena guardarlo.", "Parece que las cosas pesaron un poco menos. Quizás valga la pena fijarte en qué te ayudó."],
          N: ["Qué bien que lo hayas escrito.", "Vale la pena fijarse en esto."]},
    theme={T: "Una semana que te pidió mucha energía.", S: "Una semana con mucha presión.", D: "Una semana difícil.", G: "Una semana con buenos momentos.", N: "Una semana con altibajos."},
    energyHard="El momento más pesado pareció ser cuando escribiste: ", energyGood="El momento más ligero pareció ser cuando escribiste: ",
    buildingSuffix="Ahí hay algo que puede crecer.", watchSuffix="Vale la pena prestarle atención.",
    boost={T: "Reserva una tarde tranquila solo para ti.", S: "Elige una tarea pequeña que puedas terminar hoy.", D: "Escríbele a alguien de confianza.", G: "Haz más de lo que te sentó bien esta semana.", N: "Tómate cinco minutos para algo que te haga bien."},
    nextWeek={T: "Cuida tu descanso y deja espacio para pausas.", S: "Concéntrate en una sola cosa importante cada día.", D: "Ten paciencia contigo y sigue escribiendo cómo te sientes.", G: "Repite lo que funcionó.", N: "Fíjate en qué te da energía y qué te la quita."},
    askPrefix="Lo más cercano que has escrito:",
    monthImage={T: "Una vela que arde por los dos extremos.", S: "Una olla a presión a punto de estallar.", D: "Un cielo gris que todavía no se ha despejado.", G: "Una ventana que se abre a la luz de la mañana.", N: "Un tiempo que no dejaba de cambiar: sol, luego lluvia, luego sol otra vez."},
    monthTension={T: "Entre todo lo que te pide energía y el descanso que necesitas.", S: "Entre lo que se espera de ti y lo que puedes cargar.", D: "Entre las ganas de seguir adelante y el tiempo que necesitas para sentirlo.", G: "Entre disfrutar lo bueno y preguntarte si va a durar.", N: "Entre los días que te dejaron sin energía y los que te la devolvieron."},
    monthQuestion={T: "¿Qué podrías soltar para tener más energía el próximo mes?", S: "¿Qué cosa podrías quitarte de encima el próximo mes?", D: "¿Quién o qué podría apoyarte un poco más el próximo mes?", G: "¿Qué te ayudaría a conservar más de esto el próximo mes?", N: "¿Qué te dio energía este mes y cómo podrías darle más espacio?"},
    momentLead="El {date} escribiste: ", momentSuffix="Momentos así dicen mucho de tu mes.",
    becomingSuffix="Parece que estás aprendiendo a notar lo que te hace bien.", releaseSuffix="Quizás es momento de aferrarte un poco menos a esto.",
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
          S: ["Ça fait beaucoup d'un coup. Commencer par une seule petite chose pourrait t'aider.", "Tu sembles sous pression. Une courte pause pourrait t'aider à souffler."],
          D: ["Ça a l'air lourd. Prends soin de toi aujourd'hui.", "Ça semble difficile. C'est normal d'y aller doucement."],
          G: ["On dirait un bon moment. Garde-le précieusement.", "Ça semble plus léger. Note peut-être ce qui t'a fait du bien."],
          N: ["C'est bien que tu l'aies écrit.", "Ça vaut la peine de le remarquer."]},
    theme={T: "Une semaine qui t'a demandé beaucoup d'énergie.", S: "Une semaine sous pression.", D: "Une semaine difficile.", G: "Une semaine avec de bons moments.", N: "Une semaine en dents de scie."},
    energyHard="Le moment le plus lourd semble être quand tu as écrit"+NB+": ", energyGood="Le moment le plus léger semble être quand tu as écrit"+NB+": ",
    buildingSuffix="Il y a là quelque chose qui peut grandir.", watchSuffix="Garde un œil là-dessus.",
    boost={T: "Prévois une soirée calme rien que pour toi.", S: "Choisis une petite tâche que tu peux terminer aujourd'hui.", D: "Écris à quelqu'un en qui tu as confiance.", G: "Refais ce qui t'a fait du bien cette semaine.", N: "Prends cinq minutes pour quelque chose qui te fait du bien."},
    nextWeek={T: "Protège ton sommeil et prévois des pauses.", S: "Concentre-toi sur une seule chose importante par jour.", D: "Prends ton temps et continue d'écrire ce que tu ressens.", G: "Continue ce qui a marché.", N: "Observe ce qui te donne de l'énergie et ce qui t'en prend."},
    askPrefix="Ce que tu as écrit de plus proche"+NB+":",
    monthImage={T: "Une chandelle qui brûle par les deux bouts.", S: "Une cocotte-minute prête à exploser.", D: "Un ciel gris qui ne s'est pas encore dégagé.", G: "Une fenêtre qui s'ouvre sur la lumière du matin.", N: "Une météo qui changeait sans cesse"+NB+": soleil, puis pluie, puis soleil."},
    monthTension={T: "Entre tout ce qui réclame ton énergie et le repos dont tu as besoin.", S: "Entre ce qu'on attend de toi et ce que tu peux porter.", D: "Entre l'envie d'avancer et le temps qu'il te faut pour le ressentir.", G: "Entre profiter de ce qui est bon et te demander si ça va durer.", N: "Entre les jours qui t'ont pris de l'énergie et ceux qui t'en ont redonné."},
    monthQuestion={T: "Qu'est-ce que tu pourrais lâcher pour avoir plus d'énergie le mois prochain"+NB+"?", S: "De quelle tâche pourrais-tu te décharger le mois prochain"+NB+"?", D: "Qui ou quoi pourrait te soutenir un peu plus le mois prochain"+NB+"?", G: "Qu'est-ce qui t'aiderait à garder davantage de tout ça le mois prochain"+NB+"?", N: "Qu'est-ce qui t'a donné de l'énergie ce mois-ci, et comment lui faire plus de place"+NB+"?"},
    momentLead="Le {date}, tu as écrit"+NB+": ", momentSuffix="Ce genre de moment en dit long sur ton mois.",
    becomingSuffix="Tu sembles apprendre à remarquer ce qui te fait du bien.", releaseSuffix="Il est peut-être temps de t'y accrocher un peu moins.",
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
          S: ["Sembrano tante cose tutte insieme. Magari inizia da una sola piccola cosa.", "Sembra che ci sia parecchia pressione. Una breve pausa potrebbe aiutarti a riprendere fiato."],
          D: ["Sembra pesante. Oggi trattati con gentilezza.", "Sembra un momento difficile. Va bene prendersela con calma."],
          G: ["Sembra un bel momento. Vale la pena tenerlo a mente.", "Sembra che ci sia stata un po' di leggerezza. Forse vale la pena notare cosa ti ha aiutato."],
          N: ["È bello che tu l'abbia scritto.", "Vale la pena notarlo."]},
    theme={T: "Una settimana che ti ha chiesto molte energie.", S: "Una settimana con molta pressione.", D: "Una settimana difficile.", G: "Una settimana con bei momenti.", N: "Una settimana di alti e bassi."},
    energyHard="Il momento più pesante sembra essere stato quando hai scritto: ", energyGood="Il momento più leggero sembra essere stato quando hai scritto: ",
    buildingSuffix="Qui c'è qualcosa che può crescere.", watchSuffix="Vale la pena tenerlo d'occhio.",
    boost={T: "Tieni libera una serata tranquilla solo per te.", S: "Scegli un piccolo compito da finire oggi.", D: "Scrivi a qualcuno di cui ti fidi.", G: "Fai più spesso ciò che ti ha fatto bene questa settimana.", N: "Prenditi cinque minuti per qualcosa che ti fa bene."},
    nextWeek={T: "Proteggi il sonno e prevedi delle pause.", S: "Concentrati su una sola cosa importante al giorno.", D: "Prenditi il tuo tempo e continua a scrivere come stai.", G: "Ripeti ciò che ha funzionato.", N: "Nota cosa ti dà energia e cosa te la toglie."},
    askPrefix="Le cose più vicine che hai scritto:",
    monthImage={T: "Una candela che brucia da entrambe le estremità.", S: "Una pentola a pressione pronta a scoppiare.", D: "Un cielo grigio che non si è ancora rasserenato.", G: "Una finestra che si apre sulla luce del mattino.", N: "Un tempo che cambiava di continuo: sole, poi pioggia, poi di nuovo sole."},
    monthTension={T: "Tra tutto ciò che ti chiede energia e il riposo di cui hai bisogno.", S: "Tra ciò che ci si aspetta da te e ciò che riesci a reggere.", D: "Tra la voglia di andare avanti e il tempo che ti serve per elaborarlo.", G: "Tra il goderti ciò che va bene e il chiederti se durerà.", N: "Tra i giorni che ti hanno tolto energia e quelli che te l'hanno restituita."},
    monthQuestion={T: "Cosa potresti lasciar andare per avere più energia il mese prossimo?", S: "Di quale impegno potresti liberarti il mese prossimo?", D: "Chi o cosa potrebbe sostenerti un po' di più il mese prossimo?", G: "Cosa ti aiuterebbe a far durare tutto questo anche il mese prossimo?", N: "Cosa ti ha dato energia questo mese, e come potresti dargli più spazio?"},
    momentLead="Il {date} hai scritto: ", momentSuffix="Momenti così dicono molto del tuo mese.",
    becomingSuffix="Sembra che tu stia imparando a notare ciò che ti fa bene.", releaseSuffix="Forse è il momento di tenerlo un po' meno stretto.",
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
    feel={T: ["Parece um dia que tirou muita energia de você. Hoje à noite, se dê um descanso.", "Parece ter sido cansativo. Uma noite tranquila pode te fazer bem."],
          S: ["Parece muita coisa ao mesmo tempo. Talvez ajude começar por uma coisa pequena.", "Parece que há bastante pressão. Uma pausa curta pode te ajudar a respirar."],
          D: ["Parece pesado. Seja gentil com você hoje.", "Parece um momento difícil. Tudo bem ir devagar."],
          G: ["Parece um bom momento. Guarde isso com carinho.", "Parece que houve um pouco de leveza. Talvez valha a pena notar o que ajudou."],
          N: ["Que bom que você escreveu isso.", "Vale a pena notar isso."]},
    theme={T: "Uma semana que pediu muita energia.", S: "Uma semana com muita pressão.", D: "Uma semana difícil.", G: "Uma semana com bons momentos.", N: "Uma semana de altos e baixos."},
    energyHard="O momento mais pesado parece ter sido quando você escreveu: ", energyGood="O momento mais leve parece ter sido quando você escreveu: ",
    buildingSuffix="Há algo aí que pode crescer.", watchSuffix="Vale a pena ficar de olho nisso.",
    boost={T: "Reserve uma noite tranquila só para você.", S: "Escolha uma tarefa pequena para terminar hoje.", D: "Mande uma mensagem para alguém de confiança.", G: "Faça mais do que te fez bem esta semana.", N: "Tire cinco minutos para algo que te faça bem."},
    nextWeek={T: "Proteja seu sono e faça pausas.", S: "Foque em uma só coisa importante por dia.", D: "Vá com calma e continue escrevendo sobre como você se sente.", G: "Repita o que funcionou.", N: "Repare no que te dá energia e no que te tira energia."},
    askPrefix="O mais próximo que você escreveu:",
    monthImage={T: "Uma vela queimando pelas duas pontas.", S: "Uma chaleira quase fervendo.", D: "Um céu cinzento que ainda não abriu.", G: "Uma janela se abrindo para a luz da manhã.", N: "Um tempo que não parava de mudar: sol, depois chuva, depois sol de novo."},
    monthTension={T: "Entre tudo o que pede sua energia e o descanso de que você precisa.", S: "Entre o que esperam de você e o que você consegue carregar.", D: "Entre a vontade de seguir em frente e o tempo de que você precisa para sentir isso.", G: "Entre aproveitar o que é bom e se perguntar se vai durar.", N: "Entre os dias que tiraram sua energia e os que a devolveram."},
    monthQuestion={T: "O que você poderia deixar de lado para ter mais energia no próximo mês?", S: "Que peso você poderia tirar das costas no próximo mês?", D: "Quem ou o que poderia apoiar você um pouco mais no próximo mês?", G: "O que ajudaria você a manter mais disso no próximo mês?", N: "O que te deu energia este mês, e como você poderia abrir mais espaço para isso?"},
    momentLead="Em {date}, você escreveu: ", momentSuffix="Momentos assim dizem muito sobre o seu mês.",
    becomingSuffix="Parece que você está aprendendo a perceber o que faz bem a você.", releaseSuffix="Talvez seja hora de não se agarrar tanto a isso.",
    releaseFallback="Nada neste mês parece pedir para ser deixado de lado; continue percebendo o que faz bem a você.",
)
L["ru"] = dict(
    open="«", close="»", joiner=" ", youWrote="Ты пишешь: ",
    moodWord={T: "измотанным", S: "напряжённым", D: "грустным", G: "хорошо"},
    pickNudge="Перепиши слово в слово предложение из записи в дневнике, которое лучше всего объясняет, почему человек чувствовал себя {mood}. Выведи только это предложение.",
    pickNeutral="Перепиши слово в слово предложение из записи в дневнике, которое показывает самое важное за день. Выведи только это предложение.",
    pickDigest="Перепиши слово в слово три предложения из записей в дневнике, каждое на отдельной строке: сначала предложение, показывающее, когда человек казался самым измотанным, затем предложение о чём-то хорошем, что растёт, затем предложение о том, что может его тяготить. Выведи только эти три предложения.",
    pickAsk="Перепиши слово в слово одно предложение (или не больше двух) из записей в дневнике, которые лучше всего отвечают на вопрос, каждое на отдельной строке. Выведи только эти предложения.",
    pickMonthly="Перепиши слово в слово три предложения из записей в дневнике, каждое на отдельной строке: сначала предложение о моменте, который что-то изменил в этом месяце, затем предложение с надеждой, затем тяжёлое предложение. Выведи только эти три предложения.",
    entryLabel="Запись в дневнике:", weekLabel="Записи в дневнике за эту неделю:", monthLabel="Записи в дневнике за этот месяц:", entriesLabel="Записи в дневнике:", questionLabel="Вопрос:",
    feel={T: ["Похоже, этот день забрал много сил. Позволь себе вечером отдохнуть.", "Кажется, это было изматывающе. Спокойный вечер может помочь."],
          S: ["Похоже, всего слишком много сразу. Возможно, стоит начать с одного небольшого дела.", "Кажется, сейчас много напряжения. Короткая пауза может помочь выдохнуть."],
          D: ["Похоже, это тяжело. Будь сегодня бережнее к себе.", "Похоже, сейчас непросто. Можно никуда не спешить."],
          G: ["Кажется, это был хороший момент. Его стоит запомнить.", "Похоже, стало немного легче. Возможно, стоит заметить, что помогло."],
          N: ["Хорошо, что ты это записываешь.", "Это стоит заметить."]},
    theme={T: "Неделя, которая потребовала много сил.", S: "Напряжённая неделя.", D: "Тяжёлая неделя.", G: "Неделя с хорошими моментами.", N: "Неделя со взлётами и падениями."},
    energyHard="Судя по записям, тяжелее всего было здесь: ", energyGood="Судя по записям, легче всего было здесь: ",
    buildingSuffix="Из этого может что-то вырасти.", watchSuffix="За этим стоит последить.",
    boost={T: "Выдели спокойный вечер только для себя.", S: "Выбери одно небольшое дело, которое можно закончить сегодня.", D: "Напиши тому, кому доверяешь.", G: "Делай больше того, что радовало тебя на этой неделе.", N: "Удели пять минут тому, что тебе приятно."},
    nextWeek={T: "Береги сон и планируй паузы.", S: "Сосредоточься на одном важном деле в день.", D: "Не торопи себя и продолжай записывать, что чувствуешь.", G: "Повтори то, что сработало.", N: "Замечай, что даёт силы, а что их забирает."},
    askPrefix="Самое близкое в твоих записях:",
    monthImage={T: "Свеча, горящая с двух концов.", S: "Чайник, который вот-вот закипит.", D: "Серое небо, которое ещё не прояснилось.", G: "Окно, открытое навстречу утреннему свету.", N: "Погода, которая всё время менялась: солнце, потом дождь, потом снова солнце."},
    monthTension={T: "Между всем, что требует твоих сил, и отдыхом, который тебе нужен.", S: "Между тем, чего от тебя ждут, и тем, что ты можешь вынести.", D: "Между желанием двигаться дальше и временем, которое нужно, чтобы это прожить.", G: "Между радостью от хорошего и вопросом, надолго ли это.", N: "Между днями, которые забирали силы, и теми, что их возвращали."},
    monthQuestion={T: "От чего можно было бы отказаться, чтобы в следующем месяце было больше сил?", S: "Какую одну задачу можно было бы снять с себя в следующем месяце?", D: "Кто или что могло бы поддержать тебя чуть больше в следующем месяце?", G: "Что помогло бы тебе сохранить больше этого в следующем месяце?", N: "Что давало тебе силы в этом месяце и как освободить для этого больше места?"},
    momentLead="Из записи от {date}: ", momentSuffix="Такие моменты многое говорят о твоём месяце.",
    becomingSuffix="Похоже, ты учишься замечать, что тебе помогает.", releaseSuffix="Может быть, пора перестать так крепко держаться за это.",
    releaseFallback="Похоже, в этом месяце нет ничего, что нужно отпустить, — продолжай замечать, что тебе помогает.",
)
L["ja"] = dict(
    open="「", close="」", joiner="", youWrote="こう書いていましたね：",
    moodWord={T: "疲れ切っていた", S: "ストレスを感じていた", D: "悲しかった", G: "気分がよかった"},
    pickNudge="次の日記から、その人がなぜ{mood}のかをいちばんよく表している一文を、そのまま書き写してください。その一文だけを出力してください。",
    pickNeutral="次の日記から、その日いちばん大事なことを表す一文をそのまま書き写してください。その一文だけを出力してください。",
    pickDigest="次の日記から、三つの文をそのまま書き写してください。それぞれ別の行に：まず、その人がいちばん疲れていたように見える文、次に、何かよいことが育っている文、最後に、その人の負担になっていそうな文。その三つの文だけを出力してください。",
    pickAsk="次の日記から、質問にいちばんよく答えている文を一つ（多くても二つ）、そのまま書き写してください。一文ずつ別の行に。その文だけを出力してください。",
    pickMonthly="次の日記から、三つの文をそのまま書き写してください。それぞれ別の行に：まず、今月何かが変わった瞬間を表す文、次に、希望が感じられる文、最後に、重さが感じられる文。その三つの文だけを出力してください。",
    entryLabel="日記：", weekLabel="今週の日記：", monthLabel="今月の日記：", entriesLabel="日記：", questionLabel="質問：",
    feel={T: ["とても疲れた一日だったようですね。今夜はゆっくり休んでください。", "かなりお疲れのようですね。今夜は静かに過ごすといいかもしれません。"],
          S: ["いろいろなことが一度に重なっているようですね。まず小さなことを一つだけ片づけてみてはどうでしょう。", "プレッシャーが大きそうです。少し休憩をとると楽になるかもしれません。"],
          D: ["つらい時間だったようですね。今日は自分にやさしくしてください。", "気持ちが沈んでいるようですね。ゆっくりで大丈夫ですよ。"],
          G: ["いい時間だったようですね。その気持ちを大切にしてください。", "少し心が軽くなったようですね。何が助けになったのか、覚えておくといいかもしれません。"],
          N: ["書き留めておけてよかったですね。", "心に留めておきたいことですね。"]},
    theme={T: "たくさんのエネルギーを使った一週間。", S: "プレッシャーの多い一週間。", D: "つらい一週間。", G: "いいこともあった一週間。", N: "浮き沈みのあった一週間。"},
    energyHard="いちばん大変そうだったのは、こう書いたときです：", energyGood="いちばん軽やかだったのは、こう書いたときです：",
    buildingSuffix="――ここから育っていくものがありそうです。", watchSuffix="――ここは少し気にかけておきましょう。",
    boost={T: "自分のためだけの静かな夜を、一日つくってみてください。", S: "今日終わらせられる小さなことを一つ選んでみてください。", D: "信頼できる人に連絡してみてください。", G: "今週よかったことを、もう少し続けてみてください。", N: "自分をいたわる時間を五分とってみてください。"},
    nextWeek={T: "睡眠を守って、休憩を予定に入れましょう。", S: "一日ひとつの大事なことに集中しましょう。", D: "無理せず、気持ちを書き続けましょう。", G: "うまくいったことを繰り返しましょう。", N: "何が元気をくれて、何がそれを奪うのか、意識してみましょう。"},
    askPrefix="いちばん近いのは、あなたが書いたこの言葉です：",
    monthImage={T: "両端から燃えているろうそく。", S: "今にも沸騰しそうなやかん。", D: "まだ晴れない灰色の空。", G: "朝の光に向かって開く窓。", N: "晴れたり雨が降ったり、めまぐるしく変わる天気。"},
    monthTension={T: "エネルギーを求めてくるすべてのことと、必要な休息とのあいだ。", S: "期待されていることと、自分が抱えきれることとのあいだ。", D: "前に進みたい気持ちと、それを感じきるための時間とのあいだ。", G: "いいことを楽しむ気持ちと、それが続くのかという思いとのあいだ。", N: "エネルギーを奪われた日々と、取り戻せた日々とのあいだ。"},
    monthQuestion={T: "来月もっと元気でいるために、手放せることは何でしょうか？", S: "来月、抱えていることを一つ減らすとしたら何でしょうか？", D: "来月、もう少し支えになってくれそうな人やものはありますか？", G: "来月もこの感じを続けるために、何が助けになるでしょうか？", N: "今月、元気をくれたものは何でしたか？それをもっと増やすには、どうしたらいいでしょう？"},
    momentLead="{date}には、こう書いていました：", momentSuffix="――こうした瞬間が、今月をよく表しています。",
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
    feel={T: ["많이 지친 하루였던 것 같아요. 오늘 밤은 푹 쉬어요.", "꽤 힘들었던 것 같아요. 조용히 쉬는 저녁이 도움이 될 거예요."],
          S: ["한꺼번에 많은 일이 겹친 것 같아요. 작은 일 하나부터 시작해 보면 어떨까요?", "부담이 큰 것 같아요. 잠깐 쉬어 가면 숨 돌리는 데 도움이 될 거예요."],
          D: ["마음이 무거웠던 것 같아요. 오늘은 스스로에게 다정하게 대해 주세요.", "마음이 많이 가라앉은 것 같아요. 천천히 가도 괜찮아요."],
          G: ["좋은 순간이었던 것 같아요. 잘 간직해 두세요.", "마음이 조금 가벼워진 것 같아요. 무엇이 도움이 됐는지 기억해 두면 좋겠어요."],
          N: ["적어 두길 잘했어요.", "눈여겨볼 만한 일이에요."]},
    theme={T: "힘을 많이 쓴 한 주.", S: "부담이 많았던 한 주.", D: "힘든 한 주.", G: "좋은 순간들이 있었던 한 주.", N: "기복이 있었던 한 주."},
    energyHard="가장 힘들어 보였던 건 이렇게 썼을 때예요: ", energyGood="가장 가벼워 보였던 건 이렇게 썼을 때예요: ",
    buildingSuffix="여기서 자라날 무언가가 있어 보여요.", watchSuffix="이 부분은 조금 지켜봐 주세요.",
    boost={T: "하루 저녁은 나만을 위한 조용한 시간으로 비워 두세요.", S: "오늘 끝낼 수 있는 작은 일 하나를 골라 보세요.", D: "믿을 수 있는 사람에게 연락해 보세요.", G: "이번 주에 좋았던 일을 조금 더 해 보세요.", N: "나를 위한 5분을 가져 보세요."},
    nextWeek={T: "잠을 지키고 쉬는 시간을 계획해 보세요.", S: "하루에 중요한 일 하나에만 집중해 보세요.", D: "서두르지 말고 마음을 계속 적어 보세요.", G: "효과가 있었던 방법을 계속 이어 가세요.", N: "무엇이 힘을 주고 무엇이 힘을 빼는지 살펴보세요."},
    askPrefix="가장 가까운 건 이렇게 쓴 내용이에요:",
    monthImage={T: "양쪽 끝에서 타들어 가는 초.", S: "곧 끓어오를 것 같은 주전자.", D: "아직 개지 않은 잿빛 하늘.", G: "아침 햇살을 향해 열리는 창문.", N: "해가 났다가 비가 왔다가, 계속 바뀌는 날씨."},
    monthTension={T: "에너지를 요구하는 모든 일과 지금 필요한 휴식 사이.", S: "기대받는 것과 감당할 수 있는 것 사이.", D: "앞으로 나아가고 싶은 마음과 그 감정을 충분히 느낄 시간 사이.", G: "좋은 것을 누리는 마음과 그것이 계속될지 묻는 마음 사이.", N: "힘을 빼앗긴 날들과 힘을 되찾은 날들 사이."},
    monthQuestion={T: "다음 달에 더 힘을 내기 위해 내려놓을 수 있는 건 무엇일까요?", S: "다음 달에 덜어낼 수 있는 일 하나는 무엇일까요?", D: "다음 달에 조금 더 기댈 수 있는 사람이나 무언가가 있을까요?", G: "다음 달에도 이 느낌을 이어가려면 무엇이 도움이 될까요?", N: "이번 달 힘이 되어 준 것은 무엇이었나요? 그걸 위한 자리를 어떻게 더 만들 수 있을까요?"},
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
    feel={T: ["听起来是很耗精力的一天。今晚好好休息一下吧。", "看起来真的很累。今晚安安静静地放松一下，也许会好一些。"],
          S: ["听起来很多事情同时压过来。也许可以先从一件小事开始。", "看起来压力不小。短暂休息一下，也许能喘口气。"],
          D: ["听起来很沉重。今天对自己温柔一点。", "看起来这段时间不容易。慢慢来就好。"],
          G: ["听起来是个美好的时刻。值得记住。", "看起来心情轻松了一些。也许可以留意一下是什么帮到了你。"],
          N: ["能写下来，就很好。", "这值得留意。"]},
    theme={T: "耗费了很多精力的一周。", S: "压力很大的一周。", D: "艰难的一周。", G: "有美好时刻的一周。", N: "有起有落的一周。"},
    energyHard="最辛苦的时候，似乎是你写下这句话时：", energyGood="最轻松的时候，似乎是你写下这句话时：",
    buildingSuffix="这是个好苗头，可以继续下去。", watchSuffix="这一点值得留意。",
    boost={T: "给自己留一个安静的晚上。", S: "选一件今天能完成的小事。", D: "联系一个你信任的人。", G: "多做一些这周让你感觉好的事。", N: "花五分钟做一件让自己舒服的事。"},
    nextWeek={T: "保护好睡眠，安排一些休息。", S: "每天只专注一件重要的事。", D: "别着急，继续写下自己的感受。", G: "重复那些有效的做法。", N: "留意什么给你能量，什么在消耗你。"},
    askPrefix="和这个问题最接近的是你写的这些：",
    monthImage={T: "一支两头烧的蜡烛。", S: "一壶快要烧开的水。", D: "一片还没有放晴的灰色天空。", G: "一扇向晨光打开的窗。", N: "忽晴忽雨、变个不停的天气。"},
    monthTension={T: "在所有消耗你精力的事和你需要的休息之间。", S: "在别人对你的期待和你能承受的限度之间。", D: "在想要往前走的心和需要时间慢慢消化之间。", G: "在享受美好和担心它能否持续之间。", N: "在耗尽你精力的日子和让你恢复元气的日子之间。"},
    monthQuestion={T: "下个月，你可以放下什么，让自己更有精力？", S: "下个月，你可以卸下的一件事是什么？", D: "下个月，谁或什么能多支持你一点？", G: "下个月，什么能帮你留住更多这样的感觉？", N: "这个月是什么给了你能量？你可以怎样为它留出更多空间？"},
    momentLead="{date}，你写道：", momentSuffix="这样的时刻很能说明你这个月的状态。",
    becomingSuffix="你似乎正在成为一个能察觉什么对自己有帮助的人。", releaseSuffix="也许是时候不再把它抓得那么紧了。",
    releaseFallback="这个月似乎没有什么需要放下的。继续留意什么对你有帮助。",
)

# Follow-up chip on Gemma (2026-09-28). Gemma picks one numbered part of the draft (pickFollowUp,
# partsLabel: model instructions; de/es/fr/ru measured on tools/llmrig, it/pt/ja/ko/zh not), and the
# app composes one of the two followUpQuestion templates around it: {quote} = open + phrase + close.
FOLLOW_UP = {
    "de": dict(
        pickFollowUp="Kopiere Wort für Wort den Teil des Tagebucheintrags, über den die Person am liebsten mehr schreiben würde: ein Gefühl, eine Sorge oder etwas, das ihr passiert ist. Gib nur diesen Teil aus.",
        partsLabel="Teile des Eintrags:",
        followUpQuestion=["Was steckt hinter {quote}?", "Magst du mehr über {quote} schreiben?"]),
    "es": dict(
        pickFollowUp="Copia palabra por palabra la parte de la entrada del diario sobre la que la persona querría escribir más: un sentimiento, una preocupación o algo que le pasó. Escribe solo esa parte.",
        partsLabel="Partes de la entrada:",
        followUpQuestion=["¿Qué hay detrás de {quote}?", "¿Quieres contar más sobre {quote}?"]),
    "fr": dict(
        pickFollowUp="Recopie mot pour mot la partie de l'entrée du journal sur laquelle la personne aurait le plus envie d'écrire davantage : un sentiment, une inquiétude ou quelque chose qui lui est arrivé. Écris seulement cette partie.",
        partsLabel=f"Parties de l'entrée{NB}:",
        followUpQuestion=[f"Qu'est-ce qui se cache derrière {{quote}}{NB}?", f"Tu veux en dire plus sur {{quote}}{NB}?"]),
    "it": dict(
        pickFollowUp="Copia parola per parola la parte della voce del diario su cui la persona vorrebbe scrivere di più: un sentimento, una preoccupazione o qualcosa che le è successo. Scrivi solo quella parte.",
        partsLabel="Parti della voce:",
        followUpQuestion=["Cosa c'è dietro {quote}?", "Ti va di scrivere di più su {quote}?"]),
    "pt": dict(
        pickFollowUp="Copie palavra por palavra a parte da entrada do diário sobre a qual a pessoa mais gostaria de escrever: um sentimento, uma preocupação ou algo que aconteceu com ela. Escreva só essa parte.",
        partsLabel="Partes da entrada:",
        followUpQuestion=["O que está por trás de {quote}?", "Quer escrever mais sobre {quote}?"]),
    "ru": dict(
        pickFollowUp="Перепиши слово в слово ту часть записи в дневнике, о которой человеку больше всего хотелось бы написать подробнее: чувство, тревогу или то, что с ним случилось. Выведи только эту часть.",
        partsLabel="Части записи:",
        followUpQuestion=["Что стоит за {quote}?", "Можешь рассказать подробнее про {quote}?"]),
    "ja": dict(
        pickFollowUp="この日記の中から、書いた人がいちばん詳しく書きたいと思いそうな部分（気持ち、心配ごと、または起きた出来事）をそのまま書き写してください。その部分だけを出力してください。",
        partsLabel="日記の各部分：",
        followUpQuestion=["{quote}の奥には、どんな気持ちがありますか？", "{quote}について、もう少し書いてみませんか？"]),
    "ko": dict(
        pickFollowUp="이 일기에서 쓴 사람이 가장 더 이야기하고 싶어 할 부분(감정, 걱정, 또는 있었던 일)을 그대로 옮겨 적어 주세요. 그 부분만 출력하세요.",
        partsLabel="일기의 부분:",
        followUpQuestion=["{quote} 뒤에는 어떤 마음이 있나요?", "{quote}에 대해 조금 더 써 볼래요?"]),
    "zh": dict(
        pickFollowUp="请从这篇日记中，把作者最想多写一些的那一部分（一种感受、一个担心，或发生在他们身上的事）原样抄写下来。只输出这一部分。",
        partsLabel="日记的各部分：",
        followUpQuestion=["{quote}背后是什么感受？", "能再多写一点关于{quote}的事吗？"]),
}
for code, extra in FOLLOW_UP.items():
    L[code].update(extra)

# Monthly report variety (2026-10-16): two more versions of the image, tension, question, the line after the moment
# and the line after the heavy quote, rotated by calendar month with the originals (GroundedLocale.monthlyText(month:)),
# so two months with the same overall mood don't read the same. becomingSuffix and releaseFallback do not rotate: saved
# reports are recognized by them. Written to avoid gendered forms (the app doesn't know the writer's gender).
MONTHLY_MORE = {
    "de": dict(
        monthImageMore={T: ["Ein Handy auf zwei Prozent, das trotzdem klingelt.", "Eine lange Straße ohne Rastplatz."],
            S: ["Ein Schreibtisch unter einem Berg Papier.", "Ein Wasserkessel, der nicht aufhört zu pfeifen."],
            D: ["Ein Zimmer mit noch zugezogenen Vorhängen.", "Ein Lied, das leise in einem anderen Zimmer läuft."],
            G: ["Ein Garten, in dem die ersten Triebe kommen.", "Ein Weg, der sich immer leichter gehen ließ."],
            N: ["Ebbe und Flut.", "Eine belebte Straße mit einer ruhigen Ecke."]},
        monthTensionMore={T: ["Zwischen dem Versuch, mit allem Schritt zu halten, und der Zeit, die du zum Erholen brauchst.", "Zwischen dem, was du durchziehst, und dem, was du ablegen müsstest."],
            S: ["Zwischen dem Druck dessen, was fällig ist, und dem Tempo, das du halten kannst.", "Zwischen dem Zusammenhalten von allem und der Bitte um Hilfe."],
            D: ["Zwischen dem Weitermachen wie immer und dem Raum für das, was du fühlst.", "Zwischen dem, was schwer wiegt, und dem, was dich noch trägt."],
            G: ["Zwischen der Freude an dieser Zeit und dem Planen, was als Nächstes kommt.", "Zwischen dem Guten, das wächst, und der Zeit, die es braucht."],
            N: ["Zwischen den ruhigen Tagen und denen, die an dir gezerrt haben.", "Zwischen dem, was du bewältigst, und dem, wovon du gern mehr hättest."]},
        monthQuestionMore={T: ["Wozu könntest du im nächsten Monat einmal Nein sagen?", "Wann hast du dich diesen Monat am besten erholt, und wie könntest du mehr davon haben?"],
            S: ["Was würde den nächsten Monat ein kleines bisschen leichter machen?", "Wen könntest du im nächsten Monat bei einer Sache um Hilfe bitten?"],
            D: ["Was Kleines könntest du im nächsten Monat für dich tun?", "Wem möchtest du im nächsten Monat näher sein?"],
            G: ["Was hat diesen Monat gut gemacht, und wie kannst du es schützen?", "Was möchtest du im nächsten Monat weiter tun?"],
            N: ["Von welchen Tagen dieses Monats möchtest du mehr?", "Was soll der nächste Monat für dich bereithalten?"]},
        momentSuffixMore=["Dieser Moment scheint dich begleitet zu haben.", "Kleine Momente wie dieser können einen ganzen Monat verändern."],
        releaseSuffixMore=["Vielleicht musst du das nicht allein tragen.", "Vielleicht kannst du einiges davon im nächsten Monat ablegen."]),
    "es": dict(
        monthImageMore={T: ["Un móvil al dos por ciento que no deja de sonar.", "Una carretera larga sin un sitio donde parar."],
            S: ["Un escritorio enterrado bajo papeles.", "Una tetera que no deja de silbar."],
            D: ["Una habitación con las cortinas todavía cerradas.", "Una canción sonando bajito en otra habitación."],
            G: ["Un jardín que empieza a brotar.", "Un camino que cada vez costaba menos andar."],
            N: ["Una marea que sube y baja.", "Una calle llena de gente con un rincón tranquilo."]},
        monthTensionMore={T: ["Entre llegar a todo y encontrar tiempo para recuperarte.", "Entre lo que sacas adelante a pulso y lo que necesitas soltar."],
            S: ["Entre la presión de lo que vence y el ritmo que puedes mantener.", "Entre sostenerlo todo y pedir ayuda."],
            D: ["Entre seguir como siempre y hacer espacio para lo que sientes.", "Entre lo que pesa y lo que todavía te sostiene."],
            G: ["Entre disfrutar esta racha y planear lo que viene.", "Entre lo bueno que crece y el tiempo que necesita."],
            N: ["Entre los días tranquilos y los que tiraron de ti.", "Entre lo que llevas al día y aquello de lo que te gustaría más."]},
        monthQuestionMore={T: ["¿A qué podrías decir que no el próximo mes?", "¿Cuándo descansaste mejor este mes y cómo podrías tener más de eso?"],
            S: ["¿Qué haría que el próximo mes se sintiera un poco más ligero?", "¿A quién podrías pedirle ayuda con una cosa el próximo mes?"],
            D: ["¿Qué pequeño gesto podrías tener contigo el próximo mes?", "¿De quién te gustaría estar más cerca el próximo mes?"],
            G: ["¿Qué hizo bueno este mes y cómo podrías cuidarlo?", "¿Qué quieres seguir haciendo el próximo mes?"],
            N: ["¿De qué días de este mes te gustaría tener más?", "¿Qué te gustaría que trajera el próximo mes?"]},
        momentSuffixMore=["Parece que ese momento se quedó contigo.", "Momentos pequeños como ese pueden cambiar un mes entero."],
        releaseSuffixMore=["Quizás no tienes que cargar con esto sin ayuda.", "Quizás parte de esto pueda quedarse atrás el próximo mes."]),
    "fr": dict(
        monthImageMore={T: ["Un téléphone à deux pour cent qui sonne encore.", "Une longue route sans aire de repos."],
            S: ["Un bureau enseveli sous les papiers.", "Une bouilloire qui n'arrête pas de siffler."],
            D: ["Une chambre aux rideaux encore tirés.", "Une chanson qui joue doucement dans une autre pièce."],
            G: ["Un jardin qui commence à pousser.", "Un chemin de plus en plus facile à suivre."],
            N: ["Une marée qui monte et descend.", "Une rue animée avec un coin calme."]},
        monthTensionMore={T: ["Entre suivre le rythme de tout et trouver le temps de récupérer.", "Entre ce que tu tiens à bout de bras et ce que tu aurais besoin de poser."],
            S: ["Entre la pression de ce qui est dû et le rythme que tu peux tenir.", "Entre tout tenir ensemble et demander de l'aide."],
            D: ["Entre continuer comme d'habitude et faire de la place à ce que tu ressens.", "Entre ce qui pèse et ce qui te porte encore."],
            G: ["Entre profiter de cette période et préparer la suite.", "Entre les belles choses qui grandissent et le temps qu'il leur faut."],
            N: ["Entre les jours calmes et ceux qui t'ont tiré dans tous les sens.", "Entre ce que tu gères et ce dont tu aimerais davantage."]},
        monthQuestionMore={T: ["À quoi pourrais-tu dire non le mois prochain"+NB+"?", "Quels moments de repos t'ont fait du bien ce mois-ci, et comment en avoir plus"+NB+"?"],
            S: ["Qu'est-ce qui rendrait le mois prochain un peu plus léger"+NB+"?", "À qui pourrais-tu demander de l'aide pour une chose le mois prochain"+NB+"?"],
            D: ["Quelle petite chose pourrais-tu faire pour toi le mois prochain"+NB+"?", "De qui aimerais-tu te rapprocher le mois prochain"+NB+"?"],
            G: ["Qu'est-ce qui a rendu ce mois agréable, et comment le préserver"+NB+"?", "Qu'est-ce que tu veux continuer à faire le mois prochain"+NB+"?"],
            N: ["De quels jours de ce mois aimerais-tu en avoir plus"+NB+"?", "Qu'aimerais-tu que le mois prochain t'apporte"+NB+"?"]},
        momentSuffixMore=["Ce moment semble être resté avec toi.", "De petits moments comme celui-là peuvent changer tout un mois."],
        releaseSuffixMore=["Tu n'as peut-être pas à porter ça sans aide.", "Une partie de tout ça peut peut-être être posée le mois prochain."]),
    "it": dict(
        monthImageMore={T: ["Un telefono al due per cento che continua a squillare.", "Una lunga strada senza un'area di sosta."],
            S: ["Una scrivania sommersa dalle carte.", "Un bollitore che non smette di fischiare."],
            D: ["Una stanza con le tende ancora tirate.", "Una canzone che suona piano in un'altra stanza."],
            G: ["Un giardino che inizia a germogliare.", "Un sentiero sempre più facile da percorrere."],
            N: ["Una marea che sale e scende.", "Una strada affollata con un angolo tranquillo."]},
        monthTensionMore={T: ["Tra stare dietro a tutto e trovare il tempo per riprenderti.", "Tra ciò che porti avanti a fatica e ciò che avresti bisogno di posare."],
            S: ["Tra la pressione delle scadenze e il ritmo che riesci a tenere.", "Tra tenere tutto insieme e chiedere aiuto."],
            D: ["Tra andare avanti come sempre e fare spazio a ciò che senti.", "Tra ciò che pesa e ciò che ancora ti sostiene."],
            G: ["Tra il goderti questo periodo e il pensare a cosa verrà.", "Tra le cose belle che crescono e il tempo che serve loro."],
            N: ["Tra i giorni tranquilli e quelli che ti hanno tirato da ogni parte.", "Tra ciò che riesci a gestire e ciò di cui vorresti di più."]},
        monthQuestionMore={T: ["A cosa potresti dire di no il mese prossimo?", "Quali momenti di riposo ti hanno fatto bene questo mese, e come averne di più?"],
            S: ["Cosa renderebbe il mese prossimo anche solo un po' più leggero?", "A chi potresti chiedere aiuto per una cosa il mese prossimo?"],
            D: ["Quale piccola cosa potresti fare per te il mese prossimo?", "Con chi vorresti avere più contatto il mese prossimo?"],
            G: ["Cosa ha reso buono questo mese, e come potresti proteggerlo?", "Cosa vuoi continuare a fare il mese prossimo?"],
            N: ["Di quali giorni di questo mese vorresti averne di più?", "Cosa vorresti che portasse il mese prossimo?"]},
        momentSuffixMore=["Sembra che quel momento ti sia rimasto dentro.", "Piccoli momenti così possono cambiare un mese intero."],
        releaseSuffixMore=["Forse non devi portare tutto questo senza aiuto.", "Forse una parte di questo può restare indietro il mese prossimo."]),
    "pt": dict(
        monthImageMore={T: ["Um celular com dois por cento de bateria, ainda tocando.", "Uma estrada longa sem nenhum lugar para parar."],
            S: ["Uma mesa soterrada de papéis.", "Uma chaleira que não para de apitar."],
            D: ["Um quarto com as cortinas ainda fechadas.", "Uma música tocando baixinho em outro cômodo."],
            G: ["Um jardim começando a brotar.", "Um caminho cada vez mais fácil de seguir."],
            N: ["Uma maré que sobe e desce.", "Uma rua movimentada com um cantinho tranquilo."]},
        monthTensionMore={T: ["Entre dar conta de tudo e encontrar tempo para se recuperar.", "Entre o que você leva no braço e o que precisaria deixar de lado."],
            S: ["Entre a pressão dos prazos e o ritmo que você consegue manter.", "Entre segurar tudo e pedir ajuda."],
            D: ["Entre seguir como sempre e abrir espaço para o que você sente.", "Entre o que pesa e o que ainda te sustenta."],
            G: ["Entre aproveitar esta fase e planejar o que vem depois.", "Entre as coisas boas que crescem e o tempo de que elas precisam."],
            N: ["Entre os dias tranquilos e os que puxaram você para todos os lados.", "Entre o que você dá conta e aquilo de que gostaria de ter mais."]},
        monthQuestionMore={T: ["Para o que você poderia dizer não no próximo mês?", "Que momentos de descanso fizeram bem a você este mês, e como ter mais deles?"],
            S: ["O que deixaria o próximo mês um pouquinho mais leve?", "A quem você poderia pedir ajuda com uma coisa no próximo mês?"],
            D: ["Que coisa pequena você poderia fazer por você no próximo mês?", "De quem você gostaria de estar mais perto no próximo mês?"],
            G: ["O que fez este mês ser bom, e como você poderia proteger isso?", "O que você quer continuar fazendo no próximo mês?"],
            N: ["De quais dias deste mês você gostaria de ter mais?", "O que você gostaria que o próximo mês trouxesse?"]},
        momentSuffixMore=["Esse momento parece ter ficado com você.", "Pequenos momentos assim podem mudar um mês inteiro."],
        releaseSuffixMore=["Talvez você não precise carregar isso sem ajuda.", "Talvez parte disso possa ficar para trás no próximo mês."]),
    "ru": dict(
        monthImageMore={T: ["Телефон на двух процентах, который всё ещё звонит.", "Длинная дорога без единой остановки."],
            S: ["Стол, заваленный бумагами.", "Чайник, который никак не перестаёт свистеть."],
            D: ["Комната с всё ещё задёрнутыми шторами.", "Песня, тихо звучащая в другой комнате."],
            G: ["Сад, в котором начинают появляться всходы.", "Дорога, по которой идти становилось всё легче."],
            N: ["Прилив и отлив.", "Шумная улица с одним тихим уголком."]},
        monthTensionMore={T: ["Между тем, чтобы всё успевать, и временем, чтобы восстановиться.", "Между тем, что ты тянешь через силу, и тем, что пора бы отложить."],
            S: ["Между давлением сроков и темпом, который ты можешь выдержать.", "Между тем, чтобы держать всё на себе, и просьбой о помощи."],
            D: ["Между тем, чтобы жить как обычно, и местом для того, что ты чувствуешь.", "Между тем, что тяготит, и тем, что ещё держит тебя."],
            G: ["Между радостью от этого периода и мыслями о том, что дальше.", "Между хорошим, что растёт, и временем, которое ему нужно."],
            N: ["Между спокойными днями и теми, что тянули тебя в разные стороны.", "Между тем, с чем ты справляешься, и тем, чего хотелось бы больше."]},
        monthQuestionMore={T: ["Чему можно было бы сказать «нет» в следующем месяце?", "Какие моменты отдыха в этом месяце помогли тебе, и как сделать их больше?"],
            S: ["Что сделало бы следующий месяц хоть немного легче?", "Кого можно было бы попросить о помощи с одним делом в следующем месяце?"],
            D: ["Что маленькое можно сделать для себя в следующем месяце?", "С кем хотелось бы быть ближе в следующем месяце?"],
            G: ["Что сделало этот месяц хорошим и как это сберечь?", "Что хочется продолжать делать в следующем месяце?"],
            N: ["Каких дней из этого месяца хотелось бы больше?", "Чего ты ждёшь от следующего месяца?"]},
        momentSuffixMore=["Похоже, этот момент остался с тобой.", "Такие маленькие моменты могут изменить целый месяц."],
        releaseSuffixMore=["Может быть, это не нужно нести в одиночку.", "Может быть, что-то из этого можно оставить позади в следующем месяце."]),
    "ja": dict(
        monthImageMore={T: ["残り2%なのに鳴り続けるスマホ。", "休憩所のない長い道。"],
            S: ["書類に埋もれた机。", "鳴りやまないやかん。"],
            D: ["カーテンが閉じたままの部屋。", "隣の部屋で静かに流れる歌。"],
            G: ["芽が出はじめた庭。", "だんだん歩きやすくなっていく道。"],
            N: ["満ち引きを繰り返す潮。", "にぎやかな通りの、静かな一角。"]},
        monthTensionMore={T: ["すべてについていくことと、回復する時間を見つけることとのあいだ。", "無理して続けていることと、手放したほうがいいこととのあいだ。"],
            S: ["締め切りのプレッシャーと、保てるペースとのあいだ。", "すべてを一人で支えることと、助けを求めることとのあいだ。"],
            D: ["いつもどおりに過ごすことと、自分の気持ちに場所をつくることとのあいだ。", "重く感じるものと、まだ支えてくれているものとのあいだ。"],
            G: ["この時期を楽しむことと、次のことを考えることとのあいだ。", "育っているいいことと、それに必要な時間とのあいだ。"],
            N: ["穏やかな日々と、あちこちに引っぱられた日々とのあいだ。", "こなせていることと、もっと増やしたいこととのあいだ。"]},
        monthQuestionMore={T: ["来月、断ってもいいことは何でしょうか？", "今月いちばん休めたのはいつでしたか？それを増やすにはどうしたらいいでしょう？"],
            S: ["来月を少しでも軽くしてくれるものは何でしょうか？", "来月、一つのことで助けを頼めそうな人はいますか？"],
            D: ["来月、自分のためにできる小さなことは何でしょうか？", "来月、もっと近くにいたい人は誰ですか？"],
            G: ["今月をいい月にしたのは何でしたか？それをどう守れるでしょう？", "来月も続けたいことは何ですか？"],
            N: ["今月のどんな日を、もっと増やしたいですか？", "来月はどんな月になってほしいですか？"]},
        momentSuffixMore=["――その瞬間は、今も心に残っているようです。", "――こんな小さな瞬間が、ひと月を変えることもあります。"],
        releaseSuffixMore=["――これは一人で抱えなくてもいいのかもしれません。", "――来月は、このうちの少しを置いていけるかもしれません。"]),
    "ko": dict(
        monthImageMore={T: ["배터리 2%인데도 계속 울리는 휴대폰.", "쉴 곳 없는 긴 길."],
            S: ["서류 더미에 파묻힌 책상.", "멈추지 않고 우는 주전자."],
            D: ["아직 커튼이 쳐진 방.", "다른 방에서 조용히 흘러나오는 노래."],
            G: ["싹이 트기 시작한 정원.", "걸을수록 점점 쉬워진 길."],
            N: ["밀려왔다 빠져나가는 바닷물.", "북적이는 거리의 조용한 한구석."]},
        monthTensionMore={T: ["모든 걸 따라잡는 것과 회복할 시간을 찾는 것 사이.", "버티며 해내는 일과 내려놓아야 할 일 사이."],
            S: ["마감의 압박과 지킬 수 있는 속도 사이.", "모든 걸 혼자 붙잡는 것과 도움을 청하는 것 사이."],
            D: ["평소처럼 지내는 것과 마음에 자리를 내주는 것 사이.", "무겁게 느껴지는 것과 아직 붙잡아 주는 것 사이."],
            G: ["지금 이 시기를 누리는 것과 다음을 계획하는 것 사이.", "자라나는 좋은 것들과 그것에 필요한 시간 사이."],
            N: ["잔잔한 날들과 이리저리 끌려다닌 날들 사이.", "해내고 있는 것과 더 갖고 싶은 것 사이."]},
        monthQuestionMore={T: ["다음 달에는 무엇에 '아니요'라고 말할 수 있을까요?", "이번 달 가장 잘 쉬었던 때는 언제였나요? 그런 시간을 어떻게 더 늘릴 수 있을까요?"],
            S: ["다음 달을 조금이라도 가볍게 해 줄 건 무엇일까요?", "다음 달에 한 가지 일로 도움을 청할 수 있는 사람이 있을까요?"],
            D: ["다음 달에 자신을 위해 할 수 있는 작은 일은 무엇일까요?", "다음 달에 더 가까워지고 싶은 사람은 누구인가요?"],
            G: ["무엇이 이번 달을 좋은 달로 만들었나요? 그걸 어떻게 지킬 수 있을까요?", "다음 달에도 계속하고 싶은 일은 무엇인가요?"],
            N: ["이번 달의 어떤 날들이 더 많았으면 하나요?", "다음 달은 어떤 달이었으면 하나요?"]},
        momentSuffixMore=["그 순간이 마음에 남아 있는 것 같아요.", "이런 작은 순간이 한 달 전체를 바꾸기도 해요."],
        releaseSuffixMore=["이건 혼자 짊어지지 않아도 될지 몰라요.", "다음 달에는 이 중 일부를 내려놓을 수 있을지도 몰라요."]),
    "zh": dict(
        monthImageMore={T: ["电量只剩2%却还在响的手机。", "一条没有休息站的长路。"],
            S: ["被文件淹没的书桌。", "一直响个不停的水壶。"],
            D: ["窗帘还拉着的房间。", "隔壁房间里轻轻放着的一首歌。"],
            G: ["开始冒芽的花园。", "越走越顺的一条路。"],
            N: ["涨了又退的潮水。", "热闹街道上一个安静的角落。"]},
        monthTensionMore={T: ["在跟上所有事和找时间恢复之间。", "在你硬撑着做的事和需要放下的事之间。"],
            S: ["在截止日期的压力和你能维持的节奏之间。", "在独自撑起一切和开口求助之间。"],
            D: ["在照常生活和给自己的感受留出空间之间。", "在让你感到沉重的事和仍在支撑你的事之间。"],
            G: ["在享受这段时光和计划接下来之间。", "在正在生长的美好和它需要的时间之间。"],
            N: ["在平静的日子和把你拉向四面八方的日子之间。", "在你能应付的事和你想要更多的事之间。"]},
        monthQuestionMore={T: ["下个月，有什么事你可以拒绝？", "这个月你什么时候休息得最好？怎样才能多一些这样的时候？"],
            S: ["什么能让下个月轻松一点点？", "下个月，有一件事你可以找谁帮忙？"],
            D: ["下个月，你能为自己做的一件小事是什么？", "下个月，你想和谁更亲近一些？"],
            G: ["是什么让这个月变得美好？你可以怎样守护它？", "下个月你想继续做什么？"],
            N: ["这个月的哪些日子，你希望能更多一些？", "你希望下个月是什么样的？"]},
        momentSuffixMore=["那个时刻似乎一直留在你心里。", "像这样的小时刻，可能会改变整个月。"],
        releaseSuffixMore=["也许这件事不必一个人扛。", "也许下个月可以把其中一部分放下。"]),
}
for code, extra in MONTHLY_MORE.items():
    L[code].update(extra)

BUCKET = {T: ".tired", S: ".stressed", D: ".sad", G: ".good", N: ".neutral"}
SCALARS = ["open","close","joiner","youWrote","pickNudge","pickNeutral","pickDigest","pickAsk","pickMonthly","entryLabel","weekLabel","monthLabel","entriesLabel","questionLabel","energyHard","energyGood","buildingSuffix","watchSuffix","askPrefix","momentLead","momentSuffix","becomingSuffix","releaseSuffix","releaseFallback","pickFollowUp","partsLabel"]
DICTS = ["moodWord","theme","boost","nextWeek","monthImage","monthTension","monthQuestion"]
ORDER = ["open","close","joiner","youWrote","moodWord","pickNudge","pickNeutral","pickDigest","pickAsk","pickMonthly","entryLabel","weekLabel","monthLabel","entriesLabel","questionLabel","feel","theme","energyHard","energyGood","buildingSuffix","watchSuffix","boost","nextWeek","askPrefix","monthImage","monthTension","monthQuestion","momentLead","momentSuffix","becomingSuffix","releaseSuffix","releaseFallback","pickFollowUp","partsLabel","followUpQuestion","monthImageMore","monthTensionMore","monthQuestionMore","momentSuffixMore","releaseSuffixMore"]

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
            if k in ("feel", "monthImageMore", "monthTensionMore", "monthQuestionMore"):
                inner = ", ".join(f'{BUCKET[b]}: [{", ".join(sw(x) for x in v[b])}]' for b in [T,S,D,G,N])
                parts.append(f"            {k}: [{inner}]")
            elif k in ("followUpQuestion", "momentSuffixMore", "releaseSuffixMore"):
                parts.append(f"            {k}: [{', '.join(sw(x) for x in v)}]")
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
        INSTRUCTION = {"moodWord", "pickNudge", "pickNeutral", "pickDigest", "pickAsk", "pickMonthly", "entryLabel", "weekLabel", "monthLabel", "entriesLabel", "questionLabel", "pickFollowUp", "partsLabel"}
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
                elif isinstance(v, list):
                    for i, t in enumerate(v):
                        w.writerow([code, k, kind(k), str(i + 1), t])
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
