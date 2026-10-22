// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ITemporaStreamProtocol } from "../interfaces/ITemporaStreamProtocol.sol";

/// @notice Bounded read-only projection for a single payment schedule.
contract TemporaScheduleLens {
    uint256 public constant MAX_HORIZON = 30 days;

    struct Projection {
        ITemporaStreamProtocol.StreamStatus status;
        uint256 windowStartsAt;
        uint256 windowEndsAt;
        uint256 incrementalPrincipal;
        uint256 claimableNow;
        uint256 remainingBalance;
    }

    error InvalidHorizon(uint256 horizon);

    function project(
        ITemporaStreamProtocol protocol,
        uint256 streamId,
        uint256 horizonSeconds
    ) external view returns (Projection memory result) {
        if (horizonSeconds == 0 || horizonSeconds > MAX_HORIZON) {
            revert InvalidHorizon(horizonSeconds);
        }
        ITemporaStreamProtocol.StreamView memory stream = protocol.streamOf(streamId);
        result.status = stream.status;
        result.claimableNow = protocol.claimablePrincipal(streamId);
        result.remainingBalance = stream.principalBalance;
        result.windowStartsAt =
            block.timestamp > stream.startsAt ? block.timestamp : stream.startsAt;
        uint256 horizonEnd = block.timestamp + horizonSeconds;
        result.windowEndsAt = horizonEnd < stream.endsAt ? horizonEnd : stream.endsAt;

        if (
            stream.status != ITemporaStreamProtocol.StreamStatus.Active
                && stream.status != ITemporaStreamProtocol.StreamStatus.Scheduled
        ) return result;
        if (result.windowEndsAt <= result.windowStartsAt) return result;

        uint256 candidate = (result.windowEndsAt - result.windowStartsAt) * stream.ratePerSecond;
        result.incrementalPrincipal =
            candidate < stream.principalBalance ? candidate : stream.principalBalance;
    }
}
