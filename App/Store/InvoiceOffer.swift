import Foundation
import MidgarCommerce

/// When a shared invoice offers Pay Day Pro, through the shared ``MidgarOfferPolicy``: after the first invoice that
/// leaves the app, then after every third and at least three days apart, three times in all, never to a Pro customer.
enum InvoiceOffer {
    static let policy = MidgarOfferPolicy(appID: PayDayMidgar.appID, firstOfferAfter: 1, laterOfferEvery: 3)
}
