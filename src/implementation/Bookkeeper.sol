pragma solidity ^0.8.6;

import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";

import "./OptimisticProposer.sol";
import "forge-std/console.sol";

/// @title Bookkeeper
/// @dev Holds assets on behalf of account holders in the Oya network.
contract Bookkeeper is OptimisticProposer, Executor {

  using SafeERC20 for IERC20;

  event BookkeeperDeployed(string rules);

  event BookkeeperUpdated(address indexed contractAddress, uint256 indexed chainId, bool isApproved);

  /// @notice Mapping of Bookkeeper contract address to chain IDs, and whether they are authorized.
  mapping(address => mapping(uint256 => bool)) public bookkeepers;

  /**
   * @notice Construct Oya Bookkeeper contract.
   * @param _finder UMA Finder contract address.
   * @param _collateral Address of the ERC20 collateral used for bonds.
   * @param _bondAmount Amount of collateral currency to make assertions for proposed transactions
   * @param _rules Reference to the Oya global rules.
   * @param _identifier The approved identifier to be used with the contract, compatible with Optimistic Oracle V3.
   * @param _liveness The period, in seconds, in which a proposal can be disputed.
   */
  constructor(
    address _finder,
    address _collateral,
    uint256 _bondAmount,
    string memory _rules,
    bytes32 _identifier,
    uint64 _liveness
  ) {
    require(_finder != address(0), "Finder address can not be empty");
    finder = FinderInterface(_finder);
    bytes memory initializeParams = abi.encode(_collateral, _bondAmount, _rules, _identifier, _liveness);
    setUp(initializeParams);
  }

  /**
   * @notice Sets up the Oya Bookkeeper contract.
   * @param initializeParams ABI encoded parameters to initialize the contract with.
   */
  function setUp(bytes memory initializeParams) public initializer {
    _startReentrantGuardDisabled();
    __Ownable_init();
    (address _collateral, uint256 _bondAmount, string memory _rules, bytes32 _identifier, uint64 _liveness) =
      abi.decode(initializeParams, (address, uint256, string, bytes32, uint64));
    setCollateralAndBond(IERC20(_collateral), _bondAmount);
    setRules(_rules);
    setIdentifier(_identifier);
    setLiveness(_liveness);
    _sync();

    emit BookkeeperDeployed(_rules);
  }

  /// @notice Updates the address of a Bookkeeper contract for a specific chain.
  /// @dev Only callable by the contract owner. Bookkeepers are added by protocol governance.
  /// @dev There may be multiple Bookkeepers on one chain temporarily during a migration.
  /// @param _contractAddress The address of the Bookkeeper contract.
  /// @param _chainId The chain to update.
  /// @param _isApproved Set to true to add the Bookkeeper contract, false to remove.
  function updateBookkeeper(address _contractAddress, uint256 _chainId, bool _isApproved) external onlyOwner {
    bookkeepers[_contractAddress][_chainId] = _isApproved;
    emit BookkeeperUpdated(_contractAddress, _chainId, _isApproved);
  }

  /**
   * @notice Executes an approved proposal.
   * @param transactions the transactions being executed. These must exactly match those that were proposed.
   */
  function executeProposal(Transaction[] memory transactions) external nonReentrant {
    // Recreate the proposal hash from the inputs and check that it matches the stored proposal hash.
    bytes32 proposalHash = keccak256(abi.encode(transactions));

    // Get the original proposal assertionId.
    bytes32 assertionId = assertionIds[proposalHash];

    // This will reject the transaction if the proposal hash generated from the inputs does not have the associated
    // assertionId stored. This is possible when a) the transactions have not been proposed, b) transactions have
    // already been executed, c) the proposal was disputed or d) the proposal was deleted after Optimistic Oracle V3
    // upgrade.
    require(assertionId != bytes32(0), "Proposal hash does not exist");

    // Remove proposal hash and assertionId so transactions can not be executed again.
    delete assertionIds[proposalHash];
    delete proposalHashes[assertionId];

    // There is no need to check the assertion result as this point can be reached only for non-disputed assertions.
    // This will revert if the assertion has not been settled and can not currently be settled.
    optimisticOracleV3.settleAndGetAssertionResult(assertionId);

    // Execute the transactions.
    for (uint256 i = 0; i < transactions.length; i++) {
      Transaction memory transaction = transactions[i];

      require(
        execute(transaction.to, transaction.value, transaction.data, transaction.operation, type(uint256).max),
        "Failed to execute transaction"
      );
      emit TransactionExecuted(proposalHash, assertionId, i);
    }

    emit ProposalExecuted(proposalHash, assertionId);
  }

}
