
/// ports the functionality of the `OrderLib`
/// useful in calculation making and taking amounts
module fusion_plus_contracts::fusion_protocol;


use sui::clock::Clock;
use sui::coin::Coin;
use sui::balance::Balance;
use sui::hash::keccak256;
use sui::bcs;
use fusion_plus_contracts::dutch_auction::AuctionData;
use fusion_plus_contracts::dutch_auction::calculate_rate_bump;
use fusion_plus_contracts::arthematic::{mul_div_ceil, mul_div_floor};
use fusion_plus_contracts::escrow_src::create_src_escrow;
use fusion_plus_contracts::time_lock::set_deployed_at;
use fusion_plus_contracts::immutables::ExtraData;
use fusion_plus_contracts::immutables::hash_lock;
use fusion_plus_contracts::immutables::timelock;
use fusion_plus_contracts::immutables::create_immutables;
use fusion_plus_contracts::immutables::deposits;
use fusion_plus_contracts::immutables::create_dst_immutables;
use fusion_plus_contracts::immutables::dst_token;
use std::u128;
use fusion_plus_contracts::immutables::dst_chain_id;
use sui::event::emit;
use fusion_plus_contracts::immutables::DstImmutables;
use sui::coin::CoinMetadata;
use sui::sui::SUI;
use fusion_plus_contracts::dutch_auction::{ from_bytes};
use fusion_plus_contracts::immutables;
use std::option::none;

const BASE1_E7: u256 = 10000000;
const BASE1_E2: u256 = 100;

#[error]
const EInvalidOrderAmount: vector<u8> = b"the order amount cannot be zero";

#[error]
const EInvalidSurplusPercentage: vector<u8> = b"the surplus percentage cannot be more than 100";

#[error]
const EExpiredOrder: vector<u8> = b"the order is expired you cannot fill";

#[error]
const EInvalidEstimatedTakerAmount: vector<u8> = b"the estimated taker amount cannot be less than the minimum taker amount";

#[error]
const EInconsistentProtocolFeeConfig: vector<u8> = b"the protocol fee config is inconsistent, protocol fee and surplus percentage are non zero but no protcol address is provided";

#[error]
const EInvalidFusionOrder: vector<u8> = b"a fusion order must have the target coin metadate";


#[error]
const EInvalidFusionPlusOrder: vector<u8> = b"the order is marked cross chain but no timelock or hashlock was provided";

#[error]
const EInvalidFusionPlusOrderFill: vector<u8> = b"the order is marked cross chain but no immutables were provided";

#[error]
const EInvalidSafetyDepositAmount: vector<u8> = b"the safety deposit amount is less than the minimum required amount";

public struct FeeConfig has store , drop {
    /// protocol's fee in basis points where 1E5 = 100%
    protocol_fee: u16,

    /// integrator's fee in basis points where 1E5 = 100%
    integrator_fee: u16,

    /// precentage of possitive slippage taken by the protocol as an aditional fee
    /// 1E2 = 100%
    surplus_percentage: u8,

    /// value in absolute decimals
    max_cancellation_premium: u64,
}

public fun fee_config_from_bytes(
    bytes: vector<u8>,
): FeeConfig {
    let mut bcs = bcs::new(bytes);
    let protocol_fee = bcs.peel_u16();
    let integrator_fee = bcs.peel_u16();
    let surplus_percentage = bcs.peel_u8();
    let max_cancellation_premium = bcs.peel_u64();
    FeeConfig {
        protocol_fee,
        integrator_fee,
        surplus_percentage,
        max_cancellation_premium,
    }
}

public fun create_fee_config(
    protocol_fee: u16,
    integrator_fee: u16,
    surplus_percentage: u8,
    max_cancellation_premium: u64,
): FeeConfig {
    FeeConfig {
        protocol_fee,
        integrator_fee,
        surplus_percentage,
        max_cancellation_premium,
    }
}

/// normal fusion swap escrow object
public struct FusionEscrow<phantom T> has key, store {
    id: UID,
    order_hash: vector<u8>,
    balance: Balance<T>
}

public struct Order<phantom T, phantom U> has key , store{
    id: UID,
    maker: address, // address of the maker
    maker_asset: Balance<T>,
    reciever: address,
    min_taker_amount: u256,
    dutch_auction_data: AuctionData,
    expiration_time: u64,
    taker_token: Option<CoinMetadata<U>>, // in case of not a cross chain order this is the token type of the dst token
    extra_data: Option<ExtraData>,
    cross_chain: bool,
}

