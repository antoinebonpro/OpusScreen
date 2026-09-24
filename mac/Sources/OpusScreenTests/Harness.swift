import Foundation
import ObjectiveC

/// Un harnais de test minuscule, sans dependance.
///
/// XCTest n'est pas livre avec les outils en ligne de commande d'Apple : il
/// faudrait Xcode. Or cette application se construit et se verifie avec les
/// seuls outils du systeme - c'etait deja le parti pris de la version Windows,
/// dont les suites etaient compilees directement par le compilateur livre avec
/// le .NET Framework.
///
/// Les noms sont ceux de XCTest, a dessein : le jour ou Xcode est installe, les
/// memes fichiers de test se compilent tels quels contre le vrai cadre, sans
/// qu'une seule ligne change.
///
/// La decouverte des tests passe par le moteur Objective-C, comme le fait
/// XCTest : toute methode dont le nom commence par `test` est executee. C'est ce
/// qui garantit qu'aucun test ne peut etre oublie par distraction dans une liste
/// tenue a la main.
open class XCTestCase: NSObject {
    /// `required` parce que le lanceur cree les instances depuis un metatype.
    public required override init() { super.init() }

    open func setUp() {}
    open func tearDown() {}
}

/// Ce que le harnais a constate.
public enum TestReport {
    public private(set) static var failures: [String] = []
    public private(set) static var assertions = 0
    nonisolated(unsafe) static var currentTest = ""

    static func pass() { assertions += 1 }

    static func fail(_ message: String, _ file: StaticString, _ line: UInt) {
        assertions += 1
        let name = (String(describing: file) as NSString).lastPathComponent
        failures.append("  ✗ \(currentTest)\n      \(message)\n      \(name):\(line)")
    }

    static func reset() {
        failures.removeAll()
        assertions = 0
    }
}

// ------------------------------------------------------------------ assertions

public func XCTFail(_ message: String = "",
                    file: StaticString = #filePath, line: UInt = #line) {
    TestReport.fail(message.isEmpty ? "echec demande" : message, file, line)
}

public func XCTAssertTrue(_ value: @autoclosure () -> Bool, _ message: String = "",
                          file: StaticString = #filePath, line: UInt = #line) {
    if value() { TestReport.pass() }
    else { TestReport.fail(message.isEmpty ? "attendu vrai, obtenu faux" : message, file, line) }
}

public func XCTAssertFalse(_ value: @autoclosure () -> Bool, _ message: String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
    if !value() { TestReport.pass() }
    else { TestReport.fail(message.isEmpty ? "attendu faux, obtenu vrai" : message, file, line) }
}

public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
                                         _ message: String = "",
                                         file: StaticString = #filePath, line: UInt = #line) {
    let (x, y) = (a(), b())
    if x == y { TestReport.pass() }
    else { TestReport.fail(message.isEmpty ? "\(x) != \(y)" : "\(message)  (\(x) != \(y))", file, line) }
}

public func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
                                            _ message: String = "",
                                            file: StaticString = #filePath, line: UInt = #line) {
    let (x, y) = (a(), b())
    if x != y { TestReport.pass() }
    else { TestReport.fail(message.isEmpty ? "les deux valent \(x)" : message, file, line) }
}

public func XCTAssertEqual<T: FloatingPoint>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
                                             accuracy: T, _ message: String = "",
                                             file: StaticString = #filePath, line: UInt = #line) {
    let (x, y) = (a(), b())
    if x.isNaN || y.isNaN {
        TestReport.fail(message.isEmpty ? "valeur non numerique" : message, file, line)
        return
    }
    if abs(x - y) <= accuracy { TestReport.pass() }
    else {
        let detail = "\(x) et \(y) different de plus de \(accuracy)"
        TestReport.fail(message.isEmpty ? detail : "\(message)  (\(detail))", file, line)
    }
}

