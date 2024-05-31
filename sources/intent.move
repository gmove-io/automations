module automations::intent {
    // === Imports ===

    use std::string::String;

    // === Errors ===

    const EDeadlineIsInThePast: u64 = 0;

    // === Constants ===

    // === Structs ===

    public struct Intent<phantom Executor: drop, Config: store> has store {
        name: String,
        owner: address,
        execution: u64,
        expiration: u64,
        requested: vector<address>,
        required: vector<address>,
        config: Config
    }

    // === Method Aliases ===

    // === Public-Mutative Functions ===

    public fun new<Executor: drop, Config: store>(
        _: Executor,
        name: String,
        owner: address,
        execution: u64,
        expiration: u64,
        requested: vector<address>, // assert there is no duplicates
        required: vector<address>, // assert there is no duplicates
        config: Config,
        ctx: &mut TxContext        
    ): Intent<Executor, Config> {
        assert!(expiration > ctx.epoch(), EDeadlineIsInThePast);
        Intent {
            name,
            owner,
            execution,
            expiration,
            requested,
            required,
            config
        }
    }

    public(package) fun destroy<Executor: drop, Config: store>(self: Intent<Executor, Config>): Config {
        let Intent { 
            name: _,
            owner: _,
            execution: _,
            expiration: _,
            requested: _,
            required: _, 
            config
        } = self;

        config
    }

    // === Public-View Functions ===

    public fun name<Executor: drop, Config: store>(self: &Intent<Executor, Config>): String {
        self.name
    }

    public fun owner<Executor: drop, Config: store>(self: &Intent<Executor, Config>): address {
        self.owner
    }

    public fun execution<Executor: drop, Config: store>(self: &Intent<Executor, Config>): u64 {
        self.execution
    }

    public fun expiration<Executor: drop, Config: store>(self: &Intent<Executor, Config>): u64 {
        self.expiration
    }

    public fun requested<Executor: drop, Config: store>(self: &Intent<Executor, Config>): vector<address> {
        self.requested
    }

    public fun required<Executor: drop, Config: store>(self: &Intent<Executor, Config>): vector<address> {
        self.required
    }

    public fun config<Executor: drop, Config: store>(self: &Intent<Executor, Config>): &Config {
        &self.config
    }

    // === Admin Functions ===

    // === Public-Package Functions ===

    // === Private Functions ===

    // === Test Functions ===
}