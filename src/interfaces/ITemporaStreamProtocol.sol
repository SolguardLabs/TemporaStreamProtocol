// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ITemporaStreamProtocol {
    enum StreamStatus {
        None,
        Scheduled,
        Active,
        Paused,
        Settled,
        Cancelled
    }

    struct CreateStreamRequest {
        address token;
        address beneficiary;
        uint256 startsAt;
        uint256 endsAt;
        uint256 ratePerSecond;
        uint256 minimumReserve;
        bool cancelable;
        bytes32 metadataHash;
    }

    struct StreamView {
        uint256 id;
        address payer;
        address beneficiary;
        address token;
        StreamStatus status;
        uint256 startsAt;
        uint256 endsAt;
        uint256 ratePerSecond;
        uint256 fundedPrincipal;
        uint256 principalBalance;
        uint256 principalAccrued;
        uint256 principalClaimed;
        uint256 principalReleased;
        uint256 yieldAccrued;
        uint256 yieldClaimed;
        uint256 yieldIndexCheckpoint;
        uint256 totalPaused;
        uint256 pauseStartedAt;
        uint256 createdAt;
        bool cancelable;
        bytes32 metadataHash;
    }

    struct ReserveView {
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

    event StreamCreated(
        uint256 indexed streamId,
        address indexed payer,
        address indexed beneficiary,
        address token,
        uint256 startsAt,
        uint256 endsAt,
        uint256 ratePerSecond,
        uint256 fundedPrincipal,
        bytes32 metadataHash
    );

    event StreamActivated(uint256 indexed streamId, uint256 activatedAt);
    event StreamPaused(uint256 indexed streamId, address indexed caller, uint256 pausedAt);
    event StreamResumed(
        uint256 indexed streamId,
        address indexed caller,
        uint256 resumedAt,
        uint256 releasedPrincipal
    );
    event StreamCancelled(
        uint256 indexed streamId,
        address indexed caller,
        uint256 cancelledAt,
        uint256 releasedPrincipal
    );
    event PrincipalClaimed(
        uint256 indexed streamId, address indexed beneficiary, uint256 amount, uint256 claimedAt
    );
    event YieldClaimed(
        uint256 indexed streamId, address indexed beneficiary, uint256 amount, uint256 claimedAt
    );
    event ReserveConfigured(
        address indexed token, uint256 accrualRatePerSecond, uint256 minLiquidityBuffer
    );
    event ReserveYieldReported(
        address indexed token, address indexed reporter, uint256 amount, uint256 newBuffer
    );
    event ReleasedPrincipalWithdrawn(address indexed owner, address indexed token, uint256 amount);

    function createStream(
        CreateStreamRequest calldata request
    ) external returns (uint256);
    function activateStream(
        uint256 streamId
    ) external;
    function pauseStream(
        uint256 streamId
    ) external;
    function resumeStream(
        uint256 streamId
    ) external;
    function cancelStream(
        uint256 streamId
    ) external;
    function claimPrincipal(
        uint256 streamId
    ) external returns (uint256);
    function claimYield(
        uint256 streamId
    ) external returns (uint256);
    function claimAll(
        uint256 streamId
    ) external returns (uint256 principal, uint256 yieldAmount);
    function reportYield(
        address token,
        uint256 amount
    ) external;
    function withdrawReleased(
        address token,
        uint256 amount
    ) external;
    function configureReserve(
        address token,
        uint256 accrualRatePerSecond,
        uint256 minLiquidityBuffer
    ) external;
    function streamOf(
        uint256 streamId
    ) external view returns (StreamView memory);
    function reserveOf(
        address token
    ) external view returns (ReserveView memory);
    function releasable(
        address owner,
        address token
    ) external view returns (uint256);
    function claimablePrincipal(
        uint256 streamId
    ) external view returns (uint256);
    function claimableYield(
        uint256 streamId
    ) external view returns (uint256);
}
