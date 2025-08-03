#[test_only]
module fusion_plus_contracts::fusion_plus_tests;

use sui::balance;
use fusion_plus_contracts::fusion_protocol;
use fusion_plus_contracts::fusion_protocol::create_fee_config;
use sui::clock;
use std::option::none;
use sui::hash::keccak256;
use fusion_plus_contracts::immutables;
use fusion_plus_contracts::time_lock::create_timelock;
use sui::test_scenario::Scenario;
use sui::test_scenario;
use sui::test_scenario::ctx;
use sui::test_scenario::next_tx;
use fusion_plus_contracts::fusion_protocol::Order;
use sui::sui::SUI;
use sui::address;
use sui::test_scenario::return_shared;
use sui::test_scenario::take_shared;
use std::option::some;
use fusion_plus_contracts::escrow_src::FusionPlusSrcEscrow;
use sui::test_scenario::take_from_address;
use fusion_plus_contracts::escrow_src::{withdraw_to, public_withdraw};
use sui::coin::Coin;
use sui::test_scenario::return_to_address;
use fusion_plus_contracts::escrow_src::cancel;
use fusion_plus_contracts::escrow_src::resolver_cancel;
use std::debug::print;
use fusion_plus_contracts::escrow_dst::create_dst_escrow;
use sui::test_scenario::take_immutable;
use sui::test_scenario::return_immutable;
use std::bcs::to_bytes;
use std::bcs;

const ALICE: address = @0xa11ce;
const RESOLVER: address = @0x1234;
const PUBLIC_RESOLVER: address = @0x5678;

const DST_AMOUNT: u256 = 30;
const SRC_AMOUNT: u256 = 100; 

public struct SrcCoin has drop {}
public struct DstCoin has drop {}

const AUCION_DATA_BYTES : vector<u8> = x"0000000000000000007d00000000000050c300000000000002204e00000000000010270000000000001027000000000000204e000000000000";

fun test_scenario_init(sender: address): Scenario {
    let mut scenario = test_scenario::begin(sender);
    next_tx(&mut scenario, sender);
    scenario
}



fun test_order_create(): (vector<u8>, Scenario) {
    let init_balance = balance::create_for_testing<SrcCoin>(SRC_AMOUNT as u64);
    let mut scenario = test_scenario_init(ALICE);
    let secret= b"hello world";
    let hash_lock = keccak256(&secret);

    // === TIMELOCK CREATION CODE ===
    // import {TimeLocks} from "@1inch/cross-chain-sdk";
    // const timeLock = TimeLocks.new({
    //     srcWithdrawal: 60n, // 1m finality lock for test
    //     srcPublicWithdrawal: 120n, // 2m for private withdrawal
    //     srcCancellation: 121n, // 1sec public withdrawal
    //     srcPublicCancellation: 122n, // 1sec private cancellation
    //     dstWithdrawal: 0n, // no finality lock for test
    //     dstPublicWithdrawal: 120n, // 2m private withdrawal
    //     dstCancellation: 121n // 1sec public withdrawal
    // })
    // console.log(timeLock.build().toString()) // -> 759529310157168568903838870402235652103311276358706694979644
    
    let timelock = create_timelock(759529310157168568903838870402235652103311276358706694979644);
    let extra_data = immutables::create_extra_data(
        hash_lock,
        1,
        address::from_u256(0),
    timelock,
    0
    );
    // auction settings
    let time_deltas = vector[10000, 20000];
    let fill_time_stamp = time_deltas[0] + time_deltas[1] / 2;


    // order is created
    {
        let ctx = ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        clock.set_for_testing(100);
        let expiration_time = 1000000;
        let extra_data = bcs::to_bytes(&extra_data);
        fusion_protocol::create_cross_chain_order(init_balance.into_coin(ctx), DST_AMOUNT,  AUCION_DATA_BYTES, expiration_time, &clock, none(),  extra_data, ctx);
        clock.destroy_for_testing();
        // Drop ctx before next_tx to end the borrow
        let tx = next_tx(&mut scenario, RESOLVER);
        assert!(tx.num_user_events() == 1);
    };
    let mut order_hash = b"";
    
    // reciever fill
    {
        let mut order = take_shared<Order<SrcCoin, SUI>>(&scenario);
        order_hash = order.order_hash();
        assert!(order.is_cross_chain());
        assert!(order.reciever() == ALICE);
        let ctx = ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        // a thousand multiplier for the time as in ms for the fill logic
        clock.set_for_testing(fill_time_stamp * 1000);
        let sui = balance::create_for_testing(1000);
        order.fill_cross_chain_order(SRC_AMOUNT as u64, &clock, sui.into_coin(ctx), ctx);
        clock.destroy_for_testing();

        let tx = next_tx(&mut scenario, RESOLVER);
        assert!(tx.num_user_events() == 1);
        let escrow = take_shared<FusionPlusSrcEscrow<SrcCoin>>(&scenario);
        assert!(escrow.token_value() == SRC_AMOUNT as u64);
        return_shared(order);
        return_shared(escrow);
        next_tx(&mut scenario, RESOLVER); // Advance to next transaction
    };
    return (order_hash, scenario)
}


