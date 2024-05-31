/*
* @title Intent
* @description It is a Transfer To Object based intent to manage assets and capabilities. It is designed to power DAOs and Multisigs.
* @dev

Flow

1 - Create IntentPayload
2 - Store in the Proposal

--- To execute a proposal ---

3 - Create the Intent with the IntentPayload
4 - Deposit all returned objects
5 - Share Intent

--- Happy Path someone executes ---

6 - Call start
7 - Take objects
8 - Return objects (if returned)
9 - Call end

--- Unhappy Path, the deadline has passed without it being executed ---

6 - Call give_back to return objects from the intent to owner
7 - destroy the intent

*
*/
module intent::intent {
    // === Imports ===

    use std::string::String;

    use sui::dynamic_field as df;
    use sui::dynamic_object_field as dof;

    use intent::intent_payload::IntentPayload;

    // === Errors ===

    const ECallStartFirst: u64 = 0;
    const EHasExpired: u64 = 1;
    const EIsAlreadyInitiated: u64 = 2;
    const ENotARequiredObject: u64 = 3;
    const EObjectsNotReturned: u64 = 4;
    const EMissingRequestedObjects: u64 = 6;
    const EHasNotExpired: u64 = 7;
    const EHasBeenInitiated: u64 = 8;
    const ENotARequestedObject: u64 = 9;
    const ENotAnObjectToReturn: u64 = 10;

    // === Constants ===

    // === Structs ===

    public struct ConfigKey has copy, store, drop {}

    public struct Intent<phantom Executor: drop> has key {
        id: UID,
        owner: address,
        name: String,
        deadline: u64,        
        initiated: bool,
        requested: vector<address>,
        deposited: vector<address>,
        required: vector<address>,    
    }

    public struct Initializing<phantom Executor: drop> {
        intent: Intent<Executor>
    }

    public struct Executing<phantom Executor: drop> {
        intent: Intent<Executor>
    }

    // === Method Aliases ===

    // === Public-Mutative Functions ===

    public fun new<Executor: drop, Config: store>(payload: IntentPayload<Executor, Config>, ctx: &mut TxContext): Initializing<Executor> {
        let (name, owner, deadline, requested, required) = (
            payload.name(),
            payload.owner(),
            payload.deadline(),
            payload.requested(),
            payload.required()
        );

        let mut intent = Intent {
            id: object::new(ctx),
            initiated: false,
            owner,
            name,
            deadline,
            requested,
            deposited: requested,
            required
        };

        df::add(intent.storage(), ConfigKey {}, payload.destroy());

        Initializing { intent }
    }

    public fun deposit<Executor: drop, Object: store + key>(self: &mut Initializing<Executor>, object: Object) {
        assert!(!self.intent.initiated, EIsAlreadyInitiated);

        let object_id = object::id(&object).id_to_address();
        let (contains, idx) = self.intent.requested.index_of(&object_id);
        assert!(contains && !self.intent.deposited.contains(&object_id), ENotARequiredObject);
        let addr = self.intent.requested.borrow(idx);
        self.intent.deposited.push_back(*addr);

        dof::add(self.intent.storage(), object_id, object);
    }

    #[allow(lint(share_owned))]
    public fun share<Executor: drop>(self: Initializing<Executor>) {
        let Initializing { intent } = self;

        assert_vectors_equality(intent.requested, intent.deposited, EMissingRequestedObjects);

        transfer::share_object(intent);
    }

    public fun start<Executor: drop>(mut intent: Intent<Executor>, _: Executor, ctx: &mut TxContext): Executing<Executor> {
        assert!(intent.deadline > ctx.epoch(), EHasExpired);
        intent.initiated = true;
        Executing { intent }
    }

    public fun take<Executor: drop, Object: store + key>(self: &mut Executing<Executor>, object_id: address): Object {
        assert!(self.intent.initiated, ECallStartFirst);     

        let (contains, idx) = self.intent.deposited.index_of(&object_id);
        assert!(contains, ENotARequestedObject);

        self.intent.deposited.swap_remove(idx);
        dof::remove(self.intent.storage(), object_id)        
    }

    public fun put<Executor: drop, Object: store + key>(self: &mut Executing<Executor>, object: Object) {
        assert!(self.intent.initiated, ECallStartFirst);

        let (contains, idx) = self.intent.required.index_of(&object::id(&object).id_to_address());
        assert!(contains, ENotAnObjectToReturn);
        self.intent.required.swap_remove(idx);
        transfer::public_transfer(object, self.intent.owner);
    }    

    public fun end<Executor: drop>(self: Executing<Executor>) {
        let Executing { intent } = self;
        let Intent { id, owner: _, initiated, name: _, deadline: _, requested: _, deposited: _, required } = intent;

        assert!(initiated, ECallStartFirst);

        assert!(required.is_empty(), EObjectsNotReturned);

        id.delete();
    }

    public fun give_back<Executor: drop, Object: store + key>(self: &mut Intent<Executor>, object_id: address, ctx: &mut TxContext) {
        assert!(ctx.epoch() > self.deadline, EHasNotExpired);
        assert!(!self.initiated, EHasBeenInitiated);

        let object = dof::remove<address, Object>(self.storage(), object_id);

        let (contains, idx) = self.requested.index_of(&object_id);
        assert!(contains, ENotARequestedObject);
        self.requested.swap_remove(idx);

        transfer::public_transfer(object, self.owner);
    }

    public fun destroy<Executor: drop>(self: Intent<Executor>, ctx: &mut TxContext) {
        assert!(ctx.epoch() > self.deadline, EHasNotExpired);
        assert!(!self.initiated, EHasBeenInitiated);
        
        let Intent { id, owner: _, initiated: _, name: _, deadline: _, requested, deposited: _, required: _ } = self;

        assert!(requested.is_empty(), EMissingRequestedObjects);

        id.delete();
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

    public fun required<Executor: drop>(self: &Intent<Executor>): vector<address> {
        self.required
    }

    public fun config_mut<Executor: drop, Config: store>(self: &mut Intent<Executor>, _: Executor): &mut Config {
        df::borrow_mut(self.storage(), ConfigKey {})
    }

    // === Admin Functions ===

    // === Public-Package Functions ===

    // === Private Functions ===

    fun storage<Executor: drop>(self: &mut Intent<Executor>): &mut UID {
        &mut self.id
    }

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
