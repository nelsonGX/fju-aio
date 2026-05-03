import Foundation

enum RegulationOffice: String, CaseIterable, Identifiable {
    case academicAffairs = "教務處"
    case teacherEducation = "師資培育中心"
    case internationalEducation = "國際及兩岸教育處"
    case studentAffairs = "學務處"
    case physicalEducation = "體育室"
    case dormitory = "宿舍服務中心"
    case militaryTraining = "軍訓室"
    case generalAffairs = "總務處"
    case library = "圖書館"
    case informationCenter = "資訊中心"
    case otherUnits = "校內各單位"

    var id: String { rawValue }
}

struct Regulation: Identifiable, Hashable {
    let id: String
    let title: String
    let office: RegulationOffice
    let urlString: String?
    let keywords: [String]

    var url: URL? {
        guard let urlString, urlString.hasPrefix("http") else { return nil }
        if let url = URL(string: urlString) {
            return url
        }

        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: encoded)
    }

    var searchableText: String {
        ([title, office.rawValue, urlString ?? ""] + keywords).joined(separator: " ")
    }
}

enum RegulationIndex {
    static let all: [Regulation] = [
        regulation("academic-school-rules", "輔仁大學學則", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/輔仁大學學則.pdf", ["學籍", "學則"]),
        regulation("academic-dual-degree", "輔仁大學與境外大學校院合作辦理雙聯學制實施辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/fjudss.pdf", ["雙聯", "境外"]),
        regulation("academic-return-credit", "輔仁大學學生返校補修學分實施辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生返校補修學分實施辦法.pdf", ["補修", "學分"]),
        regulation("academic-double-major", "輔仁大學學生修讀雙主修辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生修讀雙主修辦法.pdf", ["雙主修"]),
        regulation("academic-double-major-rules", "輔仁大學學生修讀雙主修施行細則", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生修讀雙主修施行細則.pdf", ["雙主修"]),
        regulation("academic-minor", "輔仁大學學生修讀輔系辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生修讀輔系辦法.pdf", ["輔系"]),
        regulation("academic-minor-rules", "輔仁大學學生修讀輔系施行細則", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生修讀輔系施行細則.pdf", ["輔系"]),
        regulation("academic-transfer-department", "輔仁大學學生轉系辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生轉系辦法.pdf", ["轉系"]),
        regulation("academic-direct-phd", "輔仁大學學生逕修讀博士學位辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生逕修讀博士學位辦法.pdf", ["博士"]),
        regulation("academic-grade-correction", "輔仁大學更正學生學期成績辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/更正學生學期成績辦法.pdf", ["成績", "更正"]),
        regulation("academic-grading-credit", "輔仁大學學生成績考評及學分核計辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生成績考評及學分核計辦法.pdf", ["成績", "學分"]),
        regulation("academic-credit-waiver", "輔仁大學學生抵免科目規則", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生抵免科目規則.pdf", ["抵免"]),
        regulation("academic-programs", "輔仁大學學程設置辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學程設置辦法.pdf", ["學程"]),
        regulation("academic-credit-program", "輔仁大學學生修讀學分學程施行細則", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生修讀學分學程施行細則.pdf", ["學分學程"]),
        regulation("academic-graduate-aid", "輔仁大學研究生獎助學金發給辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/研究生獎助學金發給辦法.pdf", ["研究生", "獎助學金"]),
        regulation("academic-thesis-format", "輔仁大學學位論文印製格式統一規定", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學位論文印製格式統一規定.pdf", ["論文"]),
        regulation("academic-abroad-status", "輔仁大學學生出境期間學業及學籍處理要點", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/102102901.pdf", ["出境", "學籍"]),
        regulation("academic-dual-enrollment", "輔仁大學學生雙重學籍申請辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生雙重學籍申請辦法.pdf", ["雙重學籍"]),
        regulation("academic-domestic-exchange", "輔仁大學國內交換學生甄選作業要點", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/國內交換學生甄選作業要點.pdf", ["交換"]),
        regulation("academic-intercollegiate-double-major", "輔仁大學校際雙主修修讀辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/校際雙主修修讀辦法.pdf", ["校際", "雙主修"]),
        regulation("academic-intercollegiate-minor", "輔仁大學校際輔系修讀辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/校際輔系修讀辦法.pdf", ["校際", "輔系"]),
        regulation("academic-post-bachelor", "輔仁大學學士後多元專長培力課程實施要點", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/多元專長培力課程.pdf", ["學士後", "多元專長"]),
        regulation("academic-plagiarism", "輔仁大學學位授予涉及抄襲舞弊處理辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學位授予涉及抄襲舞弊處理辦法.pdf", ["抄襲", "舞弊"]),
        regulation("academic-course-selection", "輔仁大學學生選課辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生選課辦法.pdf", ["選課"]),
        regulation("academic-cross-program-course", "輔仁大學學生跨學制選課辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學生跨學制選課辦法.pdf", ["選課", "跨學制"]),
        regulation("academic-accessible-exam", "輔仁大學身心障礙學生調整考試形式服務申請辦法", .academicAffairs, "https://docsacademic.fju.edu.tw/edulaw/身心障礙學生調整考試形式服務申請辦法.pdf", ["身心障礙", "考試"]),
        regulation("academic-exam-rules", "輔仁大學考試規則", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/考試規則.pdf", ["考試"]),
        regulation("academic-exam-leave", "輔仁大學學生考試請假規則", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/輔仁大學學生考試請假規則.pdf", ["考試", "請假"]),
        regulation("academic-degree-exam", "輔仁大學博士班、碩士班研究生學位考試辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/輔仁大學學位考試辦法.pdf", ["學位考試", "研究生"]),
        regulation("academic-phd-candidate", "輔仁大學博士學位候選人資格考核實施要點", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/博士學位候選人資格考核實施要點.pdf", ["博士", "資格考"]),
        regulation("academic-summer-course", "輔仁大學暑期班開班授課辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/暑期班開班授課辦法.pdf", ["暑期班"]),
        regulation("academic-intercollegiate-course", "輔仁大學校際選課實施辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/panselcoureg.pdf", ["校際選課"]),
        regulation("academic-flex-course", "輔仁大學彈性課程開班授課辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/輔仁大學彈性課程開班授課辦法.pdf", ["彈性課程"]),
        regulation("academic-ethics-course", "輔仁大學學術倫理教育課程實施要點", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/學術倫理教育課程實施要點.pdf", ["學術倫理"]),
        regulation("academic-teaching-assistant", "輔仁大學教學助理設置辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/tasetreg.pdf", ["教學助理"]),
        regulation("academic-mainland-graduate-award", "輔仁大學大陸研究生獎勵辦法", .academicAffairs, "http://docs.academic.fju.edu.tw/edulaw/輔仁大學大陸研究生獎勵辦法.pdf", ["大陸", "研究生"]),
        regulation("academic-language-self-study", "語言自學室管理辦法", .academicAffairs, "http://www.flrc.fju.edu.tw/?page=regulations&category=54&item=2", ["語言自學室"]),
        regulation("academic-media-classroom", "多功能影音資源展示教室管理要點", .academicAffairs, "http://www.flrc.fju.edu.tw/?page=regulations&category=53&item=5", ["影音", "教室"]),
        regulation("academic-eschool", "創新跨領域學院eSchool場地使用管理要點", .academicAffairs, "http://www.flrc.fju.edu.tw/?page=regulations&category=77", ["eSchool", "場地"]),

        regulation("teacher-education-program", "輔仁大學學生修習教育學程辦法", .teacherEducation, "http://www.cte.fju.edu.tw/xmdoc/cont?xsmsid=0J198592031662312282", ["教育學程"]),

        regulation("international-study-agreement", "輔仁大學學生肄業期間至境外合作協議學校進修實施辦法", .internationalEducation, "http://isc.oie.fju.edu.tw/DownloadSubLabelFileServlet?menuID=4&labelID=26&subLabelID=573&fileID=1", ["境外", "交換"]),
        regulation("international-selection", "輔仁大學學生赴境外合作協議學校甄選作業要點", .internationalEducation, "http://isc.oie.fju.edu.tw/DownloadSubLabelFileServlet?menuID=4&labelID=26&subLabelID=572&fileID=1", ["境外", "甄選"]),
        regulation("international-overseas-course", "輔仁大學學生赴境外大學校院選修課程作業要點", .internationalEducation, "http://isc.oie.fju.edu.tw/DownloadSubLabelFileServlet?menuID=4&labelID=26&subLabelID=576&fileID=3", ["境外", "選修"]),

        regulation("student-rewards", "輔仁大學學生獎懲辦法", .studentAffairs, "https://life.fju.edu.tw/rewards_leave/rule/rewards_rule01.pdf", ["獎懲"]),
        regulation("student-rewards-process", "學生獎懲案件作業改進要點", .studentAffairs, "https://life.fju.edu.tw/rewards_leave/rule/rewards_rule02.pdf", ["獎懲"]),
        regulation("student-rewards-committee", "輔仁大學學生獎懲委員會設置辦法", .studentAffairs, "https://life.fju.edu.tw/rewards_leave/rule/rewards_rule03.pdf", ["獎懲委員會"]),
        regulation("student-penalty-removal", "輔仁大學學生違規銷過實施要點", .studentAffairs, "https://life.fju.edu.tw/rewards_leave/rule/rewards_rule05.pdf", ["銷過"]),
        regulation("student-conduct-grade", "輔仁大學學生操行成績考核辦法", .studentAffairs, "http://life.dsa.fju.edu.tw/rule-rule/學生操行成績考核辦法.pdf", ["操行"]),
        regulation("student-gender-equity-law", "性別平等教育法", .studentAffairs, "https://law.moj.gov.tw/LawClass/LawAll.aspx?PCode=H0080067", ["性平"]),
        regulation("student-sexual-harassment", "輔仁大學性侵害性騷擾或性霸凌防治辦法", .studentAffairs, "http://gender.fju.edu.tw/upload/download/1538988075f1np5n0p1.pdf", ["性平", "性騷擾", "性霸凌"]),
        regulation("student-bullying", "校園霸凌防制準則", .studentAffairs, "https://life.fju.edu.tw/bully/rule/bully_rule01.pdf", ["霸凌"]),
        regulation("student-appeal", "輔仁大學學生申訴處理辦法", .studentAffairs, "https://life.fju.edu.tw/suggestion/rule/appeal_rule01.pdf", ["申訴"]),
        regulation("student-suggestion", "輔仁大學愛校建言實施辦法", .studentAffairs, "https://life.fju.edu.tw/suggestion/rule/suggestion_rule01.pdf", ["建言"]),
        regulation("student-fee-reduction", "日間部同學申辦就學費用減免注意事項", .studentAffairs, "https://life.fju.edu.tw/fee/rule/fee_rule01.pdf", ["減免"]),
        regulation("student-leave", "輔仁大學學生請假規則", .studentAffairs, "https://life.fju.edu.tw/rewards_leave/rule/leave_rule01.pdf", ["請假"]),
        regulation("student-loan", "學生就學貸款申請須知", .studentAffairs, "https://life.fju.edu.tw/loan/rule/loan_rule01.pdf", ["就學貸款"]),
        regulation("student-military-deferment", "在校學生申辦緩徵、儘後召集注意事項", .studentAffairs, "https://life.fju.edu.tw/army/rule/army_rule01.pdf", ["兵役", "緩徵"]),
        regulation("student-military-travel", "役男出境相關資訊", .studentAffairs, "https://life.fju.edu.tw/army/rule/army_rule02.pdf", ["役男", "出境"]),
        regulation("student-book-award", "輔仁大學「輔仁書卷獎」獎學金頒發辦法", .studentAffairs, "https://life.fju.edu.tw/scholarship/rule/scholarship_rule01.pdf", ["獎學金"]),
        regulation("student-master-scholarship", "輔仁大學鼓勵學士班成績優異學生就讀碩士班獎學金辦法", .studentAffairs, "https://life.fju.edu.tw/scholarship/rule/scholarship_rule02.pdf", ["獎學金"]),
        regulation("student-disadvantage-plan", "教育部大專校院弱勢學生助學計畫", .studentAffairs, "https://life.fju.edu.tw/disadvantage/rule/disadvantage_rule01.pdf", ["弱勢", "助學"]),
        regulation("student-low-income-aid", "輔仁大學清寒學生助學金實施辦法", .studentAffairs, "https://life.fju.edu.tw/scholarship/rule/scholarship_rule03.pdf", ["清寒", "助學金"]),
        regulation("student-living-aid", "輔仁大學生活助學金實施辦法", .studentAffairs, "https://life.fju.edu.tw/disadvantage/rule/disadvantage_rule02.pdf", ["生活助學金"]),
        regulation("student-emergency-aid", "輔仁大學學生急難救助金實施要點", .studentAffairs, "https://life.fju.edu.tw/help/rule/help_rule01.pdf", ["急難救助"]),
        regulation("student-ministry-emergency-aid", "教育部學產基金設置急難慰問金實施要點", .studentAffairs, "https://life.fju.edu.tw/help/rule/help_rule02.pdf", ["急難"]),
        regulation("student-group-insurance", "學生團體保險", .studentAffairs, "http://life.dsa.fju.edu.tw/resource.jsp?labelID=33", ["團保", "保險"]),
        regulation("student-self-governance", "學生自治通則", .studentAffairs, "https://activity.fju.edu.tw/DownloadSubLabelFileServlet?menuID=5&labelID=4&subLabelID=807&fileID=17", ["自治"]),
        regulation("student-club-guidance", "學生社團輔導辦法", .studentAffairs, "https://activity.fju.edu.tw/DownloadSubLabelFileServlet?menuID=5&labelID=4&subLabelID=807&fileID=19", ["社團"]),
        regulation("student-meeting-representative", "學生代表參加校內各級會議實施辦法", .studentAffairs, "http://active.dsa.fju.edu.tw/download/法規下載/綜合類/輔仁大學學生代表參加校內各級會議實施辦法.pdf", ["學生代表"]),
        regulation("student-club-committee", "學生社團事務委員會設置辦法", .studentAffairs, "https://activity.fju.edu.tw/DownloadSubLabelFileServlet?menuID=5&labelID=4&subLabelID=807&fileID=15", ["社團"]),
        regulation("student-activity-center", "學生活動中心場地管理辦法", .studentAffairs, "http://active.dsa.fju.edu.tw/download/法規下載/場地、器材、宣傳類/學生活動中心場地管理辦法.pdf", ["場地"]),
        regulation("student-competition-subsidy", "學生學習成果發表補助暨專業競賽獎勵辦法", .studentAffairs, "https://activity.fju.edu.tw/DownloadSubLabelFileServlet?menuID=5&labelID=4&subLabelID=807&fileID=22", ["競賽", "補助"]),
        regulation("student-autonomy-subsidy", "獎補助學生自治組織推動多元學習經費使用原則", .studentAffairs, "https://reurl.cc/8oA0L7", ["補助", "自治"]),
        regulation("student-emergency-medical", "輔仁大學緊急送醫原則", .studentAffairs, "http://health.dsa.fju.edu.tw/generalServices.jsp?labelID=1", ["送醫"]),
        regulation("student-medical-subsidy", "輔仁大學教職員工生就醫補助實施要點", .studentAffairs, "http://health.dsa.fju.edu.tw/generalServices.jsp?labelID=2", ["就醫補助"]),
        regulation("student-restaurant", "輔仁大學餐廳(超市)管理辦法", .studentAffairs, "http://health.dsa.fju.edu.tw/teachingServices.jsp?labelID=31", ["餐廳", "超市"]),
        regulation("student-health-equipment", "輔仁大學學生事務處健康中心器材借用須知", .studentAffairs, "http://health.dsa.fju.edu.tw/generalServices.jsp?labelID=21", ["健康中心", "器材"]),
        regulation("student-hk-macau", "香港澳門居民來臺就學辦法", .studentAffairs, "https://edu.law.moe.gov.tw/LawContent.aspx?id=FL016605", ["港澳"]),
        regulation("student-overseas-chinese", "僑生回國就學及輔導辦法", .studentAffairs, "https://edu.law.moe.gov.tw/LawContent.aspx?id=FL009263", ["僑生"]),
        regulation("student-overseas-aid", "輔仁大學申請清寒僑生助學金審查作業須知", .studentAffairs, "http://overseas.fju.edu.tw/networkServices.jsp?labelID=2", ["僑生", "助學金"]),
        regulation("student-overseas-scholarship", "輔仁大學研究所優秀僑生獎學金作業須知", .studentAffairs, "http://overseas.fju.edu.tw/networkServices.jsp?labelID=2", ["僑生", "獎學金"]),
        regulation("student-mainland-study", "大陸地區人民來臺就讀專科以上學校辦法", .studentAffairs, "https://law.moj.gov.tw/LawClass/LawAll.aspx?PCode=H0030052", ["陸生"]),
        regulation("student-mainland-entry", "大陸地區人民進入臺灣地區許可辦法", .studentAffairs, "https://law.moj.gov.tw/LawClass/LawAll.aspx?PCode=Q0060002", ["大陸", "入境"]),
        regulation("student-mainland-education", "大陸地區學歷採認辦法", .studentAffairs, "https://law.moj.gov.tw/LawClass/LawAll.aspx?PCode=H0010005", ["學歷採認"]),
        regulation("student-mainland-entry-study", "大陸地區人民進入臺灣地區就學及探親送件須知", .studentAffairs, "https://www.immigration.gov.tw/5382/5385/7244/7250/7257/%E5%81%9C%E7%95%99/75374/", ["陸生", "探親"]),
        regulation("student-mainland-scholarship", "輔仁大學優秀陸生獎學金實施辦法", .studentAffairs, "http://overseas.fju.edu.tw/administration.jsp?labelID=1", ["陸生", "獎學金"]),

        regulation("pe-venue", "輔仁大學運動場館對外開放管理辦法", .physicalEducation, "http://peo.dsa.fju.edu.tw/resource.jsp?labelID=30", ["運動場館"]),
        regulation("pe-football-field", "輔仁大學人工草皮足球場管理要點", .physicalEducation, "http://peo.dsa.fju.edu.tw/resource.jsp?labelID=30", ["足球場"]),
        regulation("pe-fitness-center", "輔仁大學體適能中心管理要點", .physicalEducation, "http://peo.dsa.fju.edu.tw/resource.jsp?labelID=30", ["體適能"]),

        regulation("dorm-rules", "學生宿舍管理辦法", .dormitory, "http://www.dsc.fju.edu.tw/generalServices.jsp?labelID=5", ["宿舍"]),

        regulation("military-course-credit", "全民國防教育軍事訓練課程折減常備兵役役期及軍事訓練期間實施辦法", .militaryTraining, "https://edu.law.moe.gov.tw/LawContent.aspx?id=GL001065", ["全民國防", "兵役"]),
        regulation("military-education-plan", "各級學校推動全民國防教育實施計畫", .militaryTraining, "https://edu.law.moe.gov.tw/LawContent.aspx?id=GL000519", ["全民國防"]),

        regulation("general-refund", "輔仁大學學生休、退學退費辦法", .generalAffairs, "http://www.ga.fju.edu.tw/wordfile/rule/休退學費辦法-new.pdf", ["退費", "休學", "退學"]),
        regulation("general-gown", "畢業生借用學(碩、博)士服辦法", .generalAffairs, "http://www.ga.fju.edu.tw/wordfile/rule/畢業生借用學(碩、博)士服辦法.pdf", ["學士服"]),
        regulation("general-parking", "輔仁大學人員、車輛出入管理辦法", .generalAffairs, "http://www.ga.fju.edu.tw/file/停車管理辦法.pdf", ["停車", "車輛"]),
        regulation("general-motorcycle-bike", "輔仁大學機車及腳踏車管理辦法", .generalAffairs, "http://www.ga.fju.edu.tw/wordfile/rule/輔仁大學機車及腳踏車管理辦法-new.pdf", ["機車", "腳踏車"]),

        regulation("library-borrowing", "輔仁大學圖書館閱覽借書規則", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2022-06/read_0.pdf", ["借書"]),
        regulation("library-media", "輔仁大學圖書館媒體資源服務辦法", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2022-06/multimedia.pdf", ["媒體資源"]),
        regulation("library-entry", "輔仁大學圖書館進館須知", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2024-07/enter.pdf", ["進館"]),
        regulation("library-group-study", "輔仁大學圖書館團體討論室使用要點", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2022-06/group_study_room_0.pdf", ["討論室"]),
        regulation("library-volunteer", "輔仁大學圖書館志工服務實施要點", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2022-06/volunteer.pdf", ["志工"]),
        regulation("library-bookdrop", "輔仁大學圖書館還書箱使用要點", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2022-06/bookdrop.pdf", ["還書箱"]),
        regulation("library-thesis-replacement", "輔仁大學圖書館學位論文抽換作業要點", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2022-06/redissertation.pdf", ["論文"]),
        regulation("library-delay-thesis", "輔仁大學研究生申請學位論文延後公開作業說明", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2023-03/delaydissertation.pdf", ["論文", "延後公開"]),
        regulation("library-acquisition", "輔仁大學圖書館書刊資料介購要點", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2022-06/acquisition.pdf", ["介購"]),
        regulation("library-study-carrel", "輔仁大學圖書館研究小間使用要點", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2022-06/study_carrel_0.pdf", ["研究小間"]),
        regulation("library-fun-learning", "輔仁大學國璽樓五樓「Fun學趣自學中心」使用須知", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2022-06/mlib5f.pdf", ["Fun學趣", "自學中心"]),
        regulation("library-suspended-student", "輔仁大學休學生使用圖書館要點", .library, "https://home.lib.fju.edu.tw/TC/sites/default/files/2023-12/suspension.pdf", ["休學生"]),

        regulation("it-network", "輔仁大學校園網路使用規範", .informationCenter, "http://www.net.fju.edu.tw/file/04078C.pdf", ["校園網路"]),
        regulation("it-security-policy", "輔仁大學資訊安全政策", .informationCenter, "http://www.net.fju.edu.tw/file/IS-A-001.pdf", ["資安"]),
        regulation("it-infringement-sop", "輔仁大學網路侵權問題標準處理流程(SOP)", .informationCenter, "http://www.net.fju.edu.tw/file/04077P.pdf", ["侵權", "SOP"]),
        regulation("it-mail", "輔仁大學學生郵件帳號使用辦法", .informationCenter, "http://www.net.fju.edu.tw/file/04035C.pdf", ["學生信箱", "郵件"]),
        regulation("it-copyright-sop", "輔仁大學學生違反著作權標準處理流程(SOP)", .informationCenter, "http://www.net.fju.edu.tw/file/04079P.pdf", ["著作權", "SOP"]),
        regulation("it-traffic", "輔仁大學網路流量管理辦法", .informationCenter, "http://www.net.fju.edu.tw/file/04073C.pdf", ["網路流量"]),
        regulation("it-ldap", "輔仁大學單一帳號使用管理辦法", .informationCenter, "http://www.net.fju.edu.tw/file/ldap_terms.pdf", ["LDAP", "單一帳號"]),

        regulation("other-unit-search", "校內各單位法規查詢", .otherUnits, "http://www.secretariat.fju.edu.tw/affair.jsp?affairClassID=1", ["秘書室", "法規查詢"])
    ]

    static func filtered(by query: String) -> [Regulation] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return all }

        return all.filter {
            $0.searchableText.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    private static func regulation(
        _ id: String,
        _ title: String,
        _ office: RegulationOffice,
        _ urlString: String?,
        _ keywords: [String] = []
    ) -> Regulation {
        Regulation(id: id, title: title, office: office, urlString: urlString, keywords: keywords)
    }
}
