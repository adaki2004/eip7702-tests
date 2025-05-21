// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import {SimpleDelegate} from "../src/SimpleDelegate.sol";
import {ERC20} from "../src/SimpleDelegate.sol";

contract SimpleDelegateTest is Test {
    // Alice's address and private key (EOA with no initial contract code).
    address payable ALICE_ADDRESS = payable(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
    uint256 constant ALICE_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    // Bob's address and private key (Bob will execute transactions on Alice's behalf).
    address constant BOB_ADDRESS = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    uint256 constant BOB_PK = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    // The contract that Alice will delegate execution to.
    SimpleDelegate public implementation;

    // ERC-20 token contract for minting test tokens.
    ERC20 public token;

    function setUp() public {
        // Deploy the delegation contract (Alice will delegate calls to this contract).
        implementation = new SimpleDelegate();

        // Deploy an ERC-20 token contract where Alice is the minter.
        token = new ERC20(ALICE_ADDRESS);
    }

    function testSignDelegationAndThenAttachDelegation() public {
        // Construct a single transaction call: Mint 100 tokens to Bob.
        SimpleDelegate.Call[] memory calls = new SimpleDelegate.Call[](1);
        bytes memory data = abi.encodeCall(ERC20.mint, (100, BOB_ADDRESS));
        calls[0] = SimpleDelegate.Call({to: address(token), data: data, value: 0});

        // Alice signs a delegation allowing `implementation` to execute transactions on her behalf.
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(implementation), ALICE_PK);

        // Bob attaches the signed delegation from Alice and broadcasts it.
        vm.broadcast(BOB_PK);
        vm.attachDelegation(signedDelegation);

        // As Bob, execute the transaction via Alice's assigned contract.
        SimpleDelegate(ALICE_ADDRESS).execute(calls);

        // Verify that Alice's account now behaves as a smart contract.
        bytes memory code = address(ALICE_ADDRESS).code;
        require(code.length > 0, "no code written to Alice");

        console2.log("Contratc checks");

        bool isAliceContract = isContract(address(ALICE_ADDRESS));
        bool isBobContract = isContract(address(BOB_ADDRESS));
        bool isTokenContract = isContract(address(token));
        console2.log("Alice is currently considered contract? ", isAliceContract);
        console2.log("Bob is currently considered contract? ", isBobContract);
        console2.log("Token is currently considered contract? ", isTokenContract);

        // Verify Bob successfully received 100 tokens.
        assertEq(token.balanceOf(BOB_ADDRESS), 100);
    }


    // Took over from taiko-mono, to test with Pectra evm
    function isContract(address _addr) public view returns (bool) {
        return _isContract(_addr) // code size > 0
            && delegationOf(_addr) == address(0); // not an EOA with 7702 delegation
    }

    /// @dev Copied from https://github.com/Vectorized/solady/blob/main/src/accounts/LibEIP7702.sol
    /// @notice Returns the delegation address of an account.
    /// @param account The account to get the delegation address of.
    /// @return result The delegation address of the account.
    function delegationOf(address account) internal view returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            extcodecopy(account, 0x00, 0x00, 0x20)
            // Note: Checking that it starts with hex"ef01" is the most general and futureproof.
            // 7702 bytecode is `abi.encodePacked(hex"ef01", uint8(version), address(delegation))`.
            result := mul(shr(96, mload(0x03)), eq(0xef01, shr(240, mload(0x00))))
        }
    }

    function _isContract(address _addr) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
}
