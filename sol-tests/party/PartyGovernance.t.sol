// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/party/Party.sol";
import "../../contracts/globals/Globals.sol";
import "../proposals/DummySimpleProposalEngineImpl.sol";
import "../proposals/DummyProposalEngineImpl.sol";
import "../TestUtils.sol";
import "../DummyERC721.sol";
import "../TestUsers.sol";

contract PartyGovernanceTest is Test, TestUtils {
  PartyFactory partyFactory;
  DummySimpleProposalEngineImpl eng;

  function setUp() public {
    GlobalsAdmin globalsAdmin = new GlobalsAdmin();
    Globals globals = globalsAdmin.globals();
  
    Party partyImpl = new Party(globals);
    globalsAdmin.setPartyImpl(address(partyImpl));

    eng = new DummySimpleProposalEngineImpl();
    globalsAdmin.setProposalEng(address(eng));
  
    partyFactory = new PartyFactory(globals);

  }

  function testSimpleGovernance() public {
    vm.deal(address(1), 100 ether);
    vm.startPrank(address(1));

    address[] memory hosts = new address[](2);
    hosts[0] = address(2);
    hosts[1] = address(1);

    PartyGovernance.GovernanceOpts memory govOpts = PartyGovernance.GovernanceOpts({
      hosts: hosts,
      voteDuration: 99,
      executionDelay: 300,
      passThresholdBps: 5100,
      totalVotingPower: 100
    });
    Party.PartyOptions memory po = Party.PartyOptions({
      governance: govOpts,
      name: 'Dope party',
      symbol: 'DOPE'
    });

    DummyERC721 dummyErc721 = new DummyERC721();
    dummyErc721.mint(address(1));

    IERC721[] memory preciousTokens = new IERC721[](1);
    preciousTokens[0] = IERC721(address(dummyErc721));

    uint256[] memory preciousTokenIds = new uint256[](1);
    preciousTokenIds[0] = 1;

    Party party = partyFactory.createParty(
      address(1), po, preciousTokens, preciousTokenIds
    );
    party.mint(address(3), 49,address(3));
    assertEq(party.getVotingPowerOfToken(1), 49);
    assertEq(party.ownerOf(1), address(3));
    assertEq(party.getDistributionShareOf(1), 0.49 ether);

    vm.warp(block.timestamp + 1);
    party.mint(address(4), 10, address(3));
    assertEq(party.getVotingPowerOfToken(2), 10);
    assertEq(party.ownerOf(2), address(4));
    assertEq(party.getDistributionShareOf(2), 0.10 ether);

    uint40 firstTime = uint40(block.timestamp);

    assertEq(party.getVotingPowerAt(address(3), firstTime), 59);
    assertEq(party.getVotingPowerAt(address(4), firstTime), 0);

    uint40 nextTime = firstTime + 10;
    vm.warp(nextTime);
    vm.stopPrank();
    vm.prank(address(4));
    party.delegateVotingPower(address(4));

    assertEq(party.getVotingPowerAt(address(3), firstTime), 59); // stays same for old time
    assertEq(party.getVotingPowerAt(address(4), firstTime), 0); // stays same for old time
    assertEq(block.timestamp, nextTime);
    assertEq(party.getVotingPowerAt(address(3), nextTime), 49); // diff for new time
    assertEq(party.getVotingPowerAt(address(4), nextTime), 10); // diff for new time

    PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
      maxExecutableTime: 999999999,
      nonce: 1,
      proposalData: abi.encodePacked([0])
    });
    vm.prank(address(3));
    party.propose(p1);

    assertEq(party.getGovernanceValues().totalVotingPower, 100);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 49);

    vm.prank(address(4));
    party.accept(1);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Passed, 59);

    // execution time hasn't passed
    vm.warp(block.timestamp + 299);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Passed, 59);

    // execution time has passed
    vm.warp(block.timestamp + 2);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Ready, 59);


    DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

    assertEq(engInstance.getLastExecutedProposalId(), 0);
    assertEq(engInstance.getNumExecutedProposals(), 0);

    party.execute(1, p1, preciousTokens, preciousTokenIds, abi.encodePacked([address(0)]));
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Complete, 59);

    assertEq(engInstance.getLastExecutedProposalId(), 1);
    assertEq(engInstance.getNumExecutedProposals(), 1);

  }

  function _assertProposalState(
    Party party,
    uint256 proposalId,
    PartyGovernance.ProposalState expectedProposalState,
    uint256 expectedNumVotes
  ) private {
      (PartyGovernance.ProposalState ps, PartyGovernance.ProposalInfoValues memory pv) = party.getProposalStates(proposalId);
      assert(ps == expectedProposalState);
      assertEq(pv.votes, expectedNumVotes);
  }

}

