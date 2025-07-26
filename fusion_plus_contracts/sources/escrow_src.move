
/// similar to the `BaseEscrow` this creates an object of `EscrowSrc` and `EscrowDst` which contains the coin
/// we don't need a rescue funds function because in move there is no need to rescue funds tokens are stored as objects
/// and coin is transferred or canceled
module fusion_plus_contracts::escrow_src;

use sui::balance::Balance;
use sui::sui::SUI;
use sui::transfer::public_share_object;
use fusion_plus_contracts::immutables::Immutables;
use sui::clock::Clock;
use fusion_plus_contracts::time_lock::stage;
use sui::coin::Coin;
use fusion_plus_contracts::immutables;
use sui::transfer::public_freeze_object;

#[error]
const EOnlyTaker: vector<u8> = b"Only taker can withdraw";

#[error]
const EInvalidTime: vector<u8> = b"Invalid time for this operation";

#[error]
const EInvalidSecret: vector<u8> = b"Invalid secret for the hash lock";

#[error]
const EInvalidImmutables: vector<u8> = b"Invalid immutables for the given escrow";

/// creates the source escrow object 
public struct FusionPlusSrcEscrow<phantom T> has key, store {
    id: UID,
    token: Balance<T>,
    safety_deposit: Balance<SUI>, // safety deposit amount
    immutables_hash: vector<u8> // to validate immutables
}

fun destroy<T>(escrow: FusionPlusSrcEscrow<T>) {
    let FusionPlusSrcEscrow { id, token, safety_deposit, immutables_hash:_ } = escrow;
    id.delete();
    token.destroy_zero();
    safety_deposit.destroy_zero();
}

public fun token_value<T>(escrow: &FusionPlusSrcEscrow<T>): u64 {
    escrow.token.value()
}

public fun immutables_hash<T>(escrow: &FusionPlusSrcEscrow<T>): vector<u8> {
    escrow.immutables_hash
}

/// `public(package)` function as it should only be called on `fill`
public(package) fun create_src_escrow<T>(
    token: Balance<T>,
    safety_deposit: Coin<SUI>,
    immutables: Immutables,
    ctx: &mut TxContext
){
    let id = object::new(ctx);
    let escrow = FusionPlusSrcEscrow {
        id,
        token,
        immutables_hash: immutables.hash(),
        safety_deposit: safety_deposit.into_balance()
    };
    public_freeze_object(immutables);
    public_share_object(escrow);
}



/// private withdraw function
public fun withdraw_to<T>(
    to: address,
    secret: vector<u8>,
    escrow: &mut FusionPlusSrcEscrow<T>,
    immutables: &Immutables,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let current_time = clock.timestamp_ms() / 1000;

    assert!(immutables.only_taker(ctx), EOnlyTaker);
    // only after the `Stage.SrcWithDrawal`
    assert!(immutables.only_after(stage(0), current_time), EInvalidTime);

    assert!(immutables.only_before(stage(2), current_time), EInvalidTime);

    withdraw(secret, to, immutables, escrow, ctx);

}

public fun public_withdraw<T>(
    secret: vector<u8>,
    escrow: &mut FusionPlusSrcEscrow<T>,
    immutables: &Immutables,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let current_time = clock.timestamp_ms() / 1000;
    assert!(immutables.only_after(stage(1), current_time));
    assert!(immutables.only_before(stage(2), current_time));

   withdraw(secret, immutables.taker(), immutables, escrow, ctx);
}

fun withdraw<T>(
    secret: vector<u8>,
    to: address,
    immutables: &Immutables,
    escrow: &mut FusionPlusSrcEscrow<T>,
    ctx:  &mut TxContext
) {

    assert!(immutables.valid_secret(&secret), EInvalidSecret);
    assert!(immutables.hash() == escrow.immutables_hash, EInvalidImmutables);

    // main transfer logic
    let coin = escrow.token.withdraw_all().into_coin(ctx);

    // tansfer the tokens
    transfer::public_transfer(coin, to);

    // transfer the safety deposit
    transfer::public_transfer(escrow.safety_deposit.withdraw_all().into_coin(ctx), ctx.sender());
    
}

public fun resolver_cancel<T>(
    immutables: &Immutables,
    escrow: &mut FusionPlusSrcEscrow<T>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let current_time = clock.timestamp_ms() / 1000;
    assert!(immutables.only_taker(ctx), EOnlyTaker);
    assert!(immutables.only_after(stage(2), current_time), EInvalidTime);

    cancel(immutables, escrow, ctx)
}

public fun public_cancel<T>(
    immutables: &Immutables,
    escrow: &mut FusionPlusSrcEscrow<T>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let current_time = clock.timestamp_ms() / 1000;
    assert!(immutables.only_after(stage(3), current_time), EInvalidTime);

    cancel(immutables, escrow, ctx)
}


fun cancel<T>(immutables: &Immutables, escrow: &mut FusionPlusSrcEscrow<T>, ctx: &mut TxContext) {

    assert!(immutables.hash() == escrow.immutables_hash, EInvalidImmutables);
        // main transfer logic
    let coin = escrow.token.withdraw_all().into_coin(ctx);

    // tansfer the tokens
    transfer::public_transfer(coin, immutables.maker());

    // transfer the safety deposit
    transfer::public_transfer(escrow.safety_deposit.withdraw_all().into_coin(ctx), ctx.sender());
}


