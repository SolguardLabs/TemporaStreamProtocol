// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ITemporaStreamProtocol } from "../src/interfaces/ITemporaStreamProtocol.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { TemporaStreamProtocol } from "../src/TemporaStreamProtocol.sol";
import { TemporaScheduleLens } from "../src/lens/TemporaScheduleLens.sol";

interface Vm {
    function warp(
        uint256 timestamp
    ) external;
    function prank(
        address caller
    ) external;
    function startPrank(
        address caller
    ) external;
    function stopPrank() external;
}

contract TemporaStreamProtocolTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    TemporaStreamProtocol internal protocol;
    MockERC20 internal asset;

    address internal payer = address(0xA11CE);
    address internal beneficiary = address(0xB0B);
    address internal reporter = address(0xCAFE);

    uint256 internal constant START_TIME = 1_800_000_000;
    uint256 internal constant RATE = 1 ether;
    uint256 internal constant DURATION = 1_000;
    uint256 internal constant RESERVE_RATE = 1_000_000_000_000;

    function setUp() public {
        vm.warp(START_TIME);
        asset = new MockERC20("Tempora USD", "tUSD", 18);
        protocol = new TemporaStreamProtocol();
        protocol.configureReserve(address(asset), RESERVE_RATE, 0);
        _fundAndApprove(payer, 10_000 ether);
        _fundAndApprove(reporter, 10_000 ether);
    }

    function testCreateStreamTracksReserveAndParticipants() public {
        uint256 streamId = _createStream(payer, beneficiary, DURATION, RATE, true);

        ITemporaStreamProtocol.StreamView memory stream = protocol.streamOf(streamId);
        ITemporaStreamProtocol.ReserveView memory reserve = protocol.reserveOf(address(asset));

        _assertEq(stream.payer, payer, "payer");
        _assertEq(stream.beneficiary, beneficiary, "beneficiary");
        _assertEq(
            uint256(stream.status), uint256(ITemporaStreamProtocol.StreamStatus.Active), "status"
        );
        _assertEq(stream.fundedPrincipal, RATE * DURATION, "funded");
        _assertEq(stream.principalBalance, RATE * DURATION, "balance");
        _assertEq(reserve.totalEscrowed, RATE * DURATION, "escrowed");
        _assertEq(protocol.payerStreamCount(payer), 1, "payer streams");
        _assertEq(protocol.beneficiaryStreamCount(beneficiary), 1, "beneficiary streams");
    }

    function testScheduleLensProjectsAnActiveWindow() public {
        uint256 streamId = _createStream(payer, beneficiary, DURATION, RATE, true);
        TemporaScheduleLens lens = new TemporaScheduleLens();
        TemporaScheduleLens.Projection memory projection =
            lens.project(ITemporaStreamProtocol(address(protocol)), streamId, 90);

        _assertEq(projection.incrementalPrincipal, 90 ether, "window principal");
        _assertEq(projection.claimableNow, 0, "not yet accrued");
        _assertEq(projection.remainingBalance, 1000 ether, "remaining balance");

        vm.warp(START_TIME + 20);
        vm.prank(payer);
        protocol.pauseStream(streamId);
        projection = lens.project(ITemporaStreamProtocol(address(protocol)), streamId, 90);
        _assertEq(projection.incrementalPrincipal, 0, "paused projection");
    }

    function testBeneficiaryClaimsPrincipalForElapsedWindow() public {
        uint256 streamId = _createStream(payer, beneficiary, DURATION, RATE, true);

        vm.warp(START_TIME + 120);
        vm.prank(beneficiary);
        uint256 claimed = protocol.claimPrincipal(streamId);

        _assertEq(claimed, 120 ether, "claimed principal");
        _assertEq(asset.balanceOf(beneficiary), 120 ether, "beneficiary balance");
        ITemporaStreamProtocol.StreamView memory stream = protocol.streamOf(streamId);
        _assertEq(stream.principalClaimed, 120 ether, "claimed tracked");
        _assertEq(stream.principalBalance, 880 ether, "remaining principal");
    }

    function testReportedYieldIsPaidFromReserveBuffer() public {
        uint256 streamId = _createStream(payer, beneficiary, DURATION, RATE, true);

        vm.prank(reporter);
        protocol.reportYield(address(asset), 25 ether);

        vm.warp(START_TIME + 100);
        vm.prank(beneficiary);
        uint256 claimed = protocol.claimYield(streamId);

        _assertGt(claimed, 0, "yield");
        _assertEq(asset.balanceOf(beneficiary), claimed, "yield balance");

        ITemporaStreamProtocol.ReserveView memory reserve = protocol.reserveOf(address(asset));
        _assertEq(reserve.paidFromYield, claimed, "buffer paid");
        _assertEq(reserve.paidFromPrincipal, 0, "principal not used");
    }

    function testPauseResumeDiscountsInactivePrincipalWindow() public {
        uint256 streamId = _createStream(payer, beneficiary, DURATION, RATE, true);

        vm.warp(START_TIME + 100);
        vm.prank(beneficiary);
        protocol.pauseStream(streamId);

        vm.warp(START_TIME + 160);
        vm.prank(beneficiary);
        protocol.resumeStream(streamId);

        _assertEq(protocol.releasable(payer, address(asset)), 60 ether, "released credit");

        vm.warp(START_TIME + 260);
        vm.prank(beneficiary);
        uint256 claimed = protocol.claimPrincipal(streamId);

        _assertEq(claimed, 200 ether, "active principal");
        ITemporaStreamProtocol.StreamView memory stream = protocol.streamOf(streamId);
        _assertEq(stream.totalPaused, 60, "paused seconds");
        _assertEq(stream.principalReleased, 60 ether, "released tracked");
    }

    function testPayerWithdrawsReleasedPrincipalAfterPause() public {
        uint256 streamId = _createStream(payer, beneficiary, DURATION, RATE, true);

        vm.warp(START_TIME + 40);
        vm.prank(payer);
        protocol.pauseStream(streamId);

        vm.warp(START_TIME + 90);
        vm.prank(payer);
        protocol.resumeStream(streamId);

        uint256 payerBalanceBefore = asset.balanceOf(payer);
        vm.prank(payer);
        protocol.withdrawReleased(address(asset), 50 ether);

        _assertEq(asset.balanceOf(payer), payerBalanceBefore + 50 ether, "withdrawn");
        _assertEq(protocol.releasable(payer, address(asset)), 0, "credit cleared");
    }

    function testCancelableStreamReleasesUnvestedPrincipal() public {
        uint256 streamId = _createStream(payer, beneficiary, DURATION, RATE, true);

        vm.warp(START_TIME + 180);
        vm.prank(payer);
        protocol.cancelStream(streamId);

        ITemporaStreamProtocol.StreamView memory stream = protocol.streamOf(streamId);
        _assertEq(
            uint256(stream.status), uint256(ITemporaStreamProtocol.StreamStatus.Cancelled), "status"
        );
        _assertEq(stream.principalReleased, 820 ether, "released");
        _assertEq(protocol.releasable(payer, address(asset)), 820 ether, "credit");

        vm.prank(beneficiary);
        uint256 claimed = protocol.claimPrincipal(streamId);
        _assertEq(claimed, 180 ether, "earned principal");
    }

    function testClaimAllReturnsPrincipalAndYield() public {
        uint256 streamId = _createStream(payer, beneficiary, DURATION, RATE, true);

        vm.prank(reporter);
        protocol.reportYield(address(asset), 30 ether);

        vm.warp(START_TIME + 75);
        vm.prank(beneficiary);
        (uint256 principal, uint256 yieldAmount) = protocol.claimAll(streamId);

        _assertEq(principal, 75 ether, "principal");
        _assertGt(yieldAmount, 0, "yield");
        _assertEq(asset.balanceOf(beneficiary), principal + yieldAmount, "balance");
    }

    function _createStream(
        address streamPayer,
        address streamBeneficiary,
        uint256 durationSeconds,
        uint256 ratePerSecond,
        bool cancelable
    ) internal returns (uint256 streamId) {
        vm.prank(streamPayer);
        streamId = protocol.createStream(
            ITemporaStreamProtocol.CreateStreamRequest({
                token: address(asset),
                beneficiary: streamBeneficiary,
                startsAt: block.timestamp,
                endsAt: block.timestamp + durationSeconds,
                ratePerSecond: ratePerSecond,
                minimumReserve: 0,
                cancelable: cancelable,
                metadataHash: keccak256(abi.encode(streamPayer, streamBeneficiary, durationSeconds))
            })
        );
    }

    function _fundAndApprove(
        address account,
        uint256 amount
    ) internal {
        asset.mint(account, amount);
        vm.prank(account);
        asset.approve(address(protocol), type(uint256).max);
    }

    function _assertEq(
        address observed,
        address expected,
        string memory label
    ) internal pure {
        require(observed == expected, label);
    }

    function _assertEq(
        uint256 observed,
        uint256 expected,
        string memory label
    ) internal pure {
        require(observed == expected, label);
    }

    function _assertGt(
        uint256 observed,
        uint256 floor,
        string memory label
    ) internal pure {
        require(observed > floor, label);
    }
}

