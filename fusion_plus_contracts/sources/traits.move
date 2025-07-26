/// ports the functionality of `makerTraits` and `takerTraits`
/// only traits relevant to the sui flow are included/exposed
module fusion_plus_contracts::traits;

use sui::clock::Clock;

/// ------ MAKER TRAITS ------
const ALLOWED_SENDER_MASK : u256= 0xffffffffffffffffffff;
const EXPIRATION_OFFSET : u8= 80;
const EXPIRATION_MASK : u256= 0xffffffffff;
const NONCE_OR_EPOCH_OFFSET : u8= 120;
const NONCE_OR_EPOCH_MASK : u256= 0xffffffffff;
const SERIES_OFFSET : u8= 160;
const SERIES_MASK : u256= 0xffffffffff;
const NO_PARTIAL_FILLS_FLAG : u256= 1 << 255;
const ALLOW_MULTIPLE_FILLS_FLAG : u256= 1 << 254;
const PRE_INTERACTION_CALL_FLAG : u256= 1 << 252;
const POST_INTERACTION_CALL_FLAG : u256= 1 << 251;
const NEED_CHECK_EPOCH_MANAGER_FLAG : u256= 1 << 250;
// const HAS_EXTENSION_FLAG : u256= 1 << 249;
// const USE_PERMIT2_FLAG : u256= 1 << 248;
// const UNWRAP_WETH_FLAG : u256= 1 << 247;

public fun is_allowed_sender(maker_traits: u256, sender: address) :bool {
    let allowedSender = (maker_traits >> 160) & ALLOWED_SENDER_MASK;
    return allowedSender == 0 || allowedSender == (sender.to_u256() >> 160) & ALLOWED_SENDER_MASK
}

public fun get_expiration_time(maker_traits: u256): u256{
    return (maker_traits >> EXPIRATION_OFFSET) & EXPIRATION_MASK
}

public fun is_expired(maker_traits: u256, clock: &Clock): bool {
    let expiration_time = get_expiration_time(maker_traits);
    let clock_time = (clock.timestamp_ms() / 1000) as u256;
    return expiration_time != 0 && clock_time > expiration_time
}

public fun nonce_or_epoch(maker_traits: u256): u256 {
    return (maker_traits >> NONCE_OR_EPOCH_OFFSET) & NONCE_OR_EPOCH_MASK
}

public fun series(maker_traits: u256): u256 {
    return (maker_traits >> SERIES_OFFSET) & SERIES_MASK
}

public fun allow_partial_fills(maker_traits: u256): bool {
    return (maker_traits & NO_PARTIAL_FILLS_FLAG) == 0
}

public fun allow_multiple_fills(maker_traits: u256): bool {
    return (maker_traits & ALLOW_MULTIPLE_FILLS_FLAG) != 0
}

public fun use_bit_invalidator(maker_traits: u256): bool {
    !allow_multiple_fills(maker_traits) || !allow_partial_fills(maker_traits)
}

public fun need_epoch_manager_check(maker_traits: u256): bool {
    return (maker_traits & NEED_CHECK_EPOCH_MANAGER_FLAG) != 0
}

public fun needPostInteractionCall(maker_traits: u256): bool {
    return (maker_traits &  POST_INTERACTION_CALL_FLAG) != 0
}

public fun needPreInteractionCall(maker_traits: u256): bool {
    return (maker_traits & PRE_INTERACTION_CALL_FLAG) != 0
}



/// ------ TAKER TRAITS ------
const MAKER_AMOUNT_FLAG: u256 = 1 << 255;
// const UNWRAP_WETH_FLAG: u256 = 1 << 254;
// const SKIP_ORDER_PERMIT_FLAG: u256 = 1 << 253;
// const USE_PERMIT2_FLAG: u256 = 1 << 252;
const ARGS_HAS_TARGET: u256 = 1 << 251;

// const ARGS_EXTENSION_LENGTH_OFFSET: u8 = 224;
// const ARGS_EXTENSION_LENGTH_MASK: u256 = 0xffffff;
// const ARGS_INTERACTION_LENGTH_OFFSET: u8 = 200;
// const ARGS_INTERACTION_LENGTH_MASK: u256 = 0xffffff;

const AMOUNT_MASK: u256 = 0x000000000000000000ffffffffffffffffffffffffffffffffffffffffffffff;


public fun args_has_target(taker_traits: u256): bool {
    return (taker_traits & ARGS_HAS_TARGET) != 0
}

// not required in sui side of things
// public fun get_extension_length(taker_traits: u256): u256 {
//     return (taker_traits >> ARGS_EXTENSION_LENGTH_OFFSET) & ARGS_EXTENSION_LENGTH_MASK
// }

// not required in sui side of things
// public fun get_interaction_length(taker_traits: u256): u256 {
//     return (taker_traits >> ARGS_INTERACTION_LENGTH_OFFSET) & ARGS_INTERACTION_LENGTH_MASK
// }

public fun is_making_amount(taker_traits: u256): bool {
    return (taker_traits & MAKER_AMOUNT_FLAG) != 0
}

public fun threshold(taker_traits: u256): u256 {
    return (taker_traits & AMOUNT_MASK)
}
