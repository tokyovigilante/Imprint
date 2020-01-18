import Foundation

extension String {
    /// Truncates the string to length number of characters and
    /// appends optional trailing string if longer
    /*func truncate(length: Int, trailing: String? = nil) -> String {
        if self.characters.count > length {
            return self.substringToIndex(self.startIndex.advancedBy(length)) + (trailing ?? "")
        } else {
            return self
        }
    }

    func stripHtml() -> String {
        return self.stringByReplacingOccurrencesOfString("<[^>]+>", withString: "", options: .RegularExpressionSearch)
    }

    func stripLineBreaks() -> String {
        return self.stringByReplacingOccurrencesOfString("\n", withString: "", options: .RegularExpressionSearch)
    }*/

    /**
     Converts a clock time such as `0:05:01.2` to seconds (`Double`)
     Looks for media overlay clock formats as specified [here][1]
     - Note: this may not be the  most efficient way of doing this. It can be improved later on.
     - Returns: seconds as `Double`
     [1]: http://www.idpf.org/epub/301/spec/epub-mediaoverlays.html#app-clock-examples
    */
    func clockTimeToSeconds() -> Double {

        let val = self.trimmingCharacters(in: .whitespacesAndNewlines)

        if( val.isEmpty ){ return 0 }

        let formats = [
            "HH:mm:ss.SSS"  : "^\\d{1,2}:\\d{2}:\\d{2}\\.\\d{1,3}$",
            "HH:mm:ss"      : "^\\d{1,2}:\\d{2}:\\d{2}$",
            "mm:ss.SSS"     : "^\\d{1,2}:\\d{2}\\.\\d{1,3}$",
            "mm:ss"         : "^\\d{1,2}:\\d{2}$",
            "ss.SSS"         : "^\\d{1,2}\\.\\d{1,3}$",
        ]

        // search for normal duration formats such as `00:05:01.2`
        for (format, pattern) in formats {

            if val.range(of: pattern, options: [.regularExpression]) != nil {

                let formatter = DateFormatter()
                formatter.dateFormat = format
                guard let time = formatter.date(from: val) else {
                    return 0
                }

                formatter.dateFormat = "ss.SSS"
                let seconds = formatter.string(from: time).doubleValue

                formatter.dateFormat = "mm"
                let minutes = formatter.string(from: time).doubleValue

                formatter.dateFormat = "HH"
                let hours = formatter.string(from: time).doubleValue

                return seconds + (minutes * 60) + (hours * 60 * 60)
            }
        }

        // if none of the more common formats match, check for other possible formats
        // 2345ms
        if val.range(of: "^\\d+ms$", options: [.regularExpression]) != nil{
            return val.doubleValue / 1000.0
        }

        // 7.25h
        if val.range(of: "^\\d+(\\.\\d+)?h$", options: [.regularExpression]) != nil {
            return val.doubleValue * 60 * 60
        }

        // 13min
        if val.range(of: "^\\d+(\\.\\d+)?min$", options: [.regularExpression]) != nil {
            return val.doubleValue * 60
        }

        return 0
    }

    func clockTimeToMinutesString() -> String {

        let val = clockTimeToSeconds()

        let min = floor(val / 60)
        let sec = floor(val.truncatingRemainder(dividingBy: 60.0))

        return String(format: "%02.f:%02.f", min, sec)
    }

}
