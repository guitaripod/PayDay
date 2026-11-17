import AICreditsCore
import Foundation
import MidgarCore

/// The region refusal Midgar's model routes answer with, whichever client the call went through, and the memory of it.
enum ModelRefusal {
    /// Whether a failed model call was the refusal for the device's country: a 451 through `MidgarHTTPClient`, or mako's
    /// `unavailable_in_region` through AICredits.
    static func isRefusal(_ error: any Error) -> Bool {
        MidgarModelRegion.isRefusal(error) || (error as? AICreditsError)?.isUnavailableInRegion == true
    }

    /// Remembers a refused model call, so the features hide, and returns whether the call was one. A refused call is
    /// never charged or counted against an allowance, so the caller must not count it.
    @discardableResult
    static func note(_ error: any Error) -> Bool {
        guard isRefusal(error) else { return false }
        return MidgarModelRegion.shared.note(statusCode: MidgarModelRegion.refusalStatus)
    }
}
