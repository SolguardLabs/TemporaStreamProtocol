// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ManagedAccess } from "../access/ManagedAccess.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { Validation } from "../libraries/Validation.sol";
import { YieldIndex } from "../accounting/YieldIndex.sol";
import { ReserveSnapshot, ReserveState, StreamRecord } from "./Types.sol";

abstract contract StrategyReserve is ManagedAccess {
    using FixedPointMath for uint256;
    using YieldIndex for ReserveState;

    mapping(address => ReserveState) internal _reserves;
    mapping(address => mapping(address => uint256)) internal _releasedCredits;
    address[] internal _reserveTokens;
    mapping(address => bool) internal _knownReserveToken;

    event ReserveConfigured(
        address indexed token, uint256 accrualRatePerSecond, uint256 minLiquidityBuffer
    );
    event ReserveYieldReported(
        address indexed token, address indexed reporter, uint256 amount, uint256 newBuffer
    );
    event ReserveYieldConsumed(
        address indexed token, uint256 fromBuffer, uint256 fromPrincipal, uint256 remainingBuffer
    );
    event ReleasedPrincipalCredited(address indexed owner, address indexed token, uint256 amount);
    event ReleasedPrincipalWithdrawn(address indexed owner, address indexed token, uint256 amount);

    constructor(
        address initialOwner
    ) ManagedAccess(initialOwner) { }

    function configureReserve(
        address token,
        uint256 accrualRatePerSecond,
        uint256 minLiquidityBuffer
    ) public virtual onlyReserveManager {
        Validation.requireNonZeroAddress(token, "TOKEN");
        ReserveState storage reserve = _reserves[token];
        if (!reserve.enabled) {
            reserve.enabled = true;
            reserve.lastUpdatedAt = block.timestamp;
            _trackReserveToken(token);
        } else {
            reserve.sync();
        }
        reserve.accrualRatePerSecond = accrualRatePerSecond;
        reserve.minLiquidityBuffer = minLiquidityBuffer;
        reserve.configurationNonce += 1;
        emit ReserveConfigured(token, accrualRatePerSecond, minLiquidityBuffer);
    }

    function reportYield(
        address token,
        uint256 amount
    ) public virtual whenProtocolOpen {
        Validation.requirePositive(amount, "YIELD_AMOUNT");
        ReserveState storage reserve = _requireReserve(token);
        reserve.sync();
        _pullToken(token, msg.sender, amount);
        reserve.yieldBuffer += amount;
        emit ReserveYieldReported(token, msg.sender, amount, reserve.yieldBuffer);
    }

    function withdrawReleased(
        address token,
        uint256 amount
    ) public virtual whenProtocolOpen {
        uint256 available = _releasedCredits[msg.sender][token];
        require(amount != 0 && amount <= available, "RELEASED_AMOUNT");
        _releasedCredits[msg.sender][token] = available - amount;
        _pushToken(token, msg.sender, amount);
        emit ReleasedPrincipalWithdrawn(msg.sender, token, amount);
    }

    function releasable(
        address owner,
        address token
    ) public view returns (uint256) {
        return _releasedCredits[owner][token];
    }

    function reserveSnapshot(
        address token
    ) public view returns (ReserveSnapshot memory snapshot) {
        ReserveState storage reserve = _reserves[token];
        snapshot.token = token;
        snapshot.enabled = reserve.enabled;
        snapshot.totalEscrowed = reserve.totalEscrowed;
        snapshot.totalProductivePrincipal = reserve.totalProductivePrincipal;
        snapshot.yieldBuffer = reserve.yieldBuffer;
        snapshot.paidFromYield = reserve.paidFromYield;
        snapshot.paidFromPrincipal = reserve.paidFromPrincipal;
        snapshot.globalYieldIndex = _previewIndex(token);
        snapshot.accrualRatePerSecond = reserve.accrualRatePerSecond;
        snapshot.lastUpdatedAt = reserve.lastUpdatedAt;
        snapshot.minLiquidityBuffer = reserve.minLiquidityBuffer;
    }

    function reserveTokenAt(
        uint256 index
    ) external view returns (address) {
        return _reserveTokens[index];
    }

    function reserveTokenCount() external view returns (uint256) {
        return _reserveTokens.length;
    }

    function _requireReserve(
        address token
    ) internal view returns (ReserveState storage reserve) {
        reserve = _reserves[token];
        Validation.requireEnabled(reserve.enabled);
    }

    function _syncReserve(
        address token
    ) internal returns (uint256) {
        ReserveState storage reserve = _requireReserve(token);
        return reserve.sync();
    }

    function _previewIndex(
        address token
    ) internal view returns (uint256) {
        ReserveState storage reserve = _reserves[token];
        if (!reserve.enabled) {
            return 0;
        }
        return reserve.preview();
    }

    function _increaseEscrow(
        address token,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }
        ReserveState storage reserve = _requireReserve(token);
        reserve.sync();
        reserve.totalEscrowed += amount;
        reserve.totalProductivePrincipal += amount;
    }

    function _decreaseEscrow(
        address token,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }
        ReserveState storage reserve = _requireReserve(token);
        require(reserve.totalEscrowed >= amount, "ESCROW_TOTAL");
        reserve.totalEscrowed -= amount;
        reserve.totalProductivePrincipal = reserve.totalProductivePrincipal.saturatingSub(amount);
    }

    function _creditReleased(
        address owner_,
        address token,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }
        _releasedCredits[owner_][token] += amount;
        emit ReleasedPrincipalCredited(owner_, token, amount);
    }

    function _pullEscrow(
        address token,
        address from,
        uint256 amount
    ) internal {
        _pullToken(token, from, amount);
        _increaseEscrow(token, amount);
    }

    function _payPrincipal(
        StreamRecord storage stream,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }
        require(stream.state.principalBalance >= amount, "STREAM_BALANCE");
        stream.state.principalBalance -= amount;
        _decreaseEscrow(stream.terms.token, amount);
        _pushToken(stream.terms.token, to, amount);
    }

    function _releasePrincipal(
        StreamRecord storage stream,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }
        require(stream.state.principalBalance >= amount, "STREAM_BALANCE");
        stream.state.principalBalance -= amount;
        stream.state.principalReleased += amount;
        _decreaseEscrow(stream.terms.token, amount);
        _creditReleased(stream.terms.payer, stream.terms.token, amount);
    }

    function _payYield(
        StreamRecord storage stream,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }
        ReserveState storage reserve = _requireReserve(stream.terms.token);
        reserve.sync();

        uint256 fromBuffer = reserve.yieldBuffer < amount ? reserve.yieldBuffer : amount;
        uint256 fromPrincipal = amount - fromBuffer;

        if (fromBuffer != 0) {
            reserve.yieldBuffer -= fromBuffer;
            reserve.paidFromYield += fromBuffer;
        }
        if (fromPrincipal != 0) {
            uint256 owedPrincipal = stream.state.principalAccrued > stream.state.principalClaimed
                ? stream.state.principalAccrued - stream.state.principalClaimed
                : 0;
            uint256 liquidPrincipal = stream.state.principalBalance > owedPrincipal
                ? stream.state.principalBalance - owedPrincipal
                : 0;
            require(liquidPrincipal >= fromPrincipal, "YIELD_LIQUIDITY");
            stream.state.principalBalance -= fromPrincipal;
            reserve.paidFromPrincipal += fromPrincipal;
            _decreaseEscrow(stream.terms.token, fromPrincipal);
        }

        _pushToken(stream.terms.token, to, amount);
        emit ReserveYieldConsumed(
            stream.terms.token, fromBuffer, fromPrincipal, reserve.yieldBuffer
        );
    }

    function _trackReserveToken(
        address token
    ) internal {
        if (_knownReserveToken[token]) {
            return;
        }
        _knownReserveToken[token] = true;
        _reserveTokens.push(token);
    }

    function _pullToken(
        address token,
        address from,
        uint256 amount
    ) internal {
        require(IERC20(token).transferFrom(from, address(this), amount), "TRANSFER_FROM");
    }

    function _pushToken(
        address token,
        address to,
        uint256 amount
    ) internal {
        require(IERC20(token).transfer(to, amount), "TRANSFER");
    }

    function _tokenBalance(
        address token
    ) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}

