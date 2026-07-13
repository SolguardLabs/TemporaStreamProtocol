// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { ReserveState } from "../core/Types.sol";

library ReserveMath {
    using FixedPointMath for uint256;

    struct Health {
        uint256 totalAssets;
        uint256 totalLiabilities;
        uint256 productiveRatioWad;
        uint256 bufferRatioWad;
        uint256 principalCoverageWad;
        uint256 paymentCoverageWad;
        uint256 index;
        uint256 annualizedRateWad;
        bool enabled;
        bool liquid;
    }

    struct StressInput {
        uint256 principalClaimShock;
        uint256 yieldClaimShock;
        uint256 withdrawalShock;
        uint256 yieldHaircutBps;
        uint256 productiveHaircutBps;
    }

    struct StressResult {
        uint256 assetsAfterShock;
        uint256 liabilitiesAfterShock;
        uint256 bufferAfterShock;
        uint256 productiveAfterShock;
        uint256 shortfall;
        uint256 coverageWad;
        bool passes;
    }

    function health(
        ReserveState storage reserve
    ) internal view returns (Health memory h) {
        h.totalAssets = reserve.totalEscrowed + reserve.yieldBuffer;
        h.totalLiabilities = reserve.totalEscrowed;
        h.productiveRatioWad = ratio(reserve.totalProductivePrincipal, h.totalAssets);
        h.bufferRatioWad = ratio(reserve.yieldBuffer, h.totalAssets);
        h.principalCoverageWad = ratio(h.totalAssets, h.totalLiabilities);
        h.paymentCoverageWad =
            ratio(reserve.yieldBuffer, reserve.paidFromYield + reserve.paidFromPrincipal);
        h.index = reserve.globalYieldIndex;
        h.annualizedRateWad = reserve.accrualRatePerSecond * 365 days;
        h.enabled = reserve.enabled;
        h.liquid = h.totalAssets >= h.totalLiabilities;
    }

    function stress(
        ReserveState storage reserve,
        StressInput memory input
    ) internal view returns (StressResult memory result) {
        uint256 productive = haircut(reserve.totalProductivePrincipal, input.productiveHaircutBps);
        uint256 buffer = haircut(reserve.yieldBuffer, input.yieldHaircutBps);
        uint256 assets = productive + buffer;
        uint256 liabilities =
            reserve.totalEscrowed + input.principalClaimShock + input.yieldClaimShock;
        uint256 withdrawal = FixedPointMath.min(input.withdrawalShock, assets);
        assets -= withdrawal;
        result.assetsAfterShock = assets;
        result.liabilitiesAfterShock = liabilities;
        result.bufferAfterShock = buffer > withdrawal ? buffer - withdrawal : 0;
        result.productiveAfterShock = productive;
        result.shortfall = liabilities > assets ? liabilities - assets : 0;
        result.coverageWad = ratio(assets, liabilities);
        result.passes = result.shortfall == 0;
    }

    function ratio(
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (uint256) {
        if (denominator == 0) {
            return numerator == 0 ? 0 : type(uint256).max;
        }
        return numerator.divWadDown(denominator);
    }

    function haircut(
        uint256 amount,
        uint256 bps
    ) internal pure returns (uint256) {
        if (bps >= FixedPointMath.BPS) {
            return 0;
        }
        return amount - amount.percentOf(bps);
    }

    function requiredBuffer(
        uint256 totalEscrowed,
        uint256 bufferBps
    ) internal pure returns (uint256) {
        return totalEscrowed.percentOf(bufferBps);
    }

    function missingBuffer(
        uint256 totalEscrowed,
        uint256 currentBuffer,
        uint256 bufferBps
    ) internal pure returns (uint256) {
        uint256 required = requiredBuffer(totalEscrowed, bufferBps);
        return required > currentBuffer ? required - currentBuffer : 0;
    }

    function availableYieldLiquidity(
        ReserveState storage reserve
    ) internal view returns (uint256) {
        if (reserve.yieldBuffer <= reserve.minLiquidityBuffer) {
            return 0;
        }
        return reserve.yieldBuffer - reserve.minLiquidityBuffer;
    }

    function utilizationWad(
        ReserveState storage reserve
    ) internal view returns (uint256) {
        uint256 paid = reserve.paidFromYield + reserve.paidFromPrincipal;
        uint256 total = reserve.totalEscrowed + paid + reserve.yieldBuffer;
        return ratio(paid, total);
    }

    function principalLeakageWad(
        ReserveState storage reserve
    ) internal view returns (uint256) {
        uint256 paid = reserve.paidFromYield + reserve.paidFromPrincipal;
        return ratio(reserve.paidFromPrincipal, paid);
    }

    function forecastIndex(
        uint256 currentIndex,
        uint256 ratePerSecond,
        uint256 horizonSeconds
    ) internal pure returns (uint256) {
        return currentIndex + (ratePerSecond * horizonSeconds);
    }

    function forecastYield(
        uint256 principal,
        uint256 currentIndex,
        uint256 futureIndex
    ) internal pure returns (uint256) {
        if (futureIndex <= currentIndex) {
            return 0;
        }
        return principal.mulWadDown(futureIndex - currentIndex);
    }

    function canAbsorb(
        ReserveState storage reserve,
        uint256 paymentAmount
    ) internal view returns (bool) {
        return reserve.yieldBuffer >= paymentAmount
            || reserve.totalEscrowed + reserve.yieldBuffer >= paymentAmount;
    }

    function rebalanceTarget(
        ReserveState storage reserve,
        uint256 targetBufferBps
    ) internal view returns (uint256 target, uint256 delta, bool needsTopUp) {
        target = reserve.totalEscrowed.percentOf(targetBufferBps);
        if (reserve.yieldBuffer >= target) {
            delta = reserve.yieldBuffer - target;
            needsTopUp = false;
        } else {
            delta = target - reserve.yieldBuffer;
            needsTopUp = true;
        }
    }
}

