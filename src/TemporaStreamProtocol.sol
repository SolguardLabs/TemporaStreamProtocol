// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ITemporaStreamProtocol } from "./interfaces/ITemporaStreamProtocol.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { StreamId } from "./libraries/StreamId.sol";
import { TimeUnits } from "./libraries/TimeUnits.sol";
import { Validation } from "./libraries/Validation.sol";
import { TemporaPolicy } from "./policy/TemporaPolicy.sol";
import { YieldIndex } from "./accounting/YieldIndex.sol";
import {
    ReserveSnapshot,
    ReserveState,
    SettlementReceipt,
    StreamAccountingView,
    StreamRecord,
    StreamState,
    StreamStatus,
    StreamTerms
} from "./core/Types.sol";
import { StrategyReserve } from "./core/StrategyReserve.sol";

contract TemporaStreamProtocol is StrategyReserve {
    using FixedPointMath for uint256;
    using TimeUnits for uint256;
    using YieldIndex for ReserveState;
    using YieldIndex for StreamRecord;
    using TemporaPolicy for TemporaPolicy.PolicyConfig;

    uint256 public nextStreamId = 1;
    TemporaPolicy.PolicyConfig internal _policy;

    mapping(uint256 => StreamRecord) internal _streams;
    mapping(uint256 => bytes32) public streamCommitments;
    mapping(address => uint256[]) internal _payerStreams;
    mapping(address => uint256[]) internal _beneficiaryStreams;
    mapping(address => mapping(address => uint256)) public payerReservedByToken;
    mapping(address => mapping(address => uint256)) public beneficiaryRateByToken;
    mapping(address => uint256) public createdStreamCount;
    mapping(bytes32 => bool) public knownReferences;

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
    event PolicyUpdated(bytes32 indexed field, uint256 value);
    event PolicyFlagUpdated(bytes32 indexed field, bool value);

    constructor() StrategyReserve(msg.sender) {
        _policy = TemporaPolicy.defaultConfig();
        reserveManagers[msg.sender] = true;
        guardians[msg.sender] = true;
    }

    function createStream(
        ITemporaStreamProtocol.CreateStreamRequest calldata request
    ) external whenProtocolOpen returns (uint256 streamId) {
        Validation.requireNonZeroAddress(request.token, "TOKEN");
        Validation.requireNonZeroAddress(request.beneficiary, "BENEFICIARY");
        Validation.requireDifferent(msg.sender, request.beneficiary, "SELF_STREAM");
        _requireReserve(request.token);

        uint256 startsAt = TemporaPolicy.normalizeStart(request.startsAt, block.timestamp);
        Validation.requireOrderedWindow(startsAt, request.endsAt);
        uint256 durationSeconds = request.endsAt - startsAt;
        _policy.validateDuration(durationSeconds);
        _policy.validateRate(request.ratePerSecond);

        uint256 fundedPrincipal = TemporaPolicy.reserveFor(request.ratePerSecond, durationSeconds);
        _policy.validateReserve(fundedPrincipal, request.minimumReserve);

        streamId = nextStreamId++;
        StreamRecord storage record = _streams[streamId];
        record.terms = StreamTerms({
            payer: msg.sender,
            beneficiary: request.beneficiary,
            token: request.token,
            startsAt: startsAt,
            endsAt: request.endsAt,
            ratePerSecond: request.ratePerSecond,
            minimumReserve: request.minimumReserve,
            cancelable: request.cancelable,
            metadataHash: request.metadataHash
        });
        record.state = StreamState({
            status: startsAt <= block.timestamp ? StreamStatus.Active : StreamStatus.Scheduled,
            createdAt: block.timestamp,
            lastPrincipalAt: startsAt <= block.timestamp ? block.timestamp : startsAt,
            pauseStartedAt: 0,
            totalPaused: 0,
            fundedPrincipal: fundedPrincipal,
            principalBalance: fundedPrincipal,
            principalAccrued: 0,
            principalClaimed: 0,
            principalReleased: 0,
            yieldAccrued: 0,
            yieldClaimed: 0,
            yieldIndexCheckpoint: _syncReserve(request.token),
            updateNonce: 0
        });

        bytes32 commitment = StreamId.derive(
            msg.sender,
            request.beneficiary,
            request.token,
            startsAt,
            request.endsAt,
            request.ratePerSecond,
            streamId,
            request.metadataHash
        );
        streamCommitments[streamId] = commitment;
        if (request.metadataHash != bytes32(0)) {
            knownReferences[request.metadataHash] = true;
        }

        _payerStreams[msg.sender].push(streamId);
        _beneficiaryStreams[request.beneficiary].push(streamId);
        payerReservedByToken[msg.sender][request.token] += fundedPrincipal;
        beneficiaryRateByToken[request.beneficiary][request.token] += request.ratePerSecond;
        createdStreamCount[msg.sender] += 1;

        _pullEscrow(request.token, msg.sender, fundedPrincipal);

        emit StreamCreated(
            streamId,
            msg.sender,
            request.beneficiary,
            request.token,
            startsAt,
            request.endsAt,
            request.ratePerSecond,
            fundedPrincipal,
            request.metadataHash
        );
        if (record.state.status == StreamStatus.Active) {
            emit StreamActivated(streamId, block.timestamp);
        }
    }

    function activateStream(
        uint256 streamId
    ) external whenProtocolOpen {
        StreamRecord storage record = _existingStream(streamId);
        require(record.state.status == StreamStatus.Scheduled, "STREAM_NOT_SCHEDULED");
        require(
            TemporaPolicy.isActivationAllowed(
                record.terms.startsAt, block.timestamp, _policy.activationGraceWindow
            ),
            "ACTIVATION_EARLY"
        );
        record.state.status = StreamStatus.Active;
        record.state.lastPrincipalAt =
            block.timestamp > record.terms.startsAt ? block.timestamp : record.terms.startsAt;
        record.state.updateNonce += 1;
        emit StreamActivated(streamId, block.timestamp);
    }

    function pauseStream(
        uint256 streamId
    ) external whenProtocolOpen {
        StreamRecord storage record = _existingStream(streamId);
        _requireParticipant(record);
        _refreshLifecycle(record);
        require(record.state.status == StreamStatus.Active, "STREAM_NOT_ACTIVE");
        _accruePrincipal(record);
        record.state.status = StreamStatus.Paused;
        record.state.pauseStartedAt = block.timestamp;
        record.state.updateNonce += 1;
        beneficiaryRateByToken[record.terms.beneficiary][record.terms.token] = beneficiaryRateByToken[record.terms
                .beneficiary][record.terms.token].saturatingSub(record.terms.ratePerSecond);
        emit StreamPaused(streamId, msg.sender, block.timestamp);
    }

    function resumeStream(
        uint256 streamId
    ) external whenProtocolOpen {
        StreamRecord storage record = _existingStream(streamId);
        _requireParticipant(record);
        require(record.state.status == StreamStatus.Paused, "STREAM_NOT_PAUSED");
        require(record.state.pauseStartedAt != 0, "PAUSE_TIME");

        uint256 pausedSeconds = block.timestamp - record.state.pauseStartedAt;
        uint256 releaseQuote =
            TemporaPolicy.releaseForPausedWindow(record.terms.ratePerSecond, pausedSeconds);
        uint256 releaseAmount = FixedPointMath.min(releaseQuote, record.availableUnvested());
        if (releaseAmount != 0) {
            _releasePrincipal(record, releaseAmount);
            payerReservedByToken[record.terms.payer][record.terms.token] = payerReservedByToken[record.terms
                    .payer][record.terms.token].saturatingSub(releaseAmount);
        }

        record.state.totalPaused += pausedSeconds;
        record.state.pauseStartedAt = 0;
        record.state.lastPrincipalAt =
            block.timestamp < record.terms.endsAt ? block.timestamp : record.terms.endsAt;
        record.state.status =
            _isEconomicallyClosed(record) ? StreamStatus.Settled : StreamStatus.Active;
        record.state.updateNonce += 1;

        if (record.state.status == StreamStatus.Active) {
            beneficiaryRateByToken[
                record.terms.beneficiary
            ][record.terms.token] += record.terms.ratePerSecond;
        }

        emit StreamResumed(streamId, msg.sender, block.timestamp, releaseAmount);
    }

    function cancelStream(
        uint256 streamId
    ) external whenProtocolOpen {
        StreamRecord storage record = _existingStream(streamId);
        require(record.terms.cancelable, "STREAM_FINAL");
        _requireParticipant(record);
        _refreshLifecycle(record);
        if (record.state.status == StreamStatus.Active) {
            _accruePrincipal(record);
        }
        _streams[streamId].materialize(_reserves[record.terms.token]);

        uint256 releaseAmount = record.availableUnvested();
        if (releaseAmount != 0) {
            _releasePrincipal(record, releaseAmount);
            payerReservedByToken[record.terms.payer][record.terms.token] = payerReservedByToken[record.terms
                    .payer][record.terms.token].saturatingSub(releaseAmount);
        }
        if (record.state.status == StreamStatus.Active) {
            beneficiaryRateByToken[record.terms.beneficiary][record.terms.token] = beneficiaryRateByToken[record.terms
                .beneficiary][record.terms.token].saturatingSub(record.terms.ratePerSecond);
        }
        record.state.status = StreamStatus.Cancelled;
        record.state.pauseStartedAt = 0;
        record.state.updateNonce += 1;
        emit StreamCancelled(streamId, msg.sender, block.timestamp, releaseAmount);
    }

    function claimPrincipal(
        uint256 streamId
    ) external whenProtocolOpen returns (uint256) {
        StreamRecord storage record = _existingStream(streamId);
        require(msg.sender == record.terms.beneficiary, "BENEFICIARY");
        return _claimPrincipal(streamId, record);
    }

    function claimYield(
        uint256 streamId
    ) external whenProtocolOpen returns (uint256) {
        StreamRecord storage record = _existingStream(streamId);
        require(msg.sender == record.terms.beneficiary, "BENEFICIARY");
        return _claimYield(streamId, record);
    }

    function claimAll(
        uint256 streamId
    ) external whenProtocolOpen returns (uint256 principal, uint256 yieldAmount) {
        StreamRecord storage record = _existingStream(streamId);
        require(msg.sender == record.terms.beneficiary, "BENEFICIARY");
        principal = _claimPrincipal(streamId, record);
        yieldAmount = _claimYield(streamId, record);
    }

    function configureReserve(
        address token,
        uint256 accrualRatePerSecond,
        uint256 minLiquidityBuffer
    ) public override onlyReserveManager {
        _policy.validateReserveRate(accrualRatePerSecond);
        super.configureReserve(token, accrualRatePerSecond, minLiquidityBuffer);
    }

    function setPolicyDurations(
        uint256 minDuration,
        uint256 maxDuration
    ) external onlyOwner {
        require(minDuration != 0 && maxDuration >= minDuration, "POLICY_DURATION");
        require(maxDuration <= 730 days, "POLICY_DURATION_MAX");
        _policy.minDuration = minDuration;
        _policy.maxDuration = maxDuration;
        emit PolicyUpdated("MIN_DURATION", minDuration);
        emit PolicyUpdated("MAX_DURATION", maxDuration);
    }

    function setPolicyRateLimit(
        uint256 maxRatePerSecond
    ) external onlyOwner {
        require(maxRatePerSecond != 0, "POLICY_RATE");
        _policy.maxRatePerSecond = maxRatePerSecond;
        emit PolicyUpdated("MAX_RATE", maxRatePerSecond);
    }

    function setPolicyReserveBps(
        uint256 minReserveBps
    ) external onlyOwner {
        require(minReserveBps <= 2_000, "POLICY_RESERVE_BPS");
        _policy.minReserveBps = minReserveBps;
        emit PolicyUpdated("MIN_RESERVE_BPS", minReserveBps);
    }

    function setPolicyFlags(
        bool participantPause,
        bool openReporting
    ) external onlyOwner {
        _policy.allowParticipantPause = participantPause;
        _policy.allowOpenReporting = openReporting;
        emit PolicyFlagUpdated("PARTICIPANT_PAUSE", participantPause);
        emit PolicyFlagUpdated("OPEN_REPORTING", openReporting);
    }

    function reportYield(
        address token,
        uint256 amount
    ) public override whenProtocolOpen {
        if (!_policy.allowOpenReporting) {
            require(canManageReserve(msg.sender), "REPORTER");
        }
        super.reportYield(token, amount);
    }

    function streamOf(
        uint256 streamId
    ) external view returns (ITemporaStreamProtocol.StreamView memory view_) {
        StreamRecord storage record = _existingStreamView(streamId);
        view_.id = streamId;
        view_.payer = record.terms.payer;
        view_.beneficiary = record.terms.beneficiary;
        view_.token = record.terms.token;
        view_.status = ITemporaStreamProtocol.StreamStatus(uint8(_previewStatus(record)));
        view_.startsAt = record.terms.startsAt;
        view_.endsAt = record.terms.endsAt;
        view_.ratePerSecond = record.terms.ratePerSecond;
        view_.fundedPrincipal = record.state.fundedPrincipal;
        view_.principalBalance = record.state.principalBalance;
        view_.principalAccrued = _previewPrincipalAccrued(record);
        view_.principalClaimed = record.state.principalClaimed;
        view_.principalReleased = record.state.principalReleased;
        view_.yieldAccrued = record.state.yieldAccrued + _previewYieldIncrement(record);
        view_.yieldClaimed = record.state.yieldClaimed;
        view_.yieldIndexCheckpoint = record.state.yieldIndexCheckpoint;
        view_.totalPaused = record.state.totalPaused;
        view_.pauseStartedAt = record.state.pauseStartedAt;
        view_.createdAt = record.state.createdAt;
        view_.cancelable = record.terms.cancelable;
        view_.metadataHash = record.terms.metadataHash;
    }

    function reserveOf(
        address token
    ) external view returns (ITemporaStreamProtocol.ReserveView memory view_) {
        ReserveSnapshot memory snapshot = reserveSnapshot(token);
        view_.token = snapshot.token;
        view_.enabled = snapshot.enabled;
        view_.totalEscrowed = snapshot.totalEscrowed;
        view_.totalProductivePrincipal = snapshot.totalProductivePrincipal;
        view_.yieldBuffer = snapshot.yieldBuffer;
        view_.paidFromYield = snapshot.paidFromYield;
        view_.paidFromPrincipal = snapshot.paidFromPrincipal;
        view_.globalYieldIndex = snapshot.globalYieldIndex;
        view_.accrualRatePerSecond = snapshot.accrualRatePerSecond;
        view_.lastUpdatedAt = snapshot.lastUpdatedAt;
        view_.minLiquidityBuffer = snapshot.minLiquidityBuffer;
    }

    function claimablePrincipal(
        uint256 streamId
    ) external view returns (uint256) {
        StreamRecord storage record = _existingStreamView(streamId);
        uint256 accrued = _previewPrincipalAccrued(record);
        return accrued > record.state.principalClaimed ? accrued - record.state.principalClaimed : 0;
    }

    function claimableYield(
        uint256 streamId
    ) external view returns (uint256) {
        StreamRecord storage record = _existingStreamView(streamId);
        uint256 accrued = record.state.yieldAccrued + _previewYieldIncrement(record);
        return accrued > record.state.yieldClaimed ? accrued - record.state.yieldClaimed : 0;
    }

    function payerStreamAt(
        address payer,
        uint256 index
    ) external view returns (uint256) {
        return _payerStreams[payer][index];
    }

    function beneficiaryStreamAt(
        address beneficiary,
        uint256 index
    ) external view returns (uint256) {
        return _beneficiaryStreams[beneficiary][index];
    }

    function payerStreamCount(
        address payer
    ) external view returns (uint256) {
        return _payerStreams[payer].length;
    }

    function beneficiaryStreamCount(
        address beneficiary
    ) external view returns (uint256) {
        return _beneficiaryStreams[beneficiary].length;
    }

    function policyView()
        external
        view
        returns (
            uint256 minDuration,
            uint256 maxDuration,
            uint256 maxRatePerSecond,
            uint256 minReserveBps,
            uint256 maxAccrualRatePerSecond,
            uint256 activationGraceWindow,
            bool allowParticipantPause,
            bool allowOpenReporting
        )
    {
        minDuration = _policy.minDuration;
        maxDuration = _policy.maxDuration;
        maxRatePerSecond = _policy.maxRatePerSecond;
        minReserveBps = _policy.minReserveBps;
        maxAccrualRatePerSecond = _policy.maxAccrualRatePerSecond;
        activationGraceWindow = _policy.activationGraceWindow;
        allowParticipantPause = _policy.allowParticipantPause;
        allowOpenReporting = _policy.allowOpenReporting;
    }

    function accountingView(
        uint256 streamId
    ) external view returns (StreamAccountingView memory view_) {
        StreamRecord storage record = _existingStreamView(streamId);
        view_.earnedPrincipal = _previewPrincipalAccrued(record);
        view_.claimablePrincipal = view_.earnedPrincipal > record.state.principalClaimed
            ? view_.earnedPrincipal - record.state.principalClaimed
            : 0;
        view_.releasedPrincipal = record.state.principalReleased;
        view_.pendingYield =
            record.state.yieldAccrued + _previewYieldIncrement(record) - record.state.yieldClaimed;
        view_.productiveBase = record.productiveBase();
        view_.globalYieldIndex = _previewIndex(record.terms.token);
        view_.checkpoint = record.state.yieldIndexCheckpoint;
        view_.activeElapsed = _activeElapsed(record);
    }

    function settlementReceipt(
        uint256 streamId
    ) external view returns (SettlementReceipt memory receipt) {
        StreamRecord storage record = _existingStreamView(streamId);
        receipt.streamId = streamId;
        receipt.token = record.terms.token;
        receipt.from = record.terms.payer;
        receipt.to = record.terms.beneficiary;
        receipt.principal = _previewPrincipalAccrued(record);
        receipt.yieldAmount = record.state.yieldAccrued + _previewYieldIncrement(record);
        receipt.observedIndex = _previewIndex(record.terms.token);
        receipt.issuedAt = block.timestamp;
        receipt.metadataHash = StreamId.receiptHash(
            streamId,
            record.terms.token,
            record.terms.payer,
            record.terms.beneficiary,
            receipt.principal,
            receipt.yieldAmount,
            receipt.observedIndex,
            block.timestamp
        );
    }

    function _claimPrincipal(
        uint256 streamId,
        StreamRecord storage record
    ) internal returns (uint256 amount) {
        _refreshLifecycle(record);
        _accruePrincipal(record);
        amount = record.state.principalAccrued > record.state.principalClaimed
            ? record.state.principalAccrued - record.state.principalClaimed
            : 0;
        if (amount == 0) {
            return 0;
        }
        record.state.principalClaimed += amount;
        _payPrincipal(record, record.terms.beneficiary, amount);
        emit PrincipalClaimed(streamId, record.terms.beneficiary, amount, block.timestamp);
    }

    function _claimYield(
        uint256 streamId,
        StreamRecord storage record
    ) internal returns (uint256 amount) {
        _refreshLifecycle(record);
        record.materialize(_reserves[record.terms.token]);
        amount = record.state.yieldAccrued > record.state.yieldClaimed
            ? record.state.yieldAccrued - record.state.yieldClaimed
            : 0;
        if (amount == 0) {
            return 0;
        }
        record.state.yieldClaimed += amount;
        _payYield(record, record.terms.beneficiary, amount);
        emit YieldClaimed(streamId, record.terms.beneficiary, amount, block.timestamp);
    }

    function _accruePrincipal(
        StreamRecord storage record
    ) internal returns (uint256 amount) {
        if (
            record.state.status == StreamStatus.Scheduled
                && block.timestamp >= record.terms.startsAt
        ) {
            record.state.status = StreamStatus.Active;
            record.state.lastPrincipalAt =
                block.timestamp > record.terms.startsAt ? block.timestamp : record.terms.startsAt;
        }
        if (record.state.status != StreamStatus.Active) {
            return 0;
        }
        uint256 stop = block.timestamp < record.terms.endsAt ? block.timestamp : record.terms.endsAt;
        if (stop <= record.state.lastPrincipalAt) {
            if (_isEconomicallyClosed(record)) {
                record.state.status = StreamStatus.Settled;
            }
            return 0;
        }
        uint256 elapsedSeconds = stop - record.state.lastPrincipalAt;
        amount = elapsedSeconds * record.terms.ratePerSecond;
        uint256 maxAccruable =
            record.state.fundedPrincipal.saturatingSub(record.state.principalReleased);
        uint256 remaining = maxAccruable.saturatingSub(record.state.principalAccrued);
        amount = FixedPointMath.min(amount, remaining);
        if (amount != 0) {
            record.state.principalAccrued += amount;
        }
        record.state.lastPrincipalAt = stop;
        if (_isEconomicallyClosed(record)) {
            record.state.status = StreamStatus.Settled;
            beneficiaryRateByToken[record.terms.beneficiary][record.terms.token] = beneficiaryRateByToken[record.terms
                    .beneficiary][record.terms.token].saturatingSub(record.terms.ratePerSecond);
        }
    }

    function _refreshLifecycle(
        StreamRecord storage record
    ) internal {
        if (
            record.state.status == StreamStatus.Scheduled
                && block.timestamp >= record.terms.startsAt
        ) {
            record.state.status = StreamStatus.Active;
            record.state.lastPrincipalAt = block.timestamp;
        }
    }

    function _previewPrincipalAccrued(
        StreamRecord storage record
    ) internal view returns (uint256) {
        if (
            record.state.status != StreamStatus.Active
                && record.state.status != StreamStatus.Scheduled
        ) {
            return record.state.principalAccrued;
        }
        if (
            record.state.status == StreamStatus.Scheduled && block.timestamp < record.terms.startsAt
        ) {
            return record.state.principalAccrued;
        }
        uint256 last = record.state.lastPrincipalAt;
        if (last < record.terms.startsAt) {
            last = record.terms.startsAt;
        }
        uint256 stop = block.timestamp < record.terms.endsAt ? block.timestamp : record.terms.endsAt;
        if (stop <= last) {
            return record.state.principalAccrued;
        }
        uint256 additional = (stop - last) * record.terms.ratePerSecond;
        uint256 maxAccruable =
            record.state.fundedPrincipal.saturatingSub(record.state.principalReleased);
        uint256 capped = record.state.principalAccrued + additional;
        return capped > maxAccruable ? maxAccruable : capped;
    }

    function _previewYieldIncrement(
        StreamRecord storage record
    ) internal view returns (uint256) {
        if (
            record.state.status == StreamStatus.Cancelled
                || record.state.status == StreamStatus.Settled
        ) {
            return 0;
        }
        uint256 currentIndex = _previewIndex(record.terms.token);
        if (currentIndex <= record.state.yieldIndexCheckpoint) {
            return 0;
        }
        uint256 base = record.productiveBase();
        return base.mulWadDown(currentIndex - record.state.yieldIndexCheckpoint);
    }

    function _previewStatus(
        StreamRecord storage record
    ) internal view returns (StreamStatus) {
        if (
            record.state.status == StreamStatus.Scheduled
                && block.timestamp >= record.terms.startsAt
        ) {
            return StreamStatus.Active;
        }
        if (record.state.status == StreamStatus.Active && block.timestamp >= record.terms.endsAt) {
            return StreamStatus.Settled;
        }
        return record.state.status;
    }

    function _activeElapsed(
        StreamRecord storage record
    ) internal view returns (uint256) {
        uint256 stop = block.timestamp < record.terms.endsAt ? block.timestamp : record.terms.endsAt;
        if (stop <= record.terms.startsAt) {
            return 0;
        }
        uint256 gross = stop - record.terms.startsAt;
        uint256 paused = record.state.totalPaused;
        if (record.state.status == StreamStatus.Paused && record.state.pauseStartedAt != 0) {
            paused += block.timestamp - record.state.pauseStartedAt;
        }
        return gross.saturatingSub(paused);
    }

    function _isEconomicallyClosed(
        StreamRecord storage record
    ) internal view returns (bool) {
        if (record.state.status == StreamStatus.Cancelled) {
            return true;
        }
        uint256 maxAccruable =
            record.state.fundedPrincipal.saturatingSub(record.state.principalReleased);
        if (record.state.principalAccrued >= maxAccruable) {
            return true;
        }
        return block.timestamp >= record.terms.endsAt && record.state.status != StreamStatus.Paused;
    }

    function _existingStream(
        uint256 streamId
    ) internal view returns (StreamRecord storage record) {
        record = _streams[streamId];
        require(record.terms.payer != address(0), "STREAM_ID");
    }

    function _existingStreamView(
        uint256 streamId
    ) internal view returns (StreamRecord storage record) {
        record = _streams[streamId];
        require(record.terms.payer != address(0), "STREAM_ID");
    }

    function _requireParticipant(
        StreamRecord storage record
    ) internal view {
        if (_policy.allowParticipantPause) {
            Validation.requireParticipant(msg.sender, record.terms.payer, record.terms.beneficiary);
            return;
        }
        require(msg.sender == record.terms.payer || canOperate(msg.sender), "PARTICIPANT");
    }
}