public fun is_cross_chain<T, U>(order: &Order<T, U>): bool {
    order.cross_chain
}

public fun reciever<T, U>(order: &Order<T, U>): address {
    order.reciever
}



public struct OrderCreated has copy, drop{
    order_hash: vector<u8>,
    order_id: address,
}

public fun create_cross_chain_order<T>(
    maker_token: Coin<T>,
    min_taker_amount: u256,
    dutch_auction_data: vector<u8>,
    expiration_time: u64,
    clock: &Clock,
    reciever: Option<address>,
    extra_data: vector<u8>,
    ctx: &mut TxContext
){
    let dutch_auction_data = from_bytes(dutch_auction_data);
    let extra_data = immutables::extra_data_from_bytes(extra_data);
    // `SUI` is kept as placeholder for the dst token type
    create_order<T, SUI>(maker_token, min_taker_amount,  dutch_auction_data, expiration_time, clock, reciever, true, option::none(), option::some(extra_data), ctx);
}


/// creates the order object
/// validates the order parameters
/// creates the `FusionPlusSrcEscrow` with `hash_lock` and `time_lock` if the order is cross chain
/// else create the simple `FusionEscrow` object
public fun create_order<T,U>(
    maker_token: Coin<T>,
    min_taker_amount: u256,
    dutch_auction_data: AuctionData,
    expiration_time: u64,
    clock: &Clock,
    reciever: Option<address>,
    is_cross_chain: bool,
    taker_token: Option<CoinMetadata<U>>,
    extra_data: Option<ExtraData>,
    ctx: &mut TxContext
){
    if (maker_token.value() == 0) {
        abort EInvalidOrderAmount
    };
    if (clock.timestamp_ms() / 1000 > expiration_time) {
        abort EExpiredOrder
    };

    // if (fee.surplus_percentage > BASE1_E2 as u8) {
    //     abort EInvalidSurplusPercentage
    // };

    // if (estimated_taker_amount < min_taker_amount){
    //     abort EInvalidEstimatedTakerAmount
    // };

    // if (fee.protocol_fee > 0 ||  fee.surplus_percentage > 0){
    //     if (protocol_dst_acc.is_none()) {
    //         abort EInconsistentProtocolFeeConfig
    //     };
    // };

    // if (fee.integrator_fee > 0 && integrator_dst_acc.is_none()) {
    //     abort EInconsistentProtocolFeeConfig
    // };

    let reciever = if (reciever.is_some()){
        reciever.borrow()
    } else {
        &ctx.sender()
    };

    if (is_cross_chain) {
        if (extra_data.is_none()) {
            abort EInvalidFusionPlusOrder
        };
    } else {
        if (taker_token.is_none()) {
            abort EInvalidFusionOrder
        };
    };


    let id = object::new(ctx);
    let obj_id = id.to_inner();
    let order = Order {
        id,
        maker: ctx.sender(),
        maker_asset: maker_token.into_balance(),
        min_taker_amount,
        reciever: *reciever,
        dutch_auction_data,
        expiration_time,
        cross_chain: is_cross_chain,
        taker_token,
        extra_data,
    };
    let order_hash = order.order_hash();

    transfer::public_share_object(order);

    emit(OrderCreated{
        order_hash,
        order_id: obj_id.to_address(),
    });
}


public struct SrcEscrowCreated has copy, drop{
    immutables_id: address,
    dst_immutables: DstImmutables,
}


public fun fill_cross_chain_order<T>(
    order: &mut Order<T, SUI>,
    amount: u64, // the amount of the order to fill i.e making amount
    clock: &Clock,
    safety_deposit: Coin<SUI>,
    ctx: &mut TxContext,
) {
    if (order.cross_chain == false) {
        abort EInvalidFusionPlusOrderFill
    };
    let safety_deposit_opt = option::some(safety_deposit);
   
    fill(order, amount, none(), clock, safety_deposit_opt, ctx)
}

