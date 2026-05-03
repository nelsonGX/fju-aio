import Foundation

// MARK: - Contact Data Types (shared between ContactInfoView and SearchEngine)

struct EmergencyContact: Identifiable {
    let id = UUID()
    let name: String
    let phone: String
}

struct DepartmentContact: Identifiable {
    let id = UUID()
    let name: String
    let phones: [String]
    let fax: String?
    let email: String?
}

// MARK: - Static Data

let allEmergencyContacts: [EmergencyContact] = [
    EmergencyContact(name: "報警 / 車禍報案", phone: "110"),
    EmergencyContact(name: "火災 / 救護車", phone: "119"),
    EmergencyContact(name: "反詐騙諮詢", phone: "165"),
    EmergencyContact(name: "婦幼保護專線", phone: "113"),
    EmergencyContact(name: "衛福部安心專線", phone: "1925"),
    EmergencyContact(name: "生命線", phone: "1995"),
    EmergencyContact(name: "校安 24 小時緊急聯絡", phone: "(02) 2905-2885"),
    EmergencyContact(name: "校安行動電話", phone: "0905-298-885"),
    EmergencyContact(name: "學校總機", phone: "(02) 2905-2000"),
    EmergencyContact(name: "警衛室前門", phone: "(02) 2905-2119"),
    EmergencyContact(name: "警衛室後門", phone: "(02) 2905-3065"),
    EmergencyContact(name: "輔大附設醫院急診室", phone: "(02) 8512-8888"),
    EmergencyContact(name: "臺北醫院急診室", phone: "(02) 2276-5566"),
    EmergencyContact(name: "新泰綜合醫院急診室", phone: "(02) 2996-2121"),
    EmergencyContact(name: "衛生保健組", phone: "(02) 2905-2995"),
    EmergencyContact(name: "輔大診所", phone: "(02) 2905-2526"),
    EmergencyContact(name: "學生輔導中心", phone: "(02) 2905-3003"),
    EmergencyContact(name: "法律服務中心", phone: "(02) 2905-2642"),
    EmergencyContact(name: "福營派出所", phone: "(02) 2901-7434"),
    EmergencyContact(name: "福營消防隊", phone: "(02) 2903-2119"),
    EmergencyContact(name: "新莊交通分隊", phone: "(02) 2902-2116"),
]

