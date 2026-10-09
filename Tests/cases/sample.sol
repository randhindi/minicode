// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Confidential token (toy)
contract Token is ERC20 {
    mapping(address => uint256) private balances;
    event Transfer(address indexed from, address indexed to, uint256 amount);
    error InsufficientBalance(uint256 available);

    function transfer(address to, uint256 amount) external returns (bool) {
        if (balances[msg.sender] < amount) revert InsufficientBalance(balances[msg.sender]);
        unchecked { balances[msg.sender] -= amount; }
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
}