#[test, expected_failure]
public fun test_invalid_time_withdraw(){
    let (_order_hash, mut scenario) = test_order_create();
    // find escrow and immutables
    let secret= b"hello world";
    // auction settings
    let time_deltas = vector[10000, 20000];
    let fill_time_stamp = time_deltas[0] + time_deltas[1] / 2;

    let immutables = take_immutable<immutables::Immutables>(&scenario);
    let mut escrow = take_shared<FusionPlusSrcEscrow<SrcCoin>>(&scenario);
    // validate escrow
    assert!(immutables.hash() == escrow.immutables_hash()); 
    {
        let ctx = ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        clock.set_for_testing(fill_time_stamp * 1000);
        withdraw_to(RESOLVER, secret, &mut escrow, &immutables, &clock, ctx);
        next_tx(&mut scenario, RESOLVER);
        clock.destroy_for_testing();
    };
    return_immutable(immutables);  
    return_shared(escrow);
    scenario.end();
}


#[test, expected_failure]
public fun test_invalid_secret_withdraw(){
    let (_order_hash, mut scenario) = test_order_create();
    // find escrow and immutables
    let secret= b"wrong secret";
    // auction settings
    let time_deltas = vector[10000, 20000];
    let fill_time_stamp = time_deltas[0] + time_deltas[1] / 2;

    let immutables = take_immutable<immutables::Immutables>(&scenario);
    let mut escrow = take_shared<FusionPlusSrcEscrow<SrcCoin>>(&scenario);
    // validate escrow
    assert!(immutables.hash() == escrow.immutables_hash()); 
    {
        let ctx = ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        clock.set_for_testing(fill_time_stamp * 1000);
        withdraw_to(RESOLVER, secret, &mut escrow, &immutables, &clock, ctx);
        next_tx(&mut scenario, RESOLVER);
        clock.destroy_for_testing();
    };
    return_shared(escrow);
    return_immutable(immutables);  
    scenario.end();
}


#[test]
public fun test_valid_withdraw(){
    let (_order_hash, mut scenario) = test_order_create();
    // find escrow and immutables
    let secret= b"hello world";
    // auction settings
    let time_deltas = vector[10000, 20000];
    let fill_time_stamp = time_deltas[0] + time_deltas[1] / 2;

    let immutables = take_immutable<immutables::Immutables>(&scenario);
    let mut escrow = take_shared<FusionPlusSrcEscrow<SrcCoin>>(&scenario);
    // validate escrow
    assert!(immutables.hash() == escrow.immutables_hash()); 
    {
        let ctx = ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        clock.set_for_testing(fill_time_stamp * 1000 + 60 * 1000);
        withdraw_to(RESOLVER, secret, &mut escrow, &immutables, &clock, ctx);
        next_tx(&mut scenario, RESOLVER);

        let coin = take_from_address<Coin<SrcCoin>>(&scenario, RESOLVER);
        assert!(coin.value() == SRC_AMOUNT as u64);
        return_to_address(RESOLVER, coin);
        clock.destroy_for_testing();
    };
    return_shared(escrow);
    return_immutable(immutables);
    scenario.end();
}




