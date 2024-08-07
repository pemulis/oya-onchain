// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@uma/core/optimistic-oracle-v3/interfaces/EscalationManagerInterface.sol";

import "../src/implementation/Bookkeeper.sol";
import "../src/mocks/MockAddressWhitelist.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockFinder.sol";
import "../src/mocks/MockIdentifierWhitelist.sol";
import "../src/mocks/MockOptimisticOracleV3.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BookkeeperTest is Test {

  Bookkeeper public bookkeeper;
  MockFinder public mockFinder;
  MockAddressWhitelist public mockAddressWhitelist;
  MockIdentifierWhitelist public mockIdentifierWhitelist;
  MockOptimisticOracleV3 public mockOptimisticOracleV3;
  MockERC20 public mockCollateral;
  MockERC20 public newMockCollateral;
  EscalationManagerInterface public mockEscalationManager;
  address public owner = address(1);
  address public bookkeeperAddress = address(2);
  address public newOwner = address(3);
  address public randomAddress = address(4);
  uint256 public bondAmount = 1000;
  string public rules = "Sample rules";
  string public newRules = "New rules";
  bytes32 public identifier = keccak256("Identifier");
  uint64 public liveness = 100;
  uint64 public newLiveness = 200;

  function setUp() public {
    // Set up the mock contracts
    mockFinder = new MockFinder();
    mockAddressWhitelist = new MockAddressWhitelist();
    mockIdentifierWhitelist = new MockIdentifierWhitelist();
    mockOptimisticOracleV3 = new MockOptimisticOracleV3();
    mockCollateral = new MockERC20();
    newMockCollateral = new MockERC20();

    // Give the "owner" some collateral
    mockCollateral.transfer(owner, 1000 * 10 ** 18);

    // Setup the finder to return the mocks
    mockFinder.changeImplementationAddress(OracleInterfaces.CollateralWhitelist, address(mockAddressWhitelist));
    mockFinder.changeImplementationAddress(OracleInterfaces.IdentifierWhitelist, address(mockIdentifierWhitelist));
    mockFinder.changeImplementationAddress(OracleInterfaces.OptimisticOracleV3, address(mockOptimisticOracleV3));

    // Add collateral and identifier to the whitelist
    mockAddressWhitelist.addToWhitelist(address(mockCollateral));
    mockAddressWhitelist.addToWhitelist(address(newMockCollateral));
    mockIdentifierWhitelist.addIdentifier(identifier);

    vm.prank(owner);
    bookkeeper = new Bookkeeper(address(mockFinder), address(mockCollateral), bondAmount, rules, identifier, liveness);
  }

  function testUpdateBookkeeper() public {
    vm.startPrank(owner);
    uint256 chainId = 1;
    bookkeeper.updateBookkeeper(bookkeeperAddress, chainId, true);

    assertTrue(bookkeeper.bookkeepers(bookkeeperAddress, chainId));
    vm.stopPrank();
  }

  // Optimistic Proposer inherited tests
  function testTransferOwnership() public {
    vm.startPrank(owner);
    bookkeeper.transferOwnership(newOwner);

    assertEq(bookkeeper.owner(), newOwner);
    vm.stopPrank();
  }

  function testRenounceOwnership() public {
    vm.startPrank(owner);
    bookkeeper.renounceOwnership();
    assertEq(bookkeeper.owner(), address(0));
    vm.stopPrank();
  }

  function testNonOwnerCallShouldRevert() public {
    vm.startPrank(randomAddress);
    vm.expectRevert();
    bookkeeper.transferOwnership(randomAddress);
    vm.stopPrank();
  }

  function testSetEscalationManager() public {
    vm.startPrank(owner);
    bookkeeper.setEscalationManager(address(mockEscalationManager));
    assertEq(bookkeeper.escalationManager(), address(mockEscalationManager));
    vm.stopPrank();
  }

  function testSetRules() public {
    vm.startPrank(owner);
    bookkeeper.setRules(newRules);
    assertEq(bookkeeper.rules(), newRules);
    vm.stopPrank();
  }

  function testSetLiveness() public {
    vm.startPrank(owner);
    bookkeeper.setLiveness(newLiveness);
    assertEq(bookkeeper.liveness(), newLiveness);
    vm.stopPrank();
  }

  function testSetIdentifier() public {
    vm.startPrank(owner);
    bookkeeper.setIdentifier(identifier);
    assertEq(bookkeeper.identifier(), identifier);
    vm.stopPrank();
  }

  function testSync() public {
    vm.startPrank(randomAddress);
    bookkeeper.sync();
    vm.stopPrank();
  }

  function testSetCollateralAndBond() public {
    vm.startPrank(owner);
    bookkeeper.setCollateralAndBond(newMockCollateral, bondAmount);
    assertEq(address(bookkeeper.collateral()), address(newMockCollateral));
    assertEq(bookkeeper.bondAmount(), bondAmount);
    vm.stopPrank();
  }

  function testProposeTransactions() public {
    vm.startPrank(owner);
    mockCollateral.approve(address(bookkeeper), 1000 * 10 ** 18);
    OptimisticProposer.Transaction[] memory testTransactions = new OptimisticProposer.Transaction[](2);
    
    testTransactions[0] = OptimisticProposer.Transaction(
      address(4), Enum.Operation(0), 0, "");
    testTransactions[1] = OptimisticProposer.Transaction(
      address(mockOptimisticOracleV3), Enum.Operation(0), 0, "0x");
    
    bookkeeper.proposeTransactions(
      testTransactions, 
      "0x6f79612074657374000000000000000000000000000000000000000000000000"
    ); // "oya test" is the explanation
    vm.stopPrank();
  }

  function testSetController() public {
    address account = address(5);
    address controller = address(6);

    // Set controller by account owner
    vm.prank(account);
    bookkeeper.setController(account, controller);
    assertTrue(bookkeeper.isController(account, controller));

    // Set controller by an existing controller
    vm.prank(controller);
    bookkeeper.setController(account, address(7));
    assertTrue(bookkeeper.isController(account, address(7)));

    // Attempt to set controller by a non-authorized user
    vm.prank(randomAddress);
    vm.expectRevert("Not a controller");
    bookkeeper.setController(account, address(8));
  }

  function testSetRecoverer() public {
    address account = address(5);
    address guardian = address(6);

    // Set controller by account owner to ensure the guardian can be set
    vm.prank(account);
    bookkeeper.setController(account, address(this));

    // Set guardian by account owner
    vm.prank(account);
    bookkeeper.setRecoverer(account, guardian);
    assertTrue(bookkeeper.isRecoverer(account, guardian));

    // Set guardian by an existing controller
    vm.prank(address(this));
    bookkeeper.setRecoverer(account, address(7));
    assertTrue(bookkeeper.isRecoverer(account, address(7)));

    // Attempt to set guardian by a non-authorized user
    vm.prank(randomAddress);
    vm.expectRevert("Not a controller");
    bookkeeper.setRecoverer(account, address(8));
  }

  function testSetAccountRules() public {
    address account = address(5);
    address controller = address(6);
    string memory accountRules = "Account specific rules";

    // Set controller by account owner to ensure the controller can set rules
    vm.prank(account);
    bookkeeper.setController(account, controller);

    // Set account rules by account owner
    vm.prank(account);
    bookkeeper.setAccountRules(account, accountRules);
    assertEq(bookkeeper.accountRules(account), accountRules);

    // Set account rules by an existing controller
    vm.prank(controller);
    bookkeeper.setAccountRules(account, "Updated rules");
    assertEq(bookkeeper.accountRules(account), "Updated rules");

    // Attempt to set empty account rules
    vm.prank(account);
    vm.expectRevert("Rules can not be empty");
    bookkeeper.setAccountRules(account, "");

    // Attempt to set account rules by a non-authorized user
    vm.prank(randomAddress);
    vm.expectRevert("Not a controller");
    bookkeeper.setAccountRules(account, "New rules");
  }

  function testGoManual() public {
    address account = address(5);
    address controller = address(6);

    // Set controller by account owner to ensure the controller can set manual mode
    vm.prank(account);
    bookkeeper.setController(account, controller);

    // Go manual by account owner
    vm.prank(account);
    bookkeeper.goManual(account);
    assertTrue(bookkeeper.manualMode(account) > 0);

    // Go manual by an existing controller
    vm.prank(controller);
    bookkeeper.goManual(account);
    assertTrue(bookkeeper.manualMode(account) > 0);

    // Attempt to go manual by a non-authorized user
    vm.prank(randomAddress);
    vm.expectRevert("Not a controller");
    bookkeeper.goManual(account);
  }

  function testGoAutomatic() public {
    address account = address(5);
    address controller = address(6);

    // Set controller by account owner to ensure the controller can set automatic mode
    vm.prank(account);
    bookkeeper.setController(account, controller);

    // First, go manual
    vm.prank(account);
    bookkeeper.goManual(account);

    // Go automatic by account owner
    vm.prank(account);
    bookkeeper.goAutomatic(account);
    assertEq(bookkeeper.manualMode(account), 0);

    // Go manual again
    vm.prank(account);
    bookkeeper.goManual(account);

    // Go automatic by an existing controller
    vm.prank(controller);
    bookkeeper.goAutomatic(account);
    assertEq(bookkeeper.manualMode(account), 0);

    // Attempt to go automatic when not in manual mode
    vm.prank(account);
    vm.expectRevert("Not in manual mode");
    bookkeeper.goAutomatic(account);

    // Attempt to go automatic by a non-authorized user
    vm.prank(randomAddress);
    vm.expectRevert("Not a controller");
    bookkeeper.goAutomatic(account);
  }

  function testFreeze() public {
    address account = address(5);
    address guardian = address(6);

    // Set controller by account owner to ensure the guardian can be set
    vm.prank(account);
    bookkeeper.setController(account, address(this));

    // Set guardian
    vm.prank(account);
    bookkeeper.setRecoverer(account, guardian);

    // Freeze by guardian
    vm.prank(guardian);
    bookkeeper.freeze(account);
    assertTrue(bookkeeper.frozen(account));

    // Attempt to freeze by a non-guardian
    vm.prank(randomAddress);
    vm.expectRevert("Not a guardian");
    bookkeeper.freeze(account);
  }
}
