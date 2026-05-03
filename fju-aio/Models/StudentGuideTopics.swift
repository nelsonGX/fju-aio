import Foundation

// MARK: - Guide Data Types (shared between StudentGuideView and SearchEngine)

struct GuideTopic: Identifiable {
    let id: String
    let title: String
    let category: String
    let icon: String
    let summary: String
    let steps: [String]
    let contacts: [GuideContact]
    let links: [GuideLink]
    let keywords: [String]
}

struct GuideContact: Identifiable {
    let id = UUID()
    let name: String
    let phone: String
}

struct GuideLink: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

// MARK: - Static Data

let allGuideTopics: [GuideTopic] = [
    GuideTopic(
        id: "student-id-reissue",
        title: "學生證遺失補辦",
        category: "教務",
        icon: "person.text.rectangle.fill",
        summary: "學生證遺失、毀損、更名或轉系後，可在學生資訊平台掛失並線上繳費，約五個工作天後領卡。",
        steps: [
            "登入學生資訊平台辦理掛失與申請補辦。",
            "完成線上繳費。",
            "製卡約需五個工作天。",
            "攜帶身分證或健保卡至註冊組領取。",
            "即使悠遊卡沒有儲值，遺失後仍應掛失，避免校內門禁與圖書館權益被冒用。"
        ],
        contacts: [
            GuideContact(name: "註冊組（日間）", phone: "02-2905-3042"),
            GuideContact(name: "進修學制註冊業務", phone: "02-2905-2298")
        ],
        links: [
            GuideLink(title: "學生資訊入口網", url: URL(string: "https://portal.fju.edu.tw/student/")!)
        ],
        keywords: ["學生證", "掛失", "補辦", "註冊組", "校園卡"]
    ),
    GuideTopic(
        id: "course-selection",
        title: "選課與錯誤更正",
        category: "教務",
        icon: "list.bullet.rectangle.fill",
        summary: "選課各階段採志願分發，分發後務必查閱選課清單；有錯誤符號的課程需自行退選或辦理更正。",
        steps: [
            "預選、全人志願、初選、加退選完成後都要查閱選課結果。",
            "有錯誤標記的課程未完成更正，即使到課也視為無效選課。",
            "拒加、拒退課程於網路初選與加退選登記階段，可洽開課單位秘書協助。",
            "網路加退選後仍有問題，需於選課錯誤更正截止前送人工加退選申請單。",
            "至遲於錯誤更正截止日前確認當學期選課清單，系統資料是最終選課結果。"
        ],
        contacts: [
            GuideContact(name: "課務組（日間）", phone: "02-2905-3097"),
            GuideContact(name: "課務組（進修）", phone: "02-2905-2285")
        ],
        links: [
            GuideLink(title: "選課系統", url: URL(string: "https://signcourse.fju.edu.tw")!),
            GuideLink(title: "全人志願選課系統", url: URL(string: "http://wishcourse.fju.edu.tw")!)
        ],
        keywords: ["選課", "加退選", "錯誤更正", "全人", "超修", "課務組"]
    ),
    GuideTopic(
        id: "leave-exam",
        title: "考試請假與補考",
        category: "教務",
        icon: "doc.badge.clock.fill",
        summary: "期中、期末或畢業考試無法應考時，需依學生考試請假規則於期限內辦理。",
        steps: [
            "先確認適用「學生考試請假規則」。",
            "於規定期限內辦理請假手續。",
            "請假核准後，考試後一週內自行聯繫任課教師擇期補考。",
            "逾期不得以任何理由申請另行補考。",
            "身心障礙學生可依規定申請調整考試形式服務。"
        ],
        contacts: [
            GuideContact(name: "課務組", phone: "02-2905-3097"),
            GuideContact(name: "特殊教育學生資源中心", phone: "02-2905-3115"),
            GuideContact(name: "特殊教育學生資源中心輔具/服務", phone: "02-2905-3148")
        ],
        links: [],
        keywords: ["考試", "請假", "補考", "身心障礙", "調整考試形式"]
    ),
    GuideTopic(
        id: "aid",
        title: "助學與急難救助",
        category: "學務",
        icon: "dollarsign.circle.fill",
        summary: "就學貸款、減免、弱勢助學、生活助學金、清寒助學金、獎助學金與急難救助多由生輔組承辦。",
        steps: [
            "就學貸款須於開學前至臺灣銀行完成對保並繳回資料。",
            "就學優待減免通常於每年六月上旬與十二月中旬受理。",
            "弱勢學生助學金每學年第一學期約十月一日至十月二十日申請。",
            "生活助學金與清寒助學金通常每年約六月與十二月申請，以公告為準。",
            "家庭突遭變故或重大事故影響就學，可洽急難救助。"
        ],
        contacts: [
            GuideContact(name: "就學貸款（日間）", phone: "02-2905-2231"),
            GuideContact(name: "就學優待減免（日間）", phone: "02-2905-3173"),
            GuideContact(name: "行政院減免學雜費（日間）", phone: "02-2905-3747"),
            GuideContact(name: "獎助學金（日間）", phone: "02-2905-3101"),
            GuideContact(name: "進修部學務", phone: "02-2905-2246"),
            GuideContact(name: "急難救助（日間）", phone: "02-2905-2270"),
            GuideContact(name: "深耕起飛學生學習輔導", phone: "02-2905-3803")
        ],
        links: [
            GuideLink(title: "學務處獎助學金資訊系統", url: URL(string: "http://stuservice.fju.edu.tw/fjcugrant/")!),
            GuideLink(title: "教育部圓夢助學網", url: URL(string: "https://www.edu.tw/helpdreams/Default.aspx")!)
        ],
        keywords: ["助學", "就貸", "減免", "獎學金", "弱勢", "急難", "生活助學金", "清寒"]
    ),
    GuideTopic(
        id: "appeal-gender-bullying",
        title: "申訴、性平與霸凌通報",
        category: "安全",
        icon: "exclamationmark.shield.fill",
        summary: "學生申訴、校園性別事件與校園霸凌事件有不同程序；通報不等於啟動調查。",
        steps: [
            "學生申訴通常應於收到懲處、措施或決議次日起三十日內以書面提出。",
            "性別事件可向校安中心或生活輔導組通報；申請調查需以書面向接案單位提出。",
            "校園霸凌可由被害人、法定代理人申請調查，或由任何人檢舉。",
            "校內緊急狀況可先聯絡校安中心或警衛室。",
            "若有人身安全疑慮，優先撥打 110 或 119。"
        ],
        contacts: [
            GuideContact(name: "校安中心 24 小時", phone: "02-2905-2885"),
            GuideContact(name: "校安行動電話", phone: "0905-298-885"),
            GuideContact(name: "生活輔導組性平/霸凌", phone: "02-2905-3103"),
            GuideContact(name: "學生申訴", phone: "02-2905-3101")
        ],
        links: [
            GuideLink(title: "性平申請書下載", url: URL(string: "http://gender.fju.edu.tw/prevent3.php")!),
            GuideLink(title: "教育部防制校園霸凌專區", url: URL(string: "https://bully.moe.edu.tw/index")!)
        ],
        keywords: ["申訴", "性平", "性騷擾", "性侵害", "性霸凌", "霸凌", "通報", "調查"]
    ),
    GuideTopic(
        id: "military",
        title: "兵役與役男出境",
        category: "學務",
        icon: "figure.stand.line.dotted.figure.stand",
        summary: "新生、轉學生、復學生需依身分繳交兵役資料；尚未履行兵役義務役男短期出境需線上申請。",
        steps: [
            "新生、當學期轉學生、復學生需填寫兵役資料單，外籍生與無中華民國身分證的僑陸生免填。",
            "尚未服役役男繳交兵役資料單；已服役、免役、替代役等另附相關證明。",
            "收到徵集令時，可持學生證或繳費證明至生輔組申請暫緩徵集用在學證明。",
            "休學、退學或離校應至生輔組登記註銷緩徵或儘後召集。",
            "役男短期出境不得逾四個月，請至內政部役政署系統申請。"
        ],
        contacts: [
            GuideContact(name: "兵役（日間）", phone: "02-2905-3031"),
            GuideContact(name: "兵役（進修）", phone: "02-2905-2979")
        ],
        links: [
            GuideLink(title: "役男短期出境線上申請", url: URL(string: "https://service.dca.moi.gov.tw/departure/app/Departure/main")!)
        ],
        keywords: ["兵役", "緩徵", "儘後召集", "役男", "出境", "徵集令"]
    ),
    GuideTopic(
        id: "insurance-lost-found",
        title: "學生團保與拾物招領",
        category: "生活",
        icon: "cross.case.fill",
        summary: "團保理賠與拾物招領主要由生活輔導組辦理；下班與例假日可洽軍訓室值班教官。",
        steps: [
            "團保理賠需準備申請書、診斷證明書、醫療費收據、受益人存摺封面等資料。",
            "非本國籍學生需附居留證正反面影本。",
            "拾物招領上班時間洽日間生活輔導組或進修部學務處夜間辦公室。",
            "下班時間及例假日由軍訓室值班教官受理。"
        ],
        contacts: [
            GuideContact(name: "團保/拾物（日間）", phone: "02-2905-3100"),
            GuideContact(name: "學生團體保險（進修）", phone: "02-2905-2979"),
            GuideContact(name: "拾物招領（進修）", phone: "02-2905-2246"),
            GuideContact(name: "軍訓室值班", phone: "02-2905-2885"),
            GuideContact(name: "軍訓室值班備用", phone: "02-2902-3419")
        ],
        links: [
            GuideLink(title: "生活輔導組表件下載", url: URL(string: "http://life.dsa.fju.edu.tw/form.htm/")!)
        ],
        keywords: ["團保", "保險", "理賠", "拾物", "失物", "招領"]
    ),
    GuideTopic(
        id: "rental-safety",
        title: "租屋安全檢查",
        category: "生活安全",
        icon: "house.lodge.fill",
        summary: "看屋應結伴同行，檢查門禁、消防、熱水器、逃生通道、用電與房屋狀況。",
        steps: [
            "先觀察周遭環境與人員進出，並盡量詢問前房客或學長姐經驗。",
            "看屋務必結伴同行。",
            "檢查漏水、壁癌、門鎖、裝潢防火材質、插座電線、水質與排水。",
            "確認滅火器、偵煙器、逃生通道、安全梯、安全門與鐵窗逃生方式。",
            "押金不超過兩個月租金，付款時索取收據，交屋點交並拍照存證。"
        ],
        contacts: [
            GuideContact(name: "校外租賃/賃居訪視", phone: "02-2905-2054"),
            GuideContact(name: "校安中心", phone: "02-2905-2885")
        ],
        links: [
            GuideLink(title: "輔大雲端租屋網", url: URL(string: "https://house.nfu.edu.tw/fju")!)
        ],
        keywords: ["租屋", "賃居", "安全", "押金", "熱水器", "消防", "逃生"]
    ),
    GuideTopic(
        id: "scam",
        title: "防詐騙處理",
        category: "生活安全",
        icon: "phone.down.waves.left.and.right",
        summary: "遇到可疑電話或交易，記住一聽、二掛、三查，立即撥打 165 或 110 查證。",
        steps: [
            "一聽：聽清楚電話內容，保持戒心。",
            "二掛：聽完立刻掛電話，避免被持續操控情緒。",
            "三查：撥打 165 或 110 查證。",
            "演唱會票券、租屋訂金、假身分證取信等都是常見詐騙情境。",
            "0800、165、110 等免付費或官方號碼若顯示為來電，也可能是偽冒。"
        ],
        contacts: [
            GuideContact(name: "反詐騙諮詢", phone: "165"),
            GuideContact(name: "報警", phone: "110")
        ],
        links: [
            GuideLink(title: "165 全民防騙網", url: URL(string: "https://165.npa.gov.tw/")!)
        ],
        keywords: ["詐騙", "165", "防騙", "演唱會", "租屋", "匯款"]
    )
]
