pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./lib/ReentrancyGuard.sol";

contract LockTokens is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Lock {
        address token;
        uint256 amount;
        uint256 unlockTime;
        uint8 decimals;
    }

    struct LockInfo {
        address token;
        address owner;
        uint256 amount;
        uint8 decimals;
        uint256 unlockTime;
        uint256 remainingTime;
    }

    mapping(address => Lock[]) public userLocks;
    mapping(address => uint256) public pendingFees;
    mapping(address => address[]) public tokenUsers;
    mapping(address => mapping(address => uint256)) public userLockedTokenCount;
    mapping(address => mapping(address => uint256)) private tokenUserIndices;

    uint256 constant MINUTE = 1 minutes;
    uint256 constant MONTH = 30 days;
    uint256 constant MAX_MONTHS_LOCK = 120;
    uint256 constant PAGINATE_SIZE = 25;

    address public owner;
    address public feeAddress;
    address public testerAddress;
    uint256 public lockFee = 1 ether;
    uint256 public extendLockFee = 10 ether;

    event TokensLocked(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 unlockTime
    );
    event TokensWithdrawn(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event LockExtended(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 newUnlockTime
    );

   constructor(address _feeAddress, address _testerAddress) {
        require(_feeAddress != address(0), "Invalid fee address");
        require(_testerAddress != address(0), "Invalid tester address");
        
        owner = msg.sender;
        feeAddress = _feeAddress;
        testerAddress = _testerAddress;
    }

    /**
    * @notice Add a user to tokenUsers with index tracking
    * @param _token Address of the token
    * @param _user Address of the user to add
    */
    function addUserToTokenUsers(address _token, address _user) internal {
        if (userLockedTokenCount[_token][_user] == 0) {
            tokenUserIndices[_token][_user] = tokenUsers[_token].length;
            tokenUsers[_token].push(_user);
        }
        userLockedTokenCount[_token][_user]++;
    }

    /**
    * @notice Remove a user from the list of users for a token - O(1) operation
    * @param _token Address of the token
    * @param _user Address of the user
    */
    function removeUserFromTokenUsers(address _token, address _user) internal {
        uint256 index = tokenUserIndices[_token][_user];
        uint256 lastIndex = tokenUsers[_token].length - 1;
        
        if (index != lastIndex) {
            address lastUser = tokenUsers[_token][lastIndex];
            tokenUsers[_token][index] = lastUser;
            tokenUserIndices[_token][lastUser] = index;
        }
        
        tokenUsers[_token].pop();
        delete tokenUserIndices[_token][_user];
    } 
    /**
     * @notice Verify token implements ERC20 interface
     * @param _token Address of the token to verify
     */
    function _verifyToken(address _token) internal view returns (uint8) {
        require(_token != address(0), "Invalid token address");
        require(_token.code.length > 0, "Token must be a contract");
        
        try IERC20Metadata(_token).symbol() returns (string memory) {} catch {
            revert("Token must implement symbol()");
        }
        try IERC20Metadata(_token).name() returns (string memory) {} catch {
            revert("Token must implement name()");
        }
        uint8 decimals;
        try IERC20Metadata(_token).decimals() returns (uint8 dec) {
            decimals = dec;
        } catch {
            revert("Token must implement decimals()");
        }
        
        return decimals;
    }

    /**
     * @notice Update fee address
     * @param _newFeeAddress New fee address
     */
    function setFeeAddress(address _newFeeAddress) external {
        require(msg.sender == owner, "Only owner can set fee address");
        require(_newFeeAddress != address(0), "Invalid fee address");
        feeAddress = _newFeeAddress;
    }
    
    /**
     * @notice Update tester address
     * @param _newTesterAddress New tester address
     * Note: Only tester can lock for 1 minute
     */
    function setTesterAddress(address _newTesterAddress) external {
        require(msg.sender == owner, "Only owner can set tester address");
        require(_newTesterAddress != address(0), "Invalid tester address");
        testerAddress = _newTesterAddress;
    }

    /**
     * @notice Lock tokens for a specified period
     * @param _token Address of the ERC20 token
     * @param _amount Amount of tokens to lock
     * @param _months Number of months to lock (0 for minute, 1-120 for months)
     */
    function lockTokens(
        address _token,
        uint256 _amount,
        uint8 _months
    ) external payable nonReentrant {
        require(msg.value >= lockFee, "Insufficient payment");
        uint8 tokenDecimals = _verifyToken(_token);
        require(_amount > 0, "Amount must be greater than 0");
        require(_months <= MAX_MONTHS_LOCK, "Maximum lock time is 120 months");
        
        if (msg.sender != testerAddress) {
            require(_months > 0, "Months must be greater than 0");
        }

        uint256 unlockTime = calculateUnlockTime(_months);

        pendingFees[feeAddress] += msg.value;

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        userLocks[msg.sender].push(
            Lock({
                token: _token, 
                amount: _amount, 
                unlockTime: unlockTime, 
                decimals: tokenDecimals
            })
        );

        addUserToTokenUsers(_token, msg.sender);

        emit TokensLocked(msg.sender, _token, _amount, unlockTime);
    }

    /**
     * @notice Withdraw locked tokens after lock period
     * @param _lockIndex Index of the lock in user's locks array
     */
    function withdrawTokens(uint256 _lockIndex) external nonReentrant {
        require(
            _lockIndex < userLocks[msg.sender].length,
            "Invalid lock index"
        );

        Lock storage userLock = userLocks[msg.sender][_lockIndex];
        require(
            block.timestamp >= userLock.unlockTime,
            "Tokens are still locked"
        );
        require(userLock.amount > 0, "Already withdrawn");

        uint256 amount = userLock.amount;
        address token = userLock.token;

        IERC20(token).safeTransfer(msg.sender, amount);

        uint256 lastIndex = userLocks[msg.sender].length - 1;
        if (_lockIndex != lastIndex) {
            userLocks[msg.sender][_lockIndex] = userLocks[msg.sender][lastIndex];
        }
        userLocks[msg.sender].pop();

        userLockedTokenCount[token][msg.sender]--;
        if (userLockedTokenCount[token][msg.sender] == 0) {
            removeUserFromTokenUsers(token, msg.sender);
        }

        emit TokensWithdrawn(msg.sender, token, amount);
    }

    /**
    * @notice Extend the lock period of an existing lock
    * @param _lockIndex Index of the lock to extend
    * @param _additionalMonths Additional months to extend the lock
    */
    function extendLock(uint256 _lockIndex, uint8 _additionalMonths) external payable nonReentrant {
        require(msg.value >= extendLockFee, "Insufficient payment");
        require(_lockIndex < userLocks[msg.sender].length, "Invalid lock index");
        require(_additionalMonths > 0 && _additionalMonths <= MAX_MONTHS_LOCK, "Invalid additional months");
        
        Lock storage userLock = userLocks[msg.sender][_lockIndex];
        require(userLock.amount > 0, "Lock is empty");
        require(block.timestamp < userLock.unlockTime, "Lock already expired");
        
        uint256 additionalDuration = _additionalMonths * MONTH;
        
        pendingFees[feeAddress] += msg.value;
        
        userLock.unlockTime += additionalDuration;
        emit LockExtended(msg.sender, userLock.token, userLock.amount, userLock.unlockTime);
    }

    /**
     * @notice Get remaining lock time
     * @param _user Address of the user
     * @param _lockIndex Index of the lock
     * @return uint256 Remaining time in seconds, 0 if unlocked
     */
    function getRemainingLockTime(
        address _user,
        uint256 _lockIndex
    ) public view returns (uint256) {
        require(_lockIndex < userLocks[_user].length, "Invalid lock index");
        Lock storage userLock = userLocks[_user][_lockIndex];

        if (block.timestamp >= userLock.unlockTime || userLock.amount == 0) {
            return 0;
        }

        return userLock.unlockTime - block.timestamp;
    }

    /**
     * @notice Calculate unlock time based on months
     * @param _months Number of months (0 for minute, 1-120 for months)
     * @return uint256 Unlock timestamp
     */
    function calculateUnlockTime(uint8 _months) internal view returns (uint256) {
        if (_months == 0) {
            return block.timestamp + MINUTE;
        }
        return block.timestamp + (_months * MONTH);
    }

    /**
     * @notice Get all locks for a specific user with pagination
     * @param _user Address of the user
     * @param _startIndex Starting index for pagination
     * @param _pageSize Number of locks to return (max PAGINATE_SIZE)
     * @return LockInfo[] Array of lock information for the specified user
     * @return uint256 Total number of locks for this user
     * @return uint256 Next index for pagination, returns 0 if no more locks
     */
    function getUserLocksPaginated(
        address _user,
        uint256 _startIndex,
        uint256 _pageSize
    ) external view returns (LockInfo[] memory, uint256, uint256) {
        require(_user != address(0), "Invalid user address");
        require(_pageSize > 0 && _pageSize <= PAGINATE_SIZE, "Invalid page size");
        
        Lock[] memory userLockArray = userLocks[_user];
        uint256 totalLocks = userLockArray.length;
        
        if (totalLocks == 0 || _startIndex >= totalLocks) {
            return (new LockInfo[](0), totalLocks, 0);
        }
        
        uint256 remainingLocks = totalLocks - _startIndex;
        uint256 actualPageSize = remainingLocks < _pageSize ? remainingLocks : _pageSize;
        
        LockInfo[] memory lockInfos = new LockInfo[](actualPageSize);
        uint256 includedLocks = 0;
        
        for (uint256 j = _startIndex; j < totalLocks && includedLocks < actualPageSize; j++) {
            uint256 remaining = 0;
            if (block.timestamp < userLockArray[j].unlockTime && userLockArray[j].amount > 0) {
                remaining = userLockArray[j].unlockTime - block.timestamp;
            }
            
            lockInfos[includedLocks] = LockInfo({
                token: userLockArray[j].token,
                owner: _user,
                amount: userLockArray[j].amount,
                decimals: userLockArray[j].decimals,
                unlockTime: userLockArray[j].unlockTime,
                remainingTime: remaining
            });
            
            includedLocks++;
        }
        
        uint256 nextIndex = _startIndex + actualPageSize < totalLocks ? _startIndex + actualPageSize : 0;
        
        return (lockInfos, totalLocks, nextIndex);
    }

  /**
     * @notice Get users who have locked a specific token with pagination
     * @param _token Address of the token
     * @param _startIndex Starting index for pagination
     * @param _pageSize Number of users to return (max PAGINATE_SIZE)
     * @return address[] Array of user addresses who have locked this token
     * @return uint256 Total number of users for this token
     * @return uint256 Next index for pagination, returns 0 if no more users
     */
    function getUsersForTokenPaginated(
        address _token,
        uint256 _startIndex,
        uint256 _pageSize
    ) external view returns (address[] memory, uint256, uint256) {
        require(_token != address(0), "Invalid token address");
        require(_pageSize > 0 && _pageSize <= PAGINATE_SIZE, "Invalid page size");
        
        uint256 totalUsers = tokenUsers[_token].length;
        
        if (totalUsers == 0 || _startIndex >= totalUsers) {
            return (new address[](0), totalUsers, 0);
        }
        
        uint256 remainingUsers = totalUsers - _startIndex;
        uint256 actualPageSize = remainingUsers < _pageSize ? remainingUsers : _pageSize;
        
        address[] memory users = new address[](actualPageSize);
        
        for (uint256 i = 0; i < actualPageSize; i++) {
            users[i] = tokenUsers[_token][_startIndex + i];
        }
        
        uint256 nextIndex = _startIndex + actualPageSize < totalUsers ? _startIndex + actualPageSize : 0;
        
        return (users, totalUsers, nextIndex);
    }

    /**
     * @notice Get all locks for a specific user and token with pagination
     * @param _user Address of the user
     * @param _token Address of the token
     * @param _startIndex Starting index for pagination
     * @param _pageSize Number of locks to return (max PAGINATE_SIZE)
     * @return LockInfo[] Array of lock information for the specified user and token
     * @return uint256 Total number of locks for this user and token
     * @return uint256 Next index for pagination, returns 0 if no more locks
     */
    function getUserTokenLocksPaginated(
        address _user,
        address _token,
        uint256 _startIndex,
        uint256 _pageSize
    ) external view returns (LockInfo[] memory, uint256, uint256) {
        require(_user != address(0), "Invalid user address");
        require(_token != address(0), "Invalid token address");
        require(_pageSize > 0 && _pageSize <= PAGINATE_SIZE, "Invalid page size");
        
        Lock[] memory userLockArray = userLocks[_user];
        
        uint256 tokenLockCount = 0;
        for (uint256 i = 0; i < userLockArray.length; i++) {
            if (userLockArray[i].token == _token) {
                tokenLockCount++;
            }
        }
        
        if (tokenLockCount == 0 || _startIndex >= tokenLockCount) {
            return (new LockInfo[](0), tokenLockCount, 0);
        }
        
        uint256 remainingLocks = tokenLockCount - _startIndex;
        uint256 actualPageSize = remainingLocks < _pageSize ? remainingLocks : _pageSize;
        
        LockInfo[] memory lockInfos = new LockInfo[](actualPageSize);
        
        uint256 currentTokenLockIndex = 0;
        uint256 absoluteStartIndex = 0;
        
        for (; absoluteStartIndex < userLockArray.length; absoluteStartIndex++) {
            if (userLockArray[absoluteStartIndex].token == _token) {
                if (currentTokenLockIndex == _startIndex) {
                    break;
                }
                currentTokenLockIndex++;
            }
        }
        
        uint256 includedLocks = 0;
        for (uint256 i = absoluteStartIndex; i < userLockArray.length && includedLocks < actualPageSize; i++) {
            if (userLockArray[i].token == _token) {
                uint256 remaining = 0;
                if (block.timestamp < userLockArray[i].unlockTime && userLockArray[i].amount > 0) {
                    remaining = userLockArray[i].unlockTime - block.timestamp;
                }
                
                lockInfos[includedLocks] = LockInfo({
                    token: userLockArray[i].token,
                    owner: _user,
                    amount: userLockArray[i].amount,
                    decimals: userLockArray[i].decimals,
                    unlockTime: userLockArray[i].unlockTime,
                    remainingTime: remaining
                });
                
                includedLocks++;
            }
        }
        
        uint256 nextIndex = _startIndex + actualPageSize < tokenLockCount ? _startIndex + actualPageSize : 0;
        
        return (lockInfos, tokenLockCount, nextIndex);
    }

    function withdrawFees() external nonReentrant {
        require(msg.sender == feeAddress, "Only fee address can withdraw fees");
        
        uint256 amount = pendingFees[feeAddress];
        require(amount > 0, "No fees to withdraw");
        
        pendingFees[feeAddress] = 0;
        
        (bool success, ) = feeAddress.call{value: amount}("");
        require(success, "Fee withdrawal failed");
    }

    receive() external payable {}
}
