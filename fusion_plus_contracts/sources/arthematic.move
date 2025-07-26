module fusion_plus_contracts::arthematic;


public(package) fun mul_div_floor(
    a: u256,
    b: u256,
    denominator: u256,
) : u256 {
    let product = (a)* (b);
    let qoutient = product / (denominator);
    return qoutient 
}



public(package) fun mul_div_ceil(
    a: u256,
    b: u256,
    denominator: u256,
) : u256 {
    let product = a * b;
    let qoutient = product / denominator; 
    let remainder = product % denominator;

    if (remainder == 0) {
        return qoutient 
    };
    return (qoutient + 1) 
}