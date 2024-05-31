#[test_only]
module intent::intent_tests {
    use std::string::utf8;
    
    use sui::test_utils::{assert_eq, destroy};

    use intent::intent;
    use intent::intent_payload;

    const ALICE: address = @0x11ce;
    
    public struct Witness has drop {}

    public struct Config has store {
        value: u64
    }
}