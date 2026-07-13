// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

enum StreamStatus {
    None,
    Scheduled,
    Active,
    Paused,
    Settled,
    Cancelled
}

struct StreamTerms {
    address payer;
    address beneficiary;
    address token;
    uint256 startsAt;
    uint256 endsAt;
    uint256 ratePerSecond;
    uint256 minimumReserve;
    bool cancelable;
    bytes32 metadataHash;
}

struct StreamState {
    StreamStatus status;
    uint256 createdAt;
    uint256 lastPrincipalAt;
    uint256 pauseStartedAt;
    uint256 totalPaused;
    uint256 fundedPrincipal;
    uint256 principalBalance;
    uint256 principalAccrued;
    uint256 principalClaimed;
    uint256 principalReleased;
    uint256 yieldAccrued;
    uint256 yieldClaimed;
    uint256 yieldIndexCheckpoint;
    uint256 updateNonce;
}

struct StreamRecord {
    StreamTerms terms;
    StreamState state;
}

struct ReserveState {
    bool enabled;
    uint256 totalEscrowed;
    uint256 totalProductivePrincipal;
    uint256 yieldBuffer;
    uint256 paidFromYield;
    uint256 paidFromPrincipal;
    uint256 globalYieldIndex;
    uint256 accrualRatePerSecond;
    uint256 lastUpdatedAt;
    uint256 minLiquidityBuffer;
    uint256 configurationNonce;
}

struct ReserveSnapshot {
    address token;
    bool enabled;
    uint256 totalEscrowed;
    uint256 totalProductivePrincipal;
    uint256 yieldBuffer;
    uint256 paidFromYield;
    uint256 paidFromPrincipal;
    uint256 globalYieldIndex;
    uint256 accrualRatePerSecond;
    uint256 lastUpdatedAt;
    uint256 minLiquidityBuffer;
}

struct StreamAccountingView {
    uint256 earnedPrincipal;
    uint256 claimablePrincipal;
    uint256 releasedPrincipal;
    uint256 pendingYield;
    uint256 productiveBase;
    uint256 globalYieldIndex;
    uint256 checkpoint;
    uint256 activeElapsed;
}

struct FlowWindow {
    uint256 openedAt;
    uint256 closesAt;
    uint256 lastTouchedAt;
    uint256 quota;
    uint256 consumed;
    uint256 rollingDebt;
}

struct BeneficiarySchedule {
    address beneficiary;
    uint256 streamCount;
    uint256 activeCount;
    uint256 pausedCount;
    uint256 totalRate;
    uint256 lastIndex;
}

struct PayerSchedule {
    address payer;
    uint256 streamCount;
    uint256 activeCount;
    uint256 totalReserved;
    uint256 totalReleased;
    uint256 lastIndex;
}

struct SettlementReceipt {
    uint256 streamId;
    address token;
    address from;
    address to;
    uint256 principal;
    uint256 yieldAmount;
    uint256 observedIndex;
    uint256 issuedAt;
    bytes32 metadataHash;
}
