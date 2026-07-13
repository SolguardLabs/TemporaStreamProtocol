// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { SettlementReceipt } from "../core/Types.sol";

library ReceiptCodec {
    bytes32 internal constant RECEIPT_TYPEHASH = keccak256(
        "SettlementReceipt(uint256 streamId,address token,address from,address to,uint256 principal,uint256 yieldAmount,uint256 observedIndex,uint256 issuedAt,bytes32 metadataHash)"
    );

    struct PackedReceipt {
        bytes32 digest;
        uint256 streamId;
        uint256 value;
        uint256 issuedAt;
        address token;
        address from;
        address to;
    }

    function hash(
        SettlementReceipt memory receipt
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                RECEIPT_TYPEHASH,
                receipt.streamId,
                receipt.token,
                receipt.from,
                receipt.to,
                receipt.principal,
                receipt.yieldAmount,
                receipt.observedIndex,
                receipt.issuedAt,
                receipt.metadataHash
            )
        );
    }

    function pack(
        SettlementReceipt memory receipt
    ) internal pure returns (PackedReceipt memory packed) {
        packed.digest = hash(receipt);
        packed.streamId = receipt.streamId;
        packed.value = receipt.principal + receipt.yieldAmount;
        packed.issuedAt = receipt.issuedAt;
        packed.token = receipt.token;
        packed.from = receipt.from;
        packed.to = receipt.to;
    }

    function encode(
        SettlementReceipt memory receipt
    ) internal pure returns (bytes memory) {
        return abi.encode(
            receipt.streamId,
            receipt.token,
            receipt.from,
            receipt.to,
            receipt.principal,
            receipt.yieldAmount,
            receipt.observedIndex,
            receipt.issuedAt,
            receipt.metadataHash
        );
    }

    function decode(
        bytes memory payload
    ) internal pure returns (SettlementReceipt memory receipt) {
        (
            receipt.streamId,
            receipt.token,
            receipt.from,
            receipt.to,
            receipt.principal,
            receipt.yieldAmount,
            receipt.observedIndex,
            receipt.issuedAt,
            receipt.metadataHash
        ) =
            abi.decode(
                payload,
                (uint256, address, address, address, uint256, uint256, uint256, uint256, bytes32)
            );
    }

    function value(
        SettlementReceipt memory receipt
    ) internal pure returns (uint256) {
        return receipt.principal + receipt.yieldAmount;
    }

    function isEmpty(
        SettlementReceipt memory receipt
    ) internal pure returns (bool) {
        return receipt.streamId == 0 && receipt.principal == 0 && receipt.yieldAmount == 0;
    }

    function matchesParties(
        SettlementReceipt memory receipt,
        address from,
        address to
    ) internal pure returns (bool) {
        return receipt.from == from && receipt.to == to;
    }

    function matchesToken(
        SettlementReceipt memory receipt,
        address token
    ) internal pure returns (bool) {
        return receipt.token == token;
    }

    function isFresh(
        SettlementReceipt memory receipt,
        uint256 maxAge,
        uint256 timestamp
    ) internal pure returns (bool) {
        if (receipt.issuedAt == 0 || timestamp < receipt.issuedAt) {
            return false;
        }
        return timestamp - receipt.issuedAt <= maxAge;
    }
}

