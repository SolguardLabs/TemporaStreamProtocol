// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ITemporaStreamProtocol } from "../interfaces/ITemporaStreamProtocol.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";

interface ITemporaLensSource is ITemporaStreamProtocol {
    function payerStreamAt(
        address payer,
        uint256 index
    ) external view returns (uint256);
    function beneficiaryStreamAt(
        address beneficiary,
        uint256 index
    ) external view returns (uint256);
    function payerStreamCount(
        address payer
    ) external view returns (uint256);
    function beneficiaryStreamCount(
        address beneficiary
    ) external view returns (uint256);
    function payerReservedByToken(
        address payer,
        address token
    ) external view returns (uint256);
    function beneficiaryRateByToken(
        address beneficiary,
        address token
    ) external view returns (uint256);
}

contract TemporaLens {
    using FixedPointMath for uint256;

    struct AccountSummary {
        address account;
        address token;
        uint256 payerStreamCount;
        uint256 beneficiaryStreamCount;
        uint256 totalReserved;
        uint256 beneficiaryRate;
        uint256 releasablePrincipal;
        uint256 claimablePrincipal;
        uint256 claimableYield;
    }

    struct StreamListItem {
        uint256 streamId;
        address counterparty;
        address token;
        ITemporaStreamProtocol.StreamStatus status;
        uint256 startsAt;
        uint256 endsAt;
        uint256 ratePerSecond;
        uint256 principalBalance;
        uint256 claimablePrincipal;
        uint256 claimableYield;
    }

    struct ReserveSummary {
        address token;
        bool enabled;
        uint256 totalEscrowed;
        uint256 yieldBuffer;
        uint256 paidFromYield;
        uint256 paidFromPrincipal;
        uint256 globalYieldIndex;
        uint256 bufferCoverageWad;
        uint256 principalCoverageWad;
    }

    function accountSummary(
        ITemporaLensSource protocol,
        address account,
        address token
    ) external view returns (AccountSummary memory summary) {
        summary.account = account;
        summary.token = token;
        summary.payerStreamCount = protocol.payerStreamCount(account);
        summary.beneficiaryStreamCount = protocol.beneficiaryStreamCount(account);
        summary.totalReserved = protocol.payerReservedByToken(account, token);
        summary.beneficiaryRate = protocol.beneficiaryRateByToken(account, token);
        summary.releasablePrincipal = protocol.releasable(account, token);
        summary.claimablePrincipal = _sumBeneficiaryPrincipal(protocol, account);
        summary.claimableYield = _sumBeneficiaryYield(protocol, account);
    }

    function payerStreams(
        ITemporaLensSource protocol,
        address payer,
        uint256 cursor,
        uint256 size
    ) external view returns (StreamListItem[] memory items, uint256 nextCursor) {
        uint256 count = protocol.payerStreamCount(payer);
        if (cursor >= count) {
            return (new StreamListItem[](0), count);
        }
        uint256 end = cursor + size;
        if (end > count) {
            end = count;
        }
        items = new StreamListItem[](end - cursor);
        for (uint256 i = cursor; i < end; i++) {
            uint256 streamId = protocol.payerStreamAt(payer, i);
            items[i - cursor] = _item(protocol, streamId, true);
        }
        nextCursor = end;
    }

    function beneficiaryStreams(
        ITemporaLensSource protocol,
        address beneficiary,
        uint256 cursor,
        uint256 size
    ) external view returns (StreamListItem[] memory items, uint256 nextCursor) {
        uint256 count = protocol.beneficiaryStreamCount(beneficiary);
        if (cursor >= count) {
            return (new StreamListItem[](0), count);
        }
        uint256 end = cursor + size;
        if (end > count) {
            end = count;
        }
        items = new StreamListItem[](end - cursor);
        for (uint256 i = cursor; i < end; i++) {
            uint256 streamId = protocol.beneficiaryStreamAt(beneficiary, i);
            items[i - cursor] = _item(protocol, streamId, false);
        }
        nextCursor = end;
    }

    function reserveSummary(
        ITemporaLensSource protocol,
        address token
    ) external view returns (ReserveSummary memory summary) {
        ITemporaStreamProtocol.ReserveView memory reserve = protocol.reserveOf(token);
        summary.token = token;
        summary.enabled = reserve.enabled;
        summary.totalEscrowed = reserve.totalEscrowed;
        summary.yieldBuffer = reserve.yieldBuffer;
        summary.paidFromYield = reserve.paidFromYield;
        summary.paidFromPrincipal = reserve.paidFromPrincipal;
        summary.globalYieldIndex = reserve.globalYieldIndex;
        summary.bufferCoverageWad = _ratio(reserve.yieldBuffer, reserve.totalEscrowed);
        summary.principalCoverageWad =
            _ratio(reserve.totalEscrowed + reserve.yieldBuffer, reserve.totalEscrowed);
    }

    function _item(
        ITemporaLensSource protocol,
        uint256 streamId,
        bool fromPayer
    ) internal view returns (StreamListItem memory item) {
        ITemporaStreamProtocol.StreamView memory stream = protocol.streamOf(streamId);
        item.streamId = streamId;
        item.counterparty = fromPayer ? stream.beneficiary : stream.payer;
        item.token = stream.token;
        item.status = stream.status;
        item.startsAt = stream.startsAt;
        item.endsAt = stream.endsAt;
        item.ratePerSecond = stream.ratePerSecond;
        item.principalBalance = stream.principalBalance;
        item.claimablePrincipal = protocol.claimablePrincipal(streamId);
        item.claimableYield = protocol.claimableYield(streamId);
    }

    function _sumBeneficiaryPrincipal(
        ITemporaLensSource protocol,
        address beneficiary
    ) internal view returns (uint256 total) {
        uint256 count = protocol.beneficiaryStreamCount(beneficiary);
        for (uint256 i = 0; i < count; i++) {
            total += protocol.claimablePrincipal(protocol.beneficiaryStreamAt(beneficiary, i));
        }
    }

    function _sumBeneficiaryYield(
        ITemporaLensSource protocol,
        address beneficiary
    ) internal view returns (uint256 total) {
        uint256 count = protocol.beneficiaryStreamCount(beneficiary);
        for (uint256 i = 0; i < count; i++) {
            total += protocol.claimableYield(protocol.beneficiaryStreamAt(beneficiary, i));
        }
    }

    function _ratio(
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (uint256) {
        if (denominator == 0) {
            return numerator == 0 ? 0 : type(uint256).max;
        }
        return numerator.divWadDown(denominator);
    }
}

