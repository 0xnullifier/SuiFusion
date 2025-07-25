#[test_only]
module fusion_plus_contracts::dutch_action_tests;

use sui::test_scenario;
use fusion_plus_contracts::dutch_auction::create_auction_data;
use sui::clock;
use std::unit_test::assert_eq;
use fusion_plus_contracts::fusion_protocol::get_taker_amount;
use std::option::some;
use std::debug::print;

const BASE_POINTS: u64 = 100000000;

const ALICE: address = @0xa11ce;
const RESOLVER: address = @0x1234;

const DST_AMOUNT: u256 = 9747406676438;
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

    // let auction_data = create_auction_data(0, duration, initial_rate_bump, rate_bumps, time_deltas);
    // let auction_data_bytes = vector[181,23,140,104,0,0,0,0,180,0,0,0,0,0,0,0,173,75,1,0,0,0,0,0,2,188,249,0,0,0,0,0,0,120,0,0,0,0,0,0,0,181,134,0,0,0,0,0,0,60,0,0,0,0,0,0,0];
    // let auction_data = fusion_plus_contracts::dutch_auction::from_bytes(auction_data_bytes);
    // print(&auction_data);

    // let extra_data_bytes = vector[32,150,12,128,90,132,238,17,225,168,82,80,135,7,162,11,22,163,239,87,9,164,81,100,166,150,245,21,220,64,156,125,52,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,192,42,170,57,178,35,254,141,10,14,92,79,39,234,217,8,60,117,108,194,0,0,0,0,0,0,0,0,0,0,0,0,5,0,0,0,120,0,0,0,180,0,0,0,240,0,0,0,0,0,0,0,120,0,0,0,180,0,0,0,0,0,0,0,0,128,198,164,126,141,3,0,0,0,0,0,0,0,0,0,64,66,15,0,0,0,0,0,0,0,0,0,0,0,0,0];
    // let extra_data = fusion_plus_contracts::immutables::extra_data_from_bytes(extra_data_bytes);
    // print(&extra_data);
    // should deserialize correctly from auction_data
    // {
    //     let bytes = x"0000000000000000007d00000000000050c300000000000002204e00000000000010270000000000001027000000000000204e000000000000";
    //     let auction_data_from_bytes = fusion_plus_contracts::dutch_auction::from_bytes(bytes);
    //     assert_eq!(auction_data_from_bytes, auction_data);
    // };

    let dst_amount = get_taker_amount(SRC_AMOUNT, DST_AMOUNT, SRC_AMOUNT, some(auction_data), &clock);
    // should fill with initialRateBump before auction started
    {
        let dst_amount_that_should_be = (DST_AMOUNT * ((initial_rate_bump + BASE_POINTS) as u256)) / (BASE_POINTS as u256);
        assert_eq!(dst_amount ,dst_amount_that_should_be);
    };
    // // should fill with another price after auction started, but before first point
    // {
    //     clock.increment_for_testing(time_deltas[0]/2);
    //     let dst_with_max_rate_bump = (DST_AMOUNT * ((initial_rate_bump + BASE_POINTS) as u256)) / (BASE_POINTS as u256);
    //     let dst_wtih_rate_bump_min = (DST_AMOUNT * (( rate_bumps[0] + BASE_POINTS) as u256)) / (BASE_POINTS as u256);
    //     let dst_amount = get_taker_amount(SRC_AMOUNT, DST_AMOUNT, SRC_AMOUNT, some(auction_data), &clock);
    //     assert!(dst_amount <= dst_with_max_rate_bump);
    //     assert!(dst_amount >= dst_wtih_rate_bump_min);
    // };

    // // should fill with another price after between points
    // {
    //     clock.increment_for_testing((time_deltas[1] + time_deltas[0]) / 2 );
    //     let dst_with_max_rate_bump = (DST_AMOUNT * ((initial_rate_bump + BASE_POINTS) as u256)) / (BASE_POINTS as u256);
    //     let dst_wtih_rate_bump_min = (DST_AMOUNT * (( rate_bumps[1] + BASE_POINTS) as u256)) / (BASE_POINTS as u256); 
    //     let dst_amount = get_taker_amount(SRC_AMOUNT, DST_AMOUNT, SRC_AMOUNT, some(auction_data), &clock);
    //     assert!(dst_amount <= dst_with_max_rate_bump);
    //     assert!(dst_amount >= dst_wtih_rate_bump_min);
    // };
    // // should fill with default price after auction finished
    // {
    //     clock.increment_for_testing(time_deltas[1] / 2 + duration + 1);
    //     let dst_amount = get_taker_amount(SRC_AMOUNT, DST_AMOUNT, SRC_AMOUNT, some(auction_data), &clock);
    //     assert!(dst_amount == DST_AMOUNT)
    // };
    clock.destroy_for_testing();
    scenario.end();
}

