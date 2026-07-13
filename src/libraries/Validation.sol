// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Validation {
    function requireNonZeroAddress(
        address value,
        string memory code
    ) internal pure {
        require(value != address(0), code);
    }

    function requirePositive(
        uint256 value,
        string memory code
    ) internal pure {
        require(value != 0, code);
    }

    function requireOrderedWindow(
        uint256 startsAt,
        uint256 endsAt
    ) internal pure {
        require(startsAt != 0, "WINDOW_START");
        require(endsAt > startsAt, "WINDOW_ORDER");
    }

    function requireFutureOrNow(
        uint256 timestamp,
        uint256 nowTimestamp
    ) internal pure {
        require(timestamp >= nowTimestamp, "WINDOW_PAST");
    }

    function requireAtMost(
        uint256 value,
        uint256 maxValue,
        string memory code
    ) internal pure {
        require(value <= maxValue, code);
    }

    function requireAtLeast(
        uint256 value,
        uint256 minValue,
        string memory code
    ) internal pure {
        require(value >= minValue, code);
    }

    function requireDifferent(
        address left,
        address right,
        string memory code
    ) internal pure {
        require(left != right, code);
    }

    function requireParticipant(
        address caller,
        address first,
        address second
    ) internal pure {
        require(caller == first || caller == second, "PARTICIPANT");
    }

    function requireEnabled(
        bool enabled
    ) internal pure {
        require(enabled, "RESERVE_DISABLED");
    }

    function requireNotClosed(
        uint256 timestamp,
        uint256 endsAt
    ) internal pure {
        require(timestamp < endsAt, "STREAM_CLOSED");
    }

    function requireStatus(
        uint8 observed,
        uint8 expected,
        string memory code
    ) internal pure {
        require(observed == expected, code);
    }

    function requireNotStatus(
        uint8 observed,
        uint8 blocked,
        string memory code
    ) internal pure {
        require(observed != blocked, code);
    }
}

