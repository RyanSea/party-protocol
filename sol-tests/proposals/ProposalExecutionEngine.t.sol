// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/tokens/IERC721.sol";

import "../TestUtils.sol";

import "./TestableProposalExecutionEngine.sol";
import "./DummyProposalEngineImpl.sol";

contract ProposalExecutionEngineTest is
    Test,
    TestUtils
{
    // From TestableProposalExecutionEngine
    event TestEcho(uint256 indexed v);
    // From DummyProposalEngineImpl
    event TestInitializeCalled(address oldImpl, bytes32 initDataHash);

    TestableProposalExecutionEngine eng;
    DummyProposalEngineImpl newEngImpl;
    Globals globals;

    constructor() {
    }

    function setUp() public {
        newEngImpl = new DummyProposalEngineImpl();
        globals = new Globals(address(this));
        globals.setAddress(
            LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL,
            // We will test upgrades to this impl.
            address(newEngImpl)
        );
        eng = new TestableProposalExecutionEngine(
            globals,
            ISeaportExchange(_randomAddress()),
            ISeaportConduitController(_randomAddress()),
            IZoraAuctionHouse(_randomAddress())
        );
    }

    function _createTestProposal(bytes memory proposalData)
        private
        view
        returns (
            IProposalExecutionEngine.ExecuteProposalParams memory executeParams
        )
    {
        executeParams =
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomBytes32(),
                proposalData: proposalData,
                progressData: "",
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0)
            });
    }

    function _createTwoStepProposalData(uint256 emitValue1, uint256 emitValue2)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            bytes4(uint32(ProposalExecutionEngine.ProposalType.ListOnOpenSea)),
            emitValue1,
            emitValue2
        );
    }

    function _createOneStepProposalData(uint256 emitValue)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            bytes4(uint32(ProposalExecutionEngine.ProposalType.ListOnZora)),
            emitValue
        );
    }

    function _createUpgradeProposalData(bytes memory initData)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            bytes4(uint32(ProposalExecutionEngine.ProposalType.UpgradeProposalEngineImpl)),
            initData
        );
    }

    function test_executeProposal_rejectsBadProgressData() public {
        // This is a two-step proposal. We will execute the first step
        // then execute again with progressData that does not match
        // the progressData for the next step.
        (uint256 emitValue1, uint256 emitValue2) = (_randomUint256(), _randomUint256());
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams =
            _createTestProposal(_createTwoStepProposalData(emitValue1, emitValue2));
        vm.expectEmit(true, false, false ,false, address(eng));
        emit TestEcho(emitValue1);
        IProposalExecutionEngine.ProposalExecutionStatus status =
            eng.executeProposal(executeParams);
        assertTrue(status == IProposalExecutionEngine.ProposalExecutionStatus.InProgress);
        // Use bad progressData for the next step.
        executeParams.progressData = abi.encode('poop');
        vm.expectRevert(abi.encodeWithSelector(
            ProposalExecutionEngine.ProposalProgressDataInvalidError.selector,
            keccak256(executeParams.progressData),
            keccak256(eng.t_nextProgressData())
        ));
        eng.executeProposal(executeParams);
    }

    function test_executeProposal_onlyOneProposalAtATime() public {
        // Start a two-step proposal then try to execute a different one-step
        // proposal, which should fail.
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams =
            _createTestProposal(_createTwoStepProposalData(_randomUint256(), _randomUint256()));
        eng.executeProposal(executeParams);
        // Execute a different proposal while the first one is incomplete.
        executeParams = _createTestProposal(_createOneStepProposalData(_randomUint256()));
        vm.expectRevert(abi.encodeWithSelector(
            ProposalExecutionEngine.ProposalExecutionBlockedError.selector,
            executeParams.proposalId,
            eng.getCurrentInProgressProposalId()
        ));
        eng.executeProposal(executeParams);
    }

    function test_executeProposal_cannotExecuteCompleteProposal() public {
        // Execute a one-step proposal, then try to execute the same one again.
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams =
            _createTestProposal(_createOneStepProposalData(_randomUint256()));
        IProposalExecutionEngine.ProposalExecutionStatus status =
            eng.executeProposal(executeParams);
        assertTrue(status == IProposalExecutionEngine.ProposalExecutionStatus.Complete);
        // Try again
        vm.expectRevert(abi.encodeWithSelector(
            ProposalExecutionEngine.ProposalAlreadyCompleteError.selector,
            executeParams.proposalId
        ));
        eng.executeProposal(executeParams);
    }

    function test_executeProposal_twoStepWorks() public {
        (uint256 emitValue1, uint256 emitValue2) = (_randomUint256(), _randomUint256());
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams =
            _createTestProposal(_createTwoStepProposalData(emitValue1, emitValue2));
        vm.expectEmit(true, false, false ,false, address(eng));
        emit TestEcho(emitValue1);
        IProposalExecutionEngine.ProposalExecutionStatus status =
            eng.executeProposal(executeParams);
        assertTrue(status == IProposalExecutionEngine.ProposalExecutionStatus.InProgress);
        // Update the progressData for the next step.
        // Normally this would be captured from event logs, but we don't
        // have access to logs so the test contract surfaces it through a
        // public variable.
        executeParams.progressData = eng.t_nextProgressData();
        vm.expectEmit(true, false, false ,false, address(eng));
        emit TestEcho(emitValue2);
        status = eng.executeProposal(executeParams);
        assertTrue(status == IProposalExecutionEngine.ProposalExecutionStatus.Complete);
    }

    function test_executeProposal_oneStepWorks() public {
        uint256 emitValue = _randomUint256();
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams =
            _createTestProposal(_createOneStepProposalData(emitValue));
        vm.expectEmit(true, false, false ,false, address(eng));
        emit TestEcho(emitValue);
        IProposalExecutionEngine.ProposalExecutionStatus status =
            eng.executeProposal(executeParams);
        assertTrue(status == IProposalExecutionEngine.ProposalExecutionStatus.Complete);
    }

    function test_executeProposal_upgradeImplementationWorks() public {
        bytes memory initData = abi.encode('yooo');
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams =
            _createTestProposal(_createUpgradeProposalData(initData));
        vm.expectEmit(true, false, false ,false, address(eng));
        emit TestInitializeCalled(address(eng), keccak256(initData));
        IProposalExecutionEngine.ProposalExecutionStatus status =
            eng.executeProposal(executeParams);
        assertTrue(status == IProposalExecutionEngine.ProposalExecutionStatus.Complete);
        assertEq(address(eng.getProposalEngineImpl()), address(newEngImpl));
    }

    // TODO: ...
}