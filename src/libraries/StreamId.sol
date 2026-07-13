// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library StreamId {
    function derive(
        address payer,
        address beneficiary,
        address token,
        uint256 startsAt,
        uint256 endsAt,
        uint256 ratePerSecond,
        uint256 nonce,
        bytes32 metadataHash
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "TEMPORA_STREAM",
                payer,
                beneficiary,
                token,
                startsAt,
                endsAt,
                ratePerSecond,
                nonce,
                metadataHash
            )
        );
    }

    function receiptHash(
        uint256 streamId,
        address token,
        address from,
        address to,
        uint256 principal,
        uint256 yieldAmount,
        uint256 index,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "TEMPORA_RECEIPT",
                streamId,
                token,
                from,
                to,
                principal,
                yieldAmount,
                index,
                timestamp
            )
        );
    }

    function participantKey(
        address account,
        address token
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode("TEMPORA_PARTICIPANT", account, token));
    }

    function reserveKey(
        address token
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode("TEMPORA_RESERVE", token));
    }
}
