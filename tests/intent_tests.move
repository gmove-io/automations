#[test_only]
module automations::intent_tests {
    use std::string::utf8;
    
    use sui::test_utils::{assert_eq, destroy};

    use automations::intent;

    const ALICE: address = @0x11ce;
    
    public struct Witness has drop {}

    public struct Config has store {
        value: u64
    }

    #[test]
    public fun end_to_end() {
        let name = utf8(b"Overflow is fun");
        let execution = 0;
        let expiration = 2;
        let requested = vector[@0x2, @0x3];
        let required = vector[@0x02];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            ALICE,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            &mut tx_context::dummy()
        );

        assert_eq(payload.name(), name);
        assert_eq(payload.owner(), ALICE);
        assert_eq(payload.expiration(), expiration);
        assert_eq(payload.requested(), requested);
        assert_eq(payload.required(), required);

        let config = payload.destroy();
        assert_eq(config.value, config_value);

        destroy(config);
    }

    #[test]
    #[expected_failure(abort_code = intent::EDeadlineIsInThePast)]
    public fun test_new_error_deadline_is_in_the_past() {
        let name = utf8(b"Overflow is fun");
        let execution = 0;
        let expiration = 1;
        let requested = vector[@0x2, @0x3];
        let required = vector[@0x02];
        let config_value = 7;
        let mut ctx = tx_context::dummy();

        ctx.increment_epoch_number();
        ctx.increment_epoch_number();

        let payload = intent::new(
            Witness {},
            name,
            ALICE,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            &mut ctx
        );

        destroy(payload);
    }    
}