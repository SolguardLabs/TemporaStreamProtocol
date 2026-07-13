// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { StreamRecord, StreamStatus } from "../core/Types.sol";

library StreamRiskModel {
    using FixedPointMath for uint256;

    enum Tier {
        Low,
        Standard,
        Elevated,
        Restricted
    }

    struct RiskInput {
        uint256 maxSingleStream;
        uint256 maxRatePerSecond;
        uint256 maxDuration;
        uint256 maxPauseRatioWad;
        uint256 minRemainingBalanceWad;
        uint256 elevatedRatePerSecond;
        uint256 restrictedRatePerSecond;
    }

    struct RiskScore {
        uint256 score;
        Tier tier;
        uint256 sizeComponent;
        uint256 rateComponent;
        uint256 durationComponent;
        uint256 pauseComponent;
        uint256 liquidityComponent;
        bool requiresOperatorReview;
    }

    function defaultInput() internal pure returns (RiskInput memory input) {
        input.maxSingleStream = 5_000_000 ether;
        input.maxRatePerSecond = 2_000 ether;
        input.maxDuration = 365 days;
        input.maxPauseRatioWad = 0.25e18;
        input.minRemainingBalanceWad = 0.05e18;
        input.elevatedRatePerSecond = 500 ether;
        input.restrictedRatePerSecond = 1_500 ether;
    }

    function score(
        StreamRecord storage record,
        RiskInput memory input
    ) internal view returns (RiskScore memory result) {
        result.sizeComponent = component(record.state.fundedPrincipal, input.maxSingleStream);
        result.rateComponent = component(record.terms.ratePerSecond, input.maxRatePerSecond);
        result.durationComponent = component(duration(record), input.maxDuration);
        result.pauseComponent = component(pauseRatio(record), input.maxPauseRatioWad);
        result.liquidityComponent = liquidityComponent(record, input.minRemainingBalanceWad);
        result.score = weighted(
            result.sizeComponent,
            result.rateComponent,
            result.durationComponent,
            result.pauseComponent,
            result.liquidityComponent
        );
        result.tier = tierFor(result.score, record.terms.ratePerSecond, input);
        result.requiresOperatorReview = result.tier == Tier.Restricted
            || record.state.status == StreamStatus.Paused
            && pauseRatio(record) > input.maxPauseRatioWad;
    }

    function component(
        uint256 observed,
        uint256 limit
    ) internal pure returns (uint256) {
        if (limit == 0) {
            return observed == 0 ? 0 : 100;
        }
        uint256 ratioWad = observed.divWadDown(limit);
        if (ratioWad >= 1e18) {
            return 100;
        }
        return ratioWad.mulWadDown(100);
    }

    function weighted(
        uint256 sizeComponent,
        uint256 rateComponent,
        uint256 durationComponent,
        uint256 pauseComponent,
        uint256 liquidityScore
    ) internal pure returns (uint256) {
        return (sizeComponent
                * 30
                + rateComponent
                * 25
                + durationComponent
                * 15
                + pauseComponent
                * 15
                + liquidityScore
                * 15) / 100;
    }

    function tierFor(
        uint256 riskScore,
        uint256 ratePerSecond,
        RiskInput memory input
    ) internal pure returns (Tier) {
        if (ratePerSecond >= input.restrictedRatePerSecond || riskScore >= 85) {
            return Tier.Restricted;
        }
        if (ratePerSecond >= input.elevatedRatePerSecond || riskScore >= 60) {
            return Tier.Elevated;
        }
        if (riskScore >= 30) {
            return Tier.Standard;
        }
        return Tier.Low;
    }

    function duration(
        StreamRecord storage record
    ) internal view returns (uint256) {
        if (record.terms.endsAt <= record.terms.startsAt) {
            return 0;
        }
        return record.terms.endsAt - record.terms.startsAt;
    }

    function pauseRatio(
        StreamRecord storage record
    ) internal view returns (uint256) {
        uint256 total = duration(record);
        if (total == 0) {
            return 0;
        }
        uint256 paused = record.state.totalPaused;
        if (record.state.status == StreamStatus.Paused && record.state.pauseStartedAt != 0) {
            paused += block.timestamp.saturatingSub(record.state.pauseStartedAt);
        }
        return paused.divWadDown(total);
    }

    function liquidityComponent(
        StreamRecord storage record,
        uint256 minRemainingBalanceWad
    ) internal view returns (uint256) {
        if (record.state.fundedPrincipal == 0) {
            return 0;
        }
        uint256 remainingWad =
            record.state.principalBalance.divWadDown(record.state.fundedPrincipal);
        if (remainingWad >= minRemainingBalanceWad) {
            return 0;
        }
        return
            (minRemainingBalanceWad - remainingWad).divWadDown(minRemainingBalanceWad)
                .mulWadDown(100);
    }

    function recommendedBufferBps(
        Tier tier
    ) internal pure returns (uint256) {
        if (tier == Tier.Restricted) {
            return 1_000;
        }
        if (tier == Tier.Elevated) {
            return 500;
        }
        if (tier == Tier.Standard) {
            return 150;
        }
        return 50;
    }

    function maxPauseWindow(
        Tier tier,
        uint256 streamDuration
    ) internal pure returns (uint256) {
        if (tier == Tier.Restricted) {
            return streamDuration / 20;
        }
        if (tier == Tier.Elevated) {
            return streamDuration / 10;
        }
        if (tier == Tier.Standard) {
            return streamDuration / 5;
        }
        return streamDuration / 3;
    }

    function shouldNotify(
        uint256 oldScore,
        uint256 newScore
    ) internal pure returns (bool) {
        if (newScore >= 80 && oldScore < 80) {
            return true;
        }
        if (newScore >= 60 && oldScore < 60) {
            return true;
        }
        return FixedPointMath.difference(oldScore, newScore) >= 20;
    }
}