public fun fill<T, U>(
    order: &mut Order<T, U>,
    amount: u64, // the amount of the order to fill i.e making amount
    token: Option<Coin<U>>,
    clock: &Clock,
    safety_deposit: Option<Coin<SUI>>,
    ctx: &mut TxContext,
){

    let order_hash = order.order_hash();

    // get value of the taker amount after dutch auction calculations
    let taker_amount = get_taker_amount(
        order.maker_asset.value() as u256,
         order.min_taker_amount, 
         amount as u256, 
         option::some(order.dutch_auction_data), 
         clock
    );

    if (order.cross_chain){
        if (order.extra_data.is_none() || safety_deposit.is_none()) {
            abort EInvalidFusionPlusOrderFill
        };

        // handle partial fills here
        let extra_data= order.extra_data.borrow();
        let hash_lock = hash_lock(extra_data);
        let timelock = timelock(extra_data).set_deployed_at(clock.timestamp_ms() / 1000);
        let deposits = deposits(extra_data);
        let safety_deposit_imm = deposits >> 128;
        let mut safety_deposit_coin = safety_deposit.destroy_some();
        if (safety_deposit_imm > safety_deposit_coin.value() as u256) {
            abort EInvalidSafetyDepositAmount
        };

       let immutables = create_immutables(
            order_hash,
            hash_lock, 
            order.maker,
            ctx.sender(),
            amount as u256,
            safety_deposit_imm, 
            timelock,
            ctx
        );

        let id = immutables.id();
        // amount is the taking amount
        let dst_immutables = create_dst_immutables(order.reciever, taker_amount,  dst_token(extra_data), deposits & (u128::max_value!() as u256), dst_chain_id(extra_data));
        emit(SrcEscrowCreated {
            immutables_id: id,
            dst_immutables,
        }); 
        
        let safety_deposit = safety_deposit_coin.split((safety_deposit_imm >> 64) as u64, ctx);

        create_src_escrow(order.maker_asset.withdraw_all(), safety_deposit ,immutables,ctx);
        // transfer the safety_deposit_coin to the taker
        transfer::public_transfer(safety_deposit_coin, ctx.sender());
        token.destroy_none();
    } else {
        // if (order.taker_token.is_none() && token.is_none()) {
        //     abort EInvalidFusionOrder
        // };
        // let token =token.destroy_some();
        // token.split_and_transfer(taker_amount as u64, ctx.sender(), ctx);
        // // do maker => taker
        // // the do taker => maker
        abort 100
    }
}


/// takes the hash of the order
public fun order_hash<T, U>(order: &Order<T, U>): vector<u8>{
    let mut data = vector[];
    data.append(bcs::to_bytes(&order.maker_asset.value()));
    data.append(order.maker.to_bytes());
    data.append(bcs::to_bytes(&order.min_taker_amount));
    if (order.cross_chain){
        if (order.extra_data.is_some()) {
            let extra_data = order.extra_data.borrow();
            data.append(bcs::to_bytes(extra_data));
        } else {
            abort EInvalidFusionPlusOrder
        };
    };
    keccak256(&data)
}

public fun get_taker_amount(
    initial_maker_amount: u256,
    initial_taker_amount: u256, 
    maker_amount: u256,
    opt_data: Option<AuctionData>,
    clock: &Clock,
): u256 {
    let mut result = mul_div_ceil(initial_taker_amount, maker_amount, initial_maker_amount);
    if (opt_data.is_some()){
        let data = opt_data.borrow();
        let rate_bump = calculate_rate_bump(clock.timestamp_ms(), data) as u256;
        result = mul_div_ceil(result, BASE1_E7 + rate_bump, BASE1_E7)
    };
   return result
}


public fun get_fee_amounts(
    integrator_fee: u16,
    protocol_fee: u16,
    surplus_percentage: u8,
    dst_amount: u256,
    estimated_dst_amount: u256,
): (u256, u256,u256) {
    let integrator_fee_amount = mul_div_floor(dst_amount, integrator_fee as u256, BASE1_E7);
    let mut protocol_fee_amount = mul_div_floor(dst_amount, protocol_fee as u256, BASE1_E7);
    let actual_dst_amount = dst_amount - integrator_fee_amount - protocol_fee_amount;
    if (actual_dst_amount > estimated_dst_amount) {
        protocol_fee_amount =  protocol_fee_amount + mul_div_floor(actual_dst_amount - estimated_dst_amount, surplus_percentage as u256, BASE1_E2);
    };
    (integrator_fee_amount, protocol_fee_amount, actual_dst_amount)

}

