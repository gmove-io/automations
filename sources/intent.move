/*
* @title Intent
* @description It is a Transfer To Object based intent to manage assets and capabilities. It is designed to power DAOs and Multisigs.
* @dev

Flow

1 - Create IntentPayload
2 - Store in the Proposal

--- To execute a proposal ---

3 - Create the Intent with the IntentPayload
4 - Deposit all required objects
5 - Share Intent

--- Happy Path someone executes ---

6 - Call start
7 - Take objects
8 - Return objects (if required)
9 - Call end

--- Unhappy Path, the deadline has passed without it being executed ---

6 - Call give_back to return objects from the intent to owner
7 - destroy the intent

*
*/
module intent::intent {
    // === Imports ===

    use std::string::String;

    use sui::transfer::Receiving;
    use sui::dynamic_field as df;

    use intent::intent_payload::IntentPayload;

    // === Errors ===

    const ECallStartFirst: u64 = 0;
    const EHasExpired: u64 = 1;
    const EIsAlreadyInitiated: u64 = 2;
    const ENotARequiredObject: u64 = 3;
    const EMissingRequiredObjects: u64 = 4;
    const EInvalidLock: u64 = 5;
    const EMissingRequestedObjects: u64 = 6;
    const EHasNotExpired: u64 = 7;
    const EHasBeenInitiated: u64 = 8;
    const ECannotBeShared: u64 = 9;

    // === Constants ===

    // === Structs ===

    public struct ConfigKey has copy, store, drop {}

    public struct Intent<phantom Executor: drop> has key {
        id: UID,
        storage: UID,
        owner: address,
        name: String,
        deadline: u64,        
        initiated: bool,
        shared: bool,
        requested: vector<address>,
        deposited: vector<address>,
        returned: vector<address>,
        required: vector<address>,      
    }

    public struct ShareLock {
        intent: address
    }

    public struct Lock {
        intent: address
    }

    // === Method Aliases ===

    // === Public-Mutative Functions ===

    public fun new<Executor: drop, Config: store>(payload: IntentPayload<Executor, Config>, ctx: &mut TxContext): (Intent<Executor>, ShareLock) {
        let (name, owner, deadline, requested, required) = (
            payload.name(),
            payload.owner(),
            payload.deadline(),
            payload.requested(),
            payload.required()
        );

        let mut storage = object::new(ctx);

        df::add(&mut storage, ConfigKey {}, payload.destroy());

        let intent = Intent {
            id: object::new(ctx),
            storage,
            initiated: false,
            shared: false,
            owner,
            name,
            deadline,
            requested,
            deposited: vector[],
            returned: vector[],
            required
        };

        let share_lock = ShareLock { intent: intent.id.uid_to_address() };

        (intent, share_lock)
    }

    public fun share<Executor: drop>(mut self: Intent<Executor>, share_lock: ShareLock) {
        let ShareLock { intent } = share_lock;

        assert!(intent == self.id.uid_to_address(), EInvalidLock);

        assert_vectors_equality(self.requested, self.deposited, EMissingRequestedObjects);

        self.shared = true;

        transfer::share_object(self);
    }

    public fun deposit<Executor: drop, Object: store + key>(self: &mut Intent<Executor>, object: Object) {
        assert!(!self.initiated, EIsAlreadyInitiated);
        assert!(!self.shared, ECannotBeShared);

        let object_id = object::id(&object).id_to_address();

        assert!(self.requested.contains(&object_id), ENotARequiredObject);

        self.deposited.push_back(object_id);
        transfer::public_transfer(object, self.storage.uid_to_address());
    }

    public fun start<Executor: drop>(self: &mut Intent<Executor>, _: Executor, ctx: &mut TxContext): Lock {
        assert!(self.deadline > ctx.epoch(), EHasExpired);
        self.initiated = true;
        Lock { intent: self.id.uid_to_address() }
    }

    public fun take<Executor: drop, Object: store + key>(self: &mut Intent<Executor>, receiving: Receiving<Object>): Object {
        assert!(self.initiated, ECallStartFirst);
        transfer::public_receive(&mut self.id, receiving)
    }

    public fun put<Executor: drop, Object: store + key>(self: &mut Intent<Executor>, object: Object) {
        assert!(self.initiated, ECallStartFirst);
        self.returned.push_back(object::id(&object).id_to_address());
        transfer::public_transfer(object, self.owner);
    }    

    public fun end<Executor: drop>(self: Intent<Executor>, lock: Lock) {
        let Intent { id, storage, owner: _, initiated, name: _, deadline: _, requested: _, deposited: _, returned, required, shared: _ } = self;

        assert!(initiated, ECallStartFirst);

        let Lock { intent } = lock;

        assert!(id.uid_to_address() == intent, EInvalidLock);
        
        assert_vectors_equality(required, returned, EMissingRequiredObjects);

        id.delete();
        storage.delete();
    }

    public fun give_back<Executor: drop, Object: store + key>(self: &mut Intent<Executor>, receiving: Receiving<Object>, ctx: &mut TxContext) {
        assert!(ctx.epoch() > self.deadline, EHasNotExpired);
        assert!(!self.initiated, EHasBeenInitiated);

        let object = transfer::public_receive(&mut self.id, receiving);

        self.returned.push_back(object::id(&object).id_to_address());

        transfer::public_transfer(object, self.owner);
    }

    public fun destroy<Executor: drop>(self: Intent<Executor>, ctx: &mut TxContext) {
        assert!(ctx.epoch() > self.deadline, EHasNotExpired);
        assert!(!self.initiated, EHasBeenInitiated);
        
        let Intent { id, storage, owner: _, initiated: _, name: _, deadline: _, requested: _, deposited: _, returned, required, shared: _ } = self;

        assert_vectors_equality(required, returned, EMissingRequiredObjects);

        id.delete();
        storage.delete();
    }

    // === Public-View Functions ===

    public fun name<Executor: drop>(self: &Intent<Executor>): String {
        self.name
    }

    public fun deadline<Executor: drop>(self: &Intent<Executor>): u64 {
        self.deadline
    }

    public fun initiated<Executor: drop>(self: &Intent<Executor>): bool {
        self.initiated
    }

    public fun requested<Executor: drop>(self: &Intent<Executor>): vector<address> {
        self.requested
    }

    public fun deposited<Executor: drop>(self: &Intent<Executor>): vector<address> {
        self.deposited
    }

    public fun returned<Executor: drop>(self: &Intent<Executor>): vector<address> {
        self.returned
    }

    public fun required<Executor: drop>(self: &Intent<Executor>): vector<address> {
        self.returned
    }

    public fun config_mut<Executor: drop, Config: store>(self: &mut Intent<Executor>, _: Executor): &mut Config {
        df::borrow_mut(&mut self.storage, ConfigKey {})
    }

    // === Admin Functions ===

    // === Public-Package Functions ===

    // === Private Functions ===

    fun assert_vectors_equality(x: vector<address>, y: vector<address>, error: u64) {
        let mut i = 0;
        let len = x.length();

        assert!(len == y.length(), error);

        while (len > i) {
            assert!(x.contains(&y[i]), error);
            i = i + 1;
        };        
    }

    // === Test Functions ===
}
