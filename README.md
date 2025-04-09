# Token Locking Smart Contract on Ronin Network (LockTokens)

## Overview

LockTokens is a Solidity smart contract designed to provide secure token locking functionality on the blockchain. It allows users to lock their ERC20 tokens for a specified period of time, helping to demonstrate long-term commitment to projects, promote token stability, and provide vesting mechanisms.

## Core Features

- **Token Locking**: Lock any ERC20 token for a specified period
- **Time-Based Unlocking**: Tokens automatically become available for withdrawal once the lock period expires
- **Lock Extension**: Extend the lock period for existing locked tokens
- **Pagination Support**: Efficiently query locked tokens information even with large datasets
- **User Management**: Keep track of all users who have locked a specific token

## Key Functions

### For Token Holders

- `lockTokens(address _token, uint256 _amount, uint8 _months)`: Lock tokens for a specified period
- `withdrawTokens(uint256 _lockIndex)`: Withdraw tokens after the lock period expires
- `extendLock(uint256 _lockIndex, uint8 _additionalMonths)`: Extend an existing lock period
- `getRemainingLockTime(address _user, uint256 _lockIndex)`: Check remaining time on a lock

### For Data Queries

- `getUserLocksPaginated()`: View all locks for a specific user with pagination
- `getUsersForTokenPaginated()`: Get all users who have locked a specific token with pagination
- `getUserTokenLocksPaginated()`: Get all locks for a specific user and token with pagination

### For Contract Owner

- `setFeeAddress(address _newFeeAddress)`: Update the fee collection address
- `setTesterAddress(address _newTesterAddress)`: Update the tester address

## Technical Details

- Built on Solidity 0.8.29
- Uses OpenZeppelin's SafeERC20 for secure token transfers
- Implements reentrancy protection for enhanced security
- Efficient O(1) operations for user tracking
- Token verification to ensure only proper ERC20 tokens can be locked

## Fees

The contract charges nominal fees for its services:
- Token Locking Fee: 1 ETH
- Lock Extension Fee: 10 ETH

Fees are collected in the contract and can be withdrawn by the designated fee address.

## Events

The contract emits the following events:
- `TokensLocked`: When tokens are successfully locked
- `TokensWithdrawn`: When tokens are withdrawn after the lock period
- `LockExtended`: When a lock period is extended

## Use Cases

- Project team token vesting
- Liquidity provider commitment
- Staking with time locks
- Investor confidence building
- Protocol governance voting rights