let allDepartmentContacts: [DepartmentContact] = [
    DepartmentContact(name: "董事會",       phones: ["02-2905-3117"],                                           fax: "02-2908-6242", email: "trust@mail.fju.edu.tw"),
    DepartmentContact(name: "校長室",       phones: ["02-2905-2202"],                                           fax: nil,            email: "president@mail.fju.edu.tw"),
    DepartmentContact(name: "公共事務室",   phones: ["02-2905-2211"],                                           fax: "02-2902-6201", email: "pro@mail.fju.edu.tw"),
    DepartmentContact(name: "祕書室",       phones: ["02-2905-2204"],                                           fax: "02-2904-4938", email: "secret@mail.fju.edu.tw"),
    DepartmentContact(name: "教務處",       phones: ["02-2905-2217", "02-2905-2218", "02-2905-3042 (註冊組)", "02-2905-3097 (課務組)", "02-2905-2224 (招生組)"],
                                                                                                                fax: "02-2905-2225", email: "dean@mail.fju.edu.tw"),
    DepartmentContact(name: "學務處",       phones: ["02-2905-3174"],                                           fax: "02-2905-3174", email: "dsa@mail.fju.edu.tw"),
    DepartmentContact(name: "總務處",       phones: ["02-2905-2239"],                                           fax: "02-2904-1679", email: "glafair@mail.fju.edu.tw"),
    DepartmentContact(name: "研究發展處",   phones: ["02-2905-3109", "02-2905-3136"],                           fax: "02-2904-1563", email: "rdo@mail.fju.edu.tw"),
    DepartmentContact(name: "國際教育處",   phones: ["02-2905-3137"],                                           fax: "02-2903-5524", email: "oie@mail.fju.edu.tw"),
    DepartmentContact(name: "人事室",       phones: ["02-2905-2206"],                                           fax: "02-2908-6210", email: "person@mail.fju.edu.tw"),
    DepartmentContact(name: "法務室",       phones: ["02-2905-3124"],                                           fax: "02-2904-1947", email: "legal@mail.fju.edu.tw"),
    DepartmentContact(name: "軍訓室",       phones: ["02-2905-2885", "0905-298-885 (行動)"],                    fax: "02-2902-3419", email: "smt@mail.fju.edu.tw"),
    DepartmentContact(name: "體育室",       phones: ["02-2905-3073", "02-2905-2234"],                           fax: "02-2901-7051", email: "gl6@mail.fju.edu.tw"),
    DepartmentContact(name: "會計室",       phones: ["02-2905-2300", "02-2905-3009", "02-2905-2410"],           fax: "02-2908-8360", email: "fjdp0046@mail.fju.edu.tw"),
    DepartmentContact(name: "校史室",       phones: ["02-2905-3046"],                                           fax: "02-2905-3152", email: "fuho@mail.fju.edu.tw"),
    DepartmentContact(name: "資訊中心",     phones: ["02-2905-3093", "02-2905-2712"],                           fax: "02-2902-9557", email: "pubwww@mail.fju.edu.tw"),
    DepartmentContact(name: "宗輔中心",     phones: ["02-2905-2260", "02-2905-2256"],                           fax: "02-2902-5017", email: "religion@mail.fju.edu.tw"),
    DepartmentContact(name: "學輔中心",     phones: ["02-2905-2278", "02-2905-2237"],                           fax: "02-2904-4597", email: "scc@mail.fju.edu.tw"),
    DepartmentContact(name: "進修部",       phones: ["02-2905-2855"],                                           fax: "02-2902-8002", email: "dean@mail.fju.edu.tw"),
    DepartmentContact(name: "推廣部",       phones: ["02-2905-2269", "02-2905-2259", "02-2905-3731"],           fax: "02-2901-0673", email: "ext@mail.fju.edu.tw"),
    DepartmentContact(name: "婦女大學",     phones: ["02-2905-2252", "02-2905-2276"],                           fax: "02-2905-2187", email: "029863@mail.fju.edu.tw"),
    DepartmentContact(name: "圖書館",       phones: ["02-2905-2673"],                                           fax: "02-2905-3158", email: "library@mail.fju.edu.tw"),
    DepartmentContact(name: "輔大出版社",   phones: ["02-2905-6199"],                                           fax: "02-2905-6170", email: "fjcup@mail.fju.edu.tw"),
    DepartmentContact(name: "輔大診所",     phones: ["02-2905-2526", "02-2905-3130"],                           fax: "02-2901-6040", email: "fj02101@mail.fju.edu.tw"),
    DepartmentContact(name: "輔大附設醫院", phones: ["02-8512-8888 (總機)", "02-8512-8800 (預約掛號)"],         fax: nil,            email: "fjuhospital@mail.fju.edu.tw"),
    DepartmentContact(name: "神學院",       phones: ["02-2905-2792"],                                           fax: "02-2906-2439", email: "theology@mail.fju.edu.tw"),
    DepartmentContact(name: "註冊組（學籍/成績/證明/學生證）",
                      phones: ["02-2905-3042", "02-2905-2298 (進修)"],
                      fax: nil, email: nil),
    DepartmentContact(name: "課務組（選課/考試/校際選課）",
                      phones: ["02-2905-3097 (日)", "02-2905-2285 (進)"],
                      fax: nil, email: nil),
    DepartmentContact(name: "教師發展與教學資源中心",
                      phones: ["02-2905-2387", "02-2905-3190", "02-2905-3302"],
                      fax: nil, email: nil),
    DepartmentContact(name: "雙語教育中心",
                      phones: ["02-2905-2016"],
                      fax: nil, email: nil),
    DepartmentContact(name: "深耕計畫辦公室",
                      phones: ["02-2905-3189"],
                      fax: nil, email: nil),
    DepartmentContact(name: "生活輔導組（就貸/減免/獎助/兵役/拾物）",
                      phones: ["02-2905-3173 (減免)", "02-2905-2231 (就貸)", "02-2905-3101 (獎助/申訴)", "02-2905-3100 (團保/拾物)", "02-2905-3031 (兵役)"],
                      fax: nil, email: nil),
    DepartmentContact(name: "生活輔導組（性平/霸凌/跟騷）",
                      phones: ["02-2905-3103", "02-2905-3040", "02-2905-3070"],
                      fax: nil, email: nil),
    DepartmentContact(name: "課外活動指導組（社團/場地器材）",
                      phones: ["02-2905-2233", "02-2905-3049"],
                      fax: nil, email: nil),
    DepartmentContact(name: "職涯發展與就業輔導組",
                      phones: ["02-2905-3002", "02-2905-3011", "02-2905-4142"],
                      fax: nil, email: nil),
    DepartmentContact(name: "僑生及陸生輔導組",
                      phones: ["02-2905-3125", "02-2905-3169", "02-2905-2929"],
                      fax: nil, email: nil),
    DepartmentContact(name: "特殊教育學生資源中心",
                      phones: ["02-2905-3128", "02-2905-3115", "02-2905-3148"],
                      fax: nil, email: nil),
    DepartmentContact(name: "宿舍服務中心",
                      phones: ["02-2905-5266", "02-2905-5268", "02-2905-5271"],
                      fax: nil, email: nil),
    DepartmentContact(name: "原住民族學生資源中心",
                      phones: ["02-2905-3993", "02-2905-2029", "02-2905-2168"],
                      fax: nil, email: nil),
    DepartmentContact(name: "外語教學與數位學習資源中心",
                      phones: ["02-2905-3310 (語言自學室)", "02-2905-2593 (eSchool)", "02-2905-3279 (TronClass)"],
                      fax: nil, email: nil),
    DepartmentContact(name: "游泳池",
                      phones: ["02-2905-2267"],
                      fax: nil, email: nil),
    DepartmentContact(name: "體適能中心",
                      phones: ["02-2905-3035"],
                      fax: nil, email: nil),
]
