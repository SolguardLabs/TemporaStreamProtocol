// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { StreamRecord, StreamStatus } from "../core/Types.sol";

library PrincipalLedger {
    using FixedPointMath for uint256;

    struct PrincipalPreview {
        uint256 accrued;
        uint256 claimable;
        uint256 unvested;
        uint256 refundable;
        uint256 earnedRatioWad;
        uint256 elapsedActive;
        uint256 elapsedGross;
        bool mature;
        bool solvent;
    }

    struct PrincipalMovement {
        uint256 beforeBalance;
        uint256 afterBalance;
        uint256 claimAmount;
        uint256 releaseAmount;
        uint256 owedBefore;
        uint256 owedAfter;
    }

    function preview(
        StreamRecord storage record
    ) internal view returns (PrincipalPreview memory p) {
        p.accrued = projectedAccrued(record);
        p.claimable = p.accrued.saturatingSub(record.state.principalClaimed);
        p.unvested = unvested(record, p.accrued);
        p.refundable = refundable(record, block.timestamp);
        p.earnedRatioWad = earnedRatio(record, p.accrued);
        p.elapsedActive = activeElapsed(record, block.timestamp);
        p.elapsedGross = grossElapsed(record, block.timestamp);
        p.mature = block.timestamp >= record.terms.endsAt || p.accrued >= maxAccruable(record);
        p.solvent = record.state.principalBalance >= p.claimable;
    }

    function projectedAccrued(
        StreamRecord storage record
    ) internal view returns (uint256) {
        if (record.state.status == StreamStatus.Cancelled) {
            return record.state.principalAccrued;
        }
        if (record.state.status == StreamStatus.Paused) {
            return record.state.principalAccrued;
        }
        if (
            record.state.status == StreamStatus.Scheduled && block.timestamp < record.terms.startsAt
        ) {
            return record.state.principalAccrued;
        }
        if (
            record.state.status != StreamStatus.Active
                && record.state.status != StreamStatus.Scheduled
        ) {
            return record.state.principalAccrued;
        }
        uint256 last = record.state.lastPrincipalAt < record.terms.startsAt
            ? record.terms.startsAt
            : record.state.lastPrincipalAt;
        uint256 stop = block.timestamp < record.terms.endsAt ? block.timestamp : record.terms.endsAt;
        if (stop <= last) {
            return record.state.principalAccrued;
        }
        uint256 additional = (stop - last) * record.terms.ratePerSecond;
        uint256 cap = maxAccruable(record);
        uint256 accrued = record.state.principalAccrued + additional;
        return accrued > cap ? cap : accrued;
    }

    function maxAccruable(
        StreamRecord storage record
    ) internal view returns (uint256) {
        return record.state.fundedPrincipal.saturatingSub(record.state.principalReleased);
    }

    function unvested(
        StreamRecord storage record,
        uint256 accrued
    ) internal view returns (uint256) {
        uint256 owed = accrued.saturatingSub(record.state.principalClaimed);
        if (record.state.principalBalance <= owed) {
            return 0;
        }
        return record.state.principalBalance - owed;
    }

    function refundable(
        StreamRecord storage record,
        uint256 timestamp
    ) internal view returns (uint256) {
        if (record.state.status != StreamStatus.Paused || record.state.pauseStartedAt == 0) {
            return 0;
        }
        uint256 pausedSeconds =
            timestamp > record.state.pauseStartedAt ? timestamp - record.state.pauseStartedAt : 0;
        uint256 quoted = pausedSeconds * record.terms.ratePerSecond;
        return FixedPointMath.min(quoted, unvested(record, record.state.principalAccrued));
    }

    function claimable(
        StreamRecord storage record
    ) internal view returns (uint256) {
        return projectedAccrued(record).saturatingSub(record.state.principalClaimed);
    }

    function availableForRelease(
        StreamRecord storage record
    ) internal view returns (uint256) {
        return unvested(record, projectedAccrued(record));
    }

    function earnedRatio(
        StreamRecord storage record,
        uint256 accrued
    ) internal view returns (uint256) {
        uint256 cap = maxAccruable(record);
        if (cap == 0) {
            return 0;
        }
        return accrued.divWadDown(cap);
    }

    function grossElapsed(
        StreamRecord storage record,
        uint256 timestamp
    ) internal view returns (uint256) {
        if (timestamp <= record.terms.startsAt) {
            return 0;
        }
        uint256 stop = timestamp < record.terms.endsAt ? timestamp : record.terms.endsAt;
        return stop > record.terms.startsAt ? stop - record.terms.startsAt : 0;
    }

    function activeElapsed(
        StreamRecord storage record,
        uint256 timestamp
    ) internal view returns (uint256) {
        uint256 gross = grossElapsed(record, timestamp);
        uint256 paused = record.state.totalPaused;
        if (record.state.status == StreamStatus.Paused && record.state.pauseStartedAt != 0) {
            paused += timestamp.saturatingSub(record.state.pauseStartedAt);
        }
        return gross.saturatingSub(paused);
    }

    function classify(
        StreamRecord storage record
    ) internal view returns (bytes32) {
        if (record.state.status == StreamStatus.Cancelled) {
            return "CANCELLED";
        }
        if (record.state.status == StreamStatus.Paused) {
            return "PAUSED";
        }
        if (
            record.state.status == StreamStatus.Scheduled && block.timestamp < record.terms.startsAt
        ) {
            return "SCHEDULED";
        }
        if (projectedAccrued(record) >= maxAccruable(record)) {
            return "MATURE";
        }
        if (claimable(record) != 0) {
            return "CLAIMABLE";
        }
        return "OPEN";
    }

    function movementForClaim(
        StreamRecord storage record,
        uint256 amount
    ) internal view returns (PrincipalMovement memory movement) {
        uint256 claimableNow = claimable(record);
        require(amount <= claimableNow, "LEDGER_CLAIM");
        movement.beforeBalance = record.state.principalBalance;
        movement.afterBalance = movement.beforeBalance.saturatingSub(amount);
        movement.claimAmount = amount;
        movement.owedBefore = claimableNow;
        movement.owedAfter = claimableNow.saturatingSub(amount);
    }

    function movementForRelease(
        StreamRecord storage record,
        uint256 amount
    ) internal view returns (PrincipalMovement memory movement) {
        uint256 available = availableForRelease(record);
        require(amount <= available, "LEDGER_RELEASE");
        movement.beforeBalance = record.state.principalBalance;
        movement.afterBalance = movement.beforeBalance.saturatingSub(amount);
        movement.releaseAmount = amount;
        movement.owedBefore = claimable(record);
        movement.owedAfter = movement.owedBefore;
    }

    function assertBalanced(
        StreamRecord storage record
    ) internal view returns (bool) {
        uint256 spent = record.state.principalClaimed + record.state.principalReleased;
        if (spent > record.state.fundedPrincipal) {
            return false;
        }
        uint256 accounted = record.state.principalBalance + spent;
        return accounted <= record.state.fundedPrincipal;
    }

    function remainingDuration(
        StreamRecord storage record,
        uint256 timestamp
    ) internal view returns (uint256) {
        if (timestamp >= record.terms.endsAt) {
            return 0;
        }
        return record.terms.endsAt - timestamp;
    }

    function remainingNominal(
        StreamRecord storage record,
        uint256 timestamp
    ) internal view returns (uint256) {
        return remainingDuration(record, timestamp) * record.terms.ratePerSecond;
    }

    function utilizationWad(
        StreamRecord storage record
    ) internal view returns (uint256) {
        uint256 spent = record.state.principalClaimed + record.state.principalReleased;
        if (record.state.fundedPrincipal == 0) {
            return 0;
        }
        return spent.divWadDown(record.state.fundedPrincipal);
    }

    function claimPressureWad(
        StreamRecord storage record
    ) internal view returns (uint256) {
        if (record.state.principalBalance == 0) {
            return claimable(record) == 0 ? 0 : type(uint256).max;
        }
        return claimable(record).divWadDown(record.state.principalBalance);
    }
}

