// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { ReserveState, StreamRecord, StreamStatus } from "../core/Types.sol";

library YieldIndex {
    using FixedPointMath for uint256;

    uint256 internal constant WAD = 1e18;

    function sync(
        ReserveState storage reserve
    ) internal returns (uint256 newIndex) {
        if (!reserve.enabled) {
            reserve.lastUpdatedAt = block.timestamp;
            return reserve.globalYieldIndex;
        }
        if (reserve.lastUpdatedAt == 0) {
            reserve.lastUpdatedAt = block.timestamp;
            return reserve.globalYieldIndex;
        }
        if (block.timestamp <= reserve.lastUpdatedAt) {
            return reserve.globalYieldIndex;
        }
        uint256 elapsed = block.timestamp - reserve.lastUpdatedAt;
        reserve.globalYieldIndex += reserve.accrualRatePerSecond * elapsed;
        reserve.lastUpdatedAt = block.timestamp;
        return reserve.globalYieldIndex;
    }

    function preview(
        ReserveState storage reserve
    ) internal view returns (uint256) {
        if (
            !reserve.enabled || reserve.lastUpdatedAt == 0
                || block.timestamp <= reserve.lastUpdatedAt
        ) {
            return reserve.globalYieldIndex;
        }
        uint256 elapsed = block.timestamp - reserve.lastUpdatedAt;
        return reserve.globalYieldIndex + (reserve.accrualRatePerSecond * elapsed);
    }

    function pendingYield(
        StreamRecord storage stream,
        ReserveState storage reserve
    ) internal view returns (uint256) {
        uint256 currentIndex = preview(reserve);
        if (currentIndex <= stream.state.yieldIndexCheckpoint) {
            return stream.state.yieldAccrued - stream.state.yieldClaimed;
        }
        uint256 base = productiveBase(stream);
        uint256 delta = currentIndex - stream.state.yieldIndexCheckpoint;
        uint256 indexedYield = base.mulWadDown(delta);
        return (stream.state.yieldAccrued + indexedYield) - stream.state.yieldClaimed;
    }

    function materialize(
        StreamRecord storage stream,
        ReserveState storage reserve
    ) internal returns (uint256 accruedNow) {
        uint256 currentIndex = sync(reserve);
        if (currentIndex <= stream.state.yieldIndexCheckpoint) {
            return 0;
        }
        uint256 base = productiveBase(stream);
        uint256 delta = currentIndex - stream.state.yieldIndexCheckpoint;
        accruedNow = base.mulWadDown(delta);
        stream.state.yieldAccrued += accruedNow;
        stream.state.yieldIndexCheckpoint = currentIndex;
    }

    function checkpoint(
        StreamRecord storage stream,
        ReserveState storage reserve
    ) internal {
        stream.state.yieldIndexCheckpoint = sync(reserve);
    }

    function checkpointAt(
        StreamRecord storage stream,
        uint256 observedIndex
    ) internal {
        stream.state.yieldIndexCheckpoint = observedIndex;
    }

    function productiveBase(
        StreamRecord storage stream
    ) internal view returns (uint256) {
        if (
            stream.state.status == StreamStatus.Cancelled
                || stream.state.status == StreamStatus.Settled
        ) {
            return 0;
        }
        uint256 owed = stream.state.principalAccrued > stream.state.principalClaimed
            ? stream.state.principalAccrued - stream.state.principalClaimed
            : 0;
        if (stream.state.principalBalance <= owed) {
            return 0;
        }
        return stream.state.principalBalance - owed;
    }

    function unclaimedYield(
        StreamRecord storage stream
    ) internal view returns (uint256) {
        return stream.state.yieldAccrued > stream.state.yieldClaimed
            ? stream.state.yieldAccrued - stream.state.yieldClaimed
            : 0;
    }

    function markYieldClaimed(
        StreamRecord storage stream,
        uint256 amount
    ) internal {
        uint256 available = unclaimedYield(stream);
        require(amount <= available, "YIELD_AVAILABLE");
        stream.state.yieldClaimed += amount;
    }

    function principalOwed(
        StreamRecord storage stream
    ) internal view returns (uint256) {
        return stream.state.principalAccrued > stream.state.principalClaimed
            ? stream.state.principalAccrued - stream.state.principalClaimed
            : 0;
    }

    function availableUnvested(
        StreamRecord storage stream
    ) internal view returns (uint256) {
        uint256 owed = principalOwed(stream);
        if (stream.state.principalBalance <= owed) {
            return 0;
        }
        return stream.state.principalBalance - owed;
    }

    function isLive(
        StreamRecord storage stream
    ) internal view returns (bool) {
        return
            stream.state.status == StreamStatus.Active
                || stream.state.status == StreamStatus.Scheduled;
    }
}

