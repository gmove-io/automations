module intent::intent {
    // === Imports ===

    use std::string::String;

    use sui::transfer::Receiving;

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

    // === Constants ===

    // === Structs ===

    public struct Intent<phantom Executor: drop, Config: store> has key {
        id: UID,
        storage: UID,
        owner: address,
        name: String,
        deadline: u64,        
        initiated: bool,
        requested: vector<address>,
        deposited: vector<address>,
        returned: vector<address>,
        required: vector<address>,
        config: Config        
    }

    public struct Lock {
        intent: address
    }

    // === Method Aliases ===

    // === Public-Mutative Functions ===

    public fun new<Executor: drop, Config: store>(payload: IntentPayload<Executor, Config>, ctx: &mut TxContext): Intent<Executor, Config> {
        let (name, owner, deadline, requested, required) = (
            payload.name(),
            payload.owner(),
            payload.deadline(),
            payload.requested(),
            payload.required()
        );

        Intent<Executor, Config> {
            id: object::new(ctx),
            storage: object::new(ctx),
            initiated: false,
            owner,
            name,
            deadline,
            requested,
            deposited: vector[],
            returned: vector[],
            required,
            config: payload.destroy()
        }
    }

    public fun share<Executor: drop, Config: store>(self: Intent<Executor, Config>) {
        let mut i = 0;
        let len = self.requested.length();

        assert!(len == self.deposited.length(), EMissingRequestedObjects);

        while (len > i) {
            assert!(self.deposited.contains(&self.requested[i]), EMissingRequestedObjects);
            i = i + 1;
        };

        transfer::share_object(self);
    }

    public fun deposit<Executor: drop, Config: store, Object: store + key>(self: &mut Intent<Executor, Config>, object: Object) {
        assert!(!self.initiated, EIsAlreadyInitiated);

        let object_id = object::id(&object).id_to_address();

        assert!(self.requested.contains(&object_id), ENotARequiredObject);

        self.deposited.push_back(object_id);
        transfer::public_transfer(object, self.storage.uid_to_address());
    }

    public fun start<Executor: drop, Config: store>(self: &mut Intent<Executor, Config>, _: Executor, ctx: &mut TxContext): Lock {
        assert!(self.deadline > ctx.epoch(), EHasExpired);
        self.initiated = true;
        Lock { intent: self.id.uid_to_address() }
    }

    public fun take<Executor: drop, Config: store, Object: store + key>(self: &mut Intent<Executor, Config>, receiving: Receiving<Object>): Object {
        assert!(self.initiated, ECallStartFirst);
        transfer::public_receive(&mut self.id, receiving)
    }

    public fun put<Executor: drop, Config: store, Object: store + key>(self: &mut Intent<Executor, Config>, object: Object) {
        assert!(self.initiated, ECallStartFirst);
        self.returned.push_back(object::id(&object).id_to_address());
        transfer::public_transfer(object, self.owner);
    }    

    public fun end<Executor: drop, Config: store>(self: Intent<Executor, Config>, lock: Lock): Config {
        let Intent { id, storage, owner: _, initiated, name: _, deadline: _, requested: _, deposited: _, returned, required, config } = self;

        assert!(initiated, ECallStartFirst);

        let Lock { intent } = lock;

        assert!(id.uid_to_address() == intent, EInvalidLock);

        let mut i = 0;
        let len = required.length();

        assert!(len == returned.length(), EMissingRequiredObjects);

        while (len > i) {
            assert!(required.contains(&returned[i]), EMissingRequiredObjects);
            i = i + 1;
        };


        id.delete();
        storage.delete();

        config 
    }

    public fun give_back<Executor: drop, Config: store, Object: store + key>(self: &mut Intent<Executor, Config>, receiving: Receiving<Object>, ctx: &mut TxContext) {
        assert!(ctx.epoch() > self.deadline, EHasNotExpired);
        assert!(!self.initiated, EHasBeenInitiated);

        let object = transfer::public_receive(&mut self.id, receiving);

        self.returned.push_back(object::id(&object).id_to_address());

        transfer::public_transfer(object, self.owner);
    }

    public fun destroy<Executor: drop, Config: store>(self: Intent<Executor, Config>, ctx: &mut TxContext): Config {
        assert!(ctx.epoch() > self.deadline, EHasNotExpired);
        assert!(!self.initiated, EHasBeenInitiated);
        
        let Intent { id, storage, owner: _, initiated: _, name: _, deadline: _, requested: _, deposited: _, returned, required, config } = self;

        let mut i = 0;
        let len = required.length();

        assert!(len == returned.length(), EMissingRequiredObjects);

        while (len > i) {
            assert!(required.contains(&returned[i]), EMissingRequiredObjects);
            i = i + 1;
        };


        id.delete();
        storage.delete();

        config 
    }

    // === Public-View Functions ===

    public fun name<Executor: drop, Config: store>(self: &Intent<Executor, Config>): String {
        self.name
    }

    public fun deadline<Executor: drop, Config: store>(self: &Intent<Executor, Config>): u64 {
        self.deadline
    }

    public fun initiated<Executor: drop, Config: store>(self: &Intent<Executor, Config>): bool {
        self.initiated
    }

    public fun requested<Executor: drop, Config: store>(self: &Intent<Executor, Config>): vector<address> {
        self.requested
    }

    public fun deposited<Executor: drop, Config: store>(self: &Intent<Executor, Config>): vector<address> {
        self.deposited
    }

    public fun returned<Executor: drop, Config: store>(self: &Intent<Executor, Config>): vector<address> {
        self.returned
    }

    public fun required<Executor: drop, Config: store>(self: &Intent<Executor, Config>): vector<address> {
        self.returned
    }

    public fun config_mut<Executor: drop, Config: store>(self: &mut Intent<Executor, Config>, _: Executor): &mut Config {
        &mut self.config
    }

    // === Admin Functions ===

    // === Public-Package Functions ===

    // === Private Functions ===

    // === Test Functions ===
}
