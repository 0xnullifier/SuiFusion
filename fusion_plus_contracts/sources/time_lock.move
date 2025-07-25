/// creates a onchain `TimeLock`
module fusion_plus_contracts::time_lock;

/// We can't do negation in Move, so already negate the mask
const DEPLOYED_AT_MASK_NEGATED: u256 = 0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
const DEPLOYED_AT_OFFSET : u8 = 224;
const BIT_MASK_32: u256 = 0xffffffff;


public struct TimeLock has copy, store, drop {
    inner: u256
}

public enum Stage has copy, store, drop{
    SrcWithdrawal,
    SrcPublicWithdrawal,
    SrcCancellation,
    SrcPublicCancellation,
    DstWithdrawal,
    DstPublicWithdrawal,
    DstCancellation
}


/// creates a `TimeLock` object with the given value
public fun create_timelock(value: u256): TimeLock {
    let timelock = TimeLock {
        inner: value,
    };
    return timelock
}

/// set the deployed at value of the `TimeLock` object and returns a new `TimeLock` object
public fun set_deployed_at(timelock: &TimeLock, value: u64) : TimeLock{
    let new_inner = timelock.inner & (DEPLOYED_AT_MASK_NEGATED) | ((value as u256) << DEPLOYED_AT_OFFSET);
    TimeLock {
        inner: new_inner
    }
}

/// returns the rescue start for the timelock object
public fun rescue_start(timelock: &TimeLock, rescue_delay: u64): u64 {
    return rescue_delay + ((timelock.inner >> DEPLOYED_AT_OFFSET) as u64)
}

public(package) fun stage(number: u8): Stage {
    match (number) {
        0 => Stage::SrcWithdrawal,
        1 => Stage::SrcPublicWithdrawal,
        2 => Stage::SrcCancellation,
        3 => Stage::SrcPublicCancellation,
        4 => Stage::DstWithdrawal,
        5 => Stage::DstPublicWithdrawal,
        _ => Stage::DstCancellation,
    }
}

/// returns the timing at a particular `Stage`
public fun get(timelock: &TimeLock,  stage: Stage): u64{
    let bitshift = 32 * (match (stage) {
        Stage::SrcWithdrawal => 0,
        Stage::SrcPublicWithdrawal => 1,
        Stage::SrcCancellation => 2,
        Stage::SrcPublicCancellation => 3,
        Stage::DstWithdrawal => 4,
        Stage::DstPublicWithdrawal => 5,
        Stage::DstCancellation => 6,
    });
    // safe cast as timelock.inner >> DEPLOYED_AT_OFFSET is always less than a u32
    return ((timelock.inner >> DEPLOYED_AT_OFFSET) as u64) + (((timelock.inner >> bitshift) & BIT_MASK_32) as u64)
}

