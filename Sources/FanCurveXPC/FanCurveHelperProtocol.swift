import Foundation

@objc public protocol FanCurveHelperProtocol {
    func probe(withReply reply: @escaping (Bool, String) -> Void)
    func setTargetRPM(_ rpm: Int, fanIndex: Int, withReply reply: @escaping (NSError?) -> Void)
    func restoreAutomaticControl(withReply reply: @escaping (NSError?) -> Void)
}
