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
    const ENotAnObjectToReturn: u64 = 3;
    const ENotARequestedObject: u64 = 4;
    const EObjectsNotReturned: u64 = 5;
    const EInvalidLock: u64 = 6;
    const EMissingRequestedObjects: u64 = 7;
    const EHasNotExpired: u64 = 8;
    const EHasBeenInitiated: u64 = 9;
    const ECannotBeShared: u64 = 10;

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
        to_deposit: vector<address>,
        to_return: vector<address>,    
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
        let (name, owner, deadline, requested, to_return) = (
            payload.name(),
            payload.owner(),
            payload.deadline(),
            payload.requested(),
            payload.to_return()
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
            to_deposit: requested,
            to_return
        };

        let share_lock = ShareLock { intent: intent.id.uid_to_address() };

        (intent, share_lock)
    }

    public fun deposit<Executor: drop, Object: store + key>(self: &mut Intent<Executor>, object: Object) {
        assert!(!self.initiated, EIsAlreadyInitiated);
        assert!(!self.shared, ECannotBeShared);

        let object_id = object::id(&object).id_to_address();
        let (contains, idx) = self.to_deposit.index_of(&object_id);
        assert!(contains, ENotARequestedObject);
        self.to_deposit.swap_remove(idx);

        dof::add(&mut self.storage, object_id, object);
    }

    #[allow(lint(share_owned))]
    public fun share<Executor: drop>(mut self: Intent<Executor>, share_lock: ShareLock) {
        let ShareLock { intent } = share_lock;

        assert!(intent == self.id.uid_to_address(), EInvalidLock);
        assert!(self.to_deposit.is_empty(), EMissingRequestedObjects);

        self.shared = true;
        transfer::share_object(self);
    }

    public fun start<Executor: drop>(self: &mut Intent<Executor>, _: Executor, ctx: &mut TxContext): Lock {
        assert!(self.deadline > ctx.epoch(), EHasExpired);
        self.initiated = true;
        Lock { intent: self.id.uid_to_address() }
    }

    public fun take<Executor: drop, Object: store + key>(self: &mut Intent<Executor>, object_id: address): Object {
        assert!(self.initiated, ECallStartFirst);
        dof::remove(&mut self.storage, object_id)
    }

    public fun put<Executor: drop, Object: store + key>(self: &mut Intent<Executor>, object: Object) {
        assert!(self.initiated, ECallStartFirst);

        let (contains, idx) = self.to_return.index_of(&object::id(&object).id_to_address());
        assert!(contains, ENotAnObjectToReturn);
        self.to_return.swap_remove(idx);
        transfer::public_transfer(object, self.owner);
    }    

    public fun end<Executor: drop>(self: Intent<Executor>, lock: Lock) {
        let Intent { id, storage, owner: _, initiated, name: _, deadline: _, requested: _, to_deposit: _, to_return, shared: _ } = self;

        assert!(initiated, ECallStartFirst);

        let Lock { intent } = lock;

        assert!(id.uid_to_address() == intent, EInvalidLock);
        assert!(to_return.is_empty(), EObjectsNotReturned);

        id.delete();
        storage.delete();
    }

    public fun give_back<Executor: drop, Object: store + key>(self: &mut Intent<Executor>, object_id: address, ctx: &mut TxContext) {
        assert!(ctx.epoch() > self.deadline, EHasNotExpired);
        assert!(!self.initiated, EHasBeenInitiated);

        let object = dof::remove<address, Object>(&mut self.storage, object_id);

        let (contains, idx) = self.requested.index_of(&object_id);
        assert!(contains, ENotARequestedObject);
        self.requested.swap_remove(idx);

        transfer::public_transfer(object, self.owner);
    }

    public fun destroy<Executor: drop>(self: Intent<Executor>, ctx: &mut TxContext) {
        assert!(ctx.epoch() > self.deadline, EHasNotExpired);
        assert!(!self.initiated, EHasBeenInitiated);
        
        let Intent { id, storage, owner: _, initiated: _, name: _, deadline: _, requested, to_deposit: _, to_return: _, shared: _ } = self;

        assert!(requested.is_empty(), EMissingRequestedObjects);

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

    public fun to_deposit<Executor: drop>(self: &Intent<Executor>): vector<address> {
        self.to_deposit
    }

    public fun to_return<Executor: drop>(self: &Intent<Executor>): vector<address> {
        self.to_return
    }

    public fun config_mut<Executor: drop, Config: store>(self: &mut Intent<Executor>, _: Executor): &mut Config {
        df::borrow_mut(&mut self.storage, ConfigKey {})
    }

    // === Admin Functions ===

    // === Public-Package Functions ===

    // === Private Functions ===

    // === Test Functions ===
}
