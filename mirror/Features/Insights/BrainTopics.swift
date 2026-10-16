import Foundation

/// A life area Brain View groups related words into, so the graph shows "Work" once instead of
/// "boss", "deadline" and "meeting" as three nodes. The word lists are fixed, one per language
/// the app is translated into: Apple's on-device embeddings were tried first (2026-10-16) and
/// can't group by topic (boss and manager scored below boss and mom).
///
/// Lists are space-separated. A word ending in `-` is a stem that matches any word starting with
/// it (Russian case endings, German compounds). Words are compared after the same folding as
/// `ThemeExtractionService.makeTerm` keys (lowercased, diacritic-folded).
struct BrainTopic: Sendable {
    /// Stable node id, also the layout seed.
    let id: String
    let label: String
    /// Language code (`en`, `de`, `es`, `fr`, `it`, `pt`, `ru`, `ja`, `ko`, `zh`) → word list.
    let words: [String: String]
}

enum BrainTopics {
    static let all: [BrainTopic] = [
        BrainTopic(id: "topic.work", label: String(localized: "Work"), words: [
            "en": "work job boss manager office meeting standup deadline project client colleague coworker team report presentation email promotion career interview shift workplace company startup task workload sprint desk scope customer contract business overtime layoff",
            "de": "arbeit- job chef chefin vorgesetzte büro buero meeting besprechung- termin deadline frist projekt- kunde kunden kollege kollegin kollegen team bericht präsentation praesentation e-mail beförderung karriere vorstellungsgespräch schicht firma unternehmen aufgabe aufgaben überstunden kündigung",
            "es": "trabajo trabajos jefe jefa gerente oficina reunión reunion reuniones plazo proyecto proyectos cliente clientes colega colegas compañero compañera equipo informe presentación presentacion correo ascenso carrera entrevista turno empresa tarea tareas negocio contrato despido",
            "fr": "travail boulot job patron patronne chef manager bureau réunion reunion réunions deadline échéance projet projets client clients collègue collegue collègues équipe equipe rapport présentation presentation mail email promotion carrière entretien entreprise tâche taches mission contrat licenciement",
            "it": "lavoro lavori capo capi manager ufficio riunione riunioni scadenza scadenze progetto progetti cliente clienti collega colleghi colleghe squadra team rapporto presentazione email promozione carriera colloquio turno azienda compito compiti contratto licenziamento",
            "pt": "trabalho trabalhos emprego chefe gerente escritório escritorio reunião reuniao reuniões prazo projeto projetos cliente clientes colega colegas equipe equipa relatório apresentação email promoção carreira entrevista turno empresa tarefa tarefas contrato demissão",
            "ru": "работ- начальник- начальниц- босс- офис- совещани- встреч- дедлайн- срок- проект- клиент- коллег- команд- отчёт- отчет- презентаци- карьер- собеседовани- смен- компани- задач- контракт- увольнени- переработ-",
            "ja": "仕事 職場 上司 部長 課長 会社 会議 締め切り 締切 プロジェクト 顧客 取引先 同僚 チーム 報告書 プレゼン メール 昇進 キャリア 面接 シフト 残業 業務 出勤 転職",
            "ko": "직장 회사 상사 팀장 부장 사무실 회의 마감 프로젝트 고객 동료 팀 보고서 발표 이메일 승진 경력 면접 근무 야근 업무 출근 퇴근 이직",
            "zh": "工作 上班 老板 领导 经理 公司 办公室 会议 开会 截止 项目 客户 同事 团队 报告 汇报 邮件 升职 职业 面试 加班 任务 业务 辞职",
        ]),
        BrainTopic(id: "topic.money", label: String(localized: "Money"), words: [
            "en": "money rent budget salary bill debt loan savings expense payment paycheck bank finance cash mortgage tax income investment price spending",
            "de": "geld miete budget gehalt rechnung rechnungen schulden kredit ersparnisse ausgaben zahlung bank finanzen bargeld steuer steuern einkommen investition preis",
            "es": "dinero alquiler renta presupuesto sueldo salario factura facturas deuda deudas préstamo ahorros gastos pago banco finanzas efectivo hipoteca impuestos ingresos inversión precio",
            "fr": "argent loyer budget salaire facture factures dette dettes prêt économies dépenses paiement banque finances crédit impôts revenu revenus investissement prix",
            "it": "soldi denaro affitto budget stipendio bolletta bollette debito debiti prestito risparmi spese pagamento banca finanze contanti mutuo tasse reddito investimento prezzo",
            "pt": "dinheiro aluguel aluguer orçamento salário conta contas dívida dívidas empréstimo poupança despesas pagamento banco finanças imposto impostos renda investimento preço",
            "ru": "деньг- денег аренд- бюджет- зарплат- счёт счет счета долг долга долги долгов долгу кредит- сбережени- расход- оплат- платеж- банк- финанс- налог- доход- инвестици- цена цены цену ценой",
            "ja": "お金 家賃 予算 給料 給与 請求 借金 ローン 貯金 出費 支払い 銀行 税金 収入 投資 値段",
            "ko": "돈 월세 집세 예산 월급 급여 청구서 빚 대출 저축 지출 결제 은행 세금 수입 투자 가격",
            "zh": "钱 房租 租金 预算 工资 薪水 账单 债务 贷款 存款 积蓄 开销 支出 付款 银行 税 收入 投资 价格",
        ]),
        BrainTopic(id: "topic.sleep", label: String(localized: "Sleep"), words: [
            "en": "sleep insomnia nap bed bedtime dream nightmare alarm pillow",
            "de": "schlaf schlafen schlaflosigkeit nickerchen bett traum träume albtraum wecker kissen",
            "es": "sueño sueno dormir insomnio siesta cama pesadilla despertador almohada",
            "fr": "sommeil dormir insomnie sieste lit rêve reve rêves cauchemar réveil oreiller",
            "it": "sonno dormire insonnia pisolino letto sogno sogni incubo sveglia cuscino",
            "pt": "sono dormir insônia insonia cochilo soneca cama sonho sonhos pesadelo despertador travesseiro almofada",
            "ru": "сон сна сне сну бессонниц- кровать кровати постел- сновидени- кошмар- будильник- подушк-",
            "ja": "睡眠 眠り 寝不足 不眠 昼寝 布団 ベッド 夢 悪夢 目覚まし 枕",
            "ko": "잠 수면 불면증 낮잠 침대 꿈 악몽 알람 베개",
            "zh": "睡眠 睡觉 失眠 午睡 床 梦 噩梦 闹钟 枕头",
        ]),
        BrainTopic(id: "topic.health", label: String(localized: "Health"), words: [
            "en": "health doctor hospital clinic pain headache migraine knee illness fever flu medicine medication pill appointment injury surgery symptom weight diet allergy dentist checkup blood cough pregnancy",
            "de": "gesundheit arzt ärztin krankenhaus klinik schmerz- kopfschmerz- migräne knie krankheit fieber grippe medikament- tablette- verletzung operation symptom- gewicht diät allergie zahnarzt blut husten schwangerschaft",
            "es": "salud médico medica medico doctor hospital clínica dolor jaqueca migraña rodilla enfermedad fiebre gripe medicina medicamento pastilla cita lesión cirugía síntoma síntomas peso dieta alergia dentista sangre tos embarazo",
            "fr": "santé médecin docteur hôpital clinique douleur migraine genou maladie fièvre grippe médicament médicaments cachet rendez-vous blessure opération symptôme symptômes poids régime allergie dentiste sang toux grossesse",
            "it": "salute medico dottore ospedale clinica dolore mal emicrania ginocchio malattia febbre influenza medicina farmaco pillola appuntamento infortunio intervento sintomo sintomi peso dieta allergia dentista sangue tosse gravidanza",
            "pt": "saúde médico medica doutor hospital clínica dor enxaqueca joelho doença febre gripe remédio remedio medicamento comprimido consulta lesão cirurgia sintoma sintomas peso dieta alergia dentista sangue tosse gravidez",
            "ru": "здоровь- врач- больниц- клиник- боль- мигрен- колен- болезн- температур- грипп- лекарств- таблетк- приём прием травм- операци- симптом- вес веса весом диет- аллерги- стоматолог- кров- кашл- беременност-",
            "ja": "健康 医者 病院 クリニック 痛み 頭痛 偏頭痛 膝 病気 熱 発熱 風邪 インフルエンザ 薬 診察 怪我 手術 症状 体重 ダイエット アレルギー 歯医者 血液 咳 妊娠",
            "ko": "건강 의사 병원 클리닉 통증 두통 편두통 무릎 질병 감기 독감 진료 부상 수술 증상 체중 다이어트 알레르기 치과 기침 임신",
            "zh": "健康 医生 医院 诊所 疼 疼痛 头疼 头痛 偏头痛 膝盖 生病 病 发烧 感冒 流感 药 吃药 预约 受伤 手术 症状 体重 节食 过敏 牙医 血 咳嗽 怀孕",
        ]),
        BrainTopic(id: "topic.exercise", label: String(localized: "Exercise"), words: [
            "en": "exercise workout gym run running jog jogging walk walking yoga swim swimming bike cycling hike hiking marathon training stretch steps football soccer cricket tennis basketball badminton sport pilates",
            "de": "sport training workout fitnessstudio gym laufen joggen spaziergang wandern yoga schwimmen fahrrad radfahren marathon dehnen schritte fußball fussball tennis basketball pilates",
            "es": "ejercicio entrenamiento gimnasio gym correr carrera trotar caminar caminata paseo yoga nadar natación bicicleta bici ciclismo senderismo maratón estiramiento pasos fútbol futbol tenis baloncesto deporte pilates",
            "fr": "sport exercice entraînement entrainement salle gym course courir footing jogging marche promenade randonnée yoga natation nager vélo velo marathon étirements foot football tennis basket pilates",
            "it": "esercizio allenamento palestra corsa correre jogging camminata passeggiata escursione yoga nuoto nuotare bici bicicletta ciclismo maratona stretching passi calcio tennis basket sport pilates",
            "pt": "exercício exercicio treino academia ginásio corrida correr caminhada caminhar passeio trilha yoga ioga natação nadar bicicleta bike ciclismo maratona alongamento passos futebol tênis tenis basquete esporte desporto pilates",
            "ru": "спорт- трениров- зал фитнес- бег- пробежк- прогулк- поход- йог- плаван- велосипед- марафон- растяжк- шаг- футбол- теннис- баскетбол- пилатес-",
            "ja": "運動 トレーニング ジム ランニング ジョギング 散歩 ウォーキング ハイキング ヨガ 水泳 自転車 マラソン ストレッチ 歩数 サッカー テニス バスケ スポーツ ピラティス 筋トレ",
            "ko": "운동 트레이닝 헬스 헬스장 달리기 러닝 조깅 산책 걷기 등산 하이킹 요가 수영 자전거 마라톤 스트레칭 걸음 축구 테니스 농구 스포츠 필라테스",
            "zh": "运动 锻炼 健身 健身房 跑步 慢跑 散步 走路 徒步 爬山 瑜伽 游泳 骑车 自行车 马拉松 拉伸 步数 足球 网球 篮球 羽毛球 体育 普拉提",
        ]),
        BrainTopic(id: "topic.food", label: String(localized: "Food"), words: [
            "en": "food coffee tea breakfast lunch dinner meal snack cooking recipe pizza rice noodle dal bread cake restaurant cafe grocery groceries chocolate dessert soup salad fruit curry pasta brunch",
            "de": "essen kaffee tee frühstück fruehstueck mittagessen abendessen mahlzeit snack kochen rezept pizza reis nudeln brot kuchen restaurant café cafe einkauf lebensmittel schokolade nachtisch suppe salat obst curry pasta",
            "es": "comida café cafe té desayuno almuerzo cena merienda cocinar receta pizza arroz fideos pan pastel tarta restaurante supermercado chocolate postre sopa ensalada fruta pasta",
            "fr": "nourriture repas café cafe thé the petit-déjeuner déjeuner dejeuner dîner diner goûter cuisine cuisiner recette pizza riz nouilles pain gâteau restaurant courses chocolat dessert soupe salade fruit fruits pâtes",
            "it": "cibo caffè caffe tè colazione pranzo cena spuntino cucinare ricetta pizza riso pane torta ristorante bar spesa cioccolato dolce dolci zuppa insalata frutta pasta",
            "pt": "comida café cafe chá cha pequeno-almoço almoço almoco jantar lanche cozinhar receita pizza arroz macarrão pão bolo restaurante mercado compras chocolate sobremesa sopa salada fruta frutas massa",
            "ru": "еда еды еде еду кофе чай чая чаю завтрак- обед- ужин- перекус- готовк- рецепт- пицц- рис риса рисом лапш- хлеб- торт- ресторан- кафе продукт- шоколад- десерт- суп супа супом салат- фрукт- макарон-",
            "ja": "食事 ご飯 ごはん コーヒー お茶 紅茶 朝ごはん 朝食 昼ごはん 昼食 ランチ 晩ごはん 夕食 夕飯 おやつ 料理 レシピ ピザ 米 ラーメン うどん パン ケーキ レストラン カフェ 買い物 チョコレート デザート スープ サラダ 果物 カレー パスタ",
            "ko": "음식 밥 커피 아침 아침밥 점심 저녁 저녁밥 간식 요리 레시피 피자 쌀 라면 국수 빵 케이크 식당 레스토랑 카페 장보기 초콜릿 디저트 수프 샐러드 과일 카레 파스타",
            "zh": "吃饭 食物 饭 咖啡 茶 早饭 早餐 午饭 午餐 晚饭 晚餐 零食 做饭 菜谱 披萨 米饭 面条 面包 蛋糕 餐厅 饭店 咖啡馆 买菜 巧克力 甜点 汤 沙拉 水果 咖喱 意面",
        ]),
        BrainTopic(id: "topic.family", label: String(localized: "Family"), words: [
            "en": "family mom mother mum dad father parent sister brother sibling son daughter kid child children baby grandma grandmother grandpa grandfather aunt uncle cousin nephew niece relative",
            "de": "familie mama mutter papa vater eltern schwester bruder geschwister sohn tochter kind kinder baby oma großmutter opa großvater tante onkel cousin cousine neffe nichte verwandte",
            "es": "familia mamá mama madre papá papa padre padres hermana hermano hermanos hijo hija hijos niño niña niños bebé abuela abuelo abuelos tía tío primo prima sobrino sobrina pariente",
            "fr": "famille maman mère mere papa père pere parents sœur soeur frère frere fils fille enfant enfants bébé bebe grand-mère mamie grand-père papi tante oncle cousin cousine neveu nièce",
            "it": "famiglia mamma madre papà papa padre genitori sorella sorelle fratello fratelli figlio figlia figli bambino bambina bambini neonato nonna nonno nonni zia zio cugino cugina nipote parenti",
            "pt": "família familia mãe mae mamãe pai papai pais irmã irma irmão irmao irmãos filho filha filhos criança crianças bebê bebe avó avô avós tia tio primo prima sobrinho sobrinha parente",
            "ru": "семья семьи семье семью семьей мам- мать матер- пап- отец отц- родител- сестр- брат- сын- доч- ребён- ребен- дети детей детям детьми детск- малыш- бабушк- дедушк- тетя тети тете тетю дяд- двоюродн- племянни- родственни-",
            "ja": "家族 母 お母さん ママ 父 お父さん パパ 両親 親 姉 妹 兄 弟 兄弟 姉妹 息子 娘 子供 子ども 赤ちゃん 祖母 おばあちゃん 祖父 おじいちゃん おば おじ いとこ 甥 姪 親戚",
            "ko": "가족 엄마 어머니 아빠 아버지 부모님 부모 언니 누나 여동생 오빠 형 남동생 동생 형제 아들 딸 아이 아이들 아기 할머니 할아버지 이모 고모 삼촌 사촌 조카 친척",
            "zh": "家人 家庭 妈妈 母亲 爸爸 父亲 父母 姐姐 妹妹 哥哥 弟弟 兄弟 姐妹 儿子 女儿 孩子 宝宝 婴儿 奶奶 外婆 姥姥 爷爷 外公 姥爷 阿姨 姑姑 叔叔 舅舅 表哥 表姐 堂哥 侄子 外甥 亲戚",
        ]),
        BrainTopic(id: "topic.friends", label: String(localized: "Friends"), words: [
            "en": "friend friendship buddy party hangout gathering roommate neighbor neighbour birthday reunion",
            "de": "freund freundin freunde freundinnen freundschaft kumpel party feier treffen mitbewohner nachbar nachbarin geburtstag",
            "es": "amigo amiga amigos amigas amistad fiesta quedada reunión vecino vecina cumpleaños",
            "fr": "ami amie amis amies copain copine potes amitié fête fete soirée colocataire coloc voisin voisine anniversaire",
            "it": "amico amica amici amiche amicizia festa serata coinquilino coinquilina vicino vicina compleanno",
            "pt": "amigo amiga amigos amigas amizade festa encontro colega vizinho vizinha aniversário aniversario",
            "ru": "друг друз- подруг- дружб- приятел- вечеринк- праздник- сосед- рождени-",
            "ja": "友達 友人 親友 友情 パーティー 飲み会 集まり ルームメイト 隣人 誕生日",
            "ko": "친구 친구들 우정 파티 모임 룸메이트 이웃 생일",
            "zh": "朋友 好友 闺蜜 友谊 聚会 派对 室友 邻居 生日",
        ]),
        BrainTopic(id: "topic.love", label: String(localized: "Love"), words: [
            "en": "partner boyfriend girlfriend husband wife dating relationship marriage wedding love crush breakup anniversary fiance fiancee",
            "de": "partner partnerin freund freundin ehemann ehefrau date dating beziehung ehe hochzeit liebe schwarm trennung jahrestag verlobte verlobter",
            "es": "pareja novio novia esposo esposa marido cita citas relación relacion matrimonio boda amor ruptura aniversario prometido prometida",
            "fr": "partenaire copain copine mari couple rendez-vous relation mariage noces amour crush rupture anniversaire fiancé fiancée",
            "it": "partner ragazzo ragazza fidanzato fidanzata marito moglie appuntamento relazione matrimonio nozze amore cotta rottura anniversario",
            "pt": "parceiro parceira namorado namorada marido esposa encontro relacionamento casamento amor paixão término noivo noiva",
            "ru": "парн- девушк- муж мужа мужу мужем жена жены жене жену женой свидани- отношени- брак- свадьб- любов- влюблён- влюблен- расставани- годовщин- жених- невест-",
            "ja": "恋人 彼氏 彼女 夫 旦那 妻 奥さん デート 関係 交際 結婚 結婚式 恋 愛 片思い 別れ 記念日 婚約者",
            "ko": "애인 남자친구 남친 여자친구 여친 남편 아내 와이프 데이트 연애 관계 결혼 결혼식 사랑 짝사랑 이별 기념일 약혼자",
            "zh": "对象 男朋友 女朋友 男友 女友 老公 丈夫 老婆 妻子 约会 恋爱 感情 婚姻 结婚 婚礼 爱 暗恋 分手 纪念日 未婚夫 未婚妻",
        ]),
        BrainTopic(id: "topic.study", label: String(localized: "Study"), words: [
            "en": "school college university class exam study homework assignment lecture teacher professor course thesis test grade semester studying campus tuition essay",
            "de": "schule uni universität hochschule unterricht klasse prüfung pruefung klausur studium lernen hausaufgaben vorlesung lehrer lehrerin professor kurs abschlussarbeit test note noten semester",
            "es": "escuela colegio universidad facultad clase clases examen exámenes estudio estudiar deberes tarea conferencia profesor profesora curso tesis prueba nota notas semestre",
            "fr": "école ecole collège lycée fac université cours classe examen examens partiel études etudes réviser devoirs professeur prof cours thèse test note notes semestre",
            "it": "scuola liceo università universita lezione lezioni classe esame esami studio studiare compiti professore professoressa corso tesi verifica voto voti semestre",
            "pt": "escola colégio faculdade universidade aula aulas turma prova provas exame exames estudo estudar dever lição professor professora curso tese teste nota notas semestre",
            "ru": "школ- колледж- университет- универ- урок- класс- экзамен- сесси- учёб- учеб- домашк- лекци- учител- преподавател- профессор- курс- диплом- контрольн- оценк- семестр-",
            "ja": "学校 大学 授業 クラス 試験 テスト 勉強 宿題 課題 講義 先生 教授 コース 卒論 論文 成績 学期 受験",
            "ko": "학교 대학 대학교 수업 시험 공부 숙제 과제 강의 선생님 교수 교수님 수강 논문 성적 학기 수능",
            "zh": "学校 大学 上课 课 班 考试 学习 作业 功课 讲座 老师 教授 课程 论文 测验 成绩 学期 高考",
        ]),
        BrainTopic(id: "topic.home", label: String(localized: "Home"), words: [
            "en": "home house apartment room chore cleaning laundry dish dishes garden plant landlord furniture kitchen repair",
            "de": "zuhause haus wohnung zimmer hausarbeit putzen wäsche waesche abwasch geschirr garten pflanze pflanzen vermieter möbel küche kueche reparatur umzug",
            "es": "casa hogar piso apartamento departamento habitación cuarto tareas limpieza limpiar ropa colada platos jardín planta plantas casero muebles cocina reparación mudanza",
            "fr": "maison chez-moi appartement appart chambre ménage menage lessive linge vaisselle jardin plante plantes propriétaire meubles cuisine réparation déménagement",
            "it": "casa appartamento stanza camera faccende pulizie bucato piatti giardino pianta piante padrone mobili cucina riparazione trasloco",
            "pt": "casa lar apartamento quarto tarefas limpeza faxina roupa louça loiça jardim planta plantas senhorio móveis cozinha conserto mudança",
            "ru": "дом дома доме домой домашн- квартир- комнат- уборк- стирк- посуд- сад саду сада растени- хозяин- мебел- кухн- ремонт- переезд-",
            "ja": "家 自宅 実家 部屋 アパート マンション 家事 掃除 洗濯 皿洗い 庭 植物 大家 家具 台所 キッチン 修理 引っ越し",
            "ko": "집 아파트 방 원룸 집안일 청소 빨래 설거지 정원 식물 화분 집주인 가구 부엌 주방 수리 이사",
            "zh": "家 房子 公寓 房间 家务 打扫 洗衣服 洗碗 花园 植物 房东 家具 厨房 修理 搬家",
        ]),
        BrainTopic(id: "topic.travel", label: String(localized: "Travel"), words: [
            "en": "trip travel vacation holiday flight airport journey hotel beach mountain visa packing passport luggage tour",
            "de": "reise reisen urlaub ferien flug flughafen hotel strand berg berge visum packen reisepass gepäck ausflug",
            "es": "viaje viajes viajar vacaciones vuelo aeropuerto hotel playa montaña visa visado maleta pasaporte equipaje excursión",
            "fr": "voyage voyages voyager vacances vol aéroport aeroport hôtel hotel plage montagne visa valise passeport bagages excursion",
            "it": "viaggio viaggi viaggiare vacanza vacanze volo aeroporto albergo hotel spiaggia montagna visto valigia passaporto bagagli gita",
            "pt": "viagem viagens viajar férias ferias voo aeroporto hotel praia montanha visto mala passaporte bagagem passeio excursão",
            "ru": "поездк- путешестви- отпуск- каникул- рейс- перелёт- аэропорт- гостиниц- отел- пляж- горы горах виз- чемодан- паспорт- багаж- экскурси-",
            "ja": "旅行 旅 休暇 休み 飛行機 フライト 空港 ホテル 海 ビーチ 山 ビザ 荷造り パスポート 荷物 ツアー",
            "ko": "여행 휴가 방학 비행기 항공편 공항 호텔 해변 바다 산 비자 짐 여권 투어",
            "zh": "旅行 旅游 出差 假期 度假 航班 飞机 机场 酒店 海边 沙滩 山 签证 行李 护照 出游",
        ]),
        BrainTopic(id: "topic.commute", label: String(localized: "Commute"), words: [
            "en": "commute traffic bus metro subway train drive car taxi uber",
            "de": "pendeln arbeitsweg stau verkehr bus u-bahn s-bahn zug bahn auto taxi",
            "es": "trayecto tráfico trafico atasco autobús autobus bus metro tren coche carro taxi",
            "fr": "trajet transports trafic embouteillage bouchons bus métro metro train rer voiture taxi",
            "it": "tragitto pendolare traffico ingorgo autobus bus metro metropolitana treno macchina auto taxi",
            "pt": "trajeto trânsito transito engarrafamento ônibus onibus autocarro metrô metro comboio trem carro táxi taxi",
            "ru": "дорога дороге дорогу пробк- автобус- метро электричк- поезд- машин- такси",
            "ja": "通勤 渋滞 交通 バス 地下鉄 電車 運転 車 タクシー",
            "ko": "출퇴근 통근 교통 막힘 버스 지하철 기차 운전 자동차 택시",
            "zh": "通勤 堵车 交通 公交 公交车 地铁 火车 开车 车 出租车 打车",
        ]),
        BrainTopic(id: "topic.mind", label: String(localized: "Mind"), words: [
            "en": "anxiety stress panic worry therapy therapist mood depression burnout overthinking meditation mindfulness calm peace loneliness confidence fear anger sadness grief gratitude motivation emotion tears crying",
            "de": "angst ängste stress panik sorge sorgen therapie therapeut therapeutin stimmung depression burnout grübeln meditation achtsamkeit ruhe frieden einsamkeit selbstvertrauen furcht wut trauer dankbarkeit motivation gefühl gefühle tränen weinen",
            "es": "ansiedad estrés estres pánico preocupación terapia terapeuta psicólogo psicóloga ánimo depresión agotamiento meditación calma paz soledad confianza miedo ira enojo tristeza duelo gratitud motivación emoción emociones lágrimas llanto",
            "fr": "anxiété angoisse stress panique inquiétude thérapie thérapeute psy psychologue humeur dépression burn-out méditation calme paix solitude confiance peur colère tristesse deuil gratitude motivation émotion émotions larmes",
            "it": "ansia stress panico preoccupazione terapia terapeuta psicologo psicologa umore depressione burnout meditazione calma pace solitudine fiducia paura rabbia tristezza lutto gratitudine motivazione emozione emozioni lacrime pianto",
            "pt": "ansiedade estresse stress pânico preocupação terapia terapeuta psicólogo psicóloga humor depressão burnout meditação calma paz solidão confiança medo raiva tristeza luto gratidão motivação emoção emoções lágrimas choro",
            "ru": "тревог- стресс- паник- беспокойств- терапи- терапевт- психолог- настроени- депресси- выгорани- медитаци- спокойстви- покой одиночеств- уверенност- страх- злост- гнев- грусть груст- печал- горе благодарност- мотиваци- эмоци- слёз- слез- плач-",
            "ja": "不安 ストレス パニック 心配 セラピー カウンセリング カウンセラー 気分 うつ 鬱 燃え尽き 瞑想 マインドフルネス 落ち着き 平和 孤独 自信 恐怖 怒り 悲しみ 感謝 やる気 モチベーション 感情 涙",
            "ko": "불안 스트레스 공황 걱정 상담 치료 상담사 기분 우울 우울증 번아웃 명상 마음챙김 평온 평화 외로움 자신감 두려움 분노 슬픔 감사 동기 의욕 감정 눈물",
            "zh": "焦虑 压力 惊恐 担心 心理咨询 咨询 治疗 心情 情绪 抑郁 倦怠 冥想 正念 平静 安宁 孤独 寂寞 自信 恐惧 愤怒 生气 悲伤 难过 感恩 动力 眼泪 哭",
        ]),
        BrainTopic(id: "topic.hobbies", label: String(localized: "Hobbies"), words: [
            "en": "book reading novel chapter writing music song guitar piano painting drawing art movie film show series game gaming podcast photography poetry poem concert album knitting",
            "de": "buch bücher lesen roman kapitel schreiben musik lied song gitarre klavier malen zeichnen kunst film serie spiel spiele podcast fotografie gedicht konzert album stricken",
            "es": "libro libros lectura leer novela capítulo escribir escritura música musica canción guitarra piano pintura dibujo arte película pelicula serie juego videojuego pódcast podcast fotografía poesía poema concierto álbum tejer",
            "fr": "livre livres lecture lire roman chapitre écriture écrire musique chanson guitare piano peinture dessin art film série serie jeu jeux podcast photo photographie poésie poème concert album tricot",
            "it": "libro libri lettura leggere romanzo capitolo scrittura scrivere musica canzone chitarra pianoforte pittura disegno arte film serie gioco giochi videogioco podcast fotografia poesia concerto album maglia",
            "pt": "livro livros leitura ler romance capítulo escrita escrever música musica canção guitarra violão piano pintura desenho arte filme série serie jogo jogos podcast fotografia poesia poema show concerto álbum tricô",
            "ru": "книг- чтени- роман- глава главы главу писательств- музык- песн- гитар- пианино рисовани- рисунок искусств- фильм- кино сериал- игр- подкаст- фотографи- стих- поэзи- концерт- альбом- вязани-",
            "ja": "本 読書 小説 章 執筆 音楽 曲 歌 ギター ピアノ 絵 絵画 アート 映画 ドラマ ゲーム ポッドキャスト 写真 詩 コンサート ライブ アルバム 編み物 趣味",
            "ko": "책 독서 소설 글쓰기 음악 노래 기타 피아노 그림 미술 영화 드라마 게임 팟캐스트 사진 콘서트 공연 앨범 뜨개질 취미",
            "zh": "书 读书 看书 小说 章节 写作 音乐 歌 歌曲 吉他 钢琴 画画 绘画 艺术 电影 电视剧 剧 游戏 播客 摄影 拍照 诗 诗歌 演唱会 音乐会 专辑 织毛衣 爱好",
        ]),
        BrainTopic(id: "topic.outdoors", label: String(localized: "Outdoors"), words: [
            "en": "rain weather sun sunshine snow river park nature tree sky ocean sea lake forest sunset sunrise storm",
            "de": "regen wetter sonne sonnenschein schnee fluss park natur baum bäume himmel meer see wald sonnenuntergang sonnenaufgang sturm gewitter",
            "es": "lluvia clima sol nieve río rio parque naturaleza árbol árboles cielo océano mar lago bosque atardecer amanecer tormenta",
            "fr": "pluie météo meteo soleil neige rivière fleuve parc nature arbre arbres ciel océan mer lac forêt foret orage tempête",
            "it": "pioggia meteo sole neve fiume parco natura albero alberi cielo oceano mare lago bosco foresta tramonto alba temporale tempesta",
            "pt": "chuva clima sol neve rio parque natureza árvore árvores céu ceu oceano mar lago floresta bosque pôr-do-sol nascer tempestade",
            "ru": "дожд- погод- солнц- снег- река реки реке реку парк- природ- дерев- небо неба небе океан- море моря морю морем озер- лес леса лесу лесом закат- рассвет- гроз-",
            "ja": "雨 天気 太陽 日差し 晴れ 雪 川 公園 自然 木 空 海 湖 森 夕日 夕焼け 日の出 嵐 台風",
            "ko": "비 날씨 햇살 햇빛 강 공원 자연 나무 하늘 바다 호수 숲 노을 일몰 일출 폭풍 태풍",
            "zh": "雨 下雨 天气 太阳 阳光 晴天 雪 下雪 河 公园 大自然 自然 树 天空 海 大海 湖 森林 日落 夕阳 日出 暴风雨 台风",
        ]),
        BrainTopic(id: "topic.screens", label: String(localized: "Screens"), words: [
            "en": "phone laptop computer instagram screen internet app twitter youtube netflix scrolling tiktok message text",
            "de": "handy smartphone telefon laptop computer instagram bildschirm internet app tiktok youtube netflix nachricht nachrichten",
            "es": "móvil movil celular teléfono laptop portátil ordenador computadora instagram pantalla internet app redes tiktok youtube netflix mensaje mensajes",
            "fr": "téléphone telephone portable smartphone ordi ordinateur instagram écran ecran internet appli réseaux tiktok youtube netflix message messages",
            "it": "telefono cellulare smartphone portatile computer instagram schermo internet app social tiktok youtube netflix messaggio messaggi",
            "pt": "celular telemóvel telemovel telefone notebook portátil computador instagram tela ecrã internet app redes tiktok youtube netflix mensagem mensagens",
            "ru": "телефон- смартфон- ноутбук- компьютер- инстаграм- экран- интернет- приложени- соцсет- тикток- ютуб- нетфликс- сообщени-",
            "ja": "スマホ 携帯 電話 パソコン ノートパソコン インスタ 画面 ネット インターネット アプリ SNS ツイッター ユーチューブ ネットフリックス ティックトック メッセージ ライン",
            "ko": "휴대폰 핸드폰 폰 전화 노트북 컴퓨터 인스타 인스타그램 화면 인터넷 앱 SNS 유튜브 넷플릭스 틱톡 메시지 카톡",
            "zh": "手机 电话 电脑 笔记本 屏幕 网络 上网 应用 社交媒体 微博 微信 抖音 视频 短信 消息 刷手机",
        ]),
        BrainTopic(id: "topic.pets", label: String(localized: "Pets"), words: [
            "en": "dog cat puppy kitten pet vet",
            "de": "hund katze welpe kätzchen haustier tierarzt",
            "es": "perro perra gato gata cachorro gatito mascota veterinario",
            "fr": "chien chienne chat chatte chiot chaton animal vétérinaire veto",
            "it": "cane gatto gatta cucciolo gattino animale veterinario",
            "pt": "cachorro cão cao cadela gato gata filhote gatinho animal pet veterinário",
            "ru": "собак- пёс пес кот кошка кошки кошке кошку щен- котён- котен- питом- ветеринар-",
            "ja": "犬 猫 子犬 子猫 ペット 獣医",
            "ko": "강아지 고양이 반려동물 반려견 반려묘 동물병원 수의사",
            "zh": "狗 狗狗 小狗 猫 猫咪 小猫 宠物 兽医",
        ]),
        BrainTopic(id: "topic.faith", label: String(localized: "Faith"), words: [
            "en": "church temple prayer god faith mosque spirituality gurdwara worship",
            "de": "kirche tempel gebet gott glaube moschee spiritualität gottesdienst",
            "es": "iglesia templo oración oracion dios fe mezquita espiritualidad misa",
            "fr": "église eglise temple prière priere dieu foi mosquée spiritualité messe",
            "it": "chiesa tempio preghiera dio fede moschea spiritualità messa",
            "pt": "igreja templo oração oracao deus fé mesquita espiritualidade missa culto",
            "ru": "церк- храм- молитв- бог- бож- вера веры вере веру мечет- духовност-",
            "ja": "教会 寺 神社 祈り 神様 神 信仰 モスク 礼拝 お参り",
            "ko": "교회 성당 기도 하나님 하느님 신앙 모스크 예배 미사",
            "zh": "教堂 寺庙 庙 祈祷 祷告 上帝 神 信仰 清真寺 礼拜 拜佛",
        ]),
        BrainTopic(id: "topic.goals", label: String(localized: "Goals"), words: [
            "en": "goal plan habit routine resolution progress future decision",
            "de": "ziel ziele plan pläne gewohnheit gewohnheiten routine vorsatz fortschritt zukunft entscheidung",
            "es": "meta metas objetivo objetivos plan planes hábito hábitos rutina propósito progreso futuro decisión",
            "fr": "objectif objectifs but plan plans habitude habitudes routine résolution progrès avenir futur décision",
            "it": "obiettivo obiettivi abitudine abitudini routine proposito progressi futuro decisione",
            "pt": "meta metas objetivo objetivos plano planos hábito hábitos rotina resolução progresso futuro decisão",
            "ru": "цел- план- привычк- рутин- распорядок- прогресс- будущ- решени-",
            "ja": "目標 計画 予定 習慣 ルーティン 抱負 進歩 将来 未来 決断",
            "ko": "목표 계획 습관 루틴 다짐 결심 진전 미래 결정",
            "zh": "目标 计划 打算 习惯 作息 决心 进步 未来 将来 决定",
        ]),
    ]

