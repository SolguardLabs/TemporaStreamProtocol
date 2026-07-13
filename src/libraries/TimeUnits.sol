// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library TimeUnits {
    uint256 internal constant SECOND = 1;
    uint256 internal constant MINUTE = 60;
    uint256 internal constant HOUR = 60 minutes;
    uint256 internal constant DAY = 24 hours;
    uint256 internal constant WEEK = 7 days;
    uint256 internal constant MONTH_30 = 30 days;
    uint256 internal constant YEAR_365 = 365 days;

    function elapsed(
        uint256 from,
        uint256 to
    ) internal pure returns (uint256) {
        return to > from ? to - from : 0;
    }

    function elapsedSince(
        uint256 from
    ) internal view returns (uint256) {
        return elapsed(from, block.timestamp);
    }

    function boundedElapsed(
        uint256 from,
        uint256 to,
        uint256 upper
    ) internal pure returns (uint256) {
        if (to <= from) {
            return 0;
        }
        uint256 stop = to < upper ? to : upper;
        return stop > from ? stop - from : 0;
    }

    function clampTimestamp(
        uint256 timestamp,
        uint256 lower,
        uint256 upper
    ) internal pure returns (uint256) {
        if (timestamp < lower) {
            return lower;
        }
        if (timestamp > upper) {
            return upper;
        }
        return timestamp;
    }

    function isOpen(
        uint256 startsAt,
        uint256 endsAt,
        uint256 timestamp
    ) internal pure returns (bool) {
        return timestamp >= startsAt && timestamp < endsAt;
    }

    function hasClosed(
        uint256 endsAt,
        uint256 timestamp
    ) internal pure returns (bool) {
        return timestamp >= endsAt;
    }

    function nextBoundary(
        uint256 timestamp,
        uint256 interval
    ) internal pure returns (uint256) {
        require(interval != 0, "TIME_INTERVAL");
        uint256 remainder = timestamp % interval;
        if (remainder == 0) {
            return timestamp;
        }
        return timestamp + interval - remainder;
    }

    function previousBoundary(
        uint256 timestamp,
        uint256 interval
    ) internal pure returns (uint256) {
        require(interval != 0, "TIME_INTERVAL");
        return timestamp - (timestamp % interval);
    }

    function prorata(
        uint256 amount,
        uint256 elapsedTime,
        uint256 totalDuration
    ) internal pure returns (uint256) {
        require(totalDuration != 0, "TIME_DURATION");
        if (elapsedTime >= totalDuration) {
            return amount;
        }
        return (amount * elapsedTime) / totalDuration;
    }

    function remaining(
        uint256 nowTimestamp,
        uint256 endsAt
    ) internal pure returns (uint256) {
        return endsAt > nowTimestamp ? endsAt - nowTimestamp : 0;
    }

    function duration(
        uint256 startsAt,
        uint256 endsAt
    ) internal pure returns (uint256) {
        require(endsAt > startsAt, "TIME_ORDER");
        return endsAt - startsAt;
    }

    function safeWindow(
        uint256 startsAt,
        uint256 endsAt
    ) internal pure returns (uint256 start, uint256 end, uint256 length) {
        require(startsAt != 0, "TIME_START");
        require(endsAt > startsAt, "TIME_ORDER");
        return (startsAt, endsAt, endsAt - startsAt);
    }

    function minTimestamp(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function maxTimestamp(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
