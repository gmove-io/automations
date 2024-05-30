module intent::intent_payload {
    // === Imports ===

    use std::string::String;

    // === Errors ===

    const EDeadlineIsInThePast: u64 = 0;

    // === Constants ===

    // === Structs ===

    public struct IntentPayload<phantom Executor: drop, Config: store> has store {
        name: String,
        owner: address,
        deadline: u64,
        requested: vector<address>,
        required: vector<address>,
        config: Config
    }

    // === Method Aliases ===

    // === Public-Mutative Functions ===

    public fun new<Executor: drop, Config: store>(
        name: String,
        owner: address,
        deadline: u64,
        requested: vector<address>,
        required: vector<address>,
        config: Config,
        ctx: &mut TxContext        
    ): IntentPayload<Executor, Config> {
        assert!(deadline > ctx.epoch(), EDeadlineIsInThePast);
        IntentPayload {
            name,
            owner,
            deadline,
            requested,
            required,
            config
        }
    }

    public(package) fun destroy<Executor: drop, Config: store>(self: IntentPayload<Executor, Config>): Config {
        let IntentPayload { 
            name: _,
            owner: _,
            deadline: _,
            requested: _,
            required: _, 
            config
         } = self;

         config
    }

    // === Public-View Functions ===

    public fun name<Executor: drop, Config: store>(self: &IntentPayload<Executor, Config>): String {
     self.name
    }

    public fun owner<Executor: drop, Config: store>(self: &IntentPayload<Executor, Config>): address {
     self.owner
    }

    public fun deadline<Executor: drop, Config: store>(self: &IntentPayload<Executor, Config>): u64 {
     self.deadline
    }

    public fun requested<Executor: drop, Config: store>(self: &IntentPayload<Executor, Config>): vector<address> {
     self.requested
    }

    public fun required<Executor: drop, Config: store>(self: &IntentPayload<Executor, Config>): vector<address> {
     self.required
    }

    public fun config<Executor: drop, Config: store>(self: &IntentPayload<Executor, Config>): &Config {
     &self.config
    }

    // === Admin Functions ===

    // === Public-Package Functions ===

    // === Private Functions ===

    // === Test Functions ===
}