    static let byID: [String: BrainTopic] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The app's language code for an `NLLanguage` raw value (`zh-Hans` → `zh`), or nil for a
    /// language with no list.
    static func listLanguage(_ raw: String) -> String? {
        let base = raw.hasPrefix("zh") ? "zh" : String(raw.prefix(2))
        return lexicons[base] == nil ? nil : base
    }

    /// One language's words, folded like term keys. A word listed under two topics stays with
    /// the first.
    struct Lexicon: Sendable {
        var exact: [String: String] = [:]
        /// Stems grouped by their first two characters, so a token checks a few stems, not all.
        var stems: [String: [(stem: String, topicID: String)]] = [:]
    }

    static let lexicons: [String: Lexicon] = {
        var result: [String: Lexicon] = [:]
        for topic in all {
            for (language, list) in topic.words {
                var lexicon = result[language] ?? Lexicon()
                for raw in list.split(separator: " ") {
                    if raw.hasSuffix("-") && raw.count > 3 {
                        let stem = fold(String(raw.dropLast()))
                        lexicon.stems[String(stem.prefix(2)), default: []].append((stem, topic.id))
                    } else {
                        let word = fold(String(raw))
                        if lexicon.exact[word] == nil { lexicon.exact[word] = topic.id }
                    }
                }
                result[language] = lexicon
            }
        }
        return result
    }()

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }

    /// Korean particles that stick to the noun before them ("회의를" → "회의").
    private static let koreanParticles = ["에서", "으로", "에게", "한테", "까지", "부터", "처럼", "보다", "하고",
                                          "이랑", "랑", "를", "을", "가", "이", "는", "은", "와", "과", "에", "도", "의", "로", "만"]

    /// The topic id for a folded word in a list language, trying simple plural and particle forms.
    static func topicID(for key: String, language: String) -> String? {
        guard let lexicon = lexicons[language] else { return nil }
        if let id = lexicon.exact[key] { return id }
        var candidates: [String] = []
        switch language {
        case "en":
            if key.hasSuffix("ies") { candidates.append(String(key.dropLast(3)) + "y") }
            if key.hasSuffix("es") { candidates.append(String(key.dropLast(2))) }
            if key.hasSuffix("s") { candidates.append(String(key.dropLast())) }
        case "es", "fr", "pt", "it", "de":
            for suffix in ["es", "en", "er", "s", "x", "n", "e"] where key.hasSuffix(suffix) && key.count > suffix.count + 2 {
                candidates.append(String(key.dropLast(suffix.count)))
            }
        case "ko":
            for particle in koreanParticles where key.hasSuffix(particle) && key.count > particle.count {
                candidates.append(String(key.dropLast(particle.count)))
            }
        default:
            break
        }
        for candidate in candidates {
            if let id = lexicon.exact[candidate] { return id }
        }
        if let stems = lexicon.stems[String(key.prefix(2))] {
            for entry in stems where key.hasPrefix(entry.stem) { return entry.topicID }
        }
        return nil
    }
}
