#[test_only]
module automations::automation_tests {
    use std::string::utf8;
    
    use sui::clock;
    use sui::test_scenario as ts;
    use sui::test_utils::{assert_eq, destroy};

    use automations::intent;
    use automations::automation::{Self, Automation};

    const OWNER: address = @0x11ce;
    
    public struct Witness has drop {}

    public struct Config has store {
        value: u64
    }

    public struct Object has key, store {
        id: UID
    }

    #[test]
    fun test_happy_path() {
        let mut scenario = ts::begin(OWNER);
        let clock = clock::create_for_testing(scenario.ctx()); 
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();
        let obj2_id = obj2.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id, obj2_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);
        automation_initializing.deposit(obj2);

        automation_initializing.share();

        scenario.next_tx(OWNER);

        let mut automation = ts::take_shared<Automation<Witness>>(&scenario);

        assert_eq(automation.name(), name);
        assert_eq(automation.expiration(), expiration);
        assert_eq(automation.requested(), requested);
        assert_eq(automation.deposited(), requested);
        assert_eq(automation.required(), required);
        assert_eq(automation.config_mut<Witness, Config>(Witness {}).value, config_value);

        let mut automation_executing = automation.start(Witness {}, &clock, scenario.ctx());

        let obj1 = automation_executing.take<Witness, Object>(obj1_id);

        assert_eq(obj1.id.uid_to_address(), obj1_id);
        assert_eq(automation_executing.inner().deposited(), vector[obj2_id]);

        let obj2 = automation_executing.take<Witness, Object>(obj2_id);

        assert_eq(obj2.id.uid_to_address(), obj2_id);
        assert_eq(automation_executing.inner().required(), vector[obj1_id]);

        automation_executing.put(obj1);

        assert_eq(automation_executing.inner().required(), vector[]);

        automation_executing.end();

        destroy(obj2);

        scenario.next_tx(OWNER);

        let obj1 = ts::take_from_sender<Object>(&scenario);

        assert_eq(obj1.id.uid_to_address(), obj1_id);