/// Comparer deux entiers a une tolerance pres : les tables de couleurs se
/// comparent en entiers 16 bits, et l'arrondi y est une difference legitime.
public func XCTAssertEqual(_ a: @autoclosure () -> Int, _ b: @autoclosure () -> Int,
                           accuracy: Int, _ message: String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
    let (x, y) = (a(), b())
    if abs(x - y) <= accuracy { TestReport.pass() }
    else {
        let detail = "\(x) et \(y) different de plus de \(accuracy)"
        TestReport.fail(message.isEmpty ? detail : "\(message)  (\(detail))", file, line)
    }
}

public func XCTAssertEqual(_ a: @autoclosure () -> UInt16, _ b: @autoclosure () -> UInt16,
                           accuracy: Int, _ message: String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(Int(a()), Int(b()), accuracy: accuracy, message, file: file, line: line)
}

public func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
                                                _ message: String = "",
                                                file: StaticString = #filePath, line: UInt = #line) {
    let (x, y) = (a(), b())
    if x > y { TestReport.pass() }
    else { TestReport.fail(message.isEmpty ? "\(x) n'est pas > \(y)" : "\(message)  (\(x) <= \(y))", file, line) }
}

public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
                                                       _ message: String = "",
                                                       file: StaticString = #filePath, line: UInt = #line) {
    let (x, y) = (a(), b())
    if x >= y { TestReport.pass() }
    else { TestReport.fail(message.isEmpty ? "\(x) n'est pas >= \(y)" : "\(message)  (\(x) < \(y))", file, line) }
}

public func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
                                             _ message: String = "",
                                             file: StaticString = #filePath, line: UInt = #line) {
    let (x, y) = (a(), b())
    if x < y { TestReport.pass() }
    else { TestReport.fail(message.isEmpty ? "\(x) n'est pas < \(y)" : "\(message)  (\(x) >= \(y))", file, line) }
}

public func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
                                                    _ message: String = "",
                                                    file: StaticString = #filePath, line: UInt = #line) {
    let (x, y) = (a(), b())
    if x <= y { TestReport.pass() }
    else { TestReport.fail(message.isEmpty ? "\(x) n'est pas <= \(y)" : "\(message)  (\(x) > \(y))", file, line) }
}

public func XCTAssertNil<T>(_ value: @autoclosure () -> T?, _ message: String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
    if let v = value() { TestReport.fail(message.isEmpty ? "attendu nil, obtenu \(v)" : message, file, line) }
    else { TestReport.pass() }
}

public func XCTAssertNotNil<T>(_ value: @autoclosure () -> T?, _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
    if value() != nil { TestReport.pass() }
    else { TestReport.fail(message.isEmpty ? "attendu une valeur, obtenu nil" : message, file, line) }
}

// ------------------------------------------------------------------ execution

public enum TestRunner {

    /// Execute toutes les methodes `test...` d'une suite, decouvertes par le
    /// moteur Objective-C. Rend le nombre de tests executes.
    @discardableResult
    public static func run(_ type: XCTestCase.Type) -> Int {
        let name = String(describing: type)
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(type, &count) else {
            print("  ! \(name) : aucune methode trouvee")
            return 0
        }
        defer { free(methods) }

        var selectors: [Selector] = []
        for i in 0..<Int(count) {
            let selector = method_getName(methods[i])
            if NSStringFromSelector(selector).hasPrefix("test") { selectors.append(selector) }
        }

        // Ordre stable : un test qui echoue doit se retrouver au meme endroit
        // d'une execution a l'autre.
        selectors.sort { NSStringFromSelector($0) < NSStringFromSelector($1) }

        let before = TestReport.failures.count
        for selector in selectors {
            let instance = type.init()
            TestReport.currentTest = "\(name).\(NSStringFromSelector(selector))"
            instance.setUp()
            instance.perform(selector)
            instance.tearDown()
        }

        let failed = TestReport.failures.count - before
        let mark = failed == 0 ? "✓" : "✗"
        print("  \(mark) \(name.padding(toLength: 16, withPad: " ", startingAt: 0))"
            + " \(selectors.count) tests"
            + (failed == 0 ? "" : ", \(failed) echec(s)"))
        return selectors.count
    }
}
