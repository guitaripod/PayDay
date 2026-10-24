import Testing

/// Every suite that talks to the process-wide gateway stub or to StoreKit. They share one stub and one StoreKit, so they
/// run one after the other: a reset in one must never land inside another.
@Suite(.serialized)
enum StoreBacked {}