        destroy(clock);
        destroy(obj1);
        scenario.end();
    }

    #[test]
    fun test_unhappy_path() {
        let mut scenario = ts::begin(OWNER);
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();
        let obj2_id = obj2.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id, obj2_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);
        automation_initializing.deposit(obj2);

        automation_initializing.share();

        scenario.next_tx(OWNER);
        scenario.next_epoch(OWNER);
        scenario.next_epoch(OWNER);
        scenario.next_epoch(OWNER);

        let mut automation = ts::take_shared<Automation<Witness>>(&scenario);

        assert_eq(automation.requested(), requested);

        automation.give_back<Witness, Object>(obj1_id, scenario.ctx());
        assert_eq(automation.requested(), vector[obj2_id]);

        automation.give_back<Witness, Object>(obj2_id, scenario.ctx());
        assert_eq(automation.requested(), vector[]);

        automation.destroy(scenario.ctx());

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = automation::ENotARequestedObject)]
    fun test_deposit_error_not_required_object() {
        let mut scenario = ts::begin(OWNER);
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);
        automation_initializing.deposit(obj2);


        destroy(automation_initializing);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = automation::EMissingRequestedObjects)]
    fun test_deposit_error_missing_requested_objects() {
        let mut scenario = ts::begin(OWNER);
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();
        let obj2_id = obj2.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id, obj2_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);

        automation_initializing.share();

        destroy(obj2);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = automation::EHasExpired)]    
    fun test_start_error_has_expired() {
        let mut scenario = ts::begin(OWNER);
        let clock = clock::create_for_testing(scenario.ctx());
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();
        let obj2_id = obj2.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id, obj2_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);
        automation_initializing.deposit(obj2);

        automation_initializing.share();

        scenario.next_tx(OWNER);
        scenario.next_epoch(OWNER);
        scenario.next_epoch(OWNER);
        scenario.next_epoch(OWNER);

        let automation = ts::take_shared<Automation<Witness>>(&scenario);

        let executing_automation = automation.start(Witness {}, &clock, scenario.ctx());

        destroy(clock);
        destroy(executing_automation);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = automation::ENotExecutable)]    
    fun test_start_error_not_executable() {
        let mut scenario = ts::begin(OWNER);
        let mut clock = clock::create_for_testing(scenario.ctx());
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();
        let obj2_id = obj2.id.uid_to_address();

        let execution = 2;
        let expiration = 2;
        let requested = vector[obj1_id, obj2_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);
        automation_initializing.deposit(obj2);

        automation_initializing.share();

        scenario.next_tx(OWNER);
        
        clock.set_for_testing(1);

        let automation = ts::take_shared<Automation<Witness>>(&scenario);

        let executing_automation = automation.start(Witness {}, &clock, scenario.ctx());

        destroy(clock);
        destroy(executing_automation);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = automation::ENotARequestedObject)]    
    fun test_take_error_not_a_requested_object() {
        let mut scenario = ts::begin(OWNER);
        let clock = clock::create_for_testing(scenario.ctx()); 
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();
        let obj2_id = obj2.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);
        destroy(obj2);

        automation_initializing.share();

        scenario.next_tx(OWNER);

        let automation = ts::take_shared<Automation<Witness>>(&scenario);

        let mut automation_executing = automation.start(Witness {}, &clock, scenario.ctx());

        let obj1 = automation_executing.take<Witness, Object>(obj1_id);
        let obj2 = automation_executing.take<Witness, Object>(obj2_id);

        destroy(automation_executing);
        destroy(obj2);
        destroy(clock);
        destroy(obj1);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = automation::ENotAnObjectToReturn)]    
    fun test_put_error_not_an_object_to_return() {
        let mut scenario = ts::begin(OWNER);
        let clock = clock::create_for_testing(scenario.ctx()); 
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();
        let obj2_id = obj2.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id, obj2_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);
        automation_initializing.deposit(obj2);

        automation_initializing.share();

        scenario.next_tx(OWNER);

        let automation = ts::take_shared<Automation<Witness>>(&scenario);

        let mut automation_executing = automation.start(Witness {}, &clock, scenario.ctx());

        let obj1 = automation_executing.take<Witness, Object>(obj1_id);
        let obj2 = automation_executing.take<Witness, Object>(obj2_id);

        automation_executing.put(obj1);
        automation_executing.put(obj2);

        automation_executing.end();

        destroy(clock);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = automation::EObjectsNotReturned)]    
    fun test_put_error_objects_not_returned() {
        let mut scenario = ts::begin(OWNER);
        let clock = clock::create_for_testing(scenario.ctx()); 
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();
        let obj2_id = obj2.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id, obj2_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);
        automation_initializing.deposit(obj2);

        automation_initializing.share();

        scenario.next_tx(OWNER);

        let automation = ts::take_shared<Automation<Witness>>(&scenario);

        let automation_executing = automation.start(Witness {}, &clock, scenario.ctx());

        automation_executing.end();

        destroy(clock);
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = automation::ENotARequestedObject)]  
    fun test_give_back_error_not_a_requested_object() {
        let mut scenario = ts::begin(OWNER);
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();
        let obj2_id = obj2.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);

        automation_initializing.share();
        destroy(obj2);

        scenario.next_tx(OWNER);
        scenario.next_epoch(OWNER);
        scenario.next_epoch(OWNER);
        scenario.next_epoch(OWNER);

        let mut automation = ts::take_shared<Automation<Witness>>(&scenario);

        automation.give_back<Witness, Object>(obj1_id, scenario.ctx());
        automation.give_back<Witness, Object>(obj2_id, scenario.ctx());

        automation.destroy(scenario.ctx());
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = automation::EHasNotExpired)]  
    fun test_give_back_error_has_not_expired() {
        let mut scenario = ts::begin(OWNER);
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);

        automation_initializing.share();
        destroy(obj2);

        scenario.next_tx(OWNER);

        let mut automation = ts::take_shared<Automation<Witness>>(&scenario);

        automation.give_back<Witness, Object>(obj1_id, scenario.ctx());

        destroy(automation);
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = automation::EHasNotExpired)]  
    fun test_destroy_error_has_not_expired() {
        let mut scenario = ts::begin(OWNER);
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);

        automation_initializing.share();
        destroy(obj2);

        scenario.next_tx(OWNER);

        let automation = ts::take_shared<Automation<Witness>>(&scenario);

        automation.destroy(scenario.ctx());
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = automation::EMissingRequestedObjects)]  
    fun test_destroy_error_missing_requested_objects() {
        let mut scenario = ts::begin(OWNER);
        let name = utf8(b"Overflow is fun");

        let obj1 = new_object(scenario.ctx());
        let obj2 = new_object(scenario.ctx());

        let obj1_id = obj1.id.uid_to_address();

        let execution = 0;
        let expiration = 2;
        let requested = vector[obj1_id];
        let required = vector[obj1_id];
        let config_value = 7;

        let payload = intent::new(
            Witness {},
            name,
            OWNER,
            execution,
            expiration,
            requested,
            required,
            Config { value: config_value },
            scenario.ctx()           
        );

        let mut automation_initializing = automation::new(payload, scenario.ctx());

        automation_initializing.deposit(obj1);

        automation_initializing.share();
        destroy(obj2);

        scenario.next_tx(OWNER);
        scenario.next_epoch(OWNER);
        scenario.next_epoch(OWNER);
        scenario.next_epoch(OWNER);

        let automation = ts::take_shared<Automation<Witness>>(&scenario);

        automation.destroy(scenario.ctx());
        
        scenario.end();
    }

    fun new_object(ctx: &mut TxContext): Object {
        Object {
            id: object::new(ctx)
        }
    }
}