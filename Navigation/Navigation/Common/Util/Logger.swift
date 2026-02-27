import Foundation

func date() -> String {
    let date = Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSSS"

    return formatter.string(from: date)
}

func log(_ message: String,
         filePath: String = #file,
         funcName: String = #function,
         lineNumber: Int = #line,
         columnNumber: Int = #column) {
    #if DEBUG
    let fileName = (filePath as NSString).lastPathComponent.split(separator: ".")[0]
    print("[\(date())][\(fileName)-\(funcName):\(lineNumber)] - \(message)")
    #endif
}
