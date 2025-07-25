
// Similar to the `DuctionAuctionExtension` contract calculates decay of value over time
module fusion_plus_contracts::dutch_auction;


use sui::bcs;

public struct PointAndTimeDelta has store, copy, drop {
    rate_bump: u64,
    time_delta: u64,
}

public struct AuctionData has store, copy, drop {
    start_time: u64,
    duration: u64,
    initial_rate_bump: u64,
    point_and_time_deltas: vector<PointAndTimeDelta>,
}

public fun from_bytes(
    bytes: vector<u8>,
): AuctionData {
    let mut bcs = bcs::new(bytes);
    let (start_time, duration, initial_rate_bump) = (
        bcs.peel_u64(),
        bcs.peel_u64(),
        bcs.peel_u64(),
    );
    let mut len = bcs.peel_vec_length();
    let mut vec = vector[];
    while (len > 0){
        let (rate_bump, time_delta) = (
            bcs.peel_u64(),
            bcs.peel_u64(),
        );
        vec.push_back(PointAndTimeDelta{rate_bump, time_delta});
        len = len - 1;
    };
    AuctionData {
        start_time,
        duration,
        initial_rate_bump,
        point_and_time_deltas: vec
    }
}

public fun create_auction_data(
    start_time: u64,
    duration: u64,
    initial_rate_bump: u64,
    rate_bumps: vector<u64>,
    time_deltas: vector<u64>,
): AuctionData {
    let point_and_time_deltas = rate_bumps.zip_map!(time_deltas, |rate_bump, time_delta| PointAndTimeDelta{rate_bump, time_delta});
    let auction_data = AuctionData {
        start_time,
        duration,
        initial_rate_bump,
        point_and_time_deltas
    };
    auction_data
}

public fun calculate_rate_bump(
    timestamp: u64,
    data: &AuctionData,
) : u64 {
    if (timestamp <= data.start_time) {
        return data.initial_rate_bump
    };

    let auction_finish_time = data.start_time + data.duration;

    if (timestamp >= auction_finish_time) {
            return 0
    };

    let mut current_rate_bump = data.initial_rate_bump;
    let mut current_point_time = data.start_time;

    let mut idx = 0;

    while (idx < data.point_and_time_deltas.length()) {
        let point_time_delta = &data.point_and_time_deltas[idx];
        let next_rate_bump = point_time_delta.rate_bump;
        let point_time_delta = point_time_delta.time_delta;
        let next_point_time = current_point_time + point_time_delta;

        if (timestamp <= next_point_time){
            return ((timestamp - current_point_time) * next_rate_bump + (next_point_time - timestamp) * current_rate_bump) / point_time_delta
        };

        current_rate_bump = next_rate_bump;
        current_point_time = next_point_time;

        idx = idx + 1;
    };

    return current_rate_bump * ((auction_finish_time - timestamp) / (auction_finish_time - current_point_time))

}

public fun calculate_premium(timestamp: u64, auction_start_time: u64, auction_duration: u64, max_cancellation_premium: u64): u64 {
    if (timestamp <= auction_start_time){
        return 0
    };

    let time_elapsed = timestamp - auction_start_time;
    if (time_elapsed >= auction_duration) {
        return max_cancellation_premium
    };

    (time_elapsed * max_cancellation_premium) / auction_duration
   
}