#[test, expected_failure]
public fun test_invalid_public_withdraw(){
    let (_, mut scenario) = test_order_create();
    // find escrow and immutables
    let secret= b"hello world";
    // auction settings
    let time_deltas = vector[10000, 20000];
    let fill_time_stamp = time_deltas[0] + time_deltas[1] / 2;

    let immutables = take_immutable<immutables::Immutables>(&scenario);
    let mut escrow = take_shared<FusionPlusSrcEscrow<SrcCoin>>(&scenario);
    // validate escrow and withdraw before public withdraw starts at 2mins
    assert!(immutables.hash() == escrow.immutables_hash()); 
    {
        let ctx = ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        clock.set_for_testing(fill_time_stamp * 1000 + 60 * 1000);
         public_withdraw( secret, &mut escrow, &immutables, &clock, ctx);
        next_tx(&mut scenario, PUBLIC_RESOLVER);

        let coin = take_from_address<Coin<SrcCoin>>(&scenario, RESOLVER);
        assert!(coin.value() == SRC_AMOUNT as u64);
        return_to_address(PUBLIC_RESOLVER, coin);
        clock.destroy_for_testing();
    };
    return_shared(escrow);
    return_immutable(immutables);
    scenario.end();
}



#[test]
public fun test_valid_public_withdraw(){
    let (_order_hash, mut scenario) = test_order_create();
    // find escrow and immutables
    let secret= b"hello world";
    // auction settings
    let time_deltas = vector[10000, 20000];
    let fill_time_stamp = time_deltas[0] + time_deltas[1] / 2;

    let immutables = take_immutable<immutables::Immutables>(&scenario);
    let mut escrow = take_shared<FusionPlusSrcEscrow<SrcCoin>>(&scenario);
    // validate escrow and withdraw before public withdraw starts at 2mins
    assert!(immutables.hash() == escrow.immutables_hash()); 
    {
        let ctx = ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        // 120 - 2mins is the start of public withdraw
        clock.set_for_testing(fill_time_stamp * 1000 + 120 * 1000);
        public_withdraw( secret, &mut escrow, &immutables, &clock, ctx);
        next_tx(&mut scenario, PUBLIC_RESOLVER);

        let coin = take_from_address<Coin<SrcCoin>>(&scenario, RESOLVER);
        assert!(coin.value() == SRC_AMOUNT as u64);
        return_to_address(RESOLVER, coin);
        clock.destroy_for_testing();
    };
    return_shared(escrow);
        return_immutable(immutables);
    scenario.end();
}



#[test]
public fun test_cancel_by_resolver(){
    let (order_hash, mut scenario) = test_order_create();
    // find escrow and immutables
    let secret= b"hello world";
    let hash_lock = keccak256(&secret);
    let timelock = create_timelock(759529310157168568903838870402235652103311276358706694979644);
    // auction settings
    let time_deltas = vector[10000, 20000];
    let fill_time_stamp = time_deltas[0] + time_deltas[1] / 2;

    let immutables = take_immutable<immutables::Immutables>(&scenario);
    print(&immutables);
    print(&immutables.maker().to_bytes());
    let mut escrow = take_shared<FusionPlusSrcEscrow<SrcCoin>>(&scenario);
    // validate escrow and withdraw before public withdraw starts at 2mins
    assert!(immutables.hash() == escrow.immutables_hash()); 
    {
        let ctx = ctx(&mut scenario);
        let mut clock = clock::create_for_testing(ctx);
        // 121 - 1 sec after public withdraw
        clock.set_for_testing(fill_time_stamp * 1000 + 121 * 1000);
        resolver_cancel(&immutables,&mut escrow,  &clock, ctx);
        next_tx(&mut scenario, RESOLVER);
        // coin should have returned back to ALICE i.e the maker
        let coin = take_from_address<Coin<SrcCoin>>(&scenario, ALICE);
        assert!(coin.value() == SRC_AMOUNT as u64);
        return_to_address(ALICE, coin);
        clock.destroy_for_testing();
    };
    return_shared(escrow);
    return_immutable(immutables);
    scenario.end();
}

const DST_IMMUTABLES: vector<u8> = x"210047173285a8d7341e5e972fc677286384f802f8ef42a5ec5f03bbfa254cb01fad00000000000000000000000000000000000000000000000000000000000a11ce1e000000000000003c00000078000000790000007a000000000000007800000079000000204e0000e803000000000000";

#[test]
public fun test_create_dst_escrow(): Scenario{
    let mut scenario = test_scenario_init(RESOLVER);
    let token = balance::create_for_testing<DstCoin>(DST_AMOUNT as u64);
    let safety_deposit = balance::create_for_testing<SUI>(1000);
    let ctx = ctx(&mut scenario);
    create_dst_escrow(token.into_coin(ctx), safety_deposit.into_coin(ctx), DST_IMMUTABLES, ctx);
    scenario.next_tx(RESOLVER);
    return scenario
}
