/*
* @title Automations
* @description It uses a Transfer To Object-based Automation 
* and enables the execution of an operation with assets by any signer, manually or via a backend. 
* It is designed to power DAOs, Multisigs and any other on-chain package needing to be automatically triggered.
* @dev

Flow

--- To instantiate an Automation ---

1 - Create Automation
2 - Store in the Proposal (optional)

--- To execute an Automation ---

3 - Create the Automation with the Automation (opt: received from proposal)
4 - Deposit all requested objects
5 - Share Automation

--- Happy Path: Automation is executed ---

6 - Call start
7 - Take objects
8 - Return objects (if required)
9 - Call end

--- Unhappy Path: the expiration has passed without execution ---

6 - Call give_back to return objects from the Automation to owner
7 - destroy the Automation

*
*/
module automations::automation {
    // === Imports ===

    use std::string::String;

    use sui::clock::Clock;
    use sui::dynamic_field as df;
    use sui::dynamic_object_field as dof;

    use automations::intent::Intent;

    // === Errors ===

    const EHasExpired: u64 = 1;
    const ENotARequiredObject: u64 = 2;
    const EObjectsNotReturned: u64 = 3;
    const EMissingRequestedObjects: u64 = 4;
    const EHasNotExpired: u64 = 5;
    const ENotExecutable: u64 = 6;
    const ENotARequestedObject: u64 = 7;
    const ENotAnObjectToReturn: u64 = 8;

    // === Constants ===

    // === Structs ===

    public struct ConfigKey has copy, store, drop {}

    public struct Automation<phantom Executor: drop> has key {
        id: UID,
        // initial owner of the requested objects
        owner: address,
        // label for the automation
        name: String,
        // from what timestamp (ms) it can be triggered
        execution: u64,
        // from what epoch it can be no longer triggered and deleted
        expiration: u64,        
        // objects to use
        requested: vector<address>,
        // to be filled during deposit
        deposited: vector<address>,
        // objects to be returned to owner
        required: vector<address>,    
    }

    // hot potato wrapper enforcing correct initialization 
    public struct Initializing<phantom Executor: drop> {
        automation: Automation<Executor>
    }

    // hot potato wrapper enforcing correct execution
    public struct Executing<phantom Executor: drop> {
        automation: Automation<Executor>
    }

    // === Method Aliases ===

    public use fun initializing_inner as Initializing.inner;
    public use fun executing_inner as Executing.inner;

    // === Public-Mutative Functions ===

    public fun new<Executor: drop, Config: store>(payload: Intent<Executor, Config>, ctx: &mut TxContext): Initializing<Executor> {
        let (name, owner, execution, expiration, requested, required) = (
            payload.name(),
            payload.owner(),
            payload.execution(),
            payload.expiration(),
            payload.requested(),
            payload.required()
        );

        let mut automation = Automation {
            id: object::new(ctx),
            owner,
            name,
            execution,
            expiration,
            requested,
            deposited: vector[],
            required
        };

        df::add(automation.storage(), ConfigKey {}, payload.destroy());

        Initializing { automation }
    }

    public fun deposit<Executor: drop, Object: store + key>(self: &mut Initializing<Executor>, object: Object) {
        let object_id = object::id(&object).id_to_address();
        let (contains, idx) = self.automation.requested.index_of(&object_id);
        assert!(contains && !self.automation.deposited.contains(&object_id), ENotARequiredObject);
        let addr = self.automation.requested.borrow(idx);
        // adds only requested items that are not in deposited yet
        self.automation.deposited.push_back(*addr);

        dof::add(self.automation.storage(), object_id, object);
    }

    #[allow(lint(share_owned))]
    public fun share<Executor: drop>(self: Initializing<Executor>) {
        let Initializing { automation } = self;
        // this is sufficient since there cannot have duplicates
        assert!(automation.requested.length() == automation.deposited.length(), EMissingRequestedObjects);

        transfer::share_object(automation);
    }

    public fun start<Executor: drop>(automation: Automation<Executor>, _: Executor, clock: &Clock, ctx: &mut TxContext): Executing<Executor> {
        assert!(automation.expiration > ctx.epoch(), EHasExpired);
        assert!(automation.execution <= clock.timestamp_ms(), ENotExecutable);
        Executing { automation }
    }

    public fun take<Executor: drop, Object: store + key>(self: &mut Executing<Executor>, object_id: address): Object {
        let (contains, idx) = self.automation.deposited.index_of(&object_id);
        assert!(contains, ENotARequestedObject);

        self.automation.deposited.swap_remove(idx);
        dof::remove(self.automation.storage(), object_id)        
    }

    public fun put<Executor: drop, Object: store + key>(self: &mut Executing<Executor>, object: Object) {
        let (contains, idx) = self.automation.required.index_of(&object::id(&object).id_to_address());
        assert!(contains, ENotAnObjectToReturn);
        self.automation.required.swap_remove(idx);
        transfer::public_transfer(object, self.automation.owner);
    }    

    public fun end<Executor: drop>(self: Executing<Executor>) {
        let Executing { automation } = self;
        let Automation { id, owner: _, name: _, execution: _, expiration: _, requested: _, deposited: _, required } = automation;

        assert!(required.is_empty(), EObjectsNotReturned);

        id.delete();
    }

    public fun give_back<Executor: drop, Object: store + key>(self: &mut Automation<Executor>, object_id: address, ctx: &mut TxContext) {
        assert!(ctx.epoch() > self.expiration, EHasNotExpired);

        let object = dof::remove<address, Object>(self.storage(), object_id);

        let (contains, idx) = self.requested.index_of(&object_id);
        assert!(contains, ENotARequestedObject);
        self.requested.swap_remove(idx);

        transfer::public_transfer(object, self.owner);
    }

    public fun destroy<Executor: drop>(self: Automation<Executor>, ctx: &mut TxContext) {
        assert!(ctx.epoch() > self.expiration, EHasNotExpired);

        let Automation { id, owner: _, name: _, execution: _, expiration: _, requested, deposited: _, required: _ } = self;

        assert!(requested.is_empty(), EMissingRequestedObjects);

        id.delete();
    }

    // === Public-View Functions ===

    public fun name<Executor: drop>(self: &Automation<Executor>): String {
        self.name
    }

    public fun expiration<Executor: drop>(self: &Automation<Executor>): u64 {
        self.expiration
    }

    public fun requested<Executor: drop>(self: &Automation<Executor>): vector<address> {
        self.requested
    }

    public fun deposited<Executor: drop>(self: &Automation<Executor>): vector<address> {
        self.deposited
    }

    public fun required<Executor: drop>(self: &Automation<Executor>): vector<address> {
        self.required
    }

    public fun config_mut<Executor: drop, Config: store>(self: &mut Automation<Executor>, _: Executor): &mut Config {
        df::borrow_mut(self.storage(), ConfigKey {})
    }

    public fun initializing_inner<Executor: drop>(self: &Initializing<Executor>): &Automation<Executor> {
        &self.automation
    }

    public fun executing_inner<Executor: drop>(self: &Executing<Executor>): &Automation<Executor> {
        &self.automation
    }

    // === Admin Functions ===

    // === Public-Package Functions ===

    // === Private Functions ===

    fun storage<Executor: drop>(self: &mut Automation<Executor>): &mut UID {
        &mut self.id
    }

    // === Test Functions ===
}
