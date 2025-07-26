module fusion_plus_contracts::escrow_dst;


use sui::balance::Balance;
use sui::sui::SUI;
use sui::coin::Coin;
use sui::bcs;
use sui::hash::keccak256;
use sui::transfer::public_share_object;
use fusion_plus_contracts::time_lock::{TimeLock, create_timelock, stage};
use sui::clock::Clock;
use std::debug::print;
use sui::transfer::public_freeze_object;

#[error]
const EOnlyTaker: vector<u8> = b"Only taker can withdraw";

#[error]
const EInvalidSecret: vector<u8> = b"Invalid secret for the order";

#[error]
const EInvalidImmutables: vector<u8> = b"Invalid immutables for the order";

#[error]
const EInvalidTime: vector<u8> = b"Invalid time for this operation";

#[error]
const EInvalidSecurityDeposit: vector<u8> = b"the security deposit does not match the amount in the specified immutables";

#[error]
const EInvalidAmount: vector<u8> = b"the amount does not match the amount in the specified immutables";

/// the destination escrow object
/// this is the object that is created when the order is resolved by the resolver
public struct FusionPlusDstEscrow<phantom T> has key, store {
    id: UID,
    token: Balance<T>,
    safety_deposit: Balance<SUI>, // safety deposit amount
    immutables_hash: vector<u8>, // to validate immutables
    taker: address, // address of the taker
}

public struct SuiDstImmutables has key,store {
    id: UID,
    hash_lock: vector<u8>, // hash of the secret
    maker: address, // address of the maker
    amount: u64, // `taking_amount` of the order
    timelock: TimeLock, // timelock for the order
    safety_deposit: u64, // safety deposit amount
}


public fun from_bytes(
    bytes: vector<u8>,
    ctx: &mut TxContext
): SuiDstImmutables{
    let mut bcs=bcs::new(bytes);
    let (haslock, maker, amount, timelock_inner, safety_deposit) = (bcs.peel_vec_u8(), bcs.peel_address(), bcs.peel_u64(), bcs.peel_u256(), bcs.peel_u64());
    SuiDstImmutables {
        id: object::new(ctx),
        hash_lock: haslock,
        maker,
        amount,
        timelock: create_timelock(timelock_inner),
        safety_deposit,
    }
}

public fun hash(immutables: &SuiDstImmutables): vector<u8> {
    let mut data = vector[];
    data.append(immutables.hash_lock);
    data.append(immutables.maker.to_bytes());
    data.append(bcs::to_bytes(&immutables.amount));
    keccak256(&data)
}

public fun valid_secret(immutables: &SuiDstImmutables, secret: &vector<u8>): bool {
    let hash = keccak256(secret);
    hash == immutables.hash_lock
}

public fun create_dst_escrow<T>(
    token: Coin<T>,
    safety_deposit: Coin<SUI>,
    immutables_bytes: vector<u8> ,
    ctx: &mut TxContext
) {
    let immutables = from_bytes(immutables_bytes, ctx);
    print(&immutables);
    if (immutables.safety_deposit != safety_deposit.value()) {
        abort EInvalidSecurityDeposit
    };
    if (immutables.amount != token.value()) {
        abort EInvalidAmount
    };

    let id = object::new(ctx);
    let escrow = FusionPlusDstEscrow {
        id,
        token: token.into_balance(),
        immutables_hash: immutables.hash(),
        safety_deposit: safety_deposit.into_balance(),
        taker: ctx.sender()
    };
    public_share_object(escrow);
    public_freeze_object(immutables);
}


public fun resolver_withdraw<T>(
    secret: vector<u8>,
    immutables: &SuiDstImmutables,
    escrow: &mut FusionPlusDstEscrow<T>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let current_time = clock.timestamp_ms() / 1000;
    assert!(escrow.taker == ctx.sender(), EOnlyTaker);
    assert!(current_time >= immutables.timelock.get(stage(4)), EInvalidTime);
    assert!(current_time < immutables.timelock.get(stage(6)), EInvalidTime);

    withdraw(secret, immutables, escrow, ctx);
}

public fun public_withdraw<T>(
    secret: vector<u8>,
    immutables: &SuiDstImmutables,
    escrow: &mut FusionPlusDstEscrow<T>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let current_time = clock.timestamp_ms() / 1000;
    assert!(current_time >= immutables.timelock.get(stage(5)), EInvalidTime);
    assert!(current_time < immutables.timelock.get(stage(6)), EInvalidTime);

    withdraw(secret, immutables, escrow, ctx);
}


fun withdraw<T>(
    secret: vector<u8>,
    immutables: &SuiDstImmutables,
    escrow: &mut FusionPlusDstEscrow<T>,
    ctx: &mut TxContext,
) {
    assert!(immutables.valid_secret(&secret), EInvalidSecret);
    assert!(immutables.hash() == escrow.immutables_hash, EInvalidImmutables);
    
    // transfer the token to the `to` address
    let token = escrow.token.withdraw_all().into_coin(ctx);
    transfer::public_transfer(token, immutables.maker);

    transfer::public_transfer(escrow.safety_deposit.withdraw_all().into_coin(ctx), ctx.sender());
}


public fun cancel<T>(
    immutables: &SuiDstImmutables,
    escrow: &mut FusionPlusDstEscrow<T>,
    clock: &Clock,
    ctx: &mut TxContext,
)  {

    // `onlyValidImmutables`
    assert!(immutables.hash() == escrow.immutables_hash, EInvalidImmutables);

    // `onlyTaker`
    assert!(escrow.taker == ctx.sender(), EOnlyTaker);

    // `onlyAfter(stage(6), current_time)`
    let current_time = clock.timestamp_ms() / 1000;
    assert!(current_time >= immutables.timelock.get(stage(6)), EInvalidTime);

    // main transfer logic
    let coin = escrow.token.withdraw_all().into_coin(ctx);

    // tansfer the tokens
    transfer::public_transfer(coin, immutables.maker);

    // transfer the safety deposit
    transfer::public_transfer(escrow.safety_deposit.withdraw_all().into_coin(ctx), ctx.sender());
}
