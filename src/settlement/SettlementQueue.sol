// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { FixedPointMath } from "../libraries/FixedPointMath.sol";

library SettlementQueue {
    using FixedPointMath for uint256;

    enum ItemStatus {
        None,
        Queued,
        Ready,
        Consumed,
        Cancelled
    }

    struct QueueItem {
        uint256 id;
        uint256 streamId;
        address token;
        address payer;
        address beneficiary;
        uint256 principal;
        uint256 yieldAmount;
        uint256 notBefore;
        uint256 expiresAt;
        uint256 createdAt;
        ItemStatus status;
        bytes32 metadataHash;
    }

    struct EnqueueRequest {
        uint256 streamId;
        address token;
        address payer;
        address beneficiary;
        uint256 principal;
        uint256 yieldAmount;
        uint256 notBefore;
        uint256 expiresAt;
        bytes32 metadataHash;
    }

    struct QueueState {
        mapping(uint256 => QueueItem) items;
        uint256 head;
        uint256 tail;
        uint256 queuedCount;
        uint256 readyCount;
        uint256 consumedCount;
        uint256 cancelledCount;
        uint256 pendingPrincipal;
        uint256 pendingYield;
    }

    struct QueueStats {
        uint256 head;
        uint256 tail;
        uint256 queuedCount;
        uint256 readyCount;
        uint256 consumedCount;
        uint256 cancelledCount;
        uint256 pendingPrincipal;
        uint256 pendingYield;
        uint256 pendingValue;
    }

    function initialize(
        QueueState storage queue
    ) internal {
        if (queue.head == 0 && queue.tail == 0) {
            queue.head = 1;
            queue.tail = 1;
        }
    }

    function enqueue(
        QueueState storage queue,
        EnqueueRequest memory request
    ) internal returns (uint256 itemId) {
        initialize(queue);
        require(request.streamId != 0, "QUEUE_STREAM");
        require(request.token != address(0), "QUEUE_TOKEN");
        require(request.payer != address(0), "QUEUE_PAYER");
        require(request.beneficiary != address(0), "QUEUE_BENEFICIARY");
        require(request.principal != 0 || request.yieldAmount != 0, "QUEUE_VALUE");
        require(request.expiresAt == 0 || request.expiresAt > request.notBefore, "QUEUE_EXPIRY");

        itemId = queue.tail++;
        queue.items[itemId] = QueueItem({
            id: itemId,
            streamId: request.streamId,
            token: request.token,
            payer: request.payer,
            beneficiary: request.beneficiary,
            principal: request.principal,
            yieldAmount: request.yieldAmount,
            notBefore: request.notBefore,
            expiresAt: request.expiresAt,
            createdAt: block.timestamp,
            status: ItemStatus.Queued,
            metadataHash: request.metadataHash
        });
        queue.queuedCount += 1;
        queue.pendingPrincipal += request.principal;
        queue.pendingYield += request.yieldAmount;
    }

    function markReady(
        QueueState storage queue,
        uint256 itemId
    ) internal {
        QueueItem storage item = existing(queue, itemId);
        require(item.status == ItemStatus.Queued, "QUEUE_NOT_QUEUED");
        require(block.timestamp >= item.notBefore, "QUEUE_NOT_READY");
        require(item.expiresAt == 0 || block.timestamp < item.expiresAt, "QUEUE_EXPIRED");
        item.status = ItemStatus.Ready;
        queue.readyCount += 1;
    }

    function consume(
        QueueState storage queue,
        uint256 itemId
    ) internal returns (QueueItem memory item) {
        QueueItem storage stored = existing(queue, itemId);
        require(
            stored.status == ItemStatus.Ready || stored.status == ItemStatus.Queued, "QUEUE_STATUS"
        );
        require(block.timestamp >= stored.notBefore, "QUEUE_NOT_READY");
        require(stored.expiresAt == 0 || block.timestamp < stored.expiresAt, "QUEUE_EXPIRED");
        stored.status = ItemStatus.Consumed;
        queue.consumedCount += 1;
        if (queue.readyCount != 0) {
            queue.readyCount -= 1;
        }
        queue.pendingPrincipal = queue.pendingPrincipal.saturatingSub(stored.principal);
        queue.pendingYield = queue.pendingYield.saturatingSub(stored.yieldAmount);
        item = stored;
        _advanceHead(queue);
    }

    function cancel(
        QueueState storage queue,
        uint256 itemId
    ) internal returns (QueueItem memory item) {
        QueueItem storage stored = existing(queue, itemId);
        require(
            stored.status == ItemStatus.Queued || stored.status == ItemStatus.Ready, "QUEUE_STATUS"
        );
        ItemStatus previous = stored.status;
        stored.status = ItemStatus.Cancelled;
        queue.cancelledCount += 1;
        if (previous == ItemStatus.Ready && queue.readyCount != 0) {
            queue.readyCount -= 1;
        }
        queue.pendingPrincipal = queue.pendingPrincipal.saturatingSub(stored.principal);
        queue.pendingYield = queue.pendingYield.saturatingSub(stored.yieldAmount);
        item = stored;
        _advanceHead(queue);
    }

    function expire(
        QueueState storage queue,
        uint256 itemId
    ) internal returns (QueueItem memory item) {
        QueueItem storage stored = existing(queue, itemId);
        require(stored.expiresAt != 0 && block.timestamp >= stored.expiresAt, "QUEUE_ACTIVE");
        require(
            stored.status == ItemStatus.Queued || stored.status == ItemStatus.Ready, "QUEUE_STATUS"
        );
        ItemStatus previous = stored.status;
        stored.status = ItemStatus.Cancelled;
        queue.cancelledCount += 1;
        if (previous == ItemStatus.Ready && queue.readyCount != 0) {
            queue.readyCount -= 1;
        }
        queue.pendingPrincipal = queue.pendingPrincipal.saturatingSub(stored.principal);
        queue.pendingYield = queue.pendingYield.saturatingSub(stored.yieldAmount);
        item = stored;
        _advanceHead(queue);
    }

    function peek(
        QueueState storage queue,
        uint256 itemId
    ) internal view returns (QueueItem memory) {
        return existing(queue, itemId);
    }

    function nextOpen(
        QueueState storage queue
    ) internal view returns (uint256 itemId) {
        for (uint256 i = queue.head; i < queue.tail; i++) {
            ItemStatus status = queue.items[i].status;
            if (status == ItemStatus.Queued || status == ItemStatus.Ready) {
                return i;
            }
        }
        return 0;
    }

    function dueCount(
        QueueState storage queue,
        uint256 timestamp
    ) internal view returns (uint256 count) {
        for (uint256 i = queue.head; i < queue.tail; i++) {
            QueueItem storage item = queue.items[i];
            if (
                (item.status == ItemStatus.Queued || item.status == ItemStatus.Ready)
                    && timestamp >= item.notBefore
                    && (item.expiresAt == 0 || timestamp < item.expiresAt)
            ) {
                count += 1;
            }
        }
    }

    function expiredCount(
        QueueState storage queue,
        uint256 timestamp
    ) internal view returns (uint256 count) {
        for (uint256 i = queue.head; i < queue.tail; i++) {
            QueueItem storage item = queue.items[i];
            if (
                (item.status == ItemStatus.Queued || item.status == ItemStatus.Ready)
                    && item.expiresAt != 0 && timestamp >= item.expiresAt
            ) {
                count += 1;
            }
        }
    }

    function stats(
        QueueState storage queue
    ) internal view returns (QueueStats memory s) {
        s.head = queue.head;
        s.tail = queue.tail;
        s.queuedCount = queue.queuedCount;
        s.readyCount = queue.readyCount;
        s.consumedCount = queue.consumedCount;
        s.cancelledCount = queue.cancelledCount;
        s.pendingPrincipal = queue.pendingPrincipal;
        s.pendingYield = queue.pendingYield;
        s.pendingValue = queue.pendingPrincipal + queue.pendingYield;
    }

    function length(
        QueueState storage queue
    ) internal view returns (uint256) {
        if (queue.tail <= queue.head) {
            return 0;
        }
        return queue.tail - queue.head;
    }

    function activeLength(
        QueueState storage queue
    ) internal view returns (uint256 count) {
        for (uint256 i = queue.head; i < queue.tail; i++) {
            ItemStatus status = queue.items[i].status;
            if (status == ItemStatus.Queued || status == ItemStatus.Ready) {
                count += 1;
            }
        }
    }

    function processableValue(
        QueueState storage queue,
        uint256 timestamp
    ) internal view returns (uint256 principal, uint256 yieldAmount) {
        for (uint256 i = queue.head; i < queue.tail; i++) {
            QueueItem storage item = queue.items[i];
            if (isProcessable(item, timestamp)) {
                principal += item.principal;
                yieldAmount += item.yieldAmount;
            }
        }
    }

    function isProcessable(
        QueueItem storage item,
        uint256 timestamp
    ) internal view returns (bool) {
        if (item.status != ItemStatus.Queued && item.status != ItemStatus.Ready) {
            return false;
        }
        if (timestamp < item.notBefore) {
            return false;
        }
        return item.expiresAt == 0 || timestamp < item.expiresAt;
    }

    function isTerminal(
        ItemStatus status
    ) internal pure returns (bool) {
        return status == ItemStatus.Consumed || status == ItemStatus.Cancelled;
    }

    function valueOf(
        QueueItem memory item
    ) internal pure returns (uint256) {
        return item.principal + item.yieldAmount;
    }

    function hash(
        QueueItem memory item
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "TEMPORA_QUEUE_ITEM",
                item.id,
                item.streamId,
                item.token,
                item.payer,
                item.beneficiary,
                item.principal,
                item.yieldAmount,
                item.notBefore,
                item.expiresAt,
                item.metadataHash
            )
        );
    }

    function existing(
        QueueState storage queue,
        uint256 itemId
    ) internal view returns (QueueItem storage item) {
        item = queue.items[itemId];
        require(item.status != ItemStatus.None, "QUEUE_ID");
    }

    function _advanceHead(
        QueueState storage queue
    ) private {
        while (queue.head < queue.tail) {
            ItemStatus status = queue.items[queue.head].status;
            if (status == ItemStatus.Queued || status == ItemStatus.Ready) {
                break;
            }
            queue.head += 1;
        }
    }
}
