// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "../interfaces/IERC20.sol";

contract TemporaReceiptToken is IERC20 {
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    uint256 private _totalSupply;
    address public owner;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public minters;

    event MinterUpdated(address indexed account, bool enabled);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "ONLY_OWNER");
        _;
    }

    modifier onlyMinter() {
        require(msg.sender == owner || minters[msg.sender], "ONLY_MINTER");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address owner_
    ) {
        require(owner_ != address(0), "OWNER");
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(
        address owner_,
        address spender
    ) external view returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(
        address spender,
        uint256 value
    ) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(
        address to,
        uint256 value
    ) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "ALLOWANCE");
            unchecked {
                _allowances[from][msg.sender] = allowed - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    function setMinter(
        address account,
        bool enabled
    ) external onlyOwner {
        require(account != address(0), "MINTER");
        minters[account] = enabled;
        emit MinterUpdated(account, enabled);
    }

    function transferOwnership(
        address newOwner
    ) external onlyOwner {
        require(newOwner != address(0), "OWNER");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function mint(
        address to,
        uint256 value
    ) external onlyMinter {
        require(to != address(0), "MINT_TO");
        _totalSupply += value;
        _balances[to] += value;
        emit Transfer(address(0), to, value);
    }

    function burn(
        address from,
        uint256 value
    ) external onlyMinter {
        require(from != address(0), "BURN_FROM");
        uint256 balance = _balances[from];
        require(balance >= value, "BALANCE");
        unchecked {
            _balances[from] = balance - value;
            _totalSupply -= value;
        }
        emit Transfer(from, address(0), value);
    }

    function _approve(
        address owner_,
        address spender,
        uint256 value
    ) internal {
        require(owner_ != address(0), "APPROVE_OWNER");
        require(spender != address(0), "APPROVE_SPENDER");
        _allowances[owner_][spender] = value;
        emit Approval(owner_, spender, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal {
        require(from != address(0), "TRANSFER_FROM");
        require(to != address(0), "TRANSFER_TO");
        uint256 balance = _balances[from];
        require(balance >= value, "BALANCE");
        unchecked {
            _balances[from] = balance - value;
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }
}

