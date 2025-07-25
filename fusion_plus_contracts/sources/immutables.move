

module fusion_plus_contracts::immutables;

use fusion_plus_contracts::time_lock::TimeLock;
use sui::hash::keccak256;
use fusion_plus_contracts::time_lock::Stage;
use sui::bcs;
use sui::transfer::public_freeze_object;
use fusion_plus_contracts::time_lock::create_timelock;


public struct Immutables has key, store {
    id: UID,
    order_hash: vector<u8>, // hash of the order
    hash_lock: vector<u8>, // hash of the secret
    maker: address, // address of the maker
    taker: address,
    amount: u256, // amount of the order
    safety_deposit: u256, // safety deposit amount
    timelock: TimeLock, // timelock for the order
}

public(package) fun create_immutables(
    order_hash: vector<u8>,
    hash_lock: vector<u8>,
    maker: address,
    taker: address,
    amount: u256,
    safety_deposit: u256,
    timelock: TimeLock,
    ctx: &mut TxContext
): Immutables{
    let immutables = Immutables {
        id: object::new(ctx),
        order_hash,
        hash_lock,
        maker,
        taker,
        amount,
        safety_deposit,
        timelock
    };
    immutables
}

public fun id(immutables: &Immutables): address {
    immutables.id.to_address()
}

public fun hash(immutables: &Immutables): vector<u8> {
    let mut data = vector[];
    data.append(immutables.order_hash);
    data.append(immutables.hash_lock);
    data.append(immutables.maker.to_bytes());
    data.append(immutables.taker.to_bytes());
    data.append(bcs::to_bytes(&immutables.amount));
    data.append(bcs::to_bytes(&immutables.safety_deposit));
    data.append(bcs::to_bytes(&immutables.timelock));
    keccak256(&data)
}

public fun get_timelock(immutables: &Immutables): TimeLock {
    immutables.timelock
}


public fun maker(immutables: &Immutables): address {
    immutables.maker
}

public fun taker(immutables: &Immutables): address {
    immutables.taker
}

public fun only_after(immutables: &Immutables, stage: Stage, current_time: u64): bool {
    return current_time >= immutables.timelock.get(stage)
}

public fun only_before(immutables: &Immutables, stage: Stage, current_time: u64): bool {
    return current_time < immutables.timelock.get(stage)
}


public fun only_taker(immutables: &Immutables, ctx: &mut TxContext): bool{
    ctx.sender() == immutables.taker
}

public fun valid_secret(immutables: &Immutables,secret: &vector<u8>): bool {
    keccak256(secret) == immutables.hash_lock
}

public struct ExtraData has store, copy, drop {
    hash_lock: vector<u8>, // hash of the secret
    dst_chain_id: u256, // chain id of the destination
    dst_token: address, // address of the token on evm
    timelock: TimeLock,
    deposits: u256 // safety deposit
}

public fun extra_data_from_bytes(
    bytes: vector<u8>,
): ExtraData {
    let mut bcs = bcs::new(bytes);
    let mut hashlock_vec_len = bcs.peel_vec_length(); 
    let mut hash_lock = vector[];
    while (hashlock_vec_len > 0){
        hash_lock.push_back(bcs.peel_u8());
        hashlock_vec_len = hashlock_vec_len - 1;
    };
    let dst_chain_id = bcs.peel_u256();
    let dst_token = bcs.peel_address();
    let timelock = bcs.peel_u256();
    let deposits = bcs.peel_u256();
    ExtraData {
        hash_lock,
        dst_chain_id,
        dst_token,
        timelock: create_timelock(timelock),
        deposits
    }

}


public fun create_extra_data(
    hash_lock: vector<u8>,
    dst_chain_id: u256,
    dst_token: address,
    timelock: TimeLock,
    deposits: u256,
): ExtraData {
    ExtraData {
        hash_lock,
        dst_chain_id,
        dst_token,
        timelock,
        deposits
    }
}

public fun hash_lock(extra_data: &ExtraData): vector<u8> {
    extra_data.hash_lock
}
public fun dst_chain_id(extra_data: &ExtraData): u256 {
    extra_data.dst_chain_id
}
public fun dst_token(extra_data: &ExtraData): address {
    extra_data.dst_token
}
public fun timelock(extra_data: &ExtraData): TimeLock {
    extra_data.timelock
}

public fun deposits(extra_data: &ExtraData): u256 {
    extra_data.deposits
}

/// the destination immutables object for evm
public struct DstImmutables has copy, drop {
    maker: address, // address of the maker
    amount: u256, 
    token: address, // address of the token on evm
    safety_deposit: u256, // safety deposit amount
    chainId: u256, // chain id of the destination
}


public fun create_dst_immutables(
    maker: address,
    amount: u256,
    token: address,
    safety_deposit: u256,
    chainId: u256,
): DstImmutables {
    let dst_immutables = DstImmutables {
        maker,
        amount,
        token,
        safety_deposit,
        chainId
    };
    dst_immutables
}  



/// create the immutable object it is public
public fun create_extra_args(
    hash_lock: vector<u8>,
    dst_chain_id: u256,
    dst_token: address,
    deposits: u256,
    timelock: TimeLock,
): ExtraData{
    ExtraData  {
        hash_lock,
        dst_chain_id,
        dst_token,
        timelock,
        deposits
    }
}




