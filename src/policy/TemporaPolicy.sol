// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { FixedPointMath } from "../libraries/FixedPointMath.sol";

library TemporaPolicy {
    using FixedPointMath for uint256;

    uint256 internal constant MAX_STREAM_DURATION = 730 days;
    uint256 internal constant MIN_STREAM_DURATION = 60 seconds;
    uint256 internal constant MAX_RATE_PER_SECOND = 1_000_000_000 ether;
    uint256 internal constant DEFAULT_MIN_RESERVE_BPS = 50;
    uint256 internal constant MAX_ACCRUAL_RATE_PER_SECOND = 2_000_000_000_000;
    uint256 internal constant MAX_LIQUIDITY_BUFFER_BPS = 3_000;
    uint256 internal constant GRACE_WINDOW = 15 minutes;
    uint256 internal constant MAX_REFERENCE_BYTES = 32;

    struct PolicyConfig {
        uint256 minDuration;
        uint256 maxDuration;
        uint256 maxRatePerSecond;
        uint256 minReserveBps;
        uint256 maxAccrualRatePerSecond;
        uint256 maxLiquidityBufferBps;
        uint256 activationGraceWindow;
        bool allowParticipantPause;
        bool allowOpenReporting;
    }

    function defaultConfig() internal pure returns (PolicyConfig memory config) {
        config.minDuration = MIN_STREAM_DURATION;
        config.maxDuration = MAX_STREAM_DURATION;
        config.maxRatePerSecond = MAX_RATE_PER_SECOND;
        config.minReserveBps = DEFAULT_MIN_RESERVE_BPS;
        config.maxAccrualRatePerSecond = MAX_ACCRUAL_RATE_PER_SECOND;
        config.maxLiquidityBufferBps = MAX_LIQUIDITY_BUFFER_BPS;
        config.activationGraceWindow = GRACE_WINDOW;
        config.allowParticipantPause = true;
        config.allowOpenReporting = true;
    }

    function validateDuration(
        PolicyConfig memory config,
        uint256 durationSeconds
    ) internal pure {
        require(durationSeconds >= config.minDuration, "POLICY_DURATION_MIN");
        require(durationSeconds <= config.maxDuration, "POLICY_DURATION_MAX");
    }

    function validateRate(
        PolicyConfig memory config,
        uint256 ratePerSecond
    ) internal pure {
        require(ratePerSecond != 0, "POLICY_RATE_ZERO");
        require(ratePerSecond <= config.maxRatePerSecond, "POLICY_RATE_MAX");
    }

    function validateReserve(
        PolicyConfig memory config,
        uint256 amount,
        uint256 minimum
    ) internal pure {
        if (minimum != 0) {
            require(amount >= minimum, "POLICY_MIN_RESERVE");
        }
        uint256 suggested = amount.percentOf(config.minReserveBps);
        if (suggested != 0) {
            require(amount >= suggested, "POLICY_RESERVE_FLOOR");
        }
    }

    function validateReserveRate(
        PolicyConfig memory config,
        uint256 ratePerSecond
    ) internal pure {
        require(ratePerSecond <= config.maxAccrualRatePerSecond, "POLICY_ACCRUAL_RATE");
    }

    function validateLiquidityBuffer(
        PolicyConfig memory config,
        uint256 bps
    ) internal pure {
        require(bps <= config.maxLiquidityBufferBps, "POLICY_BUFFER");
    }

    function normalizeStart(
        uint256 requestedStart,
        uint256 nowTimestamp
    ) internal pure returns (uint256) {
        return requestedStart == 0 || requestedStart < nowTimestamp ? nowTimestamp : requestedStart;
    }

    function reserveFor(
        uint256 ratePerSecond,
        uint256 durationSeconds
    ) internal pure returns (uint256) {
        return ratePerSecond * durationSeconds;
    }

    function liquidityBufferFor(
        uint256 amount,
        uint256 bps
    ) internal pure returns (uint256) {
        return amount.percentOf(bps);
    }

    function isActivationAllowed(
        uint256 startsAt,
        uint256 nowTimestamp,
        uint256 graceWindow
    ) internal pure returns (bool) {
        if (nowTimestamp >= startsAt) {
            return true;
        }
        return startsAt - nowTimestamp <= graceWindow;
    }

    function releaseForPausedWindow(
        uint256 ratePerSecond,
        uint256 pausedSeconds
    ) internal pure returns (uint256) {
        return ratePerSecond * pausedSeconds;
    }

    function streamIsMature(
        uint256 endsAt,
        uint256 nowTimestamp
    ) internal pure returns (bool) {
        return nowTimestamp >= endsAt;
    }

    function effectiveStop(
        uint256 endsAt,
        uint256 nowTimestamp
    ) internal pure returns (uint256) {
        return nowTimestamp < endsAt ? nowTimestamp : endsAt;
    }
}

