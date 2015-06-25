
import Foundation

class InputHistory {
    
    var candidatesRecord = [Candidate]()
    var history = [String: Int]()
    
    var databaseQueue: FMDatabaseQueue?
    
    var recentCreatedCandidate: (text: String, querycode: String)? {
        set {
            NSUserDefaults.standardUserDefaults().setObject(newValue?.text, forKey: "InputHistory.recentCreatedCandidate.text")
            NSUserDefaults.standardUserDefaults().setObject(newValue?.querycode, forKey: "InputHistory.recentCreatedCandidate.querycode")
        }
        get {
            if let text = NSUserDefaults.standardUserDefaults().objectForKey("InputHistory.recentCreatedCandidate.text") as? String, querycode = NSUserDefaults.standardUserDefaults().objectForKey("InputHistory.recentCreatedCandidate.querycode") as? String {
                return (text: text, querycode: querycode)
            } else {
                return nil
            }
        }
    }
    
    init() {
        let documentsFolder = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0] as! String
        let databasePath = documentsFolder.stringByAppendingPathComponent("history.sqlite")
        println(databasePath)
        
        databaseQueue = FMDatabaseQueue(path: databasePath)
        
        if databaseQueue == nil {
            println("Unable to open database")
            return
        }
        
        databaseQueue?.inDatabase() {
            db in
            if !db.executeUpdate("create table if not exists history(candidate text, shuangpin text, shengmu text, length integer, frequency integer, candidate_type integer, primary key (candidate, shuangpin))", withArgumentsInArray: nil) {
                println("create table failed: \(db.lastErrorMessage())")
            }
            
            if !db.executeUpdate("CREATE INDEX IF NOT EXISTS idx_shengmu on history(shengmu)", withArgumentsInArray: nil) {
                println("create index failed: \(db.lastErrorMessage())")
            }
        }
    }
    
    deinit {
        databaseQueue!.close()
    }
    
    func getFrequencyOf(candidate: Candidate) -> Int {
        return getFrequencyOf(candidateText: candidate.text, queryCode: candidate.queryCode)
    }
    
    func getFrequencyOf(#candidateText: String, queryCode: String) -> Int {
        var frequency: Int? = nil
        var whereStatement = "candidate = ? and shuangpin = ?"
        let queryStatement = "select frequency from history where " + whereStatement + " order by length desc, frequency desc"
        
        databaseQueue?.inDatabase() {
            db in
            if let rs = db.executeQuery(queryStatement, withArgumentsInArray: [candidateText, queryCode]) {
                while rs.next() {
                    frequency = Int(rs.intForColumn("frequency"))
                    break
                }
            } else {
                println("select failed: \(db.lastErrorMessage())")
            }
        }
        return frequency ?? 0
    }
    
    func updateDatabase(#candidatesString: String) {
        let candidatesArray = candidatesString.componentsSeparatedByString("\n")
        for candidateStr in candidatesArray {
            if candidateStr != "" {
                let arr = candidateStr.componentsSeparatedByString("\t")
                updateDatabase(candidateText: arr[0], customCandidateQueryString: arr[1])
            }
        }
    }
    
    func updateDatabase(#candidateText: String, queryString: String, candidateType: String) -> Bool {
        switch candidateType {
        case "1":
            updateDatabase(candidateText: candidateText, shuangpinString: queryString)
            return true
        case "2":
            updateDatabase(candidateText: candidateText, englishString: queryString)
            return true
        case "3":
            updateDatabase(candidateText: candidateText, specialString: queryString)
            return true
        case "4":
            updateDatabase(candidateText: candidateText, customCandidateQueryString: queryString)
            return true
        default:
            return false
        }
    }
    
    func updateDatabase(#candidateText: String, customCandidateQueryString: String) {
        updateDatabase(with: Candidate(text: candidateText, withCustomString: customCandidateQueryString))
    }
    
    func updateDatabase(#candidateText: String, shuangpinString: String) {
        updateDatabase(with: Candidate(text: candidateText, withShuangpinString: shuangpinString))
    }

    func updateDatabase(#candidateText: String, englishString: String) {
        updateDatabase(with: Candidate(text: candidateText, withEnglishString: englishString))
    }
    
    func updateDatabase(#candidateText: String, specialString: String) {
        updateDatabase(with: Candidate(text: candidateText, withSpecialString: specialString))
    }
    
    func updateDatabase(with candidate: Candidate) {
        
        func canInsertIntoInputHistory(candidate: Candidate) -> Bool {
            
            func candidateIsTooSimple(candidate: Candidate) -> Bool {
                if candidate.queryCode.getReadingLength() == 2 && candidate.text == candidate.queryCode || candidate.queryCode.getReadingLength() == 1 {
                    return true
                } else {
                    return false
                }
            }
            
            if candidateIsTooSimple(candidate) {
                return false
            } else {
                return true
            }
        }
        
        if canInsertIntoInputHistory(candidate) == false {
            return
        }
        
        updateDatabase(candidateText: candidate.text, shuangpin: candidate.shuangpinAttributeString, shengmu: candidate.shengmuAttributeString, length: candidate.lengthAttribute as NSNumber, frequency: 1 as NSNumber, candidateType: candidate.typeAttributeString)
    }
    
    func updateDatabase(#candidateText: String, shuangpin: String, shengmu: String, length: NSNumber, frequency: NSNumber, candidateType: String) {
        let previousFrequency = getFrequencyOf(candidateText: candidateText, queryCode: shuangpin)
        
        databaseQueue?.inDatabase() {
            db in
            if previousFrequency == 0 {
                if !db.executeUpdate("insert into history (candidate, shuangpin, shengmu, length, frequency, candidate_type) values (?, ?, ?, ?, ?, ?)", withArgumentsInArray: [candidateText, shuangpin, shengmu, length, frequency, candidateType]) {
                    println("insert 1 table failed: \(db.lastErrorMessage()) \(candidateText) \(shuangpin)")
                }
                self.recentCreatedCandidate = (text: candidateText, querycode: shuangpin)
            } else {
                if !db.executeUpdate("update history set frequency = ? where shuangpin = ? and candidate = ?", withArgumentsInArray: [NSNumber(long: previousFrequency + frequency.longValue), shuangpin, candidateText]) {
                    println("update 1 table failed: \(db.lastErrorMessage()) \(candidateText) \(shuangpin)")
                }
            }
        }
    }
    
    func updateHistoryWith(candidate: Candidate) {
        if candidate.type == .OnlyText {
            return
        }
        updateDatabase(with: candidate)
    }
    
    func deleteRecentCreatedCandidate() {
        databaseQueue?.inDatabase() {
            db in
            if let candidate = self.recentCreatedCandidate {
                if !db.executeUpdate("delete from history where candidate == ? and shuangpin == ?", withArgumentsInArray: [candidate.text, candidate.querycode]) {
                    println("delete 1 table failed: \(db.lastErrorMessage()) \(candidate.text) \(candidate.querycode)")
                }
                self.recentCreatedCandidate = nil
            }
        }
    }
    
    func cleanAllCandidates() {    // Drop table in database.
        databaseQueue?.inDatabase() {
            db in
            if !db.executeUpdate("drop table history", withArgumentsInArray: []) {
                println("drop table history failed: \(db.lastErrorMessage())")
            }
        }
    }
    
    func getCandidatesByQueryArguments(queryArguments: [String], andWhereStatement whereStatement: String, withQueryCode queryCode: String) -> [Candidate] {
        let queryStatement = "select candidate, shuangpin, candidate_type from history where " + whereStatement + " order by length desc, frequency desc"
        println(queryStatement)
        println(queryArguments)
        let candidates = databaseQueue!.getCandidates(byQueryStatement: queryStatement, byQueryArguments: queryArguments, withQueryCode: queryCode, needTruncateCandidates: false)
        
        return candidates
    }
    
}
