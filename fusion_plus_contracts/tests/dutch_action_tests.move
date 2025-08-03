#[test_only]
module fusion_plus_contracts::dutch_action_tests;

use sui::test_scenario;
use fusion_plus_contracts::dutch_auction::create_auction_data;
use sui::clock;
use std::unit_test::assert_eq;
use fusion_plus_contracts::fusion_protocol::get_taker_amount;
use std::option::some;
use std::debug::print;

const BASE_POINTS: u64 = 10000000;

const ALICE: address = @0xa11ce;
const RESOLVER: address = @0x1234;

const DST_AMOUNT: u256 = 3000;
const SRC_AMOUNT: u256 = 100; 


#[test]
fun test_dutch_action() {
    let mut scenario = test_scenario::begin(ALICE);
    let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock.set_for_testing(0);
    let initial_rate_bump = 84909; // 0.5%
    let rate_bumps = vector[63932, 34485];
    let time_deltas = vector[12000, 60000]; // 12s, 60s
    let duration = 180000;
    let auction_data = create_auction_data(
        100, // auction id
        duration,
        initial_rate_bump,
        rate_bumps,
        time_deltas
    );

    print(&auction_data);

    let dst_amount = get_taker_amount(SRC_AMOUNT, DST_AMOUNT, SRC_AMOUNT, some(auction_data), &clock);
    print(&dst_amount);
    // should fill with initialRateBump before auction started
    {
        let dst_amount_that_should_be = (DST_AMOUNT * ((initial_rate_bump + BASE_POINTS) as u256)) / (BASE_POINTS as u256);
        print(&dst_amount_that_should_be);
        assert!(dst_amount > dst_amount_that_should_be);
    };
    // // should fill with another price after auction started, but before first point
    {
        clock.increment_for_testing(time_deltas[0]/2);
        let dst_with_max_rate_bump = (DST_AMOUNT * ((initial_rate_bump + BASE_POINTS) as u256)) / (BASE_POINTS as u256);
        let dst_wtih_rate_bump_min = (DST_AMOUNT * (( rate_bumps[0] + BASE_POINTS) as u256)) / (BASE_POINTS as u256);
        let dst_amount = get_taker_amount(SRC_AMOUNT, DST_AMOUNT, SRC_AMOUNT, some(auction_data), &clock);
        print(&dst_with_max_rate_bump);
        print(&dst_wtih_rate_bump_min);
        print(&dst_amount);
        assert!(dst_amount <= dst_with_max_rate_bump);
        assert!(dst_amount >= dst_wtih_rate_bump_min);
    };

    // should fill with another price after between points
    {
        clock.increment_for_testing((time_deltas[1] + time_deltas[0]) / 2 );
        let dst_with_max_rate_bump = (DST_AMOUNT * ((initial_rate_bump + BASE_POINTS) as u256)) / (BASE_POINTS as u256);
        let dst_wtih_rate_bump_min = (DST_AMOUNT * (( rate_bumps[1] + BASE_POINTS) as u256)) / (BASE_POINTS as u256); 
        let dst_amount = get_taker_amount(SRC_AMOUNT, DST_AMOUNT, SRC_AMOUNT, some(auction_data), &clock);
        print(&dst_with_max_rate_bump);
        print(&dst_wtih_rate_bump_min);
        print(&dst_amount);
        assert!(dst_amount <= dst_with_max_rate_bump);
        assert!(dst_amount >= dst_wtih_rate_bump_min);
    };
    // should fill with default price after auction finished
    {
        clock.increment_for_testing(time_deltas[1] / 2 + duration + 1);
        let dst_amount = get_taker_amount(SRC_AMOUNT, DST_AMOUNT, SRC_AMOUNT, some(auction_data), &clock);
        print(&dst_amount);
        assert!(dst_amount == DST_AMOUNT)
    };
    clock.destroy_for_testing();
    scenario.end();
}

