// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract ManagedAccess {
    address public owner;
    address public pendingOwner;

    mapping(address => bool) public operators;
    mapping(address => bool) public guardians;
    mapping(address => bool) public reserveManagers;

    bool public protocolPaused;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OperatorUpdated(address indexed account, bool enabled);
    event GuardianUpdated(address indexed account, bool enabled);
    event ReserveManagerUpdated(address indexed account, bool enabled);
    event ProtocolPauseUpdated(address indexed caller, bool paused);

    constructor(
        address initialOwner
    ) {
        require(initialOwner != address(0), "OWNER");
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "ONLY_OWNER");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == owner || operators[msg.sender], "ONLY_OPERATOR");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == owner || guardians[msg.sender], "ONLY_GUARDIAN");
        _;
    }

    modifier onlyReserveManager() {
        require(msg.sender == owner || reserveManagers[msg.sender], "ONLY_RESERVE_MANAGER");
        _;
    }

    modifier whenProtocolOpen() {
        require(!protocolPaused, "PROTOCOL_PAUSED");
        _;
    }

    function transferOwnership(
        address newOwner
    ) external onlyOwner {
        require(newOwner != address(0), "OWNER");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "PENDING_OWNER");
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, owner);
    }

    function setOperator(
        address account,
        bool enabled
    ) external onlyOwner {
        require(account != address(0), "OPERATOR");
        operators[account] = enabled;
        emit OperatorUpdated(account, enabled);
    }

    function setGuardian(
        address account,
        bool enabled
    ) external onlyOwner {
        require(account != address(0), "GUARDIAN");
        guardians[account] = enabled;
        emit GuardianUpdated(account, enabled);
    }

    function setReserveManager(
        address account,
        bool enabled
    ) external onlyOwner {
        require(account != address(0), "RESERVE_MANAGER");
        reserveManagers[account] = enabled;
        emit ReserveManagerUpdated(account, enabled);
    }

    function setProtocolPaused(
        bool paused
    ) external onlyGuardian {
        protocolPaused = paused;
        emit ProtocolPauseUpdated(msg.sender, paused);
    }

    function canOperate(
        address account
    ) public view returns (bool) {
        return account == owner || operators[account];
    }

    function canManageReserve(
        address account
    ) public view returns (bool) {
        return account == owner || reserveManagers[account];
    }

    function canGuard(
        address account
    ) public view returns (bool) {
        return account == owner || guardians[account];
    }
}

