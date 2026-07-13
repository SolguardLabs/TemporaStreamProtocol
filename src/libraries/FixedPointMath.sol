// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library FixedPointMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant BPS = 10_000;

    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256) {
        require(denominator != 0, "MATH_DENOMINATOR");
        if (x == 0 || y == 0) {
            return 0;
        }
        return (x * y) / denominator;
    }

    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256) {
        require(denominator != 0, "MATH_DENOMINATOR");
        if (x == 0 || y == 0) {
            return 0;
        }
        return ((x * y) - 1) / denominator + 1;
    }

    function mulWadDown(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    function mulWadUp(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivUp(x, y, WAD);
    }

    function divWadDown(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    function divWadUp(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y);
    }

    function mulRayDown(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivDown(x, y, RAY);
    }

    function divRayDown(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivDown(x, RAY, y);
    }

    function percentOf(
        uint256 amount,
        uint256 bps
    ) internal pure returns (uint256) {
        return mulDivDown(amount, bps, BPS);
    }

    function percentOfUp(
        uint256 amount,
        uint256 bps
    ) internal pure returns (uint256) {
        return mulDivUp(amount, bps, BPS);
    }

    function min(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function clamp(
        uint256 value,
        uint256 lower,
        uint256 upper
    ) internal pure returns (uint256) {
        if (value < lower) {
            return lower;
        }
        if (value > upper) {
            return upper;
        }
        return value;
    }

    function saturatingSub(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    function difference(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function weightedAverage(
        uint256 a,
        uint256 weightA,
        uint256 b,
        uint256 weightB
    ) internal pure returns (uint256) {
        uint256 totalWeight = weightA + weightB;
        if (totalWeight == 0) {
            return 0;
        }
        return mulDivDown(a, weightA, totalWeight) + mulDivDown(b, weightB, totalWeight);
    }

    function scaleByDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        }
        if (fromDecimals < toDecimals) {
            return amount * (10 ** uint256(toDecimals - fromDecimals));
        }
        return amount / (10 ** uint256(fromDecimals - toDecimals));
    }

    function annualRateToSecondRate(
        uint256 annualRateWad
    ) internal pure returns (uint256) {
        return annualRateWad / 365 days;
    }

    function linearGrowth(
        uint256 principal,
        uint256 ratePerSecondWad,
        uint256 elapsed
    ) internal pure returns (uint256) {
        return mulWadDown(principal, ratePerSecondWad * elapsed);
    }

    function applyIndex(
        uint256 principal,
        uint256 indexDeltaWad
    ) internal pure returns (uint256) {
        return mulWadDown(principal, indexDeltaWad);
    }

    function previewIndex(
        uint256 currentIndex,
        uint256 ratePerSecondWad,
        uint256 elapsed
    ) internal pure returns (uint256) {
        return currentIndex + (ratePerSecondWad * elapsed);
    }

    function bpsDelta(
        uint256 value,
        uint256 bps
    ) internal pure returns (uint256) {
        return (value * bps) / BPS;
    }

    function isWithin(
        uint256 value,
        uint256 expected,
        uint256 toleranceBps
    ) internal pure returns (bool) {
        if (expected == 0) {
            return value == 0;
        }
        uint256 delta = difference(value, expected);
        return mulDivDown(delta, BPS, expected) <= toleranceBps;
    }

    function ceilDiv(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        require(b != 0, "MATH_DENOMINATOR");
        if (a == 0) {
            return 0;
        }
        return ((a - 1) / b) + 1;
    }

    function toInt256(
        uint256 value
    ) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "MATH_INT_OVERFLOW");
        return int256(value);
    }

    function abs(
        int256 value
    ) internal pure returns (uint256) {
        return uint256(value >= 0 ? value : -value);
    }
